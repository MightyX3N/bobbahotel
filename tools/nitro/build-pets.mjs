#!/usr/bin/env node
// Pets, the Habbo way (Nitro's pet format): <out>/bundled/pet/<type>.nitro
//
//   cat  from sprites/cats (IsoCat: IsoCat_Ginger/Black/Grey.png, each a 6x6 sheet of 64 px frames,
//        all three drawn the same with other colours). The colours become Habbo's pet palettes:
//        the pictures are stored once with a colour number in each pixel (green channel) and each
//        palette says which colour each number is, so the server's race 0/1/2 picks ginger/black/grey.
//
// Sheet rows: 0 walking towards us (facing right), 1 walking away (facing right), 2 sitting, 3 lying
// (frame 0) then standing up on its hind legs, 4 eating towards us, 5 eating away from us.
// Every frame's feet are at (32, 58), so every frame is pinned there and nothing shifts.
//
// Usage: node tools/nitro/build-pets.mjs [outDir] [spritesDir]
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { blank, box, crop, encode, half, load } from './png.mjs';
import { writeBundle } from './bundle.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
const out = process.argv[2] ?? join(root, 'build', 'nitro');
const spritesDir = process.argv[3] ?? join(root, 'sprites');
const dir = join(out, 'bundled', 'pet');
mkdirSync(dir, { recursive: true });

const CAT_COLOURS = [
  ['Ginger', 'F2A541'],
  ['Black', '3A3A44'],
  ['Grey', 'A0A4AC'],
];
const FRAME = 64;
const FEET = [32, 58];

function buildCat() {
  const sheets = CAT_COLOURS.map(([n]) => load(join(spritesDir, 'cats', `IsoCat_${n}.png`)));
  const W = sheets[0].width, H = sheets[0].height;
  // Colour numbers: one per combination of (ginger, black, grey) colours at a pixel. Shadow pixels
  // (half see-through) get numbers from 200 up: Nitro reads the number after multiplying by the
  // pixel's alpha, so their halves (100+) map to the shadow colour too.
  const numbers = new Map();
  const rgb = CAT_COLOURS.map(() => Array.from({ length: 256 }, () => [0, 0, 0]));
  let next = 1, nextShadow = 200;
  const indexed = blank(W, H);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const px = sheets.map((s) => [...s.data.subarray((y * W + x) * 4, (y * W + x) * 4 + 4)]);
      const alpha = Math.max(...px.map((p) => p[3]));
      if (!alpha) continue;
      const key = px.map((p) => p.join(',')).join('|');
      if (!numbers.has(key)) {
        const shadow = alpha < 255;
        const n = shadow ? nextShadow++ : next++;
        if (n > 255 || (!shadow && n >= 100)) throw new Error('too many cat colours');
        numbers.set(key, n);
        px.forEach((p, i) => {
          const c = p[3] ? p.slice(0, 3) : px.find((q) => q[3]).slice(0, 3);
          rgb[i][n] = c;
          if (shadow) rgb[i][Math.round((n * alpha) / 255)] = c;
        });
      }
      const n = numbers.get(key);
      indexed.data.set([n, n, n, alpha], (y * W + x) * 4);
    }
  }

  const frame = (row, col) => crop(indexed, [col * FRAME, row * FRAME, col * FRAME + FRAME, row * FRAME + FRAME]);
  // Animations: [posture, sheet row towards us, sheet row away from us, frames, speed]
  const ANIMS = [
    ['std', [0, [0]], [1, [0]]],
    ['mv', [0, [0, 1, 2, 3, 4, 5]], [1, [0, 1, 2, 3, 4, 5]]],
    ['sit', [2, [0, 1, 2, 3, 4, 5, 4, 3, 2, 1]], [2, [0, 1, 2, 3, 4, 5, 4, 3, 2, 1]]],
    ['lay', [3, [0]], [3, [0]]],
    ['eat', [4, [0, 1, 2, 3, 4, 5, 5, 5, 4, 5]], [5, [0, 1, 2, 3, 4, 5, 5, 5, 4, 5]]],
    ['jmp', [3, [1, 2, 3, 4, 5, 5, 4, 3, 2, 1]], [3, [1, 2, 3, 4, 5, 5, 4, 3, 2, 1]]],
  ];
  // Other postures the server sends, shown as one of ours.
  const ALIASES = { drk: 'eat', snf: 'eat', beg: 'jmp', ded: 'lay', slp: 'lay', rlx: 'lay', scr: 'sit', bnd: 'sit', grn: 'sit', wav: 'jmp', flt: 'std', spd: 'mv' };
  // Directions (0 up-right ... 7 up, clockwise): which drawing (towards us / away) and mirrored.
  const DIRS = { 0: ['away', false], 1: ['near', false], 2: ['near', false], 3: ['near', false], 4: ['near', true], 5: ['near', true], 6: ['away', true], 7: ['away', false] };

  const name = 'cat';
  const images = {};
  const assets = {};
  const animations = {};
  const postures = [];
  ANIMS.forEach(([posture, near, away], animId) => {
    const frames = {};
    near[1].forEach((col, i) => {
      const fid = animId * 100 + i;
      frames[i] = { id: fid };
      for (const [d, [which, flip]] of Object.entries(DIRS)) {
        const [row, cols] = which === 'near' ? near : away;
        const c = cols[i % cols.length];
        for (const size of [64, 32]) {
          const asset = `${name}_${size}_a_${d}_${fid}`;
          const src = `${name}_${size}_a_${which === 'near' ? 2 : 0}_${fid}`;
          if (!flip && (d === '2' || d === '0')) {
            const img = frame(row, c);
            // Rooms use the small view (32) at TinyHouse scale: the cat at its own size there too.
            images[`${name}_${asset}`] = img;
            assets[asset] = { x: FEET[0], y: FEET[1], usesPalette: true };
          } else {
            assets[asset] = { source: src, flipH: flip, x: FEET[0], y: FEET[1], usesPalette: true };
          }
        }
      }
    });
    animations[animId] = { layers: { 0: { frameRepeat: 3, frameSequences: { 0: { frames } } } } };
    postures.push({ id: posture, animationId: animId });
  });
  for (const [alias, to] of Object.entries(ALIASES)) postures.push({ id: alias, animationId: ANIMS.findIndex(([p]) => p === to) });
  // Sources come before the assets that use them (Nitro reads them in order).
  const ordered = Object.fromEntries([...Object.entries(assets).filter(([, a]) => !a.source), ...Object.entries(assets).filter(([, a]) => a.source)]);

  const directions = Object.fromEntries(Object.keys(DIRS).map((d) => [d, {}]));
  const vis = (size) => ({
    size,
    layerCount: 1,
    angle: 45,
    layers: { 0: { z: 0 } },
    directions,
    animations,
    postures: { defaultPosture: 'std', postures },
    gestures: [],
  });
  const palettes = Object.fromEntries(
    CAT_COLOURS.map(([n, colour], i) => [String(i), { id: i, source: `${name}_palette_${i}`, master: true, tags: [], breed: i, colorTag: i, color1: colour, color2: 'FFFFFF', rgb: rgb[i] }]),
  );
  writeBundle(join(dir, `${name}.nitro`), name, {
    type: name,
    visualizationType: 'pet_animated',
    logicType: 'pet',
    assets: ordered,
    palettes,
    visualizations: [vis(64), vis(32)],
  }, images);
  // The catalogue's Pets page icon: the ginger cat sitting, at half size.
  const sitting = crop(sheets[0], [0, 2 * FRAME, FRAME, 3 * FRAME]);
  const icons = join(out, 'c_images', 'catalogue');
  mkdirSync(icons, { recursive: true });
  writeFileSync(join(icons, 'icon_9150.png'), encode(half(crop(sitting, box(sitting) ?? [0, 0, FRAME, FRAME]))));
  console.log(`pet ${name}: ${numbers.size} colours, ${Object.keys(images).length} pictures`);
}

if (existsSync(join(spritesDir, 'cats', 'IsoCat_Ginger.png'))) buildCat();
else console.warn('  no cats (sprites/cats is missing)');
