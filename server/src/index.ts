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
import { size, covers, standHeight, hasOnTop, seatHeight, seatDir, stairStep, type Defs, type Item } from '../../shared/furni.ts';

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
const FURNI_FILE = process.env.FURNI_JSON ?? new URL('../../data/furni.json', import.meta.url).pathname;
const FURNI_RAW = readFileSync(FURNI_FILE, 'utf8');
const shop = JSON.parse(FURNI_RAW) as { furni: Defs; pages: { id: string; kind: string; items?: [string, number][]; price?: number }[] };
const defs = shop.furni;
const bundles = new Map(shop.pages.filter(p => p.kind === 'bundle' && p.items).map(p => [p.id, p]));
const START_SILVER = 300;
const db = new DatabaseSync(DB_FILE);
db.exec(`
CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, name TEXT UNIQUE COLLATE NOCASE, token TEXT, look TEXT, created INTEGER, last_room TEXT);
CREATE TABLE IF NOT EXISTS chat_log(id INTEGER PRIMARY KEY, room TEXT, user_id INTEGER, text TEXT, at INTEGER);
`);
for (const [col, def] of [['silver', 'INTEGER DEFAULT ' + START_SILVER], ['gold', 'INTEGER DEFAULT 0'], ['steamid', 'TEXT'], ['banned', 'INTEGER DEFAULT 0'], ['ban_reason', 'TEXT'], ['muted_until', 'INTEGER DEFAULT 0']])
  if (!(db.prepare('PRAGMA table_info(users)').all() as any[]).some(c => c.name === col)) db.exec(`ALTER TABLE users ADD COLUMN ${col} ${def}`);
db.exec('CREATE TABLE IF NOT EXISTS rooms(id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, name TEXT NOT NULL, description TEXT, layout TEXT NOT NULL, floor TEXT, wall TEXT, created INTEGER)');
db.exec('CREATE TABLE IF NOT EXISTS items(id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, furni TEXT NOT NULL, room INTEGER, x INTEGER, y INTEGER, flip INTEGER DEFAULT 0, z REAL DEFAULT 0, state INTEGER DEFAULT 0)');
db.exec('CREATE INDEX IF NOT EXISTS items_room ON items(room)'); db.exec('CREATE INDEX IF NOT EXISTS items_owner ON items(owner_id)');
db.exec('CREATE UNIQUE INDEX IF NOT EXISTS users_steam ON users(steamid) WHERE steamid IS NOT NULL');
initAuth(db);
const qItemsIn = db.prepare('SELECT * FROM items WHERE room = ?');
const qInv = db.prepare('SELECT * FROM items WHERE owner_id = ? AND room IS NULL ORDER BY id');
const qItem = db.prepare('SELECT * FROM items WHERE id = ?');
const qItemIns = db.prepare('INSERT INTO items(owner_id, furni) VALUES(?,?)');
const qItemPlace = db.prepare('UPDATE items SET room=?, x=?, y=?, flip=?, z=? WHERE id=?');
const qItemPick = db.prepare('UPDATE items SET room=NULL, x=NULL, y=NULL, flip=0, z=0, state=0 WHERE id=?');
const qItemState = db.prepare('UPDATE items SET state=? WHERE id=?');
const qBal = db.prepare('SELECT silver, gold FROM users WHERE id = ?');
const qPay = db.prepare('UPDATE users SET silver = silver - ? WHERE id = ? AND silver >= ?');
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
  x: number; y: number; z: number; dir: number; sit: number | null; path: [number, number][]; lastChat: number; steam?: string; mutedUntil: number;
};
class Room {
  floor = 'stone'; wall = 'whitecheck'; ownerId = 0; owner = ''; desc = '';
  id: string; name: string; layout: Layout; grid: Grid; players = new Map<number, Player>();
  items = new Map<number, Item>(); private _walk: Grid | null = null;
  /** Floor heights people can walk on: blocked tiles are -1, stairs and seats raise the tile. */
  get walk(): Grid { return this._walk ??= computeWalk(this); }
  dirty() { this._walk = null; }
  get dbId() { return this.id.startsWith('g:') ? Number(this.id.slice(2)) : 0; }
  constructor(id: string, name: string, layout: Layout) {
    this.id = id; this.name = name; this.layout = layout;
    this.grid = layout.map.map(r => [...r].map(c => (c === 'x' ? -1 : parseInt(c, 36))));
  }
  send(msg: object, except?: Player) {
    const s = JSON.stringify(msg);
    for (const p of this.players.values()) if (p !== except && p.ws.readyState === 1) p.ws.send(s);
  }
  pub(p: Player) { return { id: p.id, name: p.name, look: p.look, x: p.x, y: p.y, z: p.z, dir: p.dir, sit: p.sit != null }; }
}
const toItem = (r: any): Item => ({ id: r.id, furni: r.furni, x: r.x, y: r.y, flip: r.flip, z: r.z, state: r.state });
function computeWalk(r: Room): Grid {
  const g = r.grid.map(row => row.slice());
  const stairs = new Set<string>(), raise = new Map<string, number>(), block = new Set<string>();
  for (const it of r.items.values()) {
    const d = defs[it.furni]; if (!d || d.wall) continue;
    const [w, dd] = size(d, it.flip);
    for (let i = 0; i < w; i++) for (let j = 0; j < dd; j++) {
      const k = (it.x + i) + ',' + (it.y + j);
      if (d.stairs) { stairs.add(k); raise.set(k, it.z + stairStep(d, it, it.x + i, it.y + j)); }
      else if (d.seat) { if (!raise.has(k)) raise.set(k, it.z + seatHeight(d)); }
      else if (d.flat || (d.walkable && !d.stack)) { /* rugs and mats: walk over them */ }
      else block.add(k);
    }
  }
  for (const k of block) if (!stairs.has(k) && !raise.has(k)) { const [x, y] = k.split(',').map(Number); if ((g[y]?.[x] ?? -1) >= 0) g[y][x] = -1; }
  for (const [k, v] of raise) { const [x, y] = k.split(',').map(Number); if ((g[y]?.[x] ?? -1) >= 0 && !(block.has(k) && !stairs.has(k))) g[y][x] += v; }
  return g;
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
  for (const it of qItemsIn.all(r.id) as any[]) room.items.set(it.id, toItem(it));
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
  p.x = x; p.y = y; p.z = r.grid[y][x]; p.dir = 2; p.path = []; p.sit = null;
  p.room = r; r.players.set(p.id, p);
  qLast.run(r.id, p.id);
  p.ws.send(JSON.stringify({ t: 'room', id: r.id, name: r.name, map: r.layout.map, floor: r.floor, wall: r.wall, door: d, you: p.id, edit: r.ownerId === p.id, items: [...r.items.values()], users: [...r.players.values()].map(u => r.pub(u)) }));
  r.send({ t: 'join', user: r.pub(p) }, p);
}

function seatAt(r: Room, x: number, y: number): Item | null {
  for (const it of r.items.values()) { const d = defs[it.furni]; if (d?.seat && covers(d, it, x, y)) return it; }
  return null;
}
/** Called when someone stops walking: sit down if they stopped on a free seat. */
function trySit(p: Player) {
  const r = p.room; if (!r || p.path.length || p.sit != null || !r.players.has(p.id)) return;
  const it = seatAt(r, p.x, p.y); if (!it) return;
  if ([...r.players.values()].some(o => o !== p && o.sit === it.id && o.x === p.x && o.y === p.y)) return;
  p.sit = it.id; p.dir = seatDir(defs[it.furni], it.flip);
  r.send({ t: 'sit', id: p.id, dir: p.dir, z: p.z });
}
/** Make anyone whose seat is gone stand up. */
function checkSitters(r: Room) {
  for (const p of r.players.values()) {
    if (p.sit != null) { const it = r.items.get(p.sit); const d = it && defs[it.furni]; if (!it || !d || !covers(d, it, p.x, p.y)) { p.sit = null; p.z = Math.max(0, r.walk[p.y]?.[p.x] ?? r.grid[p.y][p.x]); r.send({ t: 'step', id: p.id, x: p.x, y: p.y, z: p.z, dir: p.dir, ms: 1, last: true }); } }
    else { const z = r.walk[p.y]?.[p.x]; if (z != null && z >= 0 && z !== p.z) { p.z = z; r.send({ t: 'step', id: p.id, x: p.x, y: p.y, z: p.z, dir: p.dir, ms: 1, last: true }); } }
  }
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
    if ((r.walk[nx[1]]?.[nx[0]] ?? -1) < 0) { p.path = []; continue; } // something was put in the way
    p.dir = dirOf(nx[0] - p.x, nx[1] - p.y); p.x = nx[0]; p.y = nx[1]; p.z = r.walk[p.y][p.x];
    r.send({ t: 'step', id: p.id, x: p.x, y: p.y, z: p.z, dir: p.dir, ms: STEP_MS, last: p.path.length === 0 });
    if (!p.path.length) setTimeout(() => trySit(p), STEP_MS);
  }
}, STEP_MS);

// ---- furniture -----------------------------------------------------------------
/** Where may this piece go? Returns the height it stands at, or why not. */
function canPlace(r: Room, d: typeof defs[string], x: number, y: number, flip: number, except: number): { z: number } | string {
  if (d.wall) return 'Wall items cannot be placed yet';
  const [w, dd] = size(d, flip);
  let base: number | undefined;
  for (let i = 0; i < w; i++) for (let j = 0; j < dd; j++) {
    const h = r.grid[y + j]?.[x + i] ?? -1;
    if (h < 0) return 'There is no floor there';
    if (base === undefined) base = h; else if (h !== base) return 'That does not fit on uneven floor';
  }
  const z = standHeight(r.items.values(), defs, d, x, y, flip, except);
  if (z === null) return 'Something is in the way';
  if (!d.flat && !d.seat && !d.stairs && !d.walkable)
    for (const p of r.players.values()) if (p.x >= x && p.x < x + w && p.y >= y && p.y < y + dd) return 'Someone is standing there';
  return { z };
}
const balanceMsg = (id: number) => ({ t: 'balance', ...(qBal.get(id) as any) });
const invMsg = (id: number) => ({ t: 'inventory', items: (qInv.all(id) as any[]).map(r => ({ id: r.id, furni: r.furni })) });
function giveItem(owner: number, furni: string) { return Number(qItemIns.run(owner, furni).lastInsertRowid); }
function furniMsg(me: Player, m: any, send: (o: object) => void) {
  const r = me.room;
  if (m.t === 'inventory') return send(invMsg(me.id));
  if (m.t === 'buy') { // a single piece or a bundle
    const id = String(m.furni ?? ''), b = bundles.get(id), d = defs[id];
    const list: string[] = [], price = b ? (b.price ?? 0) : d && !d.wall ? d.price : -1;
    if (price < 0) return send({ t: 'error', msg: 'That is not for sale' });
    if (b) for (const [f, n] of b.items!) for (let i = 0; i < n; i++) { if (defs[f]) list.push(f); } else list.push(id);
    if (!qPay.run(price, me.id, price).changes) return send({ t: 'error', msg: 'You do not have enough silver' });
    const ids = list.map(f => giveItem(me.id, f));
    log(`[shop] ${me.name} bought ${b ? 'bundle ' : ''}${id} for ${price}`);
    send(balanceMsg(me.id)); send({ t: 'inv_add', items: ids.map((i, k) => ({ id: i, furni: list[k] })) }); send({ t: 'bought', furni: id, count: ids.length });
    return;
  }
  if (!r || r.ownerId !== me.id) return send({ t: 'error', msg: 'You can only do that in your own room' });
  const row = qItem.get(Number(m.id) | 0) as any;
  if (!row || row.owner_id !== me.id) return;
  const d = defs[row.furni]; if (!d) return;
  const x = Number(m.x) | 0, y = Number(m.y) | 0, flip = m.flip ? 1 : 0;
  const changed = () => { r.dirty(); checkSitters(r); };
  if (m.t === 'place') {
    if (row.room != null) return;
    const ok = canPlace(r, d, x, y, flip, -1); if (typeof ok === 'string') return send({ t: 'error', msg: ok });
    qItemPlace.run(r.dbId, x, y, flip, ok.z, row.id);
    const it: Item = { id: row.id, furni: row.furni, x, y, flip, z: ok.z, state: 0 }; r.items.set(it.id, it); changed();
    r.send({ t: 'item_add', item: it }); send({ t: 'inv_remove', id: row.id });
  } else if (m.t === 'move' || m.t === 'rotate') {
    const it = r.items.get(row.id); if (!it) return;
    if (hasOnTop(r.items.values(), defs, it)) return send({ t: 'error', msg: 'Take the things off it first' });
    const nx = m.t === 'rotate' ? it.x : x, ny = m.t === 'rotate' ? it.y : y, nf = m.t === 'rotate' ? (it.flip ? 0 : 1) : flip;
    const ok = canPlace(r, d, nx, ny, nf, it.id); if (typeof ok === 'string') return send({ t: 'error', msg: ok });
    Object.assign(it, { x: nx, y: ny, flip: nf, z: ok.z }); qItemPlace.run(r.dbId, nx, ny, nf, ok.z, it.id); changed();
    r.send({ t: 'item_move', item: it });
  } else if (m.t === 'pickup') {
    const it = r.items.get(row.id); if (!it) return;
    if (hasOnTop(r.items.values(), defs, it)) return send({ t: 'error', msg: 'Take the things off it first' });
    r.items.delete(it.id); qItemPick.run(it.id); changed();
    r.send({ t: 'item_remove', id: it.id }); send({ t: 'inv_add', items: [{ id: it.id, furni: it.furni }] });
  }
}

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
    } else if (url === '/api/furni') {
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=300' }); return void res.end(FURNI_RAW);
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
      me = { id: row.id, name: row.name, look: JSON.parse(row.look), ws, room: null, x: 0, y: 0, z: 0, dir: 2, sit: null, path: [], lastChat: 0, steam: steam ?? undefined, mutedUntil: row.muted_until ?? 0 };
      online.set(me.id, me);
      log(`[login] ${me.name}${steam ? ' (steam)' : ' (guest)'}`);
      send({ t: 'welcome', id: me.id, name: me.name, token: steam ? null : row.token, look: me.look, steam: !!steam });
      send({ t: 'layouts', layouts: LAYOUT_LIST }); send(balanceMsg(me.id)); send(invMsg(me.id));
      if (!(qRoomCount.get(me.id) as any).c) createRoom(me, me.name + "'s room", '', 'model_a');
      send(roomList(me.id));
      join(me, 'pub:lobby');
      return;
    }
    if (!me) return;
    if (['inventory', 'buy', 'place', 'move', 'rotate', 'pickup'].includes(m.t)) return furniMsg(me, m, send);
    if (m.t === 'use' && me.room) { // double-click: switch an animated piece on or off
      const it = me.room.items.get(Number(m.id) | 0), d = it && defs[it.furni];
      if (it && d?.anim) { it.state = it.state ? 0 : 1; qItemState.run(it.state, it.id); me.room.send({ t: 'item_state', id: it.id, state: it.state }); }
      return;
    }
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
      let g = me.room.walk; if ((g[me.y]?.[me.x] ?? -1) < 0) { g = g.map(r => r.slice()); g[me.y][me.x] = me.room.grid[me.y][me.x]; }
      const path = findPath(g, me.x, me.y, x, y, blocked);
      if (path) { me.path = path; me.sit = null; }
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
