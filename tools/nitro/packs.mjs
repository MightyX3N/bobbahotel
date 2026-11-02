// Pictures from the other packs (besides sprites/tiles, furni and cozy), turned into the formats
// the builders use. Each pack lives in its own folder in sprites/; a missing folder is skipped.
//
//   sprites/casino/  ThirdAngle Casino Pack (objects 64x64, walls 64x128, floors 64x64)
import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { blank, load } from './png.mjs';

const get = (img, x, y) => {
  if (x < 0 || y < 0 || x >= img.width || y >= img.height) return [0, 0, 0, 0];
  const i = (y * img.width + x) * 4;
  return [...img.data.subarray(i, i + 4)];
};
const set = (img, x, y, c) => {
  if (x < 0 || y < 0 || x >= img.width || y >= img.height) return;
  img.data.set(c, (y * img.width + x) * 4);
};
const darker = ([r, g, b, a], k) => [Math.round(r * k), Math.round(g * k), Math.round(b * k), a];

/**
 * Floor and wall styles made from the packs, as our 64x64 tile pictures:
 * { 'floor_<name>.png': picture, 'wall_l_<name>.png': ..., 'wall_r_<name>.png': ... }.
 */
export function derivedTiles(spritesDir) {
  const out = {};
  const casino = join(spritesDir, 'casino');
  if (existsSync(join(casino, 'wall_plain_right.png'))) {
    // Floors: their diamond is in the bottom half of the canvas; ours has its top corner at (32,16)
    // with the tile's edge (8 px) under it.
    for (const [file, name] of [['floor_casino_carpet', 'casinocarpet'], ['floor_casino_marble', 'casinomarble']]) {
      const src = load(join(casino, `${file}.png`));
      const t = blank(64, 64);
      for (let y = 32; y < 64; y++) for (let x = 0; x < 64; x++) set(t, x, y - 16, get(src, x, y));
      // The edge: the bottom outline of the diamond, carried down 8 px and darkened.
      for (let x = 0; x < 64; x++) {
        let last = -1;
        for (let y = 0; y < 48; y++) if (get(t, x, y)[3] > 0) last = y;
        if (last < 0) continue;
        const c = darker(get(t, x, last), 0.7);
        for (let k = 1; k <= 8; k++) set(t, x, last + k, c);
      }
      out[`floor_${name}.png`] = t;
    }
    // Walls: each piece is two tiles long and 70 px tall (a 3 px lighter top, then the face, the
    // brass skirting at the bottom). Our wall pictures have a 32 px wide face 40 tall at x 16..47,
    // its top at y 8 (+ half a pixel per pixel along the slope) and the wall's top above it; the
    // face repeats upwards, so it is cut from the plain middle of theirs.
    for (const [side, rising] of [['r', false], ['l', true]]) {
      const src = load(join(casino, `wall_plain_${rising ? 'left' : 'right'}.png`));
      const t = blank(64, 64);
      for (let u = 0; u < 32; u++) {
        const sx = rising ? 32 + u : u; // one tile of theirs: the half nearest the corner
        let top = 0;
        while (top < src.height && get(src, sx, top)[3] === 0) top++;
        const ourTop = 8 + (rising ? (31 - u) >> 1 : u >> 1);
        for (let k = 1; k <= 4; k++) set(t, 16 + u, ourTop - k, get(src, sx, top));
        for (let v = 0; v < 40; v++) set(t, 16 + u, ourTop + v, get(src, sx, top + 14 + v));
      }
      out[`wall_${side}_casino.png`] = t;
    }
  }
  return out;
}

/** Furni pictures made from the packs: { name: picture }, used by name in the furni list. */
export function derivedFurni(spritesDir) {
  const out = {};
  const casino = join(spritesDir, 'casino');
  if (existsSync(join(casino, 'wall_plain_right.png'))) {
    // Wall decorations: a decorated wall piece minus the plain one is the decoration alone.
    for (const deco of ['sconce_light', 'velvet_drape', 'security_camera', 'neon_accent']) {
      for (const side of ['left', 'right']) {
        const plain = load(join(casino, `wall_plain_${side}.png`));
        const full = load(join(casino, `wall_${deco}_${side}.png`));
        const t = blank(full.width, full.height);
        for (let y = 0; y < full.height; y++) {
          for (let x = 0; x < full.width; x++) {
            const a = get(full, x, y), b = get(plain, x, y);
            if (a[3] && (Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) + Math.abs(a[2] - b[2]) > 6 || !b[3])) set(t, x, y, a);
          }
        }
        out[`casino/deco_${deco}_${side}`] = t;
      }
    }
  }
  return { ...out, ...gamePictures(spritesDir), ...carPictures(spritesDir), ...cityTiles(spritesDir) };
}

/**
 * PixelHeatCity's ground tiles (one 4096 px sheet: rows of 256x136 tiles, each 4x4 of our tiles):
 * the top diamond of each, without the tile's edge, as "city/ground/<row>/<column>".
 */
function cityTiles(spritesDir) {
  const out = {};
  const file = join(spritesDir, 'city', '1_PHC_Floor_Tiles', 'PHC_Floors&Roads.png');
  if (!existsSync(file)) return out;
  const sheet = load(file);
  const ROWS = [64, 320, 575, 831, 1088];
  ROWS.forEach((y0, row) => {
    for (let col = 0; col < 16; col++) {
      const t = blank(256, 129);
      let any = false;
      for (let y = 0; y <= 128; y++) {
        for (let x = 0; x < 256; x++) {
          if (Math.abs(x + 0.5 - 128) / 128 + Math.abs(y - 64) / 64 > 1.02) continue;
          const c = get(sheet, col * 256 + x, y0 + y);
          if (c[3]) { set(t, x, y, c); any = true; }
        }
      }
      if (any) out[`city/ground/${row}/${col}`] = t;
    }
  });
  return out;
}

/**
 * PixelWheels cars: each sheet is 4 columns (lights flashing, on the "Lights" sheets) by 16 rows,
 * one row per heading, 22.5 degrees apart: row 0 drives away from us, 4 to the right, 8 towards us.
 * Habbo's four furni directions are the rows nearest to the floor's diagonals: 3 (up-right, 0),
 * 5 (down-right, 2), 11 (down-left, 4) and 13 (up-left, 6). Named "cars/<file>/<row>/<column>".
 */
export const CAR_ROWS = { 0: 3, 2: 5, 4: 11, 6: 13 };
function carPictures(spritesDir) {
  const out = {};
  const dir = join(spritesDir, 'cars');
  if (!existsSync(dir)) return out;
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.png'))) {
    const sheet = load(join(dir, file));
    const fw = sheet.width / 4, fh = sheet.height / 16;
    const name = file.slice(0, -4);
    for (const row of Object.values(CAR_ROWS)) {
      for (let col = 0; col < 4; col++) {
        const t = blank(fw, fh);
        for (let y = 0; y < fh; y++) sheet.data.copy(t.data, y * fw * 4, ((row * fh + y) * sheet.width + col * fw) * 4, ((row * fh + y) * sheet.width + col * fw + fw) * 4);
        out[`cars/${name}/${row}/${col}`] = t;
      }
    }
  }
  return out;
}

// ---- our own drawings for casino games ----

const PIPS = {
  1: [[0.5, 0.5]],
  2: [[0.25, 0.25], [0.75, 0.75]],
  3: [[0.25, 0.25], [0.5, 0.5], [0.75, 0.75]],
  4: [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]],
  5: [[0.25, 0.25], [0.75, 0.25], [0.5, 0.5], [0.25, 0.75], [0.75, 0.75]],
  6: [[0.25, 0.22], [0.75, 0.22], [0.25, 0.5], [0.75, 0.5], [0.25, 0.78], [0.75, 0.78]],
};
const OPPOSITE = { 1: 6, 2: 4, 3: 5, 4: 2, 5: 3, 6: 1 };
const SIDES = { 1: [2, 3], 2: [1, 3], 3: [1, 2], 4: [1, 5], 5: [1, 4], 6: [2, 4] };

/**
 * A die (Habbo's dice: 0 is the die closed, 1-6 a number on top, the rolling frames bounce it):
 * a white cube with red pips, standing on the middle of its tile (bottom corner at 32,57 on 64x64).
 */
function drawDie(top, lift = 0, tilt = 0) {
  const img = blank(64, 64);
  const W = 11, H = 5.5, Z = 11; // half width, half height of the top, height of the sides
  const cx = 32, cy = 57 - 2 * H - Z - lift; // top face centre
  const OUT = [70, 40, 40, 255];
  const faces = [
    // [colour, point(u, v) -> [x, y]] for the top, left and right faces
    [[250, 248, 240, 255], (u, v) => [cx + (u - v) * W, cy - H + (u + v) * H]],
    [[222, 216, 204, 255], (u, v) => [cx - W + u * W, cy + u * H + v * Z]],
    [[196, 188, 176, 255], (u, v) => [cx + u * W, cy + H - u * H + v * Z]],
  ];
  const fill = (f, col) => {
    for (let i = 0; i <= 60; i++) for (let j = 0; j <= 60; j++) {
      const [x, y] = f(i / 60, j / 60);
      set(img, Math.round(x - 0.5 + tilt * (j / 60)), Math.round(y - 0.5), col);
    }
  };
  faces.forEach(([col, f]) => fill(f, col));
  // outline: every drawn pixel next to an empty one
  const drawn = (x, y) => get(img, x, y)[3] > 0;
  const edge = [];
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) if (drawn(x, y) && (!drawn(x - 1, y) || !drawn(x + 1, y) || !drawn(x, y - 1) || !drawn(x, y + 1))) edge.push([x, y]);
  edge.forEach(([x, y]) => set(img, x, y, OUT));
  // the edges between the faces
  for (let i = 0; i <= 40; i++) {
    const [x1, y1] = faces[1][1](i / 40, 0); set(img, Math.round(x1 - 0.5), Math.round(y1 - 0.5), [180, 170, 160, 255]);
    const [x2, y2] = faces[2][1](i / 40, 0); set(img, Math.round(x2 - 0.5), Math.round(y2 - 0.5), [160, 150, 140, 255]);
    const [x3, y3] = faces[1][1](1, i / 40); set(img, Math.round(x3 - 0.5), Math.round(y3 - 0.5), [150, 140, 130, 255]);
  }
  if (top > 0) {
    const [left, right] = SIDES[top];
    const pips = (f, n, col) => PIPS[n].forEach(([u, v]) => {
      const [x, y] = f(u, v);
      set(img, Math.round(x - 1), Math.round(y - 0.5), col);
      set(img, Math.round(x), Math.round(y - 0.5), col);
    });
    pips(faces[0][1], top, [200, 30, 40, 255]);
    pips(faces[1][1], left, [170, 30, 40, 255]);
    pips(faces[2][1], right, [150, 25, 35, 255]);
  }
  void OPPOSITE;
  return img;
}

/** The jackpot wheel turned by `turn` (0..1 of a full turn): its coloured segments go round. */
function turnWheel(wheel, turn) {
  // The wheel's segments: the red, green and blue pixels. Their middle and size (it's an ellipse,
  // seen from the side) give each pixel's angle; the colour at each angle is read from the picture.
  const coloured = [];
  const isSegment = ([r, g, b, a]) => a > 200 && ((r > g + 70 && r > b + 70 && g < 90) || (g > r + 30 && g > b + 15) || (b > r + 50 && b > g));
  for (let y = 0; y < wheel.height; y++) for (let x = 0; x < wheel.width; x++) if (isSegment(get(wheel, x, y))) coloured.push([x, y]);
  if (!coloured.length) return wheel;
  const xs = coloured.map((p) => p[0]), ys = coloured.map((p) => p[1]);
  const mx = (Math.min(...xs) + Math.max(...xs) + 1) / 2, my = (Math.min(...ys) + Math.max(...ys) + 1) / 2;
  const rx = (Math.max(...xs) - Math.min(...xs) + 1) / 2, ry = (Math.max(...ys) - Math.min(...ys) + 1) / 2;
  const angle = (x, y) => Math.atan2((y + 0.5 - my) / ry, (x + 0.5 - mx) / rx);
  const BINS = 72;
  const votes = Array.from({ length: BINS }, () => new Map());
  for (const [x, y] of coloured) {
    const b = Math.floor(((angle(x, y) / (2 * Math.PI) + 1) % 1) * BINS);
    const c = get(wheel, x, y).join(',');
    votes[b].set(c, (votes[b].get(c) ?? 0) + 1);
  }
  const colourAt = votes.map((m) => [...m.entries()].sort((a, b) => b[1] - a[1])[0]?.[0]);
  const out = blank(wheel.width, wheel.height);
  wheel.data.copy(out.data);
  for (const [x, y] of coloured) {
    const b = Math.floor((((angle(x, y) / (2 * Math.PI) - turn) % 1 + 1) % 1) * BINS);
    let c = colourAt[b];
    for (let k = 1; !c && k < BINS; k++) c = colourAt[(b + k) % BINS];
    set(out, x, y, c.split(',').map(Number));
  }
  return out;
}

/**
 * A pet bowl (our own drawing): `fill` 0..1 of food (brown bits) or water (blue). Stands in the
 * middle of its tile like the dice.
 */
function drawBowl(fill, water) {
  const img = blank(64, 64);
  const cx = 32, cy = 50, rx = 12, ry = 6, h = 5;
  const RIM = [200, 60, 60, 255], RIM2 = [160, 40, 45, 255], IN = [120, 30, 35, 255], OUT = [70, 20, 25, 255];
  const inside = (x, y, a, b) => ((x - cx) / a) ** 2 + ((y - cy) / b) ** 2 <= 1;
  for (let y = cy - ry - 2; y <= cy + ry + h + 2; y++) {
    for (let x = cx - rx - 2; x <= cx + rx + 2; x++) {
      const top = inside(x + 0.5, y + 0.5, rx, ry);
      // the side: the lower half of the rim ellipse pushed down h pixels
      let side = false;
      for (let k = 0; k <= h; k++) if (inside(x + 0.5, y + 0.5 - k, rx - k * 0.3, ry - k * 0.15) && y + 0.5 - k >= cy) side = true;
      if (side && !top) set(img, x, y, RIM2);
      if (top) set(img, x, y, inside(x + 0.5, y + 0.5, rx - 2, ry - 1.5) ? IN : RIM);
    }
  }
  // what's in it
  if (fill > 0) {
    const a = (rx - 3) * Math.sqrt(fill), b = (ry - 2) * Math.sqrt(fill);
    const FOOD = [[150, 95, 50, 255], [185, 125, 70, 255], [120, 75, 40, 255]];
    const WATER = [[90, 160, 230, 255], [140, 200, 245, 255]];
    let i = 0;
    for (let y = cy - ry; y <= cy + ry; y++) {
      for (let x = cx - rx; x <= cx + rx; x++) {
        if (!inside(x + 0.5, y + 0.5 + 0.5, a, b)) continue;
        const c = water ? WATER[(x + y) % 5 === 0 ? 1 : 0] : FOOD[(i++ * 7 + y * 3) % 3];
        set(img, x, y, c);
      }
    }
  }
  // outline
  const drawn = (x, y) => get(img, x, y)[3] > 0;
  const edge = [];
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) if (drawn(x, y) && (!drawn(x - 1, y) || !drawn(x + 1, y) || !drawn(x, y - 1) || !drawn(x, y + 1))) edge.push([x, y]);
  edge.forEach(([x, y]) => set(img, x, y, OUT));
  return img;
}

/** Pictures for the casino games: dice (dice/0..6, dice/roll_0..3) and the jackpot wheel's turns. */
export function gamePictures(spritesDir) {
  const out = {};
  for (let n = 0; n <= 6; n++) out[`dice/${n}`] = drawDie(n);
  // Pet bowls: full, two thirds, a third, empty (the server counts each meal up to 3, then the
  // bowl is used up).
  [1, 0.66, 0.33, 0].forEach((f, i) => {
    out[`pets/foodbowl_${i}`] = drawBowl(f, false);
    out[`pets/waterbowl_${i}`] = drawBowl(f, true);
  });
  [[2, 4, 0], [5, 7, 1], [3, 5, 0], [6, 2, -1]].forEach(([top, lift, tilt], i) => (out[`dice/roll_${i}`] = drawDie(top, lift, tilt)));
  const wheelFile = join(spritesDir, 'casino', 'jackpot_wheel.png');
  if (existsSync(wheelFile)) {
    const wheel = load(wheelFile);
    // 8 stops (the results) and 12 frames of spinning
    for (let i = 0; i < 8; i++) out[`casino/wheel_stop_${i + 1}`] = turnWheel(wheel, i / 8);
    for (let i = 0; i < 12; i++) out[`casino/wheel_spin_${i}`] = turnWheel(wheel, i / 12);
  }
  return out;
}
