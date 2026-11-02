#!/usr/bin/env node
// Builds Nitro's avatar files from the Cozy avatar kit (sprites/cozy):
//
//   bundled/figure/bobba_<sex>_<part>_<nn>.nitro  one figure library per clothing piece
//   gamedata/FigureData.json   the set types and sets (what the avatar editor offers)
//   gamedata/FigureMap.json    which library holds which part
//   gamedata/HabboAvatarActions.json
//
// The kit: per sex (m, f), pose (idle, walk, sit) and piece (body, shoes, bottom, top, hair) one
// 512x320 sheet, 8 frames across and 4 views down (down-left, down-right, up-right, up-left),
// each frame 64x80 with the feet at (32, 75).
//
// In Nitro a figure is "settype-id" pieces ("hd-101.hr-104.ch-112.lg-103.sh-102"); each set is
// drawn as parts of a part type, and the part type decides the drawing order. Every piece is in
// the torso so it follows walking and sitting, in this order (Nitro's torso order, back to front,
// the same standing and sitting):
//
//   body bd < shoes lg < bottom ch < top wa < hair cc < high-necked top ca
//
// Set types (what the avatar editor groups by): hd body, sh shoes, lg bottom, ch top, hr hair.
// Set and part ids: 100 + n for the male pieces, 200 + n for the female ones.
//
// Directions: Nitro has 8; our views are used as 0 up-right, 1-2 down-right, 3-5 down-left,
// 6-7 up-left (the renderer is set not to mirror 4-6, so each keeps the kit's own drawing).
//
// Usage: node tools/nitro/build-figure.mjs [outDir] [spritesDir]

import { mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { blank, box, crop, half, load } from './png.mjs';
import { writeBundle } from './bundle.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
const out = process.argv[2] ?? join(root, 'build', 'nitro');
const spritesDir = process.argv[3] ?? join(root, 'sprites');
const kit = join(spritesDir, 'cozy');
mkdirSync(join(out, 'bundled', 'figure'), { recursive: true });
mkdirSync(join(out, 'gamedata'), { recursive: true });

const FRAME = { w: 64, h: 80, footX: 32, footY: 75, frames: 8 };
const POSES = { std: 'idle', wlk: 'walk', sit: 'sit' };
/** Nitro direction -> sheet row (0 down-left, 1 down-right, 2 up-right, 3 up-left). */
const ROW = [2, 1, 1, 0, 0, 0, 3, 3];
/** Tops from this number up are high-necked: drawn over the hair. */
const HIGH_TOP = 13;
const SET_TYPE = { body: 'hd', shoes: 'sh', bottom: 'lg', top: 'ch', hair: 'hr' };
const partType = (piece, n) => ({ body: 'bd', shoes: 'lg', bottom: 'ch', top: n >= HIGH_TOP ? 'ca' : 'wa', hair: 'cc' })[piece];
const idOf = (sex, n) => (sex === 'm' ? 100 : 200) + n;

const sheets = new Map();
const sheet = (file) => sheets.get(file) ?? sheets.set(file, load(file)).get(file);

/**
 * The sitting pictures keep the body where it is standing and bend the legs: the seat is 20 px
 * above the feet (row 56). Their bodies also lean a little sideways per view; SEAT_DX puts each
 * view's body back over the middle of the seat.
 */
const SEAT_ROW = 56;
const SEAT_DX = [-2, 2, -1, 1];
/** How far our pictures are moved [right, down] at full size, to stand in the middle of the tile. */
const NUDGE = [0, 2];

/** One frame of a sheet (at half size when `small`), cropped to what's drawn; null when empty. */
function frameOf(img, row, col, small = false) {
  let f = crop(img, [col * FRAME.w, row * FRAME.h, (col + 1) * FRAME.w, (row + 1) * FRAME.h]);
  if (small) f = half(f);
  const b = box(f, 0);
  return b ? { img: crop(f, b), left: b[0], top: b[1] } : null;
}

/** A soft oval for the shadow under the feet (Nitro draws it at half strength). */
function shadow(w, h) {
  const img = blank(w, h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const dx = (x + 0.5 - w / 2) / (w / 2), dy = (y + 0.5 - h / 2) / (h / 2);
    if (dx * dx + dy * dy <= 1) img.data.set([0, 0, 0, 255], (y * w + x) * 4);
  }
  return img;
}

const figureData = { palettes: [{ id: 1, colors: [{ id: 1, index: 1, club: 0, selectable: true, hexCode: 'FFFFFF' }] }], setTypes: [] };
const setTypes = {};
for (const [piece, type] of Object.entries(SET_TYPE)) {
  setTypes[piece] = {
    type, paletteId: 1,
    mandatory_m_0: piece === 'body', mandatory_f_0: piece === 'body', mandatory_m_1: piece === 'body', mandatory_f_1: piece === 'body',
    sets: [],
  };
  figureData.setTypes.push(setTypes[piece]);
}
const figureMap = { libraries: [] };
let built = 0;

for (const sex of ['m', 'f']) {
  const files = readdirSync(join(kit, sex, 'idle')).filter((f) => /^[a-z]+_\d+\.png$/.test(f)).sort();
  for (const file of files) {
    const [, piece, nn] = /^([a-z]+)_(\d+)\.png$/.exec(file);
    if (!SET_TYPE[piece]) continue;
    const n = Number(nn);
    const id = idOf(sex, n);
    const type = partType(piece, n);
    const lib = `bobba_${sex}_${piece}_${nn}`;
    const assets = {};
    const images = {};

    for (const [def, pose] of Object.entries(POSES)) {
      const img = sheet(join(kit, sex, pose, file));
      for (let row = 0; row < 4; row++) {
        for (let col = 0; col < FRAME.frames; col++) {
          const f = frameOf(img, row, col);
          if (!f) continue;
          // The first Nitro direction that uses this row owns the picture; the rest point at it.
          const dirs = ROW.map((r, d) => (r === row ? d : -1)).filter((d) => d >= 0);
          const own = dirs[0];
          // The row of the picture that goes on the avatar's point: the feet standing, the seat
          // sitting (Nitro draws sitting avatars half a tile lower, then raises them by the seat's
          // height).
          const anchor = def === 'sit' ? SEAT_ROW + 32 : FRAME.footY;
          const dx = def === 'sit' ? SEAT_DX[row] : 0;
          for (const [scale, k] of [['h', 1], ['sh', 2]]) {
            const name = `${scale}_${def}_${type}_${id}_${own}_${col}`;
            const g = k === 1 ? f : frameOf(img, row, col, true);
            // Nitro puts the image's top-left at (-scale/2 - x, -y) from the avatar's point;
            // NUDGE moves it onto the middle of the tile (measured in the client).
            const x = -g.left - Math.round((NUDGE[0] + dx) / k), y = Math.round((anchor - NUDGE[1]) / k) - g.top;
            images[`${lib}_${name}`] = g.img;
            assets[name] = { x, y };
            for (const d of dirs.slice(1)) assets[`${scale}_${def}_${type}_${id}_${d}_${col}`] = { source: name, x, y };
          }
        }
      }
    }
    if (piece === 'body') {
      images[`${lib}_h_std_sd_1_0_0`] = shadow(34, 16);
      assets.h_std_sd_1_0_0 = { x: 0, y: 0 };
      images[`${lib}_sh_std_sd_1_0_0`] = shadow(17, 8);
      assets.sh_std_sd_1_0_0 = { x: 0, y: 0 };
    }
    writeBundle(join(out, 'bundled', 'figure', `${lib}.nitro`), lib, { type: 'figure', assets }, images);
    figureMap.libraries.push({ id: lib, revision: 1, parts: [{ id, type }] });
    setTypes[piece].sets.push({
      id, gender: sex.toUpperCase(), club: 0, colorable: false, selectable: true, preselectable: true, sellable: false,
      parts: [{ id, type, colorable: false, index: 0, colorindex: 0 }],
    });
    built++;
  }
}

// Actions. Precedence: higher is applied first, so the posture (Sit, Move) wins over Default.
const actions = {
  actions: [
    { id: 'Default', state: 'std', precedence: 1000, main: true, isDefault: true, geometryType: 'vertical', activePartSet: 'figure', assetPartDefinition: 'std' },
    { id: 'Move', state: 'mv', precedence: 900, main: true, geometryType: 'vertical', activePartSet: 'walk', assetPartDefinition: 'wlk' },
    { id: 'Sit', state: 'sit', precedence: 900, main: true, geometryType: 'sitting', activePartSet: 'sit', assetPartDefinition: 'sit' },
    { id: 'Talk', state: 'talk', precedence: 500, geometryType: 'vertical', activePartSet: 'speak', assetPartDefinition: 'spk' },
    { id: 'CarryItem', state: 'cri', precedence: 300, geometryType: 'vertical', activePartSet: 'handRight', assetPartDefinition: 'crr', params: [{ id: 'default', value: '1' }] },
  ],
  actionOffsets: [],
};

writeFileSync(join(out, 'gamedata', 'FigureData.json'), JSON.stringify(figureData));
writeFileSync(join(out, 'gamedata', 'FigureMap.json'), JSON.stringify(figureMap));
writeFileSync(join(out, 'gamedata', 'HabboAvatarActions.json'), JSON.stringify(actions));
console.log(`${built} figure libraries -> ${join(out, 'bundled', 'figure')}`);
