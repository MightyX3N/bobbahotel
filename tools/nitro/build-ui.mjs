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
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
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

// Room layout pictures for "create a room" (images/navigator/models/model_<name>.png): each
// layout's floor drawn as little tiles, the door lighter.
{
  const models = JSON.parse(readFileSync(join(root, 'content', 'nitro', 'room-models.json'), 'utf8'));
  const dir = join(out, 'images', 'navigator', 'models');
  mkdirSync(dir, { recursive: true });
  const TOP = [196, 132, 80], DOOR = [240, 220, 170], LINE = [150, 96, 56];
  for (const [name, { heightmap, door }] of Object.entries(models)) {
    const rows = heightmap.map((r) => r.trimEnd());
    const cols = Math.max(...rows.map((r) => r.length));
    const tiles = [];
    rows.forEach((r, y) => [...r].forEach((c, x) => { if (c !== 'x' && c !== 'X') tiles.push([x, y]); }));
    if (!tiles.length) continue;
    const minS = Math.min(...tiles.map(([x, y]) => x - y)), maxS = Math.max(...tiles.map(([x, y]) => x - y));
    const minD = Math.min(...tiles.map(([x, y]) => x + y)), maxD = Math.max(...tiles.map(([x, y]) => x + y));
    // Tile size: as big as fits in about 150x110.
    // (a multiple of 4, so half a tile's height is whole pixels).
    const width = (t) => ((maxS - minS) * t) / 2 + t + 2;
    const height = (t) => ((maxD - minD) * t) / 4 + t / 2 + 4;
    let tw = 24;
    while (tw > 4 && (width(tw) > 150 || height(tw) > 110)) tw -= 4;
    const th = tw / 2;
    const W = width(tw), Hh = height(tw);
    const img = blank(W, Hh);
    const put = (x, y, c) => { if (x >= 0 && y >= 0 && x < W && y < Hh) img.data.set([...c, 255], (y * W + x) * 4); };
    tiles.sort((a, b) => a[0] + a[1] - (b[0] + b[1]));
    for (const [x, y] of tiles) {
      const cx = (x - y - minS) * (tw / 2) + tw / 2 + 1, cy = (x + y - minD) * (th / 2) + 1;
      const isDoor = x === door[0] && y === door[1];
      for (let r = 0; r < th; r++) {
        const half = r < th / 2 ? (r + 1) * 2 : (th - r) * 2;
        for (let i = -half; i < half; i++) put(cx + i, cy + r, isDoor ? DOOR : (r === th - 1 || Math.abs(i) >= half - 1 ? LINE : TOP));
      }
    }
    writeFileSync(join(dir, `${name}.png`), encode(img));
  }
}
