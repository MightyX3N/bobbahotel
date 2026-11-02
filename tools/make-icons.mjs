#!/usr/bin/env node
// Draws the app icon (a golden pixel room key on Bobba blue) and saves it in the sizes phones and
// browsers want: client/public/icons/*.png. Our own drawing, no licensed art.
//   node tools/make-icons.mjs
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

// Playwright (with its Chromium) is used to draw the PNGs; install it with `npm i -g playwright`.
const { chromium } = createRequire(import.meta.url)('playwright');

const out = fileURLToPath(new URL('../client/public/icons/', import.meta.url));

// The key on a 16x16 pixel grid: K = gold, D = dark gold (shade), H = shine.
const KEY = [
  '................',
  '....KKKK........',
  '...KHHHDK.......',
  '..KH....DK......',
  '..KH....DK......',
  '..KD....DK......',
  '...KDDDDK.......',
  '....KKKK........',
  '......KD........',
  '......KD........',
  '......KDKK......',
  '......KDDK......',
  '......KD........',
  '......KDKKK.....',
  '......KDDDK.....',
  '.......KK.......',
];
const COLORS = { K: '#f0b800', D: '#b07d00', H: '#ffe27a' };

function svg(size, { padding, round }) {
  const cell = (size * (1 - 2 * padding)) / 16;
  const off = size * padding;
  let rects = '';
  KEY.forEach((row, y) =>
    [...row].forEach((c, x) => {
      if (c !== '.') rects += `<rect x="${(off + x * cell + cell * 1.5).toFixed(2)}" y="${(off + y * cell).toFixed(2)}" width="${cell + 0.5}" height="${cell + 0.5}" fill="${COLORS[c]}"/>`;
    }),
  );
  const r = round ? size * 0.2 : 0;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" shape-rendering="crispEdges">
    <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a8bb3"/><stop offset="1" stop-color="#185d79"/></linearGradient></defs>
    <rect width="${size}" height="${size}" rx="${r}" fill="url(#g)"/>${rects}</svg>`;
}

const browser = await chromium.launch();
const page = await browser.newPage();
const shots = [
  ['icon-192.png', 192, { padding: 0.12, round: true }],
  ['icon-512.png', 512, { padding: 0.12, round: true }],
  // Maskable: the system cuts its own shape, so no rounding and more room around the key.
  ['icon-maskable-512.png', 512, { padding: 0.22, round: false }],
  ['apple-touch-icon.png', 180, { padding: 0.14, round: false }],
  ['favicon-32.png', 32, { padding: 0.04, round: true }],
];
for (const [name, size, opts] of shots) {
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(`<html><body style="margin:0;background:transparent">${svg(size, opts)}</body></html>`);
  writeFileSync(out + name, await page.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } }));
}
writeFileSync(out + 'icon.svg', svg(512, { padding: 0.12, round: true }));
await browser.close();
console.log('Icons written to', out);
