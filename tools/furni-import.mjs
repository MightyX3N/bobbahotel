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
// The definitions file is written from scratch every time, so fixes belong in the tables below
// (HAND, MERGE, NAMES and the guesses), not in the file. Ids stay the same between runs. The
// pictures themselves are never changed.
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

// Furni put together by hand, where the names and pictures don't say how they belong together:
// per direction, its states (each a list of frames). Taken before the guessing below.
const HAND = [
  // A front and a back view (directions 4 and 6; the other two are those mirrored).
  { base: 'Sofa_4', dirs: { 4: [['Sofa_4_A_Tile']], 6: [['Sofa_4_B_Tile']] } },
  { base: 'Fridge', dirs: { 4: [['Fridge']], 0: [['Fridge_Back']] } },
  { base: 'Fridge_2', dirs: { 4: [['Fridge_2_A_Tile']], 0: [['Fridge_2_C_Tile']] } },
  // Off and on, closed and open, empty and full.
  { base: 'Sink', dirs: { 4: [['Sink'], ['Sink_1']] } },
  { base: 'TrashBin', dirs: { 4: [['TrashBin_Closed'], ['TrashBin_Open']] } },
  { base: 'Trash', dirs: { 4: [['Trash_Empty'], ['Trash_Full']] } },
  { base: 'Plastic_Box_1', dirs: { 4: [['Plastic_Box_1_Empty'], ['Plastic_Box_1_Full']] } },
  { base: 'Plastic_Box_2', dirs: { 4: [['Plastic_Box_2_Empty'], ['Plastic_Box_2_Full']] } },
  { base: 'Pot', dirs: { 4: [['Pot'], ['Pot_Full']] } },
  // Free-standing Japanese wall panels (room dividers, standing on the floor): left and right.
  { base: 'Japanese_Wall', dirs: { 4: [['Wall_L_Japanese_128']], 2: [['Wall_R_Japanese_128']] } },
  { base: 'Japanese_Wall_Top', dirs: { 4: [['Wall_Top_L_Japanese_128']], 2: [['Wall_Top_R_Japanese_128']] } },
  { base: 'Japanese_Wall_Window', dirs: { 4: [['Wall_Window_L_Japanese_128']], 2: [['Wall_Window_R_Japanese_128']] } },
  { base: 'Japanese_Window_Wall', dirs: { 4: [['Window_L_128_Japanese']], 2: [['Window_R_128_Japanese']] } },
  { base: 'Lamp_8', dirs: { 4: [['Lamp_8_A_Tile'], ['Lamp_8_B_Tile']] } },
  { base: 'Light_Switch', dirs: { 4: [['Switch_C'], ['Switch_B']] } },
  { base: 'RotationScreen', dirs: { 4: [['RotationScreen_A_Tile'], ['RotationScreen_B_Tile'], ['RotationScreen_C_Tile']] } },
  // Blinds open, half and closed.
  { base: 'Window_7', dirs: { 4: [['Window_7_A_Tile'], ['Window_7_B_Tile'], ['Window_7_C_Tile']] } },
  { base: 'Window_8', dirs: { 4: [['Window_8'], ['Window_B_8'], ['Window_C_8']] } },
  { base: 'Window_11', dirs: { 4: [['Window_11'], ['Window_11_B'], ['Window_11_C']] } },
  // Its beam flickers.
  { base: 'Projector_2', dirs: { 4: [['Projector_2', 'Projector_3', 'Projector_4']] }, fps: 4 },
  // A present: closed, then opening (played once, then it stays open).
  { base: 'Present_100', dirs: { 4: [['Present_100'], ['Present_100_B', 'Present_100_C', 'Present_100_D', 'Present_100_E']] }, fps: 6, once: true },
];
// Pictures left out: the same picture as another furni.
const SKIP = new Set(['Present_2']);
for (const f of SKIP) used.add(f);
for (const g of HAND) {
  const all = Object.values(g.dirs).flat(2);
  if (!all.every((f) => allFiles.includes(f))) continue;
  all.forEach((f) => used.add(f));
  if (!files.includes(all[0])) files.push(all[0]);
  groups.push(g);
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
  if (list.some(([, f]) => used.has(f))) continue;
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
  TrashBin: ['Trash Bin', 'trashbin_closed'],
  Trash: ['Trash Can', 'trash_empty'],
  Plastic_Box_1: ['Plastic Box', 'plastic_box_1_empty'],
  Plastic_Box_2: ['Plastic Box 2', 'plastic_box_2_empty'],
  Light_Switch: ['Light Switch', 'switch_b'],
  Lamp_8: ['Desk Lamp', 'lamp_8_a'],
  RotationScreen: ['Rotating Screen', 'rotationscreen_a'],
  Window_7: ['Window 7', 'window_7_a'],
  Window_8: ['Window 8', 'window_8'],
  Window_11: ['Window 11', 'window_11'],
  Projector_2: ['Projector', 'projector_2'],
  Present_100: ['Present', 'present_100'],
  Sofa_4: ['Sofa 4', 'sofa_4_a'],
  Fridge_2: ['Fridge 2', 'fridge_2'],
};

// ---- guesses ----
const WALL = /(poster|picture|painting|wall_clock|window|diploma|corkboard|^switch|^light_switch|tap_wall|canvas|mirror|hanging_towel|^ac$|pipe_|cable_|wall_protection|sticky_note|^photos|blueprint|^board_|^camera|^hanger$|^rack$|^long_rack$|^shower_tap$|^tap_shower$|^big_tv|^kitchen_furniture_[a-z]+_[4-7]$|^(shelf|long_shelf|small_shelf|shelving_6)$|^lamp_7$|^lamp_modern$|^toilet_paper$|^tools$|^rag$|^medical_kit_closed$|^screen_small$)/i;
// Wall furni that stick out of the wall (tiles), and which wall their picture is drawn for when
// their outline can't tell (boxes show both slopes): 2 = a back wall, 4 = a left wall.
const WALL_DEPTH = [
  [/^kitchen_furniture_[a-z]+_[4-7]$/i, 1, 2],
  [/^(shelf|long_shelf|small_shelf|shelving_6)$/i, 0.5],
  [/^medical_kit_closed$/i, 0.4],
];
// Wall shelves: small furni can be put on them. Their top is this many height steps above the
// middle of their picture.
const SHELF = [[/^(shelf|long_shelf|small_shelf|shelving_6)$/i, 0.15]];
const SIT = /(chair|sofa|stool|seat|bench|couch)/i;
const LAY = /^bed_/i;
const WALK = /(carpet|rug|^bath_carpet|shower_floor)/i;
// Like Habbo, other furni can go on top of nearly everything (not seats and beds).

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
const title = (s) => s.replace(/_/g, ' ').replace(/\s+/g, ' ').trim();

/**
 * Is the picture drawn for a back wall (its edges run down to the right) rather than a left wall?
 * Counts the 2:1 steps of its top and bottom outline (only solid pixels, so glows and light
 * beams don't count).
 */
function slopesDownRight(file) {
  const png = load(file);
  const solid = (x, y) => png.data[(y * png.width + x) * 4 + 3] > 200;
  const top = [], bottom = [];
  for (let x = 0; x < png.width; x++) {
    let t = null, b = null;
    for (let y = 0; y < png.height; y++) if (solid(x, y)) { t ??= y; b = y; }
    top.push(t);
    bottom.push(b);
  }
  let down = 0, up = 0;
  for (const edge of [top, bottom]) {
    for (let x = 0; x + 2 < edge.length; x++) {
      if (edge[x] === null || edge[x + 2] === null) continue;
      if (edge[x + 2] - edge[x] === 1) down++;
      else if (edge[x] - edge[x + 2] === 1) up++;
    }
  }
  return down >= up;
}

/**
 * Measures where a floor furni's picture stands: the outline of its bottom edge is a V (the front
 * two sides of its footprint, sloping 1:2 on screen). The V is fitted as low as it can go with the
 * whole picture above it; where the picture's bottom touches it are the footprint's corners.
 * Returns, in the picture's pixels: the front corner (fx, fy), the left and right corners' x, and
 * the top of the picture. Only solid pixels count (soft shadows don't).
 */
function measureFloor(file) {
  const png = load(file);
  const solid = (x, y) => png.data[(y * png.width + x) * 4 + 3] > 200;
  const cols = [];
  let top = png.height;
  for (let x = 0; x < png.width; x++) {
    let b = -1;
    for (let y = 0; y < png.height; y++) if (solid(x, y)) { b = y; top = Math.min(top, y); }
    if (b >= 0) cols.push([x, b]);
  }
  if (cols.length === 0) return null;
  const xMin = cols[0][0];
  const xMax = cols.at(-1)[0];
  let fx = xMin;
  let fy = Infinity;
  for (let x = xMin; x <= xMax; x += 0.5) {
    let y = -Infinity;
    for (const [cx, b] of cols) y = Math.max(y, b + Math.abs(cx - x) / 2);
    if (y < fy - 1e-9) [fx, fy] = [x, y];
  }
  // Columns whose bottom lies on the V (within 2 px) are standing on the floor.
  const touching = cols.filter(([cx, b]) => fy - Math.abs(cx - fx) / 2 - b <= 2).map(([cx]) => cx);
  return { fx, fy: fy + 1, left: Math.min(...touching), right: Math.max(...touching) + 1, top, width: png.width, height: png.height };
}

/**
 * A floor furni's tiles, size and where its picture stands, from its measured outline. Like
 * Habbo, a furni covers whole tiles; pictures drawn a little smaller or bigger than our tiles are
 * scaled to fit them (small things, like a lamp, keep their size and stand in the middle of their
 * tile). Returns the tiles [along x, along y], the scale, the footprint's middle in the picture
 * (where the picture is pinned to the middle of its tiles) and its height in height steps.
 */
function fitFloor(file, flat) {
  const m = measureFloor(file);
  if (!m) return null;
  const w = Math.max(0, (m.fx - m.left) / 32);
  const l = Math.max(0, (m.right - m.fx) / 32);
  let size = [1, 1];
  let scale = 1;
  let stretch;
  if (flat) {
    // Rugs and mats cover their tiles exactly: stretched along each floor direction on its own
    // (they lie flat, so that only changes their shape on the floor).
    size = [Math.max(1, Math.round(w)), Math.max(1, Math.round(l))];
    const sx = Math.round((size[0] / Math.max(0.2, w)) * 1000) / 1000;
    const sy = Math.round((size[1] / Math.max(0.2, l)) * 1000) / 1000;
    if (Math.abs(sx - 1) >= 0.02 || Math.abs(sy - 1) >= 0.02) stretch = [sx, sy];
  } else if (w + l >= 1.2) {
    // The whole tiles that suit it best: it may not stick out of them (it's made smaller if it
    // would), is only made bigger to fill them when it's close, and should fill them well.
    let best = null;
    for (let W = 1; W <= 8; W++) {
      for (let L = 1; L <= 8; L++) {
        const fit = Math.min(W / Math.max(w, 0.1), L / Math.max(l, 0.1));
        const sc = fit < 1 ? fit : fit <= 1.12 ? fit : 1;
        const empty = (W - Math.min(W, w * sc)) / W + (L - Math.min(L, l * sc)) / L;
        const err = 0.5 * Math.abs(Math.log(sc)) + empty;
        if (!best || err < best.err - 1e-9) best = { W, L, sc, err };
      }
    }
    size = [best.W, best.L];
    scale = best.sc;
  } else if (w > 1 || l > 1) {
    scale = Math.min(1 / Math.max(w, 0.1), 1 / Math.max(l, 0.1));
  }
  scale = Math.round(scale * 1000) / 1000;
  if (Math.abs(scale - 1) < 0.02) scale = 1;
  // The footprint's middle: halfway between its left and right corners (for small things, the
  // middle of what touches the floor).
  const yAt = (x) => m.fy - Math.abs(x - m.fx) / 2;
  const at = [Math.round(((m.left + m.right) / 2) * 2) / 2, Math.round(((yAt(m.left) + yAt(m.right)) / 2) * 2) / 2];
  // Height: from the top of its footprint diamond (seen from above) to the top of the picture.
  const [W, L] = size;
  // (The top's diamond is as big as the measured footprint, not the tiles: a table can be smaller.)
  const height = flat ? 0 : Math.max(0, Math.round((((at[1] - m.top) / 32 - (w + l) / 4) * scale) * 10) / 10);
  return { size, scale, stretch, at, height, measured: [Math.round(w * 100) / 100, Math.round(l * 100) / 100] };
}

const added = [];
const measuredLog = [];
const f2 = (a) => a.join('x');
const ids = new Set();
for (const g of groups.sort((a, b) => a.base.localeCompare(b.base))) {
  const [name, slugName] = NAMES[g.base] ?? [title(g.base), slug(g.base)];
  let id = `${pack}_${slugName}`;
  for (let i = 2; ids.has(id); i++) id = `${pack}_${slugName}_${i}`;
  ids.add(id);
  const dirs = {};
  const kind = WALL.test(g.base) && !/^japanese_/i.test(g.base) ? 'wall' : 'floor';
  if (kind === 'wall' && !g.dirs[2]) {
    // Wall items: direction 2 hangs on the back walls (running down to the right), 4 on the left
    // walls. The picture is drawn for one of them (seen from how its top edge slopes); the other
    // is the same picture mirrored.
    const known = WALL_DEPTH.find(([re]) => re.test(g.base));
    const forBack = known?.[2] !== undefined ? known[2] === 2 : slopesDownRight(g.dirs[4][0][0]);
    dirs[forBack ? 2 : 4] = { states: g.dirs[4] };
    dirs[forBack ? 4 : 2] = { mirror: forBack ? 2 : 4 };
  } else {
    for (const [d, states] of Object.entries(g.dirs)) dirs[d] = { states };
    // Directions without their own pictures are the opposite side's mirrored, like Habbo: 2 is 4
    // mirrored (front views), 6 and 0 are each other mirrored (back views).
    if (g.dirs[4] && !g.dirs[2]) dirs[2] = { mirror: 4 };
    if (g.dirs[0] && !g.dirs[6]) dirs[6] = { mirror: 0 };
    if (g.dirs[6] && !g.dirs[0]) dirs[0] = { mirror: 6 };
  }
  const def = { id, name, source, kind, size: [1, 1], dirs };
  if (kind === 'floor') {
    // Every direction with its own pictures is measured: its tiles, scale and where it stands.
    let fits = {};
    for (const [d, images] of Object.entries(dirs)) if (images.states) fits[d] = fitFloor(images.states[0][0], WALK.test(g.base));
    // Seats face away from their long side: a sofa whose "direction 4" picture is long along y
    // really faces 2 (and its back views 0 and 6 swap too).
    if (SIT.test(g.base) && fits[4] && fits[4].size[1] > fits[4].size[0]) {
      const swap = { 4: 2, 2: 4, 0: 6, 6: 0 };
      const turned = {};
      for (const [d, images] of Object.entries(dirs)) turned[swap[d]] = images.mirror !== undefined ? { mirror: swap[images.mirror] } : images;
      for (const d of Object.keys(dirs)) delete dirs[d];
      Object.assign(dirs, turned);
      const f2s = {};
      for (const [d, f] of Object.entries(fits)) f2s[swap[d]] = f;
      fits = f2s;
    }
    const main = fits[4] ?? fits[2] ?? Object.values(fits)[0];
    if (main) {
      const [a, b] = main.size;
      // Sizes are kept for direction 4: a picture drawn facing 2 or 6 has them the other way round.
      const own = fits[4] ? 4 : fits[2] ? 2 : Number(Object.keys(fits)[0]);
      def.size = own === 2 || own === 6 ? [b, a] : [a, b];
      if (main.scale !== 1) def.scale = main.scale;
      def.height = main.height;
      for (const [d, f] of Object.entries(fits)) {
        if (!f) continue;
        dirs[d].at = f.at;
        if (f.stretch) dirs[d].stretch = f.stretch;
      }
      measuredLog.push(`${id} measured ${f2(main.measured)} -> ${def.size} x${def.scale ?? 1} h${def.height}`);
    }
  }
  if (g.dirs[4].some((st) => st.length > 1)) def.fps = g.fps ?? 8;
  if (g.once) def.once = true;
  const depth = WALL_DEPTH.find(([re]) => re.test(g.base));
  if (def.kind === 'wall' && depth) def.depth = depth[1];
  const shelf = SHELF.find(([re]) => re.test(g.base));
  if (def.kind === 'wall' && shelf) {
    def.stack = true;
    def.surface = shelf[1];
  }
  if (def.kind === 'floor') {
    if (LAY.test(g.base)) def.lay = true;
    else if (SIT.test(g.base) && !/pillow/i.test(g.base)) def.sit = true;
    else {
      if (WALK.test(g.base)) def.walk = true;
      def.stack = true;
    }
  }
  added.push(def);
}

writeFileSync(join(root, 'tools', 'furni-measured.txt'), measuredLog.join('\n') + '\n');
mkdirSync(join(root, 'content', 'furni'), { recursive: true });
const out = { pack, source, items: added };
writeFileSync(outFile, JSON.stringify(out, null, 1) + '\n');
const count = (k) => added.filter((d) => d.kind === k).length;
console.log(`${files.length} pictures → ${groups.length} furni: ${count('floor')} floor, ${count('wall')} wall.`);
console.log(`Animated: ${added.filter((d) => d.fps).length}, with states: ${added.filter((d) => Object.values(d.dirs).some((v) => v.states?.length > 1)).length}, with real directions: ${added.filter((d) => d.dirs[2] && 'states' in d.dirs[2]).length}`);
