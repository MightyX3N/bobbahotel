#!/usr/bin/env node
// UI pictures for the Nitro client that aren't furni or rooms:
//
//   images/wallet/{-1,0,5,hc}.png   currency icons in the purse (credits, duckets, diamonds, club)
//   images/hotelview.png            the hotel view picture, copied from sprites/hotelview.png
//                                   (a picture of a room made from the licensed art, so it lives
//                                   with the sprites and not in git)
//
// The icons are drawn here from little pixel maps.
//
// Usage: node tools/nitro/build-ui.mjs [outDir] [spritesDir]
import { copyFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { blank, encode } from './png.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
const out = process.argv[2] ?? join(root, 'build', 'nitro');
const spritesDir = process.argv[3] ?? join(root, 'sprites');

/** A picture from rows of characters; `colours` maps each character to [r, g, b] ('.' is empty). */
function draw(rows, colours) {
  const img = blank(rows[0].length, rows.length);
  rows.forEach((row, y) =>
    [...row].forEach((ch, x) => {
      const c = colours[ch];
      if (c) img.data.set([...c, 255], (y * img.width + x) * 4);
    }),
  );
  return img;
}

const OUTLINE = [45, 30, 20];

const coin = draw(
  [
    '....oooooo....',
    '..ooYYYYYYoo..',
    '.oYYWWYYYYyYo.',
    '.oYWYYYYYYyYo.',
    'oYYWYYyyYYYyYo',
    'oYYYYyYYyYYyYo',
    'oYYYYyYYyYYyYo',
    'oYYYYyYYyYYyYo',
    'oYYYYyYYyYYyYo',
    'oYYYYYyyYYYyYo',
    '.oYYYYYYYYyYo.',
    '.oYyYYYYYyyYo.',
    '..ooyyyyyyoo..',
    '....oooooo....',
  ],
  { o: OUTLINE, Y: [250, 196, 40], y: [205, 140, 20], W: [255, 245, 190] },
);

const ducket = draw(
  [
    '.....ooo......',
    '....oYYYo.....',
    '...oYYkYYo....',
    '...oYYYYYoo...',
    '....oYYYoRRo..',
    '...ooYYYooo...',
    '..oYYYYYYYoo..',
    '.oYYWWYYYYYYo.',
    '.oYWYYYYYYYYo.',
    '.oYYYYYYYYyYo.',
    '..oYYYYYYyYo..',
    '...ooyyyyoo...',
    '.....oooo.....',
  ],
  { o: OUTLINE, Y: [255, 214, 64], y: [214, 160, 30], W: [255, 248, 200], k: [30, 30, 30], R: [240, 120, 40] },
);

const diamond = draw(
  [
    '...ooooooo....',
    '..oWWBBBBBo...',
    '.oWWBBbBBBBo..',
    'oooooooooooooo',
    '.oBBBBBBBbbbo.',
    '..oBWBBBBbbo..',
    '...oBBBBbbo...',
    '....oBBbbo....',
    '.....oBbo.....',
    '......oo......',
  ],
  { o: [20, 40, 80], B: [80, 180, 250], b: [40, 120, 210], W: [210, 240, 255] },
);

const club = draw(
  [
    'o....oo....o..',
    'oo..oYYo..oo..',
    'oYooYYYYooYo..',
    'oYYYYYYYYYYo..',
    'oYRYYYRYYYRo..',
    'oYYYYYYYYYYo..',
    'oyyyyyyyyyyo..',
    'oooooooooooo..',
  ],
  { o: OUTLINE, Y: [250, 196, 40], y: [205, 140, 20], R: [220, 50, 60] },
);

const wallet = join(out, 'images', 'wallet');
mkdirSync(wallet, { recursive: true });
writeFileSync(join(wallet, '-1.png'), encode(coin));
writeFileSync(join(wallet, '0.png'), encode(ducket));
writeFileSync(join(wallet, '5.png'), encode(diamond));
writeFileSync(join(wallet, 'hc.png'), encode(club));

const view = join(spritesDir, 'hotelview.png');
if (existsSync(view)) copyFileSync(view, join(out, 'images', 'hotelview.png'));
console.log(`UI pictures -> ${join(out, 'images')}${existsSync(view) ? ' (with the hotel view)' : ' (no sprites/hotelview.png yet)'}`);
