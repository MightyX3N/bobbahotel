// The HTTP + WebSocket server. Kept separate from index.ts so tests can start it on a free port.
import { createReadStream, existsSync } from 'node:fs';
import http from 'node:http';
import { join } from 'node:path';
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
import type { Room } from './room.ts';
import { furniSheetDir } from './furni.ts';
import { Rooms, type Asker } from './rooms.ts';
import { runCommand } from './commands.ts';
import { Users, type User } from './users.ts';

const MAX_MESSAGE_BYTES = 16 * 1024;
const MAX_BODY_BYTES = 4 * 1024;

export interface AppOptions {
  config: Pick<Config, 'allowOrigin' | 'version' | 'publicUrl'> & Partial<Pick<Config, 'staffSteamIds' | 'buildDir'>>;
  db: Db;
  content: Content;
  /** For tests: replaces the HTTP client used to check Steam logins. */
  fetch?: Fetch;
  /** For tests: rooms don't tick on their own; call room.tick(). */
  manualTicks?: boolean;
  /** For tests: how long an avatar stays after its connection drops (default RECONNECT_GRACE_MS). */
  reconnectGraceMs?: number;
}

export interface App {
  server: http.Server;
  rooms: Rooms;
  /** The room everyone starts in. */
  readonly lobby: Room;
  close(): Promise<void>;
}

interface Client {
  user: User;
  ws: WebSocket;
  room: Room | null;
  send(message: ServerMessage): void;
  /** Answered the last heartbeat. */
  alive: boolean;
}

/**
 * How long an avatar stays in its room after the connection drops (a phone switching apps, a
 * network blip). Coming back within this time picks up right where you were.
 */
export const RECONNECT_GRACE_MS = 60_000;
/** The server checks every connection this often; one that doesn't answer is closed. */
const HEARTBEAT_MS = 30_000;

export function createApp(opts: AppOptions): App {
  const { config, db, content } = opts;
  const users = new Users(db);
  const auth = new Auth(db, { publicUrl: config.publicUrl, ...(opts.fetch ? { fetch: opts.fetch } : {}) });
  const rooms = new Rooms(db, content, { autoTick: !opts.manualTicks });
  const clients = new Map<number, Client>();
  /** Players whose connection dropped, kept in their room for RECONNECT_GRACE_MS. */
  const awayClients = new Map<number, { client: Client; timer: ReturnType<typeof setTimeout> }>();
  const staffIds = config.staffSteamIds ?? new Set<string>();
  const isStaff = (u: User) => u.steamId !== null && staffIds.has(u.steamId);
  /** Fresh account info (Club may have changed since login). */
  const meOf = (u: User) => {
    const fresh = users.byId(u.id) ?? u;
    return { id: fresh.id, name: fresh.name, guest: fresh.guest, staff: isStaff(fresh), clubUntil: fresh.clubUntil };
  };
  const askerOf = (u: User): Asker => {
    const me = meOf(u);
    return { id: me.id, staff: me.staff, club: me.clubUntil > Date.now() };
  };
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

    // Built furni sprite sheets (the version in ?v= changes whenever a sheet is rebuilt).
    const sheet = req.method === 'GET' ? /^\/api\/furni\/([a-z0-9_]+)\.png$/.exec(url.pathname) : null;
    if (sheet) {
      const id = sheet[1]!;
      const file = join(furniSheetDir(config.buildDir ?? ''), `${id}.png`);
      if (!content.furniSheets.has(id) || !existsSync(file)) return sendJson(res, 404, { error: 'not_found' });
      res.writeHead(200, { 'content-type': 'image/png', 'cache-control': 'public, max-age=31536000, immutable' });
      createReadStream(file).pipe(res);
      return;
    }

    switch (route) {
      case 'GET /api/health':
        return sendJson(res, 200, { ok: true, version: config.version, protocol: PROTOCOL_VERSION });

      // Furni definitions (what each furni is) and their sheets' frame lists (the pictures
      // themselves come from /sprites/built/furni/<id>.png).
      case 'GET /api/furni':
        return sendJson(res, 200, { status: content.furniStatus, furni: [...content.furni.values()], sheets: Object.fromEntries(content.furniSheets) });

      // Read-only: room lists and floor plans (the same public info the navigator shows), so
      // layouts can be checked outside the game.
      case 'GET /api/rooms':
        return sendJson(res, 200, { rooms: rooms.list('all', url.searchParams.get('q') ?? '', 0) });
      case 'GET /api/room-plan': {
        const plan = rooms.floorPlanOf(url.searchParams.get('id') ?? '');
        return plan ? sendJson(res, 200, plan) : sendJson(res, 404, { error: 'room_not_found' });
      }

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
    const client: Client = {
      user,
      ws,
      room: null,
      send: (message) => {
        if (ws.readyState === ws.OPEN) ws.send(encodeMessage(message));
      },
      alive: true,
    };
    // One connection per account. The new one takes over the avatar where it is: the same player
    // coming back (from another app, a dropped network), or logging in somewhere else, which
    // closes the old connection.
    const old = clients.get(user.id);
    const away = awayClients.get(user.id);
    clients.set(user.id, client);
    if (old) {
      old.send({ t: 'error', d: { code: 'replaced', message: 'You logged in somewhere else' } });
      old.ws.close(4002, 'replaced');
    }
    if (away) {
      clearTimeout(away.timer);
      awayClients.delete(user.id);
    }
    const previous = old ?? away?.client;
    if (previous?.room?.rebind({ id: user.id, name: user.name, look: user.look, send: client.send })) client.room = previous.room;
    users.touch(user.id);
    let greeted = false;
    ws.on('pong', () => (client.alive = true));

    ws.on('message', (data, isBinary) => {
      if (isBinary) return ws.close(1003, 'text only');
      const message = parseMessage(clientMessages, data.toString());
      if (!message) return client.send({ t: 'error', d: { code: 'bad_message', message: 'Unknown or malformed message' } });
      if (!greeted && message.t !== 'hello') return;
      handle(message);
    });
    ws.on('close', () => {
      if (clients.get(user.id) !== client) return;
      clients.delete(user.id);
      users.touch(user.id);
      if (!client.room) return;
      // Keep the avatar in the room for a while, in case they come straight back.
      const timer = setTimeout(() => {
        awayClients.delete(user.id);
        leave(client);
      }, opts.reconnectGraceMs ?? RECONNECT_GRACE_MS);
      timer.unref();
      awayClients.set(user.id, { client, timer });
    });

    function goTo(id: string): void {
      if (client.room?.id === id) return;
      const room = rooms.get(id);
      if (!room || (room.details.staffOnly && !isStaff(user))) return client.send({ t: 'error', d: { code: 'room_not_found', message: 'That room does not exist' } });
      if (room.isFull) return client.send({ t: 'error', d: { code: 'room_full', message: 'That room is full' } });
      leave(client);
      client.room = room;
      room.enter({ id: user.id, name: user.name, look: user.look, send: client.send });
    }

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
          client.send({ t: 'welcome', d: { server: config.version, protocol: PROTOCOL_VERSION, me: meOf(user) } });
          // Back from a dropped connection: the same room, the avatar where it was.
          if (client.room) client.room.sendSnapshot(user.id);
          // Everyone else starts in the lobby (until there is a hotel view).
          else goTo(rooms.lobbyId);
          return;
        case 'ping':
          client.send({ t: 'pong', d: {} });
          return;
        case 'navigator':
          client.send({ t: 'navigator', d: { tab: message.d.tab, query: message.d.query ?? '', rooms: rooms.list(message.d.tab, message.d.query ?? '', user.id, isStaff(user)) } });
          return;
        case 'layouts':
          client.send({ t: 'layouts', d: { layouts: rooms.layouts() } });
          return;
        case 'createRoom': {
          const result = rooms.create(askerOf(user), message.d.name, message.d.description, message.d.layout);
          if (!result.ok) return client.send({ t: 'error', d: { code: result.error, message: result.error } });
          client.send({ t: 'roomCreated', d: { id: result.id } });
          goTo(result.id);
          return;
        }
        case 'goToRoom':
          goTo(message.d.id);
          return;
        case 'saveLayout': {
          const { id, name, map, door, club } = message.d;
          const result = rooms.saveLayout(askerOf(user), { id, name, map, door, club });
          if (!result.ok) return client.send({ t: 'error', d: { code: result.error, message: result.error } });
          client.send({ t: 'layoutSaved', d: { id: result.id } });
          client.send({ t: 'layouts', d: { layouts: rooms.layouts() } });
          return;
        }
        case 'deleteLayout':
          if (rooms.deleteLayout(askerOf(user), message.d.id)) client.send({ t: 'layouts', d: { layouts: rooms.layouts() } });
          return;
        case 'saveRoomFloor': {
          const result = rooms.saveRoomFloor(askerOf(user), message.d.roomId, message.d.map, message.d.door);
          if (!result.ok) return client.send({ t: 'error', d: { code: result.error, message: result.error } });
          // Everyone in the room was moved into the rebuilt room.
          if (result.room) {
            for (const c of clients.values()) if (c.room?.id === message.d.roomId) c.room = result.room;
            for (const a of awayClients.values()) if (a.client.room?.id === message.d.roomId) a.client.room = result.room;
          }
          client.send({ t: 'info', d: { code: 'floor_saved' } });
          return;
        }
        case 'walk':
          client.room?.walkTo(user.id, message.d.x, message.d.y);
          return;
        case 'useFurni': {
          // Staff anywhere; room owners in their own rooms.
          const room = client.room;
          if (room && (isStaff(user) || room.details.ownerId === user.id)) room.useFurni(message.d.uid);
          return;
        }
        case 'chat':
          // ":" starts a command (like Habbo); commands are never shown as chat.
          if (message.d.text.trimStart().startsWith(':')) {
            runCommand(message.d.text.trim(), {
              staff: isStaff(user),
              users,
              reply: (code, vars) => client.send({ t: 'info', d: vars ? { code, vars } : { code } }),
              accountChanged: (id) => {
                const c = clients.get(id);
                if (c) c.send({ t: 'me', d: meOf(c.user) });
              },
            });
            return;
          }
          client.room?.say(user.id, message.d.text);
          return;
      }
    }
  }

  function leave(client: Client): void {
    const room = client.room;
    if (!room) return;
    room.leave(client.user.id);
    client.room = null;
    rooms.left(room);
  }

  // ---- housekeeping ----
  const cleanup = () => {
    auth.removeExpired();
    users.removeStaleGuests();
  };
  cleanup();
  const cleanupTimer = setInterval(cleanup, 3600 * 1000);
  cleanupTimer.unref();
  // Connections that went quiet without closing (a phone that lost signal) are closed, so their
  // avatar's grace period starts.
  const heartbeat = setInterval(() => {
    for (const c of clients.values()) {
      if (!c.alive) {
        c.ws.terminate();
        continue;
      }
      c.alive = false;
      c.ws.ping();
    }
  }, HEARTBEAT_MS);
  heartbeat.unref();

  return {
    server,
    rooms,
    get lobby() {
      return rooms.get(rooms.lobbyId)!;
    },
    close: () =>
      new Promise<void>((resolve) => {
        clearInterval(cleanupTimer);
        clearInterval(heartbeat);
        for (const a of awayClients.values()) clearTimeout(a.timer);
        rooms.stopAll();
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
