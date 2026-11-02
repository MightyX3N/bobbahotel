// The HTTP + WebSocket server. Kept separate from index.ts so tests can start it on a free port.
import http from 'node:http';
import { WebSocketServer, type WebSocket } from 'ws';
import {
  clientMessages,
  encodeMessage,
  parseMessage,
  PROTOCOL_VERSION,
  type ClientMessage,
  type ServerMessage,
} from '@bobba/shared';
import type { Config } from './config.ts';

const MAX_MESSAGE_BYTES = 64 * 1024;

export interface App {
  server: http.Server;
  close(): Promise<void>;
}

export function createApp(config: Pick<Config, 'allowOrigin' | 'version'>): App {
  const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MESSAGE_BYTES });

  const server = http.createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    if (req.method === 'GET' && url.pathname === '/api/health') {
      return sendJson(res, 200, { ok: true, version: config.version, protocol: PROTOCOL_VERSION });
    }
    sendJson(res, 404, { error: 'not_found' });
  });

  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    const origin = req.headers.origin;
    const originOk = config.allowOrigin.length === 0 || (origin !== undefined && config.allowOrigin.includes(origin));
    if (url.pathname !== '/ws' || !originOk) {
      socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
  });

  wss.on('connection', (ws) => onConnection(ws, config.version));

  return {
    server,
    close: () =>
      new Promise<void>((resolve) => {
        for (const ws of wss.clients) ws.terminate();
        wss.close();
        server.close(() => resolve());
      }),
  };
}

function onConnection(ws: WebSocket, version: string): void {
  const send = (message: ServerMessage) => ws.send(encodeMessage(message));

  ws.on('message', (data, isBinary) => {
    if (isBinary) return ws.close(1003, 'text only');
    const message = parseMessage(clientMessages, data.toString());
    if (!message) return send({ t: 'error', d: { code: 'bad_message', message: 'Unknown or malformed message' } });
    handle(message);
  });

  function handle(message: ClientMessage): void {
    switch (message.t) {
      case 'hello':
        if (message.d.protocol !== PROTOCOL_VERSION) {
          send({ t: 'error', d: { code: 'old_client', message: 'Please reload the page' } });
          ws.close(4000, 'protocol mismatch');
          return;
        }
        send({ t: 'welcome', d: { server: version, protocol: PROTOCOL_VERSION } });
        return;
    }
  }
}

function sendJson(res: http.ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
}
