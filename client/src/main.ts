import { Application, Assets, Container, Graphics, Rectangle, Sprite, Text, Texture } from 'pixi.js';

const params = new URLSearchParams(location.search);
const WS_URL = params.get('server') ?? (import.meta.env.VITE_WS as string | undefined) ?? 'ws://localhost:8080';
const TW = 64, TH = 32, WALL_H = 110;
const HTTP = WS_URL.replace(/^ws/, 'http');
const FW = 64, FH = 80, AX = 32, AY = 75; // avatar frame size and where the feet are
const ROW = [2, 2, 1, 1, 0, 0, 3, 3]; // facing (0=N .. 7=NW, clockwise) -> sheet row (0 down-left, 1 down-right, 2 up-right, 3 up-left)
type Look = { sex: string; body: number; hair: number; top: number; bottom: number; shoes: number };
const texCache = new Map<string, Promise<Texture | null>>();
const loadTex = (path: string) => {
  let p = texCache.get(path);
  if (!p) { p = Assets.load<Texture>(HTTP + '/sprites/' + path).then(t => { t.source.scaleMode = 'nearest'; return t; }).catch(() => null); texCache.set(path, p); }
  return p;
};
const frameCache = new Map<string, Texture>();
function frameTex(path: string, base: Texture, row: number, frame: number) {
  const k = path + row + ',' + frame; let t = frameCache.get(k);
  if (!t) { t = new Texture({ source: base.source, frame: new Rectangle(frame * FW, row * FH, FW, FH) }); frameCache.set(k, t); }
  return t;
}
const two = (n: number) => String(n).padStart(2, '0');
/** Layer pictures for one animation, bottom to top (tops 13-15 go over the hair). */
function layerPaths(l: Look, anim: string) {
  const f = (part: string, n: number, suf = '') => `cozy/${l.sex}/${anim}/${part}_${two(n)}${suf}.png`;
  const list = [f('body', l.body), f('shoes', l.shoes), f('bottom', l.bottom)];
  const high = l.top >= 13;
  if (high) list.push(f('hair', l.hair, '_tucked'));
  list.push(f('top', l.top));
  if (!high) list.push(f('hair', l.hair));
  return list;
}

type U = { id: number; name: string; look: Look; x: number; y: number; z: number; dir: number };
type View = { mt?: ReturnType<typeof setTimeout>; key?: string; u: U; g: Container; layers: Sprite[]; bodyC: Container; moving: boolean; anim: string; paths: string[]; seed: number; sx: number; sy: number; tx: number; ty: number; t: number; ms: number; label?: Text; bubble?: Container; bubbleT: number };

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const iso = (x: number, y: number, z = 0) => ({ x: (x - y) * (TW / 2), y: (x + y) * (TH / 2) - z * (TH / 2) });

const app = new Application();
await app.init({ resizeTo: $('game'), background: 0x0e1a22, antialias: true });
$('game').appendChild(app.canvas);
const world = new Container(); world.sortableChildren = true;
app.stage.addChild(world);
const floor = new Container(); floor.zIndex = -1000;
const hover = new Graphics(); hover.zIndex = -999;
world.addChild(floor, hover);

let ws: WebSocket, meId = 0, grid: number[][] = [], views = new Map<number, View>(), curRoom = '';
let myName = '';
let style = { floor: 'stone', wall: 'whitecheck' };

function connect(name: string) {
  ws = new WebSocket(WS_URL);
  const token = localStorage.getItem('bh_token:' + name.toLowerCase()) ?? undefined;
  ws.onopen = () => ws.send(JSON.stringify({ t: 'login', name, token }));
  ws.onerror = () => ($('err').textContent = 'Cannot reach the hotel server');
  ws.onclose = () => { $('login').classList.remove('hidden'); ['title', 'rooms', 'chat'].forEach(i => $(i).classList.add('hidden')); };
  ws.onmessage = e => handle(JSON.parse(e.data));
}
const send = (o: object) => ws.readyState === 1 && ws.send(JSON.stringify(o));

function handle(m: any) {
  switch (m.t) {
    case 'error': $('err').textContent = m.msg; break;
    case 'welcome':
      localStorage.setItem('bh_token:' + m.name.toLowerCase(), m.token);
      myName = m.name; meId = m.id;
      $('login').classList.add('hidden'); ['title', 'rooms', 'chat'].forEach(i => $(i).classList.remove('hidden'));
      break;
    case 'rooms': {
      const el = $('rooms'); el.innerHTML = '<b>Rooms</b>';
      for (const r of m.rooms) {
        const d = document.createElement('div'); d.textContent = `${r.name} (${r.users}/${r.max})`; d.title = r.desc;
        d.onclick = () => send({ t: 'join', room: r.id }); el.appendChild(d);
      }
      const own = document.createElement('div'); own.textContent = 'My room'; own.onclick = () => send({ t: 'join', room: 'own' }); el.appendChild(own);
      break;
    }
    case 'room': enterRoom(m); break;
    case 'join': addUser(m.user); break;
    case 'leave': { const v = views.get(m.id); if (v) { world.removeChild(v.g); views.delete(m.id); } break; }
    case 'step': {
      const v = views.get(m.id); if (!v) break;
      v.sx = v.g.x; v.sy = v.g.y; v.u.dir = m.dir; v.moving = true; clearTimeout(v.mt); v.mt = setTimeout(() => { v.moving = false; }, m.last ? m.ms : m.ms + 250); const p = iso(m.x, m.y, m.z); v.tx = p.x; v.ty = p.y; v.t = 0; v.ms = m.ms;
      v.u.x = m.x; v.u.y = m.y; v.u.z = m.z; v.g.zIndex = (m.x + m.y) * 10 + 5;
      break;
    }
    case 'chat': {
      const v = views.get(m.id); if (v) say(v, m.text);
      break;
    }
  }
  if (m.t === 'join' || m.t === 'leave') send({ t: 'rooms' });
}

async function enterRoom(m: any) {
  for (const v of views.values()) world.removeChild(v.g);
  views.clear(); curRoom = m.id;
  style = { floor: m.floor, wall: m.wall };
  grid = m.map.map((r: string) => [...r].map(c => (c === 'x' ? -1 : parseInt(c, 36))));
  $('title').textContent = m.name;
  await drawFloor();
  for (const u of m.users) addUser(u);
  // centre camera on the room
  const w = grid[0].length, h = grid.length, c = iso(w / 2, h / 2);
  world.position.set(app.screen.width / 2 - c.x, app.screen.height / 2 - c.y + 40);
  send({ t: 'rooms' });
}

function shade(c: number, f: number) { const r = ((c >> 16) & 255) * f, g = ((c >> 8) & 255) * f, b = (c & 255) * f; return (r << 16) | (g << 8) | b; }

async function drawFloor() {
  const old = floor.removeChildren(); old.forEach(c => c.destroy());
  const h = grid.length, w = grid[0].length;
  const ok = (x: number, y: number) => (grid[y]?.[x] ?? -1) >= 0;
  const [ft, wl, wr] = await Promise.all([loadTex(`tiles/floor_${style.floor}.png`), loadTex(`tiles/wall_l_${style.wall}.png`), loadTex(`tiles/wall_r_${style.wall}.png`)]);
  const g = new Graphics(); floor.addChild(g);
  const put = (t: Texture, x: number, y: number) => { const s = new Sprite(t); s.position.set(Math.floor(x), Math.floor(y)); floor.addChild(s); };
  // walls first (back edges), three pieces high like the gamemode
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (!ok(x, y)) continue;
    const c = iso(x, y, grid[y][x]); // tile centre; the sprite's top corner is 16px above it
    if (!ok(x - 1, y) && wl) for (let l = 0; l < 3; l++) put(wl, c.x - 48, c.y - 16 - 63 - l * 40 + 16);
    if (!ok(x, y - 1) && wr) for (let l = 0; l < 3; l++) put(wr, c.x - 16, c.y - 16 - 47 - l * 40);
  }
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (!ok(x, y)) continue;
    const z = grid[y][x], c = iso(x, y, 0);
    if (ft) {
      // raised floor: stack the tile every quarter step so the side looks solid
      for (let st = 0; st <= z * 4; st++) put(ft, c.x - 32, c.y - 32 - st * 4);
    } else {
      const p = iso(x, y, z), col = (x + y) % 2 ? 0x9b7a4f : 0xa88556;
      g.poly([p.x, p.y - TH / 2, p.x + TW / 2, p.y, p.x, p.y + TH / 2, p.x - TW / 2, p.y]).fill(col);
    }
  }
}

function addUser(u: U) {
  const g = new Container(), bodyC = new Container();
  const label = new Text({ text: u.name, style: { fontFamily: 'Verdana', fontSize: 11, fill: 0xffffff, stroke: { color: 0x000000, width: 3 } } });
  label.anchor.set(0.5, 1); label.y = -AY - 6;
  const sh = new Graphics(); sh.ellipse(0, 0, 14, 6).fill({ color: 0x000000, alpha: 0.25 });
  g.addChild(sh, bodyC, label);
  const p = iso(u.x, u.y, u.z); g.position.set(p.x, p.y);
  g.zIndex = (u.x + u.y) * 10 + 5;
  world.addChild(g);
  views.set(u.id, { u, g, bodyC, layers: [], moving: false, anim: '', paths: [], seed: u.id * 0.37, sx: p.x, sy: p.y, tx: p.x, ty: p.y, t: 1, ms: 1, label, bubbleT: 0 });
}
/** Show the right layer pictures for the avatar's pose and frame. */
async function pose(v: View, time: number) {
  const anim = v.moving ? 'walk' : 'idle', fps = v.moving ? 8.3 : 6;
  const frame = Math.floor(time / 1000 * fps + v.seed * 3) % 8, row = ROW[v.u.dir] ?? 0;
  if (anim !== v.anim) {
    v.anim = anim; v.paths = layerPaths(v.u.look, anim);
    const texs = await Promise.all(v.paths.map(loadTex));
    v.bodyC.removeChildren(); v.layers = texs.map(t => { const s = new Sprite(); s.position.set(-AX, -AY); s.visible = !!t; v.bodyC.addChild(s); return s; });
  }
  if (v.layers.length !== v.paths.length) return;
  const key = anim + row + frame; if (key === v.key) return; v.key = key;
  v.paths.forEach((pth, i) => { const sp = v.layers[i], base = texCache.get(pth); if (!sp || !base) return;
    base.then(b => { if (b) sp.texture = frameTex(pth, b, row, frame); }); });
}

function say(v: View, text: string) {
  if (v.bubble) v.g.removeChild(v.bubble);
  const t = new Text({ text, style: { fontFamily: 'Verdana', fontSize: 12, fill: 0x000000, wordWrap: true, wordWrapWidth: 180 } });
  const b = new Container(), bg = new Graphics();
  bg.roundRect(-6, -4, t.width + 12, t.height + 8, 8).fill(0xffffff).stroke({ width: 2, color: 0x000000 });
  b.addChild(bg, t); b.pivot.set(t.width / 2, t.height + 4); b.y = -AY - 22;
  v.g.addChild(b); v.bubble = b; v.bubbleT = 6000;
  // keep bubbles above everyone
  v.g.zIndex = 100000 + v.u.id;
  setTimeout(() => { v.g.zIndex = (v.u.x + v.u.y) * 10 + 5; }, 6000);
}

// ---- input ---------------------------------------------------------------------
function tileAt(px: number, py: number): [number, number] | null {
  const lx = px - world.x, ly = py - world.y;
  // invert iso for z=0 then check heights
  for (let pass = 0; pass < 2; pass++) {
    const fx = lx / (TW / 2), fy = ly / (TH / 2);
    const x = Math.floor((fx + fy) / 2 + 0.5), y = Math.floor((fy - fx) / 2 + 0.5);
    for (let dz = 0; dz < 6; dz++) {
      const zx = Math.floor(((lx / (TW / 2)) + (ly + dz * TH / 2) / (TH / 2)) / 2 + 0.5), zy = Math.floor((((ly + dz * TH / 2) / (TH / 2)) - lx / (TW / 2)) / 2 + 0.5);
      if (grid[zy]?.[zx] === dz) return [zx, zy];
    }
    if ((grid[y]?.[x] ?? -1) >= 0) return [x, y];
    break;
  }
  return null;
}
app.canvas.addEventListener('pointermove', e => {
  hover.clear(); const t = tileAt(e.offsetX, e.offsetY); if (!t) return;
  const p = iso(t[0], t[1], grid[t[1]][t[0]]);
  hover.poly([p.x, p.y - TH / 2, p.x + TW / 2, p.y, p.x, p.y + TH / 2, p.x - TW / 2, p.y]).fill({ color: 0xffffff, alpha: 0.35 }).stroke({ width: 2, color: 0xffffff });
});
app.canvas.addEventListener('pointerdown', e => { const t = tileAt(e.offsetX, e.offsetY); if (t) send({ t: 'walk', x: t[0], y: t[1] }); });

app.ticker.add(tk => {
  const dt = tk.deltaMS;
  for (const v of views.values()) {
    pose(v, performance.now());
    if (v.t < 1) { v.t = Math.min(1, v.t + dt / v.ms); v.g.x = v.sx + (v.tx - v.sx) * v.t; v.g.y = v.sy + (v.ty - v.sy) * v.t; }
    if (v.bubble) { v.bubbleT -= dt; if (v.bubbleT <= 0) { v.g.removeChild(v.bubble); v.bubble = undefined; } }
  }
});

$('go').onclick = () => { $('err').textContent = ''; connect(($('name') as HTMLInputElement).value.trim()); };
($('name') as HTMLInputElement).onkeydown = e => { if (e.key === 'Enter') $('go').click(); };
($('say') as HTMLInputElement).onkeydown = e => {
  if (e.key !== 'Enter') return; const i = e.target as HTMLInputElement;
  if (i.value.trim()) send({ t: 'chat', text: i.value }); i.value = '';
};
(window as any).__bh = { views, send };
