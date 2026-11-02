#!/usr/bin/env node
// Turns a pack of loose furni pictures into furni definitions (content/furni/<pack>.json).
//
//   node tools/furni-import.mjs [source folder under sprites/] [pack name]
//   node tools/furni-import.mjs furni salvaje
//
// It groups the pictures into furni and guesses everything it can from the file names and the
// pictures themselves:
//   - Name_1, Name_2, ... that look alike are animation frames of one furni (Name_Off: its
//     switched-off state); ones that don't look alike are separate furni.
//   - Name_A / _B / _C / _D are the directions it faces (when B is A mirrored), or its states (a
//     toolbox opening), or different furni.
//   - The same picture twice is used once; sheets of many furni in one picture are left out.
//   - Real brand names (consoles, computers) get made-up ones.
//   - Floor or wall, sit / walk / stack, from the name.
//   - How many tiles it covers, from the width of the picture and where its front corner is.
// Furni already in the definitions file are left exactly as they are (hand fixes are kept);
// only new ones are added. The pictures themselves are never changed.
import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PNG } from 'pngjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const source = process.argv[2] ?? 'furni';
const pack = process.argv[3] ?? 'salvaje';
const srcDir = join(root, 'sprites', source);
const outFile = join(root, 'content', 'furni', `${pack}.json`);
if (!existsSync(srcDir)) {
  console.error(`No pictures at ${srcDir}`);
  process.exit(1);
}

// ---- pictures ----
const images = new Map();
const load = (name) => {
  if (!images.has(name)) images.set(name, PNG.sync.read(readFileSync(join(srcDir, `${name}.png`))));
  return images.get(name);
};
/** Bounding box of the visible pixels: [left, top, right, bottom) or null if empty. */
function bbox(png) {
  let l = png.width, t = png.height, r = -1, b = -1;
  for (let y = 0; y < png.height; y++) {
    for (let x = 0; x < png.width; x++) {
      if (png.data[(y * png.width + x) * 4 + 3] > 16) {
        if (x < l) l = x;
        if (x > r) r = x;
        if (y < t) t = y;
        if (y > b) b = y;
      }
    }
  }
  return r < 0 ? null : [l, t, r + 1, b + 1];
}
/** How alike two pictures are (0..1): the share of visible pixels that match. */
function alike(a, b, mirrorB = false) {
  if (a.width !== b.width || a.height !== b.height) return 0;
  let same = 0, total = 0;
  for (let y = 0; y < a.height; y++) {
    for (let x = 0; x < a.width; x++) {
      const i = (y * a.width + x) * 4;
      const j = (y * a.width + (mirrorB ? a.width - 1 - x : x)) * 4;
      const va = a.data[i + 3] > 16, vb = b.data[j + 3] > 16;
      if (!va && !vb) continue;
      total++;
      if (va && vb && Math.abs(a.data[i] - b.data[j]) + Math.abs(a.data[i + 1] - b.data[j + 1]) + Math.abs(a.data[i + 2] - b.data[j + 2]) < 48) same++;
    }
  }
  return total ? same / total : 0;
}

// ---- grouping ----
// A group is one furni: per direction, its states, and per state its frames (pictures).
const allFiles = readdirSync(srcDir).filter((f) => f.endsWith('.png')).map((f) => f.slice(0, -4)).sort();
/** The name without "_Tile" (some files have it, some don't). */
const key = (name) => name.replace(/_Tile(?=_|$)/g, '');
const used = new Set();
const groups = []; // { base, dirs: { [dir]: string[][] }, fps? }

// Left out: sheets with many small furni drawn in one picture (each also comes as its own file).
const SHEETS = /^Book_Small_[A-Za-z]+$/;
// Left out: the same picture twice (e.g. one with more empty space around it); the first is kept.
const seen = new Map();
const files = [];
const family = (n) => key(n).replace(/_\d+$/, '');
const familySize = new Map();
for (const f of allFiles) if (/_\d+$/.test(key(f))) familySize.set(family(f), (familySize.get(family(f)) ?? 0) + 1);
const inSequence = (f) => /_\d+$/.test(key(f)) && (familySize.get(family(f)) ?? 0) >= 3;
for (const f of allFiles) {
  if (SHEETS.test(f)) continue;
  const png = load(f);
  const box = bbox(png);
  if (box) {
    const h = createHash('sha1');
    for (let y = box[1]; y < box[3]; y++) h.update(png.data.subarray((y * png.width + box[0]) * 4, (y * png.width + box[2]) * 4));
    const sum = h.digest('hex');
    // Frames of animations (Name_1, Name_2, Name_3…) are always kept: a repeat is a pause.
    if (!inSequence(f)) {
      if (seen.has(sum)) continue;
      seen.set(sum, f);
    }
  }
  files.push(f);
}

// Animations: Name_<n> with at least 3 numbers that look alike. Name_Off is its switched-off state.
const numbered = new Map();
for (const f of files) {
  const m = /^(.*)_(\d+)$/.exec(key(f));
  if (m) (numbered.get(m[1]) ?? numbered.set(m[1], []).get(m[1])).push([Number(m[2]), f]);
}
for (const [base, list] of numbered) {
  if (list.length < 3) continue;
  list.sort((a, b) => a[0] - b[0]);
  const first = load(list[0][1]);
  const second = load(list[1][1]);
  // Frames of one animation look alike; long runs of same-size pictures (a book opening) count too.
  const sameSize = list.every(([, f]) => load(f).width === first.width && load(f).height === first.height);
  if (alike(first, second) < 0.5 && !(sameSize && list.length >= 10)) continue;
  const frames = list.map(([, f]) => f);
  frames.forEach((f) => used.add(f));
  const off = files.find((f) => !used.has(f) && key(f) === `${base}_Off`);
  if (off) used.add(off);
  groups.push({ base, dirs: { 4: off ? [[off], frames] : [frames] }, fps: 8 });
}

// Name_A, _B, _C, _D (a plain Name counts as A when there are B/C/D):
//  - directions, when B is A mirrored (C and D are then the back views);
//  - states, when they are the same size and look alike (a toolbox opening, a door opening);
//  - otherwise different furni that only share a name.
const lettered = new Map();
for (const f of files) {
  if (used.has(f)) continue;
  const m = /^(.*)_([A-E])$/.exec(key(f));
  if (m) (lettered.get(m[1]) ?? lettered.set(m[1], {}).get(m[1]))[m[2]] = f;
}
for (const [base, letters] of lettered) {
  const plain = files.find((f) => !used.has(f) && key(f) === base);
  if (!letters.A && plain) letters.A = plain;
  const a = letters.A && load(letters.A);
  if (!a) continue;
  const b = letters.B && load(letters.B);
  if (b && alike(a, b, true) > 0.6) {
    const dirs = { 4: [[letters.A]], 2: [[letters.B]] };
    if (letters.C) dirs[0] = [[letters.C]];
    if (letters.D) dirs[6] = [[letters.D]];
    for (const l of 'ABCD') if (letters[l]) used.add(letters[l]);
    groups.push({ base, dirs });
    continue;
  }
  const states = Object.keys(letters).sort().map((l) => letters[l]).filter((f) => {
    const p = load(f);
    return p.width === a.width && p.height === a.height && (f === letters.A || alike(a, p) > 0.35);
  });
  if (states.length < 2) continue;
  states.forEach((f) => used.add(f));
  groups.push({ base, dirs: { 4: states.map((f) => [f]) } });
}

// Everything else: one picture, one furni.
for (const f of files) if (!used.has(f)) groups.push({ base: key(f), dirs: { 4: [[f]] } });

// Furni grouped by hand, where the names don't say they belong together.
const MERGE = {
  // The tall server cabinet: door closed, opening, open, and without its door (lights blinking).
  Server_2: ['Server_1'],
  // Closed, then open (animated).
  Macbook_1_Closed: ['Macbook'],
  LavaLamp_9_Off: ['Lava_Lamp'],
};
for (const [into, others] of Object.entries(MERGE)) {
  const target = groups.find((g) => g.base === into);
  if (!target) continue;
  for (const o of others) {
    const i = groups.findIndex((g) => g.base === o);
    if (i < 0) continue;
    target.dirs[4].push(...groups[i].dirs[4]);
    if (groups[i].fps) target.fps = groups[i].fps;
    groups.splice(i, 1);
  }
}

// Names: no real brands (consoles, computers), and a few clearer names.
const NAMES = {
  Atari: ['Comet Classic', 'comet_classic'],
  Dreamcast: ['Hayate Dream', 'hayate_dream'],
  SegaGenesis: ['Hayate Drive', 'hayate_drive'],
  NES: ['Kitsune Home Console', 'kitsune_home'],
  NES_4: ['Kitsune Home Console 2', 'kitsune_home_2'],
  NES_4_B: ['Kitsune Home Console 3', 'kitsune_home_3'],
  SNES: ['Kitsune Super Console', 'kitsune_super'],
  Nintendo_64: ['Kitsune 3D', 'kitsune_3d'],
  Gamecube: ['Kitsune Box', 'kitsune_box'],
  Wii: ['Kitsune Wave', 'kitsune_wave'],
  Nintendo_Switch: ['Kitsune Flip', 'kitsune_flip'],
  Gameboy: ['Kitsune Pocket', 'kitsune_pocket'],
  Gameboy_Advance: ['Kitsune Pocket Plus', 'kitsune_pocket_plus'],
  Playstation: ['Orbit One', 'orbit_1'],
  Playstation_2: ['Orbit Two', 'orbit_2'],
  Playstation_3: ['Orbit Three', 'orbit_3'],
  Playstation_4: ['Orbit Four', 'orbit_4'],
  Playstation_5: ['Orbit Five', 'orbit_5'],
  PSP: ['Orbit Portable', 'orbit_portable'],
  XBox: ['Vortex', 'vortex'],
  XBox_360: ['Vortex Loop', 'vortex_loop'],
  XBox_X: ['Vortex Prime', 'vortex_prime'],
  Macbook_1_Closed: ['Petal Laptop', 'petal_laptop'],
  LavaLamp_9_Off: ['Lava Lamp', 'lava_lamp'],
  NewImac: ['Petal Desktop', 'petal_desktop'],
  OldImac: ['Petal Classic Desktop', 'petal_classic_desktop'],
  WacomTablet: ['Drawing Tablet', 'drawing_tablet'],
  Rumba_Robot: ['Robot Vacuum', 'robot_vacuum'],
  Server_2: ['Server Cabinet', 'server_cabinet'],
  Tool_Box: ['Toolbox', 'toolbox'],
};

// ---- guesses ----
const WALL = /(poster|picture|painting|wall_clock|window|diploma|corkboard|^switch|tap_wall|canvas|mirror|hanging_towel|^ac$|ac_big|aircc|pipe_|cable_|projector_screen|wall_protection|wall_(l|r|top|window)_|sticky_note|^photos|blueprint|^board_)/i;
const SIT = /(chair|sofa|stool|seat|bench|couch|bed_)/i;
const WALK = /(carpet|rug|^bath_carpet|shower_floor)/i;
const STACK = /(table|desk|shelf|shelving|counter|kitchen_furniture|kitchen_a|cabinet|closet|drawer|dishwasher|oven|fridge|washingmachine|rack)/i;

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
const title = (s) => s.replace(/_/g, ' ').replace(/\s+/g, ' ').trim();

/** Tiles covered, from the picture: its width says how many tiles across, the front corner how they split. */
function guessSize(frames) {
  const png = load(frames[0]);
  const box = bbox(png);
  if (!box) return [1, 1];
  const [l, , r, b] = box;
  const width = r - l;
  // Where the bottom row of the picture is: the furni's front corner.
  let sum = 0, n = 0;
  for (let y = b - 1; y >= Math.max(0, b - 3); y--) {
    for (let x = l; x < r; x++) if (png.data[(y * png.width + x) * 4 + 3] > 16) (sum += x - l), n++;
    if (n) break;
  }
  const front = n ? sum / n : width / 2;
  const across = Math.min(8, Math.max(2, Math.round(width / 32)));
  const alongX = Math.min(across - 1, Math.max(1, Math.round((front / width) * across)));
  return [alongX, across - alongX];
}

const existing = existsSync(outFile) ? JSON.parse(readFileSync(outFile, 'utf8')) : { items: [] };
const known = new Set(existing.items.map((d) => d.id));
const added = [];
const ids = new Set(known);
for (const g of groups.sort((a, b) => a.base.localeCompare(b.base))) {
  const [name, slugName] = NAMES[g.base] ?? [title(g.base), slug(g.base)];
  let id = `${pack}_${slugName}`;
  if (known.has(id)) continue;
  for (let i = 2; ids.has(id); i++) id = `${pack}_${slugName}_${i}`;
  ids.add(id);
  const dirs = {};
  for (const [d, states] of Object.entries(g.dirs)) dirs[d] = { states };
  // Only pictures facing one way: the other way round is the same picture mirrored, like Habbo.
  if (!g.dirs[2]) dirs[2] = { mirror: 4 };
  const def = { id, name, source, kind: WALL.test(g.base) ? 'wall' : 'floor', size: guessSize(g.dirs[4][0]), dirs };
  if (g.dirs[4].some((st) => st.length > 1)) def.fps = g.fps ?? 8;
  if (def.kind === 'floor') {
    if (SIT.test(g.base)) def.sit = true;
    else if (WALK.test(g.base)) def.walk = true;
    else if (STACK.test(g.base)) def.stack = true;
  }
  added.push(def);
}

mkdirSync(join(root, 'content', 'furni'), { recursive: true });
const out = { pack, source, items: [...existing.items, ...added] };
writeFileSync(outFile, JSON.stringify(out, null, 1) + '\n');
const count = (k) => added.filter((d) => d.kind === k).length;
console.log(`${files.length} pictures → ${groups.length} furni. Added ${added.length} (${count('floor')} floor, ${count('wall')} wall), kept ${known.size}.`);
console.log(`Animated: ${added.filter((d) => d.fps).length}, with states: ${added.filter((d) => d.dirs[4].states.length > 1).length}, with real directions: ${added.filter((d) => d.dirs[2] && 'states' in d.dirs[2]).length}`);
