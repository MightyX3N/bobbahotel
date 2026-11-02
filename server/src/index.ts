import { WebSocketServer, WebSocket } from 'ws';
import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { join as pjoin, normalize, extname } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import os from 'node:os';
import { PUBLIC_URL, STAFF, initAuth, safeNext, steamLoginUrl, verifySteam, makeSession, cookieFor, steamidFromCookie, endSession } from './auth.ts';
import { findPath, type Grid } from './path.ts';

const PORT = Number(process.env.PORT ?? 8080);
const DB_FILE = process.env.DB_FILE ?? 'hotel.db';
const DATA = process.env.ROOMS_JSON ?? new URL('../../data/rooms.json', import.meta.url).pathname;
const LOG: { n: number; t: number; line: string }[] = []; let logN = 0;
function log(line: string) { LOG.push({ n: ++logN, t: Date.now(), line }); if (LOG.length > 1000) LOG.shift(); console.log(line); }
const STEP_MS = 480; // Habbo walks one tile every ~0.5s

const SPRITES = process.env.SPRITES_DIR ?? new URL('../../sprites', import.meta.url).pathname;
const ORIGIN = process.env.ALLOW_ORIGIN ?? '*';
type Layout = { floor?: string; wall?: string; id: string; name: string; access?: string; maxUsers: number; door: [number, number] | null; map: string[] };
const data = JSON.parse(readFileSync(DATA, 'utf8')) as {
  layouts: Record<string, Layout>;
  public: { id: string; name: string; description: string; layout: string }[];
};

// ---- database ------------------------------------------------------------------
const db = new DatabaseSync(DB_FILE);
db.exec(`
CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, name TEXT UNIQUE COLLATE NOCASE, token TEXT, look TEXT, created INTEGER, last_room TEXT);
CREATE TABLE IF NOT EXISTS chat_log(id INTEGER PRIMARY KEY, room TEXT, user_id INTEGER, text TEXT, at INTEGER);
`);
for (const [col, def] of [['steamid', 'TEXT'], ['banned', 'INTEGER DEFAULT 0'], ['ban_reason', 'TEXT'], ['muted_until', 'INTEGER DEFAULT 0']])
  if (!(db.prepare('PRAGMA table_info(users)').all() as any[]).some(c => c.name === col)) db.exec(`ALTER TABLE users ADD COLUMN ${col} ${def}`);
db.exec('CREATE TABLE IF NOT EXISTS rooms(id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, name TEXT NOT NULL, description TEXT, layout TEXT NOT NULL, floor TEXT, wall TEXT, created INTEGER)');
db.exec('CREATE UNIQUE INDEX IF NOT EXISTS users_steam ON users(steamid) WHERE steamid IS NOT NULL');
initAuth(db);
const qBySteam = db.prepare('SELECT * FROM users WHERE steamid = ?');
const qById = db.prepare('SELECT * FROM users WHERE id = ?');
const qInsertSteam = db.prepare('INSERT INTO users(name, steamid, look, created) VALUES(?,?,?,?)');
const qRoomsAll = db.prepare('SELECT r.*, u.name owner FROM rooms r JOIN users u ON u.id = r.owner_id ORDER BY r.id');
const qRoomInsert = db.prepare('INSERT INTO rooms(owner_id, name, description, layout, floor, wall, created) VALUES(?,?,?,?,?,?,?)');
const qRoomCount = db.prepare('SELECT COUNT(*) c FROM rooms WHERE owner_id = ?');
const qSetLook = db.prepare('UPDATE users SET look = ? WHERE id = ?');
const qByName = db.prepare('SELECT * FROM users WHERE name = ?');
const qInsert = db.prepare('INSERT INTO users(name, token, look, created) VALUES(?,?,?,?)');
const qLast = db.prepare('UPDATE users SET last_room = ? WHERE id = ?');
const qLog = db.prepare('INSERT INTO chat_log(room, user_id, text, at) VALUES(?,?,?,?)');

// ---- rooms ---------------------------------------------------------------------
type Look = { sex: 'm' | 'f'; body: number; hair: number; top: number; bottom: number; shoes: number };
const rnd = (n: number) => 1 + Math.floor(Math.random() * n);
const newLook = (): Look => ({ sex: Math.random() < 0.5 ? 'm' : 'f', body: rnd(4), hair: rnd(10), top: rnd(15), bottom: rnd(10), shoes: rnd(10) });
type Player = {
  id: number; name: string; look: Look; ws: WebSocket; room: Room | null;
  x: number; y: number; z: number; dir: number; path: [number, number][]; lastChat: number; steam?: string; mutedUntil: number;
};
class Room {
  floor = 'stone'; wall = 'whitecheck'; ownerId = 0; owner = ''; desc = '';
  id: string; name: string; layout: Layout; grid: Grid; players = new Map<number, Player>();
  constructor(id: string, name: string, layout: Layout) {
    this.id = id; this.name = name; this.layout = layout;
    this.grid = layout.map.map(r => [...r].map(c => (c === 'x' ? -1 : parseInt(c, 36))));
  }
  send(msg: object, except?: Player) {
    const s = JSON.stringify(msg);
    for (const p of this.players.values()) if (p !== except && p.ws.readyState === 1) p.ws.send(s);
  }
  pub(p: Player) { return { id: p.id, name: p.name, look: p.look, x: p.x, y: p.y, z: p.z, dir: p.dir }; }
}
const rooms = new Map<string, Room>();
const PUB_STYLE: Record<string, [string, string]> = { lobby: ['stone', 'bone'], cafe: ['checkboard', 'classyred'], rooftop: ['stone', 'sea'], plaza: ['stone', 'beigeyellow'] };
for (const r of data.public) { const room = new Room('pub:' + r.id, r.name, data.layouts[r.layout]); [room.floor, room.wall] = PUB_STYLE[r.id] ?? ['stone', 'bone']; rooms.set('pub:' + r.id, room); }
const FREE_LAYOUTS = Object.values(data.layouts).filter(l => l.access === 'free' && l.id !== 'model_s');
const LAYOUT_LIST = FREE_LAYOUTS.map(l => ({ id: l.id, name: l.name, max: l.maxUsers, tiles: l.map.join('').replace(/x/g, '').length, map: l.map, door: l.door }));
const FLOORS = ['stone', 'checkboard', 'whitecheck', 'woodlight', 'woodbright', 'concrete', 'natural', 'classyblue', 'classyred'];
const WALLS = ['whitecheck', 'bone', 'stone', 'beigeyellow', 'sea', 'classyred', 'classyblue', 'woodlight', 'brick'];
function loadGuestRoom(r: any) {
  const lay = data.layouts[r.layout]; if (!lay) return null;
  const room = new Room('g:' + r.id, r.name, lay);
  room.ownerId = r.owner_id; room.owner = r.owner; room.desc = r.description ?? '';
  room.floor = r.floor ?? 'stone'; room.wall = r.wall ?? 'whitecheck';
  rooms.set(room.id, room); return room;
}
for (const r of qRoomsAll.all() as any[]) loadGuestRoom(r);
function createRoom(owner: { id: number; name: string }, name: string, desc: string, layout: string): Room | string {
  const lay = FREE_LAYOUTS.find(l => l.id === layout); if (!lay) return 'Unknown layout';
  name = name.replace(/[\u0000-\u001f]/g, '').trim().slice(0, 30);
  if (name.length < 3) return 'Room name must be at least 3 characters';
  if ((qRoomCount.get(owner.id) as any).c >= 10) return 'You can have at most 10 rooms';
  const res = qRoomInsert.run(owner.id, name, desc.replace(/[\u0000-\u001f]/g, '').slice(0, 100), layout, 'stone', 'whitecheck', Date.now());
  return loadGuestRoom({ id: res.lastInsertRowid, owner_id: owner.id, owner: owner.name, name, description: desc, layout, floor: 'stone', wall: 'whitecheck' })!;
}
function roomList(forId?: number) {
  return {
    t: 'rooms',
    rooms: [...rooms.values()].map(r => ({
      id: r.id, name: r.name, users: r.players.size, max: r.layout.maxUsers, pub: r.id.startsWith('pub:'),
      owner: r.owner, mine: !!forId && r.ownerId === forId, desc: r.desc || (data.public.find(p => 'pub:' + p.id === r.id)?.description ?? ''),
    })),
  };
}
const validLook = (l: any): l is Look => l && (l.sex === 'm' || l.sex === 'f') && [['body', 4], ['hair', 10], ['top', 15], ['bottom', 10], ['shoes', 10]].every(([k, n]) => Number.isInteger(l[k as string]) && l[k as string] >= 1 && l[k as string] <= (n as number));

function leave(p: Player) {
  const r = p.room; if (!r) return;
  r.players.delete(p.id); p.room = null; p.path = [];
  r.send({ t: 'leave', id: p.id });
}
function join(p: Player, id: string) {
  const r = rooms.get(id);
  if (!r) return;
  if (r.players.size >= r.layout.maxUsers) return p.ws.send(JSON.stringify({ t: 'error', msg: 'Room is full' }));
  leave(p);
  const d = r.layout.door ?? [0, 0];
  // spawn on the door tile (or the nearest free walkable tile)
  let [x, y] = d;
  if ((r.grid[y]?.[x] ?? -1) < 0) outer: for (let rad = 1; rad < 20; rad++) for (let dy = -rad; dy <= rad; dy++) for (let dx = -rad; dx <= rad; dx++)
    if ((r.grid[y + dy]?.[x + dx] ?? -1) >= 0) { x += dx; y += dy; break outer; }
  p.x = x; p.y = y; p.z = r.grid[y][x]; p.dir = 2; p.path = [];
  p.room = r; r.players.set(p.id, p);
  qLast.run(r.id, p.id);
  p.ws.send(JSON.stringify({ t: 'room', id: r.id, name: r.name, map: r.layout.map, floor: r.floor, wall: r.wall, door: d, you: p.id, users: [...r.players.values()].map(u => r.pub(u)) }));
  r.send({ t: 'join', user: r.pub(p) }, p);
}

// ---- walking tick --------------------------------------------------------------
function dirOf(dx: number, dy: number) { // Habbo dirs: 0=N(-y) 1=NE 2=E(+x) 3=SE 4=S 5=SW 6=W 7=NW
  return ({ '0,-1': 0, '1,-1': 1, '1,0': 2, '1,1': 3, '0,1': 4, '-1,1': 5, '-1,0': 6, '-1,-1': 7 } as Record<string, number>)[`${Math.sign(dx)},${Math.sign(dy)}`] ?? 2;
}
setInterval(() => {
  for (const r of rooms.values()) for (const p of r.players.values()) {
    const nx = p.path.shift(); if (!nx) continue;
    // someone may have stepped there; re-plan if blocked
    if ([...r.players.values()].some(o => o !== p && o.x === nx[0] && o.y === nx[1] && !o.path.length)) { p.path = []; continue; }
    p.dir = dirOf(nx[0] - p.x, nx[1] - p.y); p.x = nx[0]; p.y = nx[1]; p.z = r.grid[p.y][p.x];
    r.send({ t: 'step', id: p.id, x: p.x, y: p.y, z: p.z, dir: p.dir, ms: STEP_MS, last: p.path.length === 0 });
  }
}, STEP_MS);

// ---- network -------------------------------------------------------------------
const MIME: Record<string, string> = { '.png': 'image/png' };
const ADMIN_HTML = new URL('./admin.html', import.meta.url).pathname;
const online = new Map<number, Player>();
const json = (res: import('node:http').ServerResponse, code: number, o: unknown) => { res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(o)); };
const body = (req: import('node:http').IncomingMessage) => new Promise<any>(r => { let b = ''; req.on('data', c => { b += c; if (b.length > 4096) req.destroy(); }); req.on('end', () => { try { r(JSON.parse(b || '{}')); } catch { r({}); } }); });
const isStaff = (steamid: string | null) => !!steamid && STAFF.has(steamid);

function kick(p: Player, msg: string) { p.ws.send(JSON.stringify({ t: 'kicked', msg })); p.ws.close(); }
const dbBytes = () => { try { return statSync(DB_FILE).size; } catch { return 0; } };

async function adminApi(req: import('node:http').IncomingMessage, res: import('node:http').ServerResponse, url: string, query: URLSearchParams, steam: string) {
  if (req.method === 'POST' && req.headers.origin !== PUBLIC_URL) return json(res, 403, { error: 'bad origin' });
  const who = `staff ${steam}`;
  if (url === '/admin/api/state') {
    return json(res, 200, {
      now: Date.now(), uptime: process.uptime(), rss: process.memoryUsage().rss, load: os.loadavg(), cpus: os.cpus().length, totalMem: os.totalmem(), freeMem: os.freemem(),
      dbBytes: dbBytes(), users: (db.prepare('SELECT COUNT(*) c FROM users').get() as any).c, banned: (db.prepare('SELECT COUNT(*) c FROM users WHERE banned=1').get() as any).c,
      online: [...online.values()].map(p => ({ id: p.id, name: p.name, room: p.room?.name ?? '-', steam: p.steam ?? null, muted: p.mutedUntil > Date.now() })),
      rooms: [...rooms.values()].map(r => ({ id: r.id, name: r.name, users: r.players.size, max: r.layout.maxUsers })),
    });
  }
  if (url === '/admin/api/log') { const since = Number(query.get('since') ?? 0); return json(res, 200, { lines: LOG.filter(l => l.n > since), last: logN }); }
  if (url === '/admin/api/chat') {
    const q = '%' + (query.get('q') ?? '').replace(/[%_]/g, '') + '%', u = '%' + (query.get('user') ?? '').replace(/[%_]/g, '') + '%';
    return json(res, 200, db.prepare('SELECT c.at, c.room, u.id uid, u.name, c.text FROM chat_log c JOIN users u ON u.id = c.user_id WHERE c.text LIKE ? AND u.name LIKE ? ORDER BY c.id DESC LIMIT 200').all(q, u));
  }
  if (url === '/admin/api/bans') return json(res, 200, db.prepare('SELECT id, name, steamid, ban_reason FROM users WHERE banned = 1').all());
  if (url === '/admin/api/users') {
    const u = '%' + (query.get('q') ?? '').replace(/[%_]/g, '') + '%';
    return json(res, 200, db.prepare('SELECT id, name, steamid, created, banned, muted_until FROM users WHERE name LIKE ? ORDER BY id DESC LIMIT 100').all(u));
  }
  if (req.method !== 'POST') return json(res, 404, { error: 'not found' });
  const b = await body(req); const id = Number(b.id) | 0; const p = online.get(id);
  switch (url) {
    case '/admin/api/kick': if (!p) return json(res, 404, { error: 'not online' }); log(`[admin] ${who} kicked ${p.name}`); kick(p, 'You were kicked by staff'); break;
    case '/admin/api/mute': { const until = Date.now() + Math.min(Math.max(Number(b.minutes) || 10, 1), 10080) * 60000; db.prepare('UPDATE users SET muted_until=? WHERE id=?').run(until, id); if (p) p.mutedUntil = until; log(`[admin] ${who} muted user ${id} until ${new Date(until).toISOString()}`); break; }
    case '/admin/api/unmute': db.prepare('UPDATE users SET muted_until=0 WHERE id=?').run(id); if (p) p.mutedUntil = 0; log(`[admin] ${who} unmuted user ${id}`); break;
    case '/admin/api/ban': { const reason = String(b.reason ?? '').slice(0, 200); db.prepare('UPDATE users SET banned=1, ban_reason=? WHERE id=?').run(reason, id); if (p) kick(p, 'You are banned: ' + reason); log(`[admin] ${who} banned user ${id}: ${reason}`); break; }
    case '/admin/api/unban': db.prepare('UPDATE users SET banned=0, ban_reason=NULL WHERE id=?').run(id); log(`[admin] ${who} unbanned user ${id}`); break;
    case '/admin/api/announce': { const text = String(b.text ?? '').slice(0, 200).trim(); if (!text) return json(res, 400, { error: 'empty' }); for (const r of rooms.values()) r.send({ t: 'announce', text }); log(`[admin] ${who} announced: ${text}`); break; }
    case '/admin/api/restart': log(`[admin] ${who} restarted the server`); json(res, 200, { ok: true }); return void setTimeout(() => process.exit(0), 300);
    default: return json(res, 404, { error: 'not found' });
  }
  json(res, 200, { ok: true });
}

const http = createServer(async (req, res) => {
  try {
    const u = new URL(req.url ?? '/', PUBLIC_URL), url = decodeURIComponent(u.pathname);
    // CORS only for the public API and sprites (the admin panel is same-origin only)
    if (!url.startsWith('/admin')) {
      res.setHeader('Access-Control-Allow-Origin', ORIGIN);
      if (ORIGIN !== '*') { res.setHeader('Access-Control-Allow-Credentials', 'true'); res.setHeader('Vary', 'Origin'); }
    }
    const cookie = req.headers.cookie;
    if (url.startsWith('/sprites/')) {
      const f = pjoin(SPRITES, normalize(url.slice(8)).replace(/^(\.\.[\/\\])+/, ''));
      if (f.startsWith(SPRITES) && existsSync(f) && statSync(f).isFile() && MIME[extname(f)]) {
        res.writeHead(200, { 'Content-Type': MIME[extname(f)], 'Cache-Control': 'public, max-age=86400' });
        return void createReadStream(f).pipe(res);
      }
    } else if (url === '/auth/steam') {
      res.writeHead(302, { Location: steamLoginUrl(safeNext(u.searchParams.get('next'))) }); return void res.end();
    } else if (url === '/auth/steam/return') {
      const steam = await verifySteam(u.searchParams);
      if (!steam) { res.writeHead(403, { 'Content-Type': 'text/plain' }); return void res.end('Steam login failed'); }
      log(`[auth] steam login ${steam}`);
      res.writeHead(302, { 'Set-Cookie': cookieFor(makeSession(steam)), Location: safeNext(u.searchParams.get('next')) }); return void res.end();
    } else if (url === '/auth/dev' && process.env.ALLOW_DEV_LOGIN === '1' && PUBLIC_URL.startsWith('http://localhost')) { // local testing only
      res.writeHead(302, { 'Set-Cookie': cookieFor(makeSession(u.searchParams.get('steamid') ?? '0')), Location: safeNext(u.searchParams.get('next')) }); return void res.end();
    } else if (url === '/auth/logout') {
      endSession(cookie); res.writeHead(302, { 'Set-Cookie': cookieFor('', true), Location: safeNext(u.searchParams.get('next')) }); return void res.end();
    } else if (url === '/api/me') {
      const steam = steamidFromCookie(cookie); const row = steam ? qBySteam.get(steam) as any : null;
      return json(res, 200, { steam, name: row?.name ?? null, staff: isStaff(steam) });
    } else if (url === '/admin') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Frame-Options': 'DENY', 'Content-Security-Policy': "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors 'none'" });
      return void res.end(readFileSync(ADMIN_HTML));
    } else if (url.startsWith('/admin/api/')) {
      const steam = steamidFromCookie(cookie);
      if (!isStaff(steam)) return json(res, 403, { error: 'staff only' });
      return void await adminApi(req, res, url, u.searchParams, steam!);
    }
    res.writeHead(404); res.end();
  } catch (e) { log('[http error] ' + e); res.writeHead(500); res.end(); }
});
const wss = new WebSocketServer({ server: http, maxPayload: 4096 });
http.listen(PORT);
wss.on('connection', (ws, req) => {
  let me: Player | null = null;
  const send = (o: object) => ws.send(JSON.stringify(o));
  const steam = steamidFromCookie(req.headers.cookie);
  ws.on('message', raw => {
    let m: any; try { m = JSON.parse(raw.toString()); } catch { return; }
    if (m.t === 'login' && !me) {
      let row: any;
      if (steam) {
        row = qBySteam.get(steam);
        if (!row) { // first time with this Steam account: pick a name
          const name = String(m.name ?? '').trim();
          if (!/^[A-Za-z0-9_.\-]{3,16}$/.test(name)) return send({ t: 'need_name', msg: 'Choose a name (3-16 letters, numbers or . _ -)' });
          if (qByName.get(name)) return send({ t: 'need_name', msg: 'That name is taken' });
          qInsertSteam.run(name, steam, JSON.stringify(newLook()), Date.now());
          row = qBySteam.get(steam);
        }
      } else {
        const name = String(m.name ?? '').trim();
        if (!/^[A-Za-z0-9_.\-]{3,16}$/.test(name)) return send({ t: 'error', msg: 'Name must be 3-16 letters, numbers or . _ -' });
        row = qByName.get(name);
        if (row) { if (!row.token || row.token !== m.token) return send({ t: 'error', msg: 'That name is taken' }); }
        else { const token = randomBytes(16).toString('hex'); qInsert.run(name, token, JSON.stringify(newLook()), Date.now()); row = qByName.get(name); }
      }
      if (row.banned) return send({ t: 'error', msg: 'You are banned: ' + (row.ban_reason ?? '') });
      if (online.has(row.id)) return send({ t: 'error', msg: 'Already logged in' });
      me = { id: row.id, name: row.name, look: JSON.parse(row.look), ws, room: null, x: 0, y: 0, z: 0, dir: 2, path: [], lastChat: 0, steam: steam ?? undefined, mutedUntil: row.muted_until ?? 0 };
      online.set(me.id, me);
      log(`[login] ${me.name}${steam ? ' (steam)' : ' (guest)'}`);
      send({ t: 'welcome', id: me.id, name: me.name, token: steam ? null : row.token, look: me.look, steam: !!steam });
      send({ t: 'layouts', layouts: LAYOUT_LIST });
      if (!(qRoomCount.get(me.id) as any).c) createRoom(me, me.name + "'s room", '', 'model_a');
      send(roomList(me.id));
      join(me, 'pub:lobby');
      return;
    }
    if (!me) return;
    if (m.t === 'rooms') send(roomList(me.id));
    else if (m.t === 'create_room') {
      const r = createRoom(me, String(m.name ?? ''), String(m.desc ?? ''), String(m.layout ?? ''));
      if (typeof r === 'string') return send({ t: 'error', msg: r });
      log(`[room] ${me.name} created "${r.name}" (${r.layout.id})`); join(me, r.id);
    } else if (m.t === 'look') {
      if (!validLook(m.look)) return;
      const l = m.look as Look; me.look = { sex: l.sex, body: l.body, hair: l.hair, top: l.top, bottom: l.bottom, shoes: l.shoes };
      qSetLook.run(JSON.stringify(me.look), me.id);
      me.room?.send({ t: 'look', id: me.id, look: me.look });
    } else if (m.t === 'join' && typeof m.room === 'string') { join(me, m.room); log(`[room] ${me.name} -> ${me.room?.name}`); }
    else if (m.t === 'walk' && me.room) {
      const x = Number(m.x) | 0, y = Number(m.y) | 0;
      const blocked = new Set<string>();
      for (const o of me.room.players.values()) if (o !== me) blocked.add(o.x + ',' + o.y);
      me.path = findPath(me.room.grid, me.x, me.y, x, y, blocked) ?? [];
    } else if (m.t === 'chat' && me.room) {
      const now = Date.now(); if (now - me.lastChat < 400) return; me.lastChat = now;
      const text = String(m.text ?? '').slice(0, 100).trim(); if (!text) return;
      if (me.mutedUntil > now) return send({ t: 'error', msg: 'You are muted' });
      qLog.run(me.room.id, me.id, text, now);
      log(`[chat] ${me.room.name} | ${me.name}: ${text}`);
      me.room.send({ t: 'chat', id: me.id, name: me.name, text });
    }
  });
  ws.on('close', () => { if (me) { leave(me); online.delete(me.id); log(`[logout] ${me.name}`); } });
});
log(`Bobba Hotel server listening on :${PORT} (db ${DB_FILE}, ${rooms.size} rooms, ${STAFF.size} staff, sprites ${SPRITES})`);
