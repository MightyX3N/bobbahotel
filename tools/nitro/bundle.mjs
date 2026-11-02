// Writes a Nitro bundle (.nitro): the asset data (JSON) and its sprite sheet (PNG), each
// zlib-compressed, in Nitro's container (big-endian: file count, then per file its name and data).
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { deflateSync } from 'node:zlib';
import { blank, blit, encode } from './png.mjs';

/** Packs pictures into one sheet, in rows. Returns the sheet and each picture's [x, y, w, h]. */
export function packSheet(images, maxWidth = 1024) {
  let x = 0, y = 0, rowH = 0, sheetW = 0;
  const pos = {};
  // Tallest first keeps rows tight.
  const keys = Object.keys(images).sort((a, b) => images[b].height - images[a].height);
  for (const key of keys) {
    const img = images[key];
    if (x > 0 && x + img.width > maxWidth) { x = 0; y += rowH + 1; rowH = 0; }
    pos[key] = [x, y, img.width, img.height];
    x += img.width + 1;
    rowH = Math.max(rowH, img.height);
    sheetW = Math.max(sheetW, x);
  }
  const sheet = blank(Math.max(1, sheetW), Math.max(1, y + rowH));
  for (const key of keys) blit(images[key], sheet, pos[key][0], pos[key][1]);
  return { sheet, pos };
}

/**
 * name: the library's name.
 * data: the asset data. images: {frameKey: picture}. For room content (furni, room, cursor) Nitro
 * looks pictures up as "<name>_<asset source>", for UI bundles (floor editor, avatar additions)
 * by the bare key; either way the key is written with ".png" added, which Nitro strips.
 */
export function writeBundle(file, name, data, images) {
  const { sheet, pos } = packSheet(images);
  const full = {
    ...data,
    name,
    spritesheet: {
      frames: Object.fromEntries(
        Object.entries(pos).map(([k, [x, y, w, h]]) => [
          `${k}.png`,
          { frame: { x, y, w, h }, rotated: false, trimmed: false, spriteSourceSize: { x: 0, y: 0, w, h }, sourceSize: { w, h } },
        ]),
      ),
      meta: { app: 'bobbahotel', version: '1', image: `${name}.png`, format: 'RGBA8888', size: { w: sheet.width, h: sheet.height }, scale: '1' },
    },
  };
  const files = [
    [`${name}.json`, Buffer.from(JSON.stringify(full))],
    [`${name}.png`, encode(sheet)],
  ];
  const parts = [];
  const count = Buffer.alloc(2);
  count.writeInt16BE(files.length);
  parts.push(count);
  for (const [fn, raw] of files) {
    const nameBuf = Buffer.from(fn);
    const z = deflateSync(raw, { level: 9 });
    const head = Buffer.alloc(2 + nameBuf.length + 4);
    head.writeInt16BE(nameBuf.length, 0);
    nameBuf.copy(head, 2);
    head.writeInt32BE(z.length, 2 + nameBuf.length);
    parts.push(head, z);
  }
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, Buffer.concat(parts));
}
