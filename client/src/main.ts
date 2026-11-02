import { Application, Assets, Container, Graphics, Rectangle, Sprite, Text, Texture } from 'pixi.js';
import { initUI, hideUI, uiHandle } from './ui';
import { FW, FH, AX, AY, ROW, layerPaths, type Look } from './avatar';
import { S, changed } from './ui/state';
import { size, artScale, artCorner, covers, standHeight, hasOnTop, seatFacesAway, type Def, type Item } from '../../shared/furni';

const params = new URLSearchParams(location.search);
const WS_URL = params.get('server') ?? (import.meta.env.VITE_WS as string | undefined) ?? (location.hostname === 'localhost' ? 'ws://localhost:8080' : `wss://${location.host}/ws`);
const TW = 64, TH = 32, WALL_H = 110;
const HTTP = WS_URL.replace(/^ws/, 'http').replace(/\/ws$/, '');
const texCache = new Map<string, Promise<Texture | null>>();
const texNow = new Map<string, Texture>();
const loadTex = (path: string) => {
  let p = texCache.get(path);
  if (!p) { p = Assets.load<Texture>(HTTP + '/sprites/' + path).then(t => { t.source.scaleMode = 'nearest'; texNow.set(path, t); return t; }).catch(() => null); texCache.set(path, p); }
  return p;
};
const frameCache = new Map<string, Texture>();
function frameTex(path: string, base: Texture, row: number, frame: number) {
  const k = path + row + ',' + frame; let t = frameCache.get(k);
  if (!t) { t = new Texture({ source: base.source, frame: new Rectangle(frame * FW, row * FH, FW, FH) }); frameCache.set(k, t); }
  return t;
}

type U = { id: number; name: string; look: Look; x: number; y: number; z: number; dir: number; sit?: boolean };
type View = { sit: boolean; mt?: ReturnType<typeof setTimeout>; key?: string; u: U; g: Container; layers: Sprite[]; bodyC: Container; moving: boolean; anim: string; paths: string[]; seed: number; sx: number; sy: number; tx: number; ty: number; t: number; ms: number; label?: Text; bubble?: Container; bubbleT: number };

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
  ws.onclose = () => { hideUI(); $('login').classList.remove('hidden'); if (!$('err').textContent) $('err').textContent = 'Disconnected from the hotel'; };
  ws.onmessage = e => handle(JSON.parse(e.data));
}
const send = (o: object) => ws.readyState === 1 && ws.send(JSON.stringify(o));

function handle(m: any) {
  uiHandle(m);
  switch (m.t) {
    case 'error': case 'need_name': $('err').textContent = m.msg; break;
    case 'kicked': $('err').textContent = m.msg; break;
    case 'welcome':
      if (m.token) localStorage.setItem('bh_token:' + m.name.toLowerCase(), m.token);
      myName = m.name; meId = m.id;
      $('login').classList.add('hidden');
      initUI({ http: HTTP, send, me: { id: m.id, name: m.name, look: m.look, steam: !!m.steam }, logout: () => { if (m.steam) location.href = HTTP + '/auth/logout?next=/'; else { ws.close(); } } });
      break;
    case 'room': enterRoom(m); break;
    case 'look': { const v = views.get(m.id); if (v) { v.u.look = m.look; v.anim = ''; v.key = undefined; } break; }
    case 'join': addUser(m.user); break;
    case 'leave': { const v = views.get(m.id); if (v) { world.removeChild(v.g); views.delete(m.id); } break; }
    case 'step': {
      const v = views.get(m.id); if (!v) break;
      v.sx = v.g.x; v.sy = v.g.y; v.u.dir = m.dir; v.moving = true; clearTimeout(v.mt); v.mt = setTimeout(() => { v.moving = false; }, m.last ? m.ms : m.ms + 250); const p = iso(m.x, m.y, m.z); v.tx = p.x; v.ty = p.y; v.t = 0; v.ms = m.ms;
      v.u.x = m.x; v.u.y = m.y; v.u.z = m.z; v.sit = false; v.g.zIndex = (m.x + m.y) * 10 + 5;
      break;
    }
    case 'sit': {
      const v = views.get(m.id); if (!v) break;
      v.sit = true; v.moving = false; v.u.dir = m.dir; v.u.z = m.z; const p = iso(v.u.x, v.u.y, m.z); v.sx = v.tx = p.x; v.sy = v.ty = p.y; v.t = 1; v.g.position.set(p.x, p.y); avZ(v); v.key = undefined;
      break;
    }
    case 'item_add': addItem(m.item); refreshSitters(); break;
    case 'item_move': { const iv = itemViews.get(m.item.id); if (iv) { iv.it = m.item; layoutItem(iv); if (S.selected?.id === m.item.id) { S.selected = m.item; changed(); } } refreshSitters(); break; }
    case 'item_remove': { const iv = itemViews.get(m.id); if (iv) { world.removeChild(iv.sp); iv.sp.destroy(); itemViews.delete(m.id); if (S.selected?.id === m.id) select(null); } refreshSitters(); break; }
    case 'item_state': { const iv = itemViews.get(m.id); if (iv) { iv.it.state = m.state; if (S.selected?.id === m.id) changed(); } break; }
    case 'chat': {
      const v = views.get(m.id); if (v) say(v, m.text);
      break;
    }
  }
  if (m.t === 'join' || m.t === 'leave') send({ t: 'rooms' });
}

async function enterRoom(m: any) {
  for (const v of views.values()) world.removeChild(v.g);
  views.clear(); curRoom = m.id; clearItems(); cancelGhost(); select(null);
  style = { floor: m.floor, wall: m.wall };
  grid = m.map.map((r: string) => [...r].map(c => (c === 'x' ? -1 : parseInt(c, 36))));
  await drawFloor();
  for (const it of m.items ?? []) addItem(it);
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
  if (u.sit) setTimeout(() => avZ(views.get(u.id)!), 0);
  views.set(u.id, { sit: !!u.sit, u, g, bodyC, layers: [], moving: false, anim: '', paths: [], seed: u.id * 0.37, sx: p.x, sy: p.y, tx: p.x, ty: p.y, t: 1, ms: 1, label, bubbleT: 0 });
}
/** Show the right layer pictures for the avatar's pose and frame. */
async function pose(v: View, time: number) {
  const anim = v.sit ? 'sit' : v.moving ? 'walk' : 'idle', fps = v.sit ? 0 : v.moving ? 8.3 : 6;
  const frame = v.sit ? 0 : Math.floor(time / 1000 * fps + v.seed * 3) % 8, row = ROW[v.u.dir] ?? 0;
  if (anim !== v.anim) {
    v.anim = anim; v.paths = layerPaths(v.u.look, anim);
    const texs = await Promise.all(v.paths.map(loadTex));
    v.bodyC.removeChildren(); v.key = undefined; v.layers = texs.map(t => { const s = new Sprite(); s.position.set(-AX, -AY); s.visible = !!t; v.bodyC.addChild(s); return s; });
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

// ---- furniture -------------------------------------------------------------------
type IV = { it: Item; d: Def; sp: Sprite; frame: number; shown: string };
const itemViews = new Map<number, IV>();
const hitCache = new Map<string, ImageData | null>();
const frameFiles = (iv: IV) => iv.d.anim?.length ? (iv.it.state === 0 ? iv.d.anim : [iv.d.off ?? iv.d.anim[0]]) : [iv.d.file];

/** Put a sprite where a piece of furniture with back corner (x, y) belongs. */
function placeSprite(sp: Sprite, d: Def, x: number, y: number, flip: number, z: number) {
  const A = d.art, k = artScale(d, flip), [fx, fy] = artCorner(d, flip), c = iso(x - 0.5 + fx, y - 0.5 + fy, z);
  const ax = A?.fx ?? (sp.texture.width / 2), ay = A?.fy ?? sp.texture.height;
  sp.scale.set(flip ? -k : k, k);
  sp.position.set(Math.round(flip ? c.x + ax * k : c.x - ax * k), Math.round(c.y - ay * k));
}
const depth = (d: Def, x: number, y: number, flip: number, z: number) => { const [w, dd] = size(d, flip); return d.flat ? -500 + z : (x + y + w + dd - 2) * 10 + 3 + Math.min(z, 9) * 0.1; };
function layoutItem(iv: IV) {
  const { it, d, sp } = iv; placeSprite(sp, d, it.x, it.y, it.flip, (grid[it.y]?.[it.x] ?? 0) + it.z); sp.zIndex = depth(d, it.x, it.y, it.flip, it.z);
}
function addItem(it: Item) {
  const d = S.defs[it.furni]; if (!d) return;
  const old = itemViews.get(it.id); if (old) { world.removeChild(old.sp); old.sp.destroy(); }
  const sp = new Sprite(Texture.EMPTY), iv: IV = { it, d, sp, frame: -1, shown: '' };
  world.addChild(sp); itemViews.set(it.id, iv);
  Promise.all([...new Set([...(d.anim ?? []), d.file, d.off ?? d.file])].map(f => loadTex('furni/' + f))).then(() => { iv.shown = ''; animateItem(iv, 0); });
}
function animateItem(iv: IV, time: number) {
  const files = frameFiles(iv), i = files.length > 1 ? Math.floor(time / 1000 * (iv.d.fps ?? 8)) % files.length : 0, f = files[i];
  if (f === iv.shown) return;
  const t = texNow.get('furni/' + f); if (!t) return;
  iv.shown = f; iv.sp.texture = t; layoutItem(iv);
}
function clearItems() { for (const iv of itemViews.values()) { world.removeChild(iv.sp); iv.sp.destroy(); } itemViews.clear(); }
/** Seated avatars are drawn over their seat, or under it when the seat's back is towards the viewer. */
function avZ(v: View) {
  if (!v.sit) { v.g.zIndex = (v.u.x + v.u.y) * 10 + 5; return; }
  for (const iv of itemViews.values()) if (iv.d.seat && covers(iv.d, iv.it, v.u.x, v.u.y)) { v.g.zIndex = iv.sp.zIndex + (seatFacesAway(iv.d, iv.it.flip) ? -0.5 : 0.5); return; }
  v.g.zIndex = (v.u.x + v.u.y) * 10 + 5;
}
function refreshSitters() { for (const v of views.values()) avZ(v); }

function alphaAt(iv: IV, lx: number, ly: number) {
  const t = iv.sp.texture, u = (lx - iv.sp.x) / iv.sp.scale.x + t.frame.x, v = (ly - iv.sp.y) / iv.sp.scale.y + t.frame.y;
  if (u < t.frame.x || v < t.frame.y || u >= t.frame.x + t.frame.width || v >= t.frame.y + t.frame.height) return 0;
  const key = iv.shown; let img = hitCache.get(key);
  if (img === undefined) {
    img = null; const res = t.source.resource as CanvasImageSource | undefined;
    if (res) { const c = document.createElement('canvas'); c.width = t.source.width; c.height = t.source.height; const x = c.getContext('2d', { willReadFrequently: true })!; x.drawImage(res, 0, 0); try { img = x.getImageData(0, 0, c.width, c.height); } catch { img = null; } }
    hitCache.set(key, img);
  }
  if (!img) return 255;
  return img.data[((Math.floor(v) * img.width) + Math.floor(u)) * 4 + 3];
}
function itemAt(px: number, py: number): IV | null {
  const lx = px - world.x, ly = py - world.y;
  const hits = [...itemViews.values()].filter(iv => iv.shown && alphaAt(iv, lx, ly) > 40).sort((a, b) => b.sp.zIndex - a.sp.zIndex);
  return hits.find(h => !h.d.flat) ?? hits[0] ?? null;
}

// ---- selecting, placing, moving ---------------------------------------------------
let ghost: { kind: 'place' | 'move'; id: number; furni: string; flip: number; sp: Sprite; x: number; y: number } | null = null;
const ghostG = new Graphics(); ghostG.zIndex = 99998; world.addChild(ghostG);
function select(iv: IV | null) {
  for (const o of itemViews.values()) o.sp.tint = 0xffffff;
  S.selected = iv ? iv.it : null; if (iv) iv.sp.tint = 0xffffaa; changed();
}
function cancelGhost() {
  if (!ghost) return;
  world.removeChild(ghost.sp); ghost.sp.destroy(); ghost = null; ghostG.clear();
  for (const iv of itemViews.values()) iv.sp.alpha = 1;
}
function startGhost(kind: 'place' | 'move', id: number, furni: string, flip: number, x = 0, y = 0) {
  cancelGhost(); const d = S.defs[furni]; if (!d) return;
  const sp = new Sprite(); const t = texNow.get('furni/' + d.file); if (t) sp.texture = t; else loadTex('furni/' + d.file).then(tt => { if (tt && ghost?.sp === sp) { sp.texture = tt; updateGhost(); } });
  sp.alpha = 0.8; world.addChild(sp);
  ghost = { kind, id, furni, flip, sp, x, y };
  if (kind === 'move') { const iv = itemViews.get(id); if (iv) iv.sp.alpha = 0.25; }
  updateGhost();
}
function ghostValid() {
  if (!ghost) return false; const d = S.defs[ghost.furni], { x, y, flip } = ghost;
  const [w, dd] = size(d, flip); let base: number | undefined;
  for (let i = 0; i < w; i++) for (let j = 0; j < dd; j++) { const h = grid[y + j]?.[x + i] ?? -1; if (h < 0) return false; if (base === undefined) base = h; else if (h !== base) return false; }
  return standHeight([...itemViews.values()].map(v => v.it), S.defs, d, x, y, flip, ghost.kind === 'move' ? ghost.id : -1) !== null;
}
function updateGhost() {
  if (!ghost) return; const d = S.defs[ghost.furni], ok = ghostValid(), { x, y, flip } = ghost;
  const base = grid[y]?.[x] ?? 0, z = ok ? (standHeight([...itemViews.values()].map(v => v.it), S.defs, d, x, y, flip, ghost.kind === 'move' ? ghost.id : -1) ?? 0) : 0;
  placeSprite(ghost.sp, d, x, y, flip, base + z); ghost.sp.zIndex = 99999; ghost.sp.tint = ok ? 0xbbffbb : 0xff8888;
  ghostG.clear(); const [w, dd] = size(d, flip);
  for (let i = 0; i < w; i++) for (let j = 0; j < dd; j++) { const p = iso(x + i, y + j, (grid[y + j]?.[x + i] ?? base) + z); ghostG.poly([p.x, p.y - TH / 2, p.x + TW / 2, p.y, p.x, p.y + TH / 2, p.x - TW / 2, p.y]).fill({ color: ok ? 0x44ff44 : 0xff4444, alpha: 0.35 }); }
}
function rotateGhostOrSelected() {
  if (ghost) { ghost.flip = ghost.flip ? 0 : 1; updateGhost(); }
  else if (S.selected && S.edit) send({ t: 'rotate', id: S.selected.id });
}
S.startPlace = id => { const it = S.inv.find(i => i.id === id); if (it) { select(null); startGhost('place', id, it.furni, 0, ghost?.x ?? 0, ghost?.y ?? 0); } };
S.itemAction = a => {
  const it = S.selected; if (!it) return;
  if (a === 'move' && S.edit) startGhost('move', it.id, it.furni, it.flip, it.x, it.y);
  else if (a === 'rotate' && S.edit) send({ t: 'rotate', id: it.id });
  else if (a === 'pickup' && S.edit) { send({ t: 'pickup', id: it.id }); select(null); }
  else if (a === 'use') send({ t: 'use', id: it.id });
  else if (a === 'sit') { const d = S.defs[it.furni]; if (d) send({ t: 'walk', x: it.x, y: it.y }); }
};
window.addEventListener('keydown', e => {
  if ((e.target as HTMLElement)?.tagName === 'INPUT') return;
  if (e.key === 'Escape') { cancelGhost(); select(null); }
  else if (e.key === 'r' || e.key === 'R') rotateGhostOrSelected();
});

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
  const t = tileAt(e.offsetX, e.offsetY);
  if (ghost) { if (t && (t[0] !== ghost.x || t[1] !== ghost.y)) { ghost.x = t[0]; ghost.y = t[1]; updateGhost(); } hover.clear(); return; }
  hover.clear(); if (!t) return;
  const p = iso(t[0], t[1], grid[t[1]][t[0]]);
  hover.poly([p.x, p.y - TH / 2, p.x + TW / 2, p.y, p.x, p.y + TH / 2, p.x - TW / 2, p.y]).fill({ color: 0xffffff, alpha: 0.35 }).stroke({ width: 2, color: 0xffffff });
});
app.canvas.addEventListener('contextmenu', e => { e.preventDefault(); cancelGhost(); });
app.canvas.addEventListener('pointerdown', e => {
  if (e.button !== 0) return;
  const t = tileAt(e.offsetX, e.offsetY);
  if (ghost) {
    if (t && ghostValid()) { const g = ghost; send({ t: g.kind, id: g.id, x: g.x, y: g.y, flip: g.flip }); if (g.kind === 'move') cancelGhost(); else if (!S.inv.some(i => i.id !== g.id && i.furni === g.furni)) cancelGhost(); else { /* keep placing more of the same */ const next = S.inv.find(i => i.id !== g.id && i.furni === g.furni)!; startGhost('place', next.id, next.furni, g.flip, g.x, g.y); } }
    return;
  }
  const iv = itemAt(e.offsetX, e.offsetY);
  if (iv) {
    select(iv);
    const walkable = iv.d.flat || iv.d.stairs || iv.d.walkable;
    if (walkable && t) send({ t: 'walk', x: t[0], y: t[1] });
    return;
  }
  select(null);
  if (t) send({ t: 'walk', x: t[0], y: t[1] });
});
app.canvas.addEventListener('dblclick', e => {
  const iv = itemAt(e.offsetX, e.offsetY); if (!iv) return;
  if (iv.d.seat) send({ t: 'walk', x: iv.it.x, y: iv.it.y }); else if (iv.d.anim) send({ t: 'use', id: iv.it.id });
});

app.ticker.add(tk => {
  const dt = tk.deltaMS;
  for (const iv of itemViews.values()) if (iv.d.anim && iv.d.anim.length > 1) animateItem(iv, performance.now());
  for (const v of views.values()) {
    pose(v, performance.now());
    if (v.t < 1) { v.t = Math.min(1, v.t + dt / v.ms); v.g.x = v.sx + (v.tx - v.sx) * v.t; v.g.y = v.sy + (v.ty - v.sy) * v.t; }
    if (v.bubble) { v.bubbleT -= dt; if (v.bubbleT <= 0) { v.g.removeChild(v.bubble); v.bubble = undefined; } }
  }
});

try { const f = await (await fetch(HTTP + '/api/furni')).json(); S.defs = f.furni; S.pages = f.pages; } catch { /* the shop stays empty */ }
let steamed = false;
fetch(HTTP + '/api/me', { credentials: 'include' }).then(r => r.json()).then(me => {
  if (!me.steam) return;
  steamed = true; $('steam').classList.add('hidden');
  $('who').textContent = me.name ? `Logged in with Steam as ${me.name}` : 'Logged in with Steam. Choose your hotel name:';
  if (me.name) { ($('name') as HTMLInputElement).classList.add('hidden'); connect(me.name); }
}).catch(() => {});
$('steam').onclick = () => { location.href = HTTP + '/auth/steam?next=' + encodeURIComponent(location.pathname); };
$('go').onclick = () => { $('err').textContent = ''; connect(($('name') as HTMLInputElement).value.trim()); };
($('name') as HTMLInputElement).onkeydown = e => { if (e.key === 'Enter') $('go').click(); };
(window as any).__bh = { views, send, S };
