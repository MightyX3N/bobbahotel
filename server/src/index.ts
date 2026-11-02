import { WebSocketServer, WebSocket } from 'ws';
import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { join as pjoin, normalize, extname } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { findPath, type Grid } from './path.ts';

const PORT = Number(process.env.PORT ?? 8080);
const DB_FILE = process.env.DB_FILE ?? 'hotel.db';
const DATA = process.env.ROOMS_JSON ?? new URL('../../data/rooms.json', import.meta.url).pathname;
const STEP_MS = 480; // Habbo walks one tile every ~0.5s

const SPRITES = process.env.SPRITES_DIR ?? new URL('../../sprites', import.meta.url).pathname;
const ORIGIN = process.env.ALLOW_ORIGIN ?? '*';
type Layout = { floor?: string; wall?: string; id: string; name: string; maxUsers: number; door: [number, number] | null; map: string[] };
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
  x: number; y: number; z: number; dir: number; path: [number, number][]; lastChat: number;
};
class Room {
  floor = 'stone'; wall = 'whitecheck';
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
function guestRoom(userName: string): Room {
  const id = 'own:' + userName.toLowerCase();
  let r = rooms.get(id);
  if (!r) { r = new Room(id, userName + "'s room", data.layouts['model_a']); rooms.set(id, r); }
  return r;
}
function roomList() {
  return {
    t: 'rooms',
    rooms: [...rooms.values()].filter(r => r.id.startsWith('pub:') || r.players.size > 0).map(r => ({
      id: r.id, name: r.name, users: r.players.size, max: r.layout.maxUsers, pub: r.id.startsWith('pub:'),
      desc: data.public.find(p => 'pub:' + p.id === r.id)?.description ?? '',
    })),
  };
}

function leave(p: Player) {
  const r = p.room; if (!r) return;
  r.players.delete(p.id); p.room = null; p.path = [];
  r.send({ t: 'leave', id: p.id });
}
function join(p: Player, id: string) {
  const r = id === 'own' ? guestRoom(p.name) : rooms.get(id);
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
const http = createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', ORIGIN);
  const url = decodeURIComponent((req.url ?? '/').split('?')[0]);
  if (url.startsWith('/sprites/')) {
    const f = pjoin(SPRITES, normalize(url.slice(8)).replace(/^(\.\.[\/\\])+/, ''));
    if (f.startsWith(SPRITES) && existsSync(f) && statSync(f).isFile() && MIME[extname(f)]) {
      res.writeHead(200, { 'Content-Type': MIME[extname(f)], 'Cache-Control': 'public, max-age=86400' });
      return void createReadStream(f).pipe(res);
    }
  }
  res.writeHead(404); res.end();
});
const wss = new WebSocketServer({ server: http, maxPayload: 4096 });
http.listen(PORT);
const online = new Map<number, Player>();
wss.on('connection', ws => {
  let me: Player | null = null;
  const send = (o: object) => ws.send(JSON.stringify(o));
  ws.on('message', raw => {
    let m: any; try { m = JSON.parse(raw.toString()); } catch { return; }
    if (m.t === 'login') {
      const name = String(m.name ?? '').trim();
      if (!/^[A-Za-z0-9_.\-]{3,16}$/.test(name)) return send({ t: 'error', msg: 'Name must be 3-16 letters, numbers or . _ -' });
      let row = qByName.get(name) as any;
      if (row) {
        if (row.token !== m.token) return send({ t: 'error', msg: 'That name is taken' });
      } else {
        const token = randomBytes(16).toString('hex');
        qInsert.run(name, token, JSON.stringify(newLook()), Date.now());
        row = qByName.get(name);
      }
      if (online.has(row.id)) return send({ t: 'error', msg: 'Already logged in' });
      me = { id: row.id, name: row.name, look: JSON.parse(row.look), ws, room: null, x: 0, y: 0, z: 0, dir: 2, path: [], lastChat: 0 };
      online.set(me.id, me);
      send({ t: 'welcome', id: me.id, name: me.name, token: row.token, look: me.look });
      send(roomList());
      join(me, 'pub:lobby');
      return;
    }
    if (!me) return;
    if (m.t === 'rooms') send(roomList());
    else if (m.t === 'join' && typeof m.room === 'string') join(me, m.room);
    else if (m.t === 'walk' && me.room) {
      const x = Number(m.x) | 0, y = Number(m.y) | 0;
      const blocked = new Set<string>();
      for (const o of me.room.players.values()) if (o !== me) blocked.add(o.x + ',' + o.y);
      // continue from the tile the player is walking to next
      me.path = findPath(me.room.grid, me.x, me.y, x, y, blocked) ?? [];
    } else if (m.t === 'chat' && me.room) {
      const now = Date.now(); if (now - me.lastChat < 400) return; me.lastChat = now;
      const text = String(m.text ?? '').slice(0, 100).trim(); if (!text) return;
      qLog.run(me.room.id, me.id, text, now);
      me.room.send({ t: 'chat', id: me.id, name: me.name, text });
    }
  });
  ws.on('close', () => { if (me) { leave(me); online.delete(me.id); } });
});
console.log(`Bobba Hotel server listening (sprites from ${SPRITES}) on :${PORT} (db ${DB_FILE}, ${rooms.size} rooms)`);
