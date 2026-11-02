// The connection to the game server. Reconnects by itself, and straight away when the page comes
// back from the background (phones close connections of apps you switch away from); the server
// keeps your avatar in its room for a minute, so you pick up where you were. Every message is
// checked against the shared protocol before anything sees it.
import {
  encodeMessage,
  parseMessage,
  serverMessages,
  type ClientMessage,
  type DataOf,
  type ServerMessage,
} from '@bobba/shared';

type Handler<T extends ServerMessage['t']> = (data: DataOf<ServerMessage, T>) => void;

export class Connection {
  private ws: WebSocket | undefined;
  private handlers = new Map<string, Set<(data: unknown) => void>>();
  private retryMs = 1000;
  private retryTimer: ReturnType<typeof setTimeout> | undefined;
  private pongTimer: ReturnType<typeof setTimeout> | undefined;
  private stopped = false;
  private readonly url: string;

  onOpen: () => void = () => {};
  onClose: () => void = () => {};

  constructor(url: string) {
    this.url = url;
    // Back from another app or a locked screen: check the connection at once.
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') this.check();
    });
    window.addEventListener('pageshow', () => this.check());
    window.addEventListener('online', () => this.check());
    this.on('pong', () => clearTimeout(this.pongTimer));
  }

  /** Reconnect now if the connection is gone; if it looks open, make sure it really answers. */
  private check(): void {
    if (this.stopped) return;
    const state = this.ws?.readyState;
    if (state === WebSocket.CONNECTING) return;
    if (state !== WebSocket.OPEN) {
      clearTimeout(this.retryTimer);
      this.retryMs = 1000;
      this.connect();
      return;
    }
    // A phone can leave a dead connection looking open: no answer in a few seconds, start over.
    clearTimeout(this.pongTimer);
    this.send({ t: 'ping', d: {} });
    const ws = this.ws;
    this.pongTimer = setTimeout(() => {
      if (this.ws !== ws) return;
      this.ws = undefined;
      ws?.close();
      this.onClose();
      this.retryMs = 1000;
      this.connect();
    }, 4000);
  }

  connect(): void {
    if (this.stopped) return;
    clearTimeout(this.retryTimer);
    const ws = new WebSocket(this.url);
    this.ws = ws;
    ws.onopen = () => {
      if (this.ws !== ws) return;
      this.retryMs = 1000;
      this.onOpen();
    };
    ws.onmessage = (event) => {
      // Messages still arriving on an old connection we already replaced are ignored.
      if (this.ws !== ws || typeof event.data !== 'string') return;
      const message = parseMessage(serverMessages, event.data);
      if (!message) return console.warn('Ignoring bad server message', event.data);
      for (const handler of this.handlers.get(message.t) ?? []) handler(message.d);
    };
    ws.onclose = () => {
      if (this.stopped || this.ws !== ws) return;
      this.ws = undefined;
      this.onClose();
      // In the background there is no hurry: coming back reconnects at once (see check).
      if (document.visibilityState === 'hidden') return;
      this.retryTimer = setTimeout(() => this.connect(), this.retryMs);
      this.retryMs = Math.min(this.retryMs * 2, 15000);
    };
  }

  /** Stops for good (no reconnecting), e.g. after logging in somewhere else. */
  stop(): void {
    this.stopped = true;
    this.ws?.close();
  }

  on<T extends ServerMessage['t']>(type: T, handler: Handler<T>): void {
    let set = this.handlers.get(type);
    if (!set) this.handlers.set(type, (set = new Set()));
    set.add(handler as (data: unknown) => void);
  }

  send(message: ClientMessage): void {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(encodeMessage(message));
  }
}

export function serverUrl(): string {
  return `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`;
}
