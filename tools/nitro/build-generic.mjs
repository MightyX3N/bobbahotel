#!/usr/bin/env node
// Builds Nitro's generic bundles from our own pictures:
//
//   bundled/generic/room.nitro         floors and walls (every style in sprites/tiles), door hole
//   bundled/generic/tile_cursor.nitro  the tile outline under the mouse
//   bundled/generic/selection_arrow.nitro
//   bundled/generic/place_holder*.nitro what shows while a furni's own bundle loads
//   bundled/generic/floor_editor.nitro the floor plan editor's tiles
//   bundled/generic/avatar_additions.nitro typing / idle bubbles over avatars
//
// Nitro draws floors and walls as flat textures that it projects onto the room itself, so our
// isometric tile pictures (one 64x32 floor tile with its edge, one wall piece) are un-projected:
// the floor tile's top becomes a 32x32 flat texture, each wall face a 32-wide strip.
//
// Usage: node tools/nitro/build-generic.mjs [outDir] [spritesDir]

import { mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { blank, box, crop, encode, half, load, solid } from './png.mjs';
import { writeBundle } from './bundle.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
const out = process.argv[2] ?? join(root, 'build', 'nitro');
const spritesDir = process.argv[3] ?? join(root, 'sprites');
const generic = join(out, 'bundled', 'generic');
mkdirSync(generic, { recursive: true });

const px = (img, x, y) => {
  const i = (y * img.width + x) * 4;
  return [img.data[i], img.data[i + 1], img.data[i + 2], img.data[i + 3]];
};
const put = (img, x, y, c) => {
  if (x < 0 || y < 0 || x >= img.width || y >= img.height) return;
  img.data.set(c.length === 3 ? [...c, 255] : c, (y * img.width + x) * 4);
};
const decimal = ([r, g, b]) => (r << 16) | (g << 8) | b;
/** The colour that comes out as `c` after Nitro multiplies it by the grey `tint` (0..255). */
const untint = (c, tint) => c.slice(0, 3).map((v) => Math.min(255, Math.round((v * 255) / tint)));

// ---- Room ---------------------------------------------------------------------------------

// Our tile pictures (64x64): a floor tile's top is the diamond with corners (32,16) (64,32)
// (32,48) (0,32), its edge below it; a wall piece's face is 32 px wide (x 16..47) and 40 tall,
// sheared by half a pixel per pixel, its top 8 px down at the high end.
const FLOOR_TOP = [32, 16];
const WALL_FACE = { x: 16, w: 32, h: 40, top: 8 };

/** The floor tile's top as a flat 32x32 texture (Nitro's flat floor: 32 px per tile). */
function flatFloor(img) {
  const t = blank(32, 32);
  for (let v = 0; v < 32; v++) {
    for (let u = 0; u < 32; u++) {
      // Nitro lays flat x down-right on screen and flat y down-left (checked by rendering a
      // gradient). The tile's top is 63 px wide and 31 tall (the rows under it are its edge),
      // so the flat pixels are spread over that.
      const sx = Math.floor(FLOOR_TOP[0] - 0.5 + ((u - v) * 63) / 64);
      const sy = Math.floor(FLOOR_TOP[1] + ((u + v + 1) * 31) / 64);
      put(t, u, v, px(img, Math.min(63, Math.max(0, sx)), sy));
    }
  }
  return t;
}

/** A wall piece's face as a flat 32x40 texture. `rising`: the face's top rises to the right (left wall). */
function flatWall(img, rising) {
  const { x, w, h, top } = WALL_FACE;
  const t = blank(w, h);
  for (let u = 0; u < w; u++) {
    const y0 = top + (rising ? (w - 1 - u) >> 1 : u >> 1);
    for (let v = 0; v < h; v++) put(t, u, v, px(img, x + u, Math.min(63, y0 + v)));
  }
  return t;
}

const tiles = readdirSync(join(spritesDir, 'tiles')).filter((f) => f.endsWith('.png'));
const floors = tiles.filter((f) => f.startsWith('floor_')).map((f) => f.slice(6, -4)).sort();
const walls = tiles.filter((f) => f.startsWith('wall_l_')).map((f) => f.slice(7, -4)).filter((n) => tiles.includes(`wall_r_${n}.png`)).sort();
const DEFAULT_FLOOR = 'woodlight';
const DEFAULT_WALL = 'beigeyellow';
// The server keeps a room's floor and wall as a short code (rooms.paper_floor / paper_wall, at most
// 5 characters), so each style gets a number in name order: floors 1001, 1002, ..., walls 2001,
// 2002, ... (Nitro's own defaults, 111 and 201, stay free so a room without a style gets the
// "default" plane). They are written to gamedata/paints.json for the catalogue.
const code = (list, n) => String((list === floors ? 1001 : 2001) + list.indexOf(n));

const roomImages = {};
const roomAssets = {};
const add = (name, img, x = 0, y = 0) => {
  roomImages[`room_${name}`] = img;
  roomAssets[name] = { x, y };
};
const floorData = { textures: [], materials: [], planes: [] };
const wallData = { textures: [], materials: [], planes: [] };

for (const n of floors) {
  const img = load(join(spritesDir, 'tiles', `floor_${n}.png`));
  const top = flatFloor(img);
  // The edge: the tile's left side, as seen under its left corner. Nitro shades edges itself
  // (0xDD on the left), so it is stored lightened by that much.
  const edge = solid(64, 8, untint(px(img, 4, 40), 0xdd));
  add(`floor_${n}_64`, top);
  add(`floor_${n}_32`, half(top));
  add(`floor_${n}_edge_64`, edge);
  add(`floor_${n}_edge_32`, solid(32, 4, untint(px(img, 4, 40), 0xdd)));
  for (const s of [64, 32]) {
    floorData.textures.push({ id: `floor_${n}_${s}`, bitmaps: [{ assetName: `floor_${n}_${s}`, normalMinY: 0 }, { assetName: `floor_${n}_edge_${s}`, normalMaxY: 0 }] });
    floorData.materials.push({ id: `floor_${n}_${s}`, matrices: [{ columns: [{ width: s / 2, cells: [{ textureId: `floor_${n}_${s}` }] }] }] });
  }
  const plane = (id) => ({
    id,
    visualizations: [32, 64].map((s) => ({ size: s, horizontalAngle: 45, verticalAngle: 30, allLayers: [{ materialId: `floor_${n}_${s}` }] })),
  });
  floorData.planes.push(plane(code(floors, n)));
  if (n === DEFAULT_FLOOR) floorData.planes.push(plane('default'));
}

// For checking furni placement (GRID=1): floor 9999 shows every tile's outline.
if (process.env.GRID) {
  const g = solid(32, 32, [200, 200, 200]);
  for (let i = 0; i < 32; i++) { put(g, i, 0, [60, 60, 60]); put(g, 0, i, [60, 60, 60]); }
  add('floor_grid_64', g);
  add('floor_grid_32', half(g));
  for (const s of [64, 32]) {
    floorData.textures.push({ id: `floor_grid_${s}`, bitmaps: [{ assetName: `floor_grid_${s}` }] });
    floorData.materials.push({ id: `floor_grid_${s}`, matrices: [{ columns: [{ width: s / 2, cells: [{ textureId: `floor_grid_${s}` }] }] }] });
  }
  floorData.planes.push({ id: '9999', visualizations: [32, 64].map((s) => ({ size: s, horizontalAngle: 45, verticalAngle: 30, allLayers: [{ materialId: `floor_grid_${s}` }] })) });
}

for (const n of walls) {
  const l = load(join(spritesDir, 'tiles', `wall_l_${n}.png`));
  const r = load(join(spritesDir, 'tiles', `wall_r_${n}.png`));
  const left = flatWall(l, true);
  const right = flatWall(r, false);
  add(`wall_${n}_l_64`, left);
  add(`wall_${n}_r_64`, right);
  add(`wall_${n}_l_32`, half(left));
  add(`wall_${n}_r_32`, half(right));
  // The wall's top: the colour along the top of the right piece. Nitro darkens tops to 0x99.
  const topColour = decimal(untint(px(r, 22, 4), 0x99));
  for (const s of [64, 32]) {
    wallData.textures.push({ id: `wall_${n}_${s}`, bitmaps: [{ assetName: `wall_${n}_l_${s}`, normalMinX: 0 }, { assetName: `wall_${n}_r_${s}`, normalMaxX: 0 }] });
    wallData.materials.push({ id: `wall_${n}_${s}`, matrices: [{ align: 'bottom', columns: [{ width: s / 2, cells: [{ textureId: `wall_${n}_${s}` }] }] }] });
  }
  const plane = (id) => ({
    id,
    visualizations: [32, 64].map((s) => ({ size: s, horizontalAngle: 45, verticalAngle: 30, allLayers: [{ color: topColour || 1 }, { materialId: `wall_${n}_${s}` }] })),
  });
  wallData.planes.push(plane(code(walls, n)));
  if (n === DEFAULT_WALL) wallData.planes.push(plane('default'));
}

// The doorway: a hole in the wall, pure black where the wall is cut away, pinned at its bottom middle.
add('door_64', solid(32, 104, [0, 0, 0]), 16, 104);
add('door_32', solid(16, 52, [0, 0, 0]), 8, 52);

writeBundle(join(generic, 'room.nitro'), 'room', {
  type: 'room',
  visualizationType: 'room',
  logicType: 'room',
  assets: roomAssets,
  roomVisualization: {
    floorData,
    wallData,
    landscapeData: { planes: [{ id: 'default', animatedVisualization: [32, 64].map((s) => ({ size: s, allLayers: [{ color: 0x86b6d9 }] })) }] },
    maskData: { masks: [{ id: 'door', visualizations: [32, 64].map((s) => ({ size: s, bitmaps: [{ assetName: `door_${s}` }] })) }] },
  },
}, roomImages);

// ---- Small drawn pieces -----------------------------------------------------------------

/** A tile diamond (w x w/2): its outline (2 px steps) in `line`, inside in `fill`. */
function diamond(w, line, fill = null) {
  const h = w / 2;
  const img = blank(w, h);
  for (let y = 0; y < h; y++) {
    const hw = y < h / 2 ? 2 * (y + 1) : 2 * (h - y);
    const x0 = w / 2 - hw, x1 = w / 2 + hw - 1;
    for (let x = x0; x <= x1; x++) {
      const edge = x - x0 < 2 || x1 - x < 2 || y === 0 || y === h - 1;
      if (edge) put(img, x, y, line);
      else if (fill) put(img, x, y, fill);
    }
  }
  return img;
}

/** Furni-style bundle: one layer per image list, as states (animations) when `states` given. */
function furniBundle(name, logicType, visualizationType, pieces, { layerCount = 1, animations = null, extra = {} } = {}) {
  const images = {};
  const assets = {};
  for (const [asset, img, x, y] of pieces) {
    images[`${name}_${asset}`] = img;
    assets[asset] = { x, y };
  }
  const vis = (s) => ({
    size: s,
    layerCount,
    angle: 90,
    layers: Object.fromEntries([...Array(layerCount).keys()].map((i) => [i, { ignoreMouse: true }])),
    ...(animations ? { animations } : {}),
  });
  writeBundle(join(generic, `${name}.nitro`), name, { type: name, logicType, visualizationType, assets, visualizations: [vis(32), vis(64)], ...extra }, images);
}

// Tile cursor: state 0 the outline on the tile; state 6 (over something taller) a mark on the
// floor and the outline raised to the top (Nitro raises layer b itself).
const cursorLine = [255, 255, 255, 230];
const cursorMark = [255, 255, 255, 90];
const one = (id) => ({ frameSequences: { 0: { frames: { 0: { id } } } } });
furniBundle('tile_cursor', 'tile_cursor', 'tile_cursor', [
  ['tile_cursor_64_a_0_0', diamond(64, cursorLine), 32, 16],
  ['tile_cursor_64_a_0_2', diamond(64, cursorMark), 32, 16],
  ['tile_cursor_64_b_0_1', diamond(64, cursorLine), 32, 16],
  ['tile_cursor_32_a_0_0', diamond(32, cursorLine), 16, 8],
  ['tile_cursor_32_a_0_2', diamond(32, cursorMark), 16, 8],
  ['tile_cursor_32_b_0_1', diamond(32, cursorLine), 16, 8],
], {
  layerCount: 2,
  // Frame 9 has no picture: hidden.
  animations: { 0: { layers: { 0: one(0), 1: one(9) } }, 1: { layers: { 0: one(9), 1: one(9) } }, 6: { layers: { 0: one(2), 1: one(1) } } },
});

// Selection arrow over the chosen avatar: a small white arrow pointing down, outlined.
function arrow(scale) {
  const w = 8 * scale, h = 7 * scale;
  const img = blank(w + 2, h + 2);
  const shape = (x, y) => {
    // Body: a stem on top, a triangle below.
    if (y < 3 * scale) return x >= 2.5 * scale && x < 5.5 * scale;
    const row = y - 3 * scale;
    return x >= row && x < w - row;
  };
  for (let y = -1; y <= h; y++) {
    for (let x = -1; x <= w; x++) {
      const inside = x >= 0 && y >= 0 && x < w && y < h && shape(x, y);
      if (inside) put(img, x + 1, y + 1, [255, 255, 255]);
      else if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => x + dx >= 0 && y + dy >= 0 && x + dx < w && y + dy < h && shape(x + dx, y + dy))) put(img, x + 1, y + 1, [30, 30, 30]);
    }
  }
  return img;
}
const a64 = arrow(2), a32 = arrow(1);
furniBundle('selection_arrow', 'selection_arrow', 'furniture_animated', [
  ['selection_arrow_64_a_0_0', a64, a64.width >> 1, 108],
  ['selection_arrow_32_a_0_0', a32, a32.width >> 1, 54],
], { animations: { 0: { layers: { 0: one(0) } }, 1: { layers: { 0: one(1) } } } });

// Placeholders: a faint tile while the real picture loads.
const faint = [255, 255, 255, 70];
for (const [name, x64, y64] of [['place_holder', 16, 8], ['place_holder_wall', 16, 8], ['place_holder_pet', 16, 8]]) {
  furniBundle(name, 'furniture_basic', 'furniture_static', [
    [`${name}_64_a_0_0`, diamond(32, faint), x64, y64],
    [`${name}_32_a_0_0`, diamond(16, faint), x64 / 2, y64 / 2],
  ], { extra: { logic: { model: { dimensions: { x: 1, y: 1, z: 1 } } } } });
}

// Floor plan editor: one 32x16 tile per height, coloured like Nitro's editor.
const COLORMAP = {
  x: '101010', 0: '0065ff', 1: '0091ff', 2: '00bcff', 3: '00e8ff', 4: '00ffea', 5: '00ffbf', 6: '00ff93', 7: '00ff68', 8: '00ff3d', 9: '19ff00',
  a: '44ff00', b: '70ff00', c: '9bff00', d: 'f2ff00', e: 'ffe000', f: 'ffb500', g: 'ff8900', h: 'ff5e00', i: 'ff3200', j: 'ff0700', k: 'ff0023',
  l: 'ff007a', m: 'ff00a5', n: 'ff00d1', o: 'ff00fc', p: 'd600ff', q: 'aa00ff',
};
const hex = (s) => [parseInt(s.slice(0, 2), 16), parseInt(s.slice(2, 4), 16), parseInt(s.slice(4, 6), 16)];
const darker = (c) => c.map((v) => Math.round(v * 0.6));
const editorImages = {};
for (const [k, c] of Object.entries(COLORMAP)) editorImages[`floor_editor_${k}`] = diamond(32, darker(hex(c)), hex(c));
editorImages.floor_editor_r_door = diamond(32, [200, 200, 200], [255, 255, 255]);
editorImages.floor_editor_r_blocked = diamond(32, [120, 0, 0], [200, 40, 40]);
writeBundle(join(generic, 'floor_editor.nitro'), 'floor_editor', {}, editorImages);

// Avatar additions: the typing bubble and the idle "z"s (bare keys; Nitro places them itself).
function bubble(w, h, dots) {
  const img = blank(w, h);
  for (let y = 0; y < h - 3; y++) for (let x = 0; x < w; x++) {
    const corner = (x === 0 || x === w - 1) && (y === 0 || y === h - 4);
    if (corner) continue;
    const edge = x === 0 || x === w - 1 || y === 0 || y === h - 4;
    put(img, x, y, edge ? [40, 40, 40] : [255, 255, 255]);
  }
  // Tail.
  for (let i = 0; i < 3; i++) for (let x = 3; x < 3 + 3 - i; x++) put(img, x, h - 3 + i, x === 3 + 2 - i ? [40, 40, 40] : [255, 255, 255]);
  if (dots) for (let i = 0; i < 3; i++) { const cx = Math.round(w / 2 - 4 + 4 * i), cy = Math.round((h - 3) / 2) - 1; put(img, cx, cy, [40, 40, 40]); put(img, cx + 1, cy, [40, 40, 40]); put(img, cx, cy + 1, [40, 40, 40]); put(img, cx + 1, cy + 1, [40, 40, 40]); }
  return img;
}
function zz(size) {
  const img = blank(size * 3 + 2, size * 3 + 2);
  for (const [ox, oy, s] of [[0, size * 2, size], [size + 1, size, size], [size * 2 + 1, 0, size]]) {
    for (let x = 0; x < s; x++) { put(img, ox + x, oy, [255, 255, 255]); put(img, ox + x, oy + s - 1, [255, 255, 255]); put(img, ox + s - 1 - x, oy + x, [255, 255, 255]); }
  }
  return img;
}
writeBundle(join(generic, 'avatar_additions.nitro'), 'avatar_additions', {}, {
  avatar_addition_user_typing: bubble(22, 17, true),
  avatar_addition_user_typing_small: bubble(14, 11, false),
  avatar_addition_user_idle_left_1: zz(3),
  avatar_addition_user_idle_left_2: zz(4),
  avatar_addition_user_idle_right_1: zz(3),
  avatar_addition_user_idle_right_2: zz(4),
  avatar_addition_user_idle_left_1_small: zz(2),
  avatar_addition_user_idle_left_2_small: zz(2),
  avatar_addition_user_idle_right_1_small: zz(2),
  avatar_addition_user_idle_right_2_small: zz(2),
});

mkdirSync(join(out, 'gamedata'), { recursive: true });
// Catalogue icons for the floor and wallpaper items: our own tile pictures.
{
  const icons = join(out, 'dcr', 'hof_furni', 'icons');
  mkdirSync(icons, { recursive: true });
  const icon = (file) => {
    const img = load(join(spritesDir, 'tiles', file));
    const b = box(img) ?? [0, 0, img.width, img.height];
    return encode(half(crop(img, b)));
  };
  writeFileSync(join(icons, 'floor_icon.png'), icon(`floor_${DEFAULT_FLOOR}.png`));
  writeFileSync(join(icons, 'wallpaper_icon.png'), icon(`wall_r_${DEFAULT_WALL}.png`));
  writeFileSync(join(icons, 'landscape_icon.png'), icon(`wall_r_sky.png`));
  // The catalogue's floor and wall pages show one picture per style (c_images/catalogue/th_*).
  const thumbs = join(out, 'c_images', 'catalogue');
  mkdirSync(thumbs, { recursive: true });
  const thumb = (file) => {
    const img = load(join(spritesDir, 'tiles', file));
    return encode(crop(img, box(img) ?? [0, 0, img.width, img.height]));
  };
  for (const n of floors) writeFileSync(join(thumbs, `th_floor_${code(floors, n)}.png`), thumb(`floor_${n}.png`));
  for (const n of walls) writeFileSync(join(thumbs, `th_wall_${code(walls, n)}.png`), thumb(`wall_r_${n}.png`));
}
writeFileSync(
  join(out, 'gamedata', 'paints.json'),
  JSON.stringify({ floors: Object.fromEntries(floors.map((n) => [code(floors, n), n])), walls: Object.fromEntries(walls.map((n) => [code(walls, n), n])) }, null, 1),
);

console.log(`generic bundles: ${floors.length} floors, ${walls.length} walls -> ${generic}`);
