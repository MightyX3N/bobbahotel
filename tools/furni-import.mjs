#!/usr/bin/env node
// Turns a pack of loose furni pictures into furni definitions (content/furni/<pack>.json).
//
//   node tools/furni-import.mjs [source folder under sprites/] [pack name]
//   node tools/furni-import.mjs furni salvaje
//
// It groups the pictures into furni and guesses everything it can from the file names and the
// pictures themselves:
//   - Name_1, Name_2, ... that look alike are animation frames of one furni (Name_Off: switched off);
//     ones that don't look alike are separate furni.
//   - Name_A / _B / _C / _D are the directions it faces (B mirrored from A when that's what it is).
//   - Floor or wall, sit / walk / stack, from the name.
//   - How many tiles it covers, from the width of the picture and where its front corner is.
// Furni already in the definitions file are left exactly as they are (hand fixes are kept);
// only new ones are added. The pictures themselves are never changed.
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
const files = readdirSync(srcDir).filter((f) => f.endsWith('.png')).map((f) => f.slice(0, -4)).sort();
/** The name without "_Tile" (some files have it, some don't). */
const key = (name) => name.replace(/_Tile(?=_|$)/g, '');
const used = new Set();
const groups = []; // { base, dirs: {dir: frames[] | {mirror}}, off?, fps? }

// Animations: Name_<n> with at least 3 numbers that look alike.
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
  groups.push({ base, dirs: { 4: frames }, off, fps: 8 });
}

// Directions: Name_A, _B, _C, _D (a plain Name counts as A when there are B/C/D).
const lettered = new Map();
for (const f of files) {
  if (used.has(f)) continue;
  const m = /^(.*)_([A-D])$/.exec(key(f));
  if (m) (lettered.get(m[1]) ?? lettered.set(m[1], {}).get(m[1]))[m[2]] = f;
}
for (const [base, letters] of lettered) {
  const plain = files.find((f) => !used.has(f) && key(f) === base);
  if (!letters.A && plain) letters.A = plain;
  const a = letters.A && load(letters.A);
  if (!a) continue;
  const b = letters.B && load(letters.B);
  const bMirrorsA = b && alike(a, b, true) > 0.6;
  // Four directions: A to D, where B is not just A again (then they are states, like a present opening).
  const all4 = letters.A && letters.B && letters.C && letters.D && (bMirrorsA || alike(a, b) < 0.6);
  if (!all4 && !bMirrorsA) continue; // different furni that only share a name
  const dirs = { 4: [letters.A] };
  if (letters.B) dirs[2] = [letters.B];
  if (letters.C) dirs[0] = [letters.C];
  if (letters.D) dirs[6] = [letters.D];
  Object.values(letters).forEach((f) => used.add(f));
  groups.push({ base, dirs });
}

// Everything else: one picture, one furni.
for (const f of files) if (!used.has(f)) groups.push({ base: key(f), dirs: { 4: [f] } });

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
  let id = `${pack}_${slug(g.base)}`;
  if (known.has(id)) continue;
  for (let i = 2; ids.has(id); i++) id = `${pack}_${slug(g.base)}_${i}`;
  ids.add(id);
  const dirs = {};
  for (const [d, frames] of Object.entries(g.dirs)) dirs[d] = { frames };
  // Only one picture direction: the other way round is the same picture mirrored, like Habbo.
  if (!g.dirs[2] && !g.dirs[6] && !g.dirs[0]) dirs[2] = { mirror: 4 };
  else if (g.dirs[4] && !g.dirs[2]) dirs[2] = { mirror: 4 };
  const def = { id, name: title(g.base), source, kind: WALL.test(g.base) ? 'wall' : 'floor', size: guessSize(g.dirs[4]), dirs };
  if (g.dirs[4].length > 1) def.fps = g.fps ?? 8;
  if (g.off) def.off = g.off;
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
console.log(`Animated: ${added.filter((d) => d.fps).length}, with real directions: ${added.filter((d) => d.dirs[2] && 'frames' in d.dirs[2]).length}`);
