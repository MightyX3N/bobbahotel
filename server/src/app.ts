// The HTTP + WebSocket server. Kept separate from index.ts so tests can start it on a free port.
import http from 'node:http';
import { WebSocketServer, type WebSocket } from 'ws';
import {
  clientMessages,
  encodeMessage,
  nameProblem,
  parseMessage,
  PROTOCOL_VERSION,
  type ClientMessage,
  type ServerMessage,
} from '@bobba/shared';
import { Auth, type Fetch, type Session } from './auth.ts';
import type { Config } from './config.ts';
import type { Content } from './content.ts';
import type { Db } from './db.ts';
import { Room } from './room.ts';
import { Users, type User } from './users.ts';

const MAX_MESSAGE_BYTES = 16 * 1024;
const MAX_BODY_BYTES = 4 * 1024;

export interface AppOptions {
  config: Pick<Config, 'allowOrigin' | 'version' | 'publicUrl'>;
  db: Db;
  content: Content;
  /** For tests: replaces the HTTP client used to check Steam logins. */
  fetch?: Fetch;
  /** For tests: rooms don't tick on their own; call room.tick(). */
  manualTicks?: boolean;
}

export interface App {
  server: http.Server;
  lobby: Room;
  close(): Promise<void>;
}

interface Client {
  user: User;
  ws: WebSocket;
  room: Room | null;
  send(message: ServerMessage): void;
}

export function createApp(opts: AppOptions): App {
  const { config, db, content } = opts;
  const users = new Users(db);
  const auth = new Auth(db, { publicUrl: config.publicUrl, ...(opts.fetch ? { fetch: opts.fetch } : {}) });
  const lobbyInfo = content.publicRooms[0];
  if (!lobbyInfo) throw new Error('rooms.json has no public rooms');
  const lobby = new Room(lobbyInfo.id, lobbyInfo.name, lobbyInfo.layout, { autoTick: !opts.manualTicks });
  const clients = new Map<number, Client>();
  const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MESSAGE_BYTES });

  const originOk = (origin: string | undefined) =>
    config.allowOrigin.length === 0 || (origin !== undefined && config.allowOrigin.includes(origin));

  // ---- HTTP ----

  const server = http.createServer((req, res) => {
    handleHttp(req, res).catch((err) => {
      console.error('HTTP error', err);
      if (!res.headersSent) sendJson(res, 500, { error: 'server_error' });
    });
  });

  async function handleHttp(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    const url = new URL(req.url ?? '/', 'http://localhost');
    const route = `${req.method} ${url.pathname}`;

    if (req.method === 'POST' && !originOk(req.headers.origin)) return sendJson(res, 403, { error: 'bad_origin' });

    switch (route) {
      case 'GET /api/health':
        return sendJson(res, 200, { ok: true, version: config.version, protocol: PROTOCOL_VERSION });

      case 'GET /api/me': {
        const session = auth.fromCookie(req.headers.cookie);
        const user = session?.userId != null ? users.byId(session.userId) : null;
        if (user) return sendJson(res, 200, { state: 'in', user: { id: user.id, name: user.name, guest: user.guest } });
        if (session?.steamId) return sendJson(res, 200, { state: 'name' });
        return sendJson(res, 200, { state: 'out' });
      }

      case 'GET /api/auth/steam':
        return redirect(res, auth.steamLoginUrl());

      case 'GET /api/auth/steam/return': {
        const steamId = await auth.verifySteam(url.searchParams);
        if (!steamId) return redirect(res, '/?login=failed');
        // Several accounts per Steam account come later; for now the first one is used.
        const account = users.bySteamId(steamId)[0];
        const token = auth.start({ steamId, ...(account ? { userId: account.id } : {}) });
        return redirect(res, '/', auth.cookie(token));
      }

      case 'POST /api/auth/name': {
        const session = auth.fromCookie(req.headers.cookie);
        if (!session?.steamId || session.userId != null) return sendJson(res, 403, { error: 'not_allowed' });
        const name = await readName(req);
        if (typeof name !== 'string') return sendJson(res, 400, { error: name.error });
        try {
          const user = users.create({ name, steamId: session.steamId });
          auth.bindUser(session, user.id);
          return sendJson(res, 200, { ok: true });
        } catch (err) {
          if ((err as Error).message === 'name_taken') return sendJson(res, 409, { error: 'name_taken' });
          throw err;
        }
      }

      case 'POST /api/auth/guest': {
        const name = await readName(req);
        if (typeof name !== 'string') return sendJson(res, 400, { error: name.error });
        try {
          const user = users.create({ name, guest: true });
          const token = auth.start({ userId: user.id });
          return sendJson(res, 200, { ok: true }, auth.cookie(token));
        } catch (err) {
          if ((err as Error).message === 'name_taken') return sendJson(res, 409, { error: 'name_taken' });
          throw err;
        }
      }

      case 'POST /api/auth/logout': {
        const session = auth.fromCookie(req.headers.cookie);
        if (session) {
          auth.end(session);
          if (session.userId != null) clients.get(session.userId)?.ws.close(4001, 'logged out');
        }
        return sendJson(res, 200, { ok: true }, auth.clearCookie());
      }
    }
    sendJson(res, 404, { error: 'not_found' });
  }

  // ---- WebSocket ----

  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    if (url.pathname !== '/ws' || !originOk(req.headers.origin)) {
      socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
      return;
    }
    const session: Session | null = auth.fromCookie(req.headers.cookie);
    const user = session?.userId != null ? users.byId(session.userId) : null;
    if (!user) {
      socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => onConnection(ws, user));
  });

  function onConnection(ws: WebSocket, user: User): void {
    // One connection per account: a new login replaces the old one.
    const old = clients.get(user.id);
    if (old) {
      old.send({ t: 'error', d: { code: 'replaced', message: 'You logged in somewhere else' } });
      old.ws.close(4002, 'replaced');
      leave(old);
    }
    users.touch(user.id);
    const client: Client = {
      user,
      ws,
      room: null,
      send: (message) => {
        if (ws.readyState === ws.OPEN) ws.send(encodeMessage(message));
      },
    };
    let greeted = false;
    clients.set(user.id, client);

    ws.on('message', (data, isBinary) => {
      if (isBinary) return ws.close(1003, 'text only');
      const message = parseMessage(clientMessages, data.toString());
      if (!message) return client.send({ t: 'error', d: { code: 'bad_message', message: 'Unknown or malformed message' } });
      if (!greeted && message.t !== 'hello') return;
      handle(message);
    });
    ws.on('close', () => {
      if (clients.get(user.id) === client) {
        clients.delete(user.id);
        leave(client);
        users.touch(user.id);
      }
    });

    function handle(message: ClientMessage): void {
      switch (message.t) {
        case 'hello':
          if (greeted) return;
          if (message.d.protocol !== PROTOCOL_VERSION) {
            client.send({ t: 'error', d: { code: 'old_client', message: 'A new version is out. Reloading…' } });
            ws.close(4000, 'protocol mismatch');
            return;
          }
          greeted = true;
          client.send({ t: 'welcome', d: { server: config.version, protocol: PROTOCOL_VERSION, me: { id: user.id, name: user.name, guest: user.guest } } });
          // Until there is a navigator, everyone goes straight to the lobby.
          client.room = lobby;
          lobby.enter({ id: user.id, name: user.name, look: user.look, send: client.send });
          return;
        case 'walk':
          client.room?.walkTo(user.id, message.d.x, message.d.y);
          return;
        case 'chat':
          client.room?.say(user.id, message.d.text);
          return;
      }
    }
  }

  function leave(client: Client): void {
    client.room?.leave(client.user.id);
    client.room = null;
  }

  // ---- housekeeping ----
  const cleanup = () => {
    auth.removeExpired();
    users.removeStaleGuests();
  };
  cleanup();
  const cleanupTimer = setInterval(cleanup, 3600 * 1000);
  cleanupTimer.unref();

  return {
    server,
    lobby,
    close: () =>
      new Promise<void>((resolve) => {
        clearInterval(cleanupTimer);
        lobby.stop();
        for (const ws of wss.clients) ws.terminate();
        wss.close();
        server.close(() => resolve());
      }),
  };
}

async function readName(req: http.IncomingMessage): Promise<string | { error: string }> {
  const body = await readJson(req);
  const name = typeof body === 'object' && body !== null ? (body as { name?: unknown }).name : undefined;
  if (typeof name !== 'string') return { error: 'bad_request' };
  const problem = nameProblem(name.trim());
  return problem ? { error: problem } : name.trim();
}

async function readJson(req: http.IncomingMessage): Promise<unknown> {
  if (!(req.headers['content-type'] ?? '').startsWith('application/json')) return null;
  let size = 0;
  const chunks: Buffer[] = [];
  for await (const chunk of req as AsyncIterable<Buffer>) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) return null;
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    return null;
  }
}

function sendJson(res: http.ServerResponse, status: number, body: unknown, cookie?: string): void {
  const headers: http.OutgoingHttpHeaders = { 'content-type': 'application/json', 'cache-control': 'no-store' };
  if (cookie) headers['set-cookie'] = cookie;
  res.writeHead(status, headers);
  res.end(JSON.stringify(body));
}

function redirect(res: http.ServerResponse, location: string, cookie?: string): void {
  const headers: http.OutgoingHttpHeaders = { location, 'cache-control': 'no-store' };
  if (cookie) headers['set-cookie'] = cookie;
  res.writeHead(302, headers);
  res.end();
}
