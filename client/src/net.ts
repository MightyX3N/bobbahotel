// The connection to the game server. Reconnects by itself. Every message is checked against
// the shared protocol before anything sees it.
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
  private stopped = false;
  private readonly url: string;

  onOpen: () => void = () => {};
  onClose: () => void = () => {};

  constructor(url: string) {
    this.url = url;
  }

  connect(): void {
    if (this.stopped) return;
    const ws = new WebSocket(this.url);
    this.ws = ws;
    ws.onopen = () => {
      this.retryMs = 1000;
      this.onOpen();
    };
    ws.onmessage = (event) => {
      if (typeof event.data !== 'string') return;
      const message = parseMessage(serverMessages, event.data);
      if (!message) return console.warn('Ignoring bad server message', event.data);
      for (const handler of this.handlers.get(message.t) ?? []) handler(message.d);
    };
    ws.onclose = () => {
      if (this.stopped) return;
      this.onClose();
      setTimeout(() => this.connect(), this.retryMs);
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
