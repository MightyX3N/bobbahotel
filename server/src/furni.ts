// Furni definitions (content/furni/*.json) and their sprite sheets.
//
// A definition says which of a pack's pictures a furni uses. When the server starts it turns each
// definition into one sprite sheet plus a frame list (sprites/built/furni/<id>.png + .json), like
// Habbo's furni packages: every frame trimmed to the same box, with the anchor (the footprint's
// front corner) worked out from the definition's size. Sheets are only rebuilt when the
// definition or its pictures change. The pictures themselves are never changed.
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { PNG } from 'pngjs';
import { z } from 'zod';
import { furniFootprint, type FurniDef, type FurniDir, type FurniFrame, type FurniSheet } from '@bobba/shared';

const dirKey = z.enum(['0', '2', '4', '6']);
const dirImages = z.union([z.object({ frames: z.array(z.string()).min(1) }), z.object({ mirror: z.union([z.literal(0), z.literal(2), z.literal(4), z.literal(6)]) })]);
const defSchema = z.object({
  id: z.string().regex(/^[a-z0-9_]+$/),
  name: z.string().min(1),
  source: z.string().regex(/^[A-Za-z0-9_-]+$/).optional(),
  kind: z.enum(['floor', 'wall']),
  size: z.tuple([z.number().int().min(1).max(16), z.number().int().min(1).max(16)]),
  dirs: z.partialRecord(dirKey, dirImages),
  fps: z.number().positive().max(60).optional(),
  off: z.string().optional(),
  scale: z.number().positive().max(8).optional(),
  offset: z.tuple([z.number(), z.number()]).optional(),
  sit: z.boolean().optional(),
  walk: z.boolean().optional(),
  stack: z.boolean().optional(),
});
const packSchema = z.object({ pack: z.string(), source: z.string().regex(/^[A-Za-z0-9_-]+$/), items: z.array(defSchema) });

/** Definitions from content/furni/*.json, by id. */
export function loadFurniDefs(contentDir: string): Map<string, FurniDef> {
  const dir = join(contentDir, 'furni');
  const defs = new Map<string, FurniDef>();
  if (!existsSync(dir)) return defs;
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.json')).sort()) {
    const pack = packSchema.parse(JSON.parse(readFileSync(join(dir, file), 'utf8')));
    for (const raw of pack.items) {
      if (defs.has(raw.id)) throw new Error(`Furni ${raw.id} is defined twice (${file})`);
      const dirs: FurniDef['dirs'] = {};
      for (const [d, images] of Object.entries(raw.dirs)) dirs[Number(d) as FurniDir] = images;
      for (const images of Object.values(dirs)) {
        if ('mirror' in images && !(images.mirror in dirs && 'frames' in dirs[images.mirror]!)) throw new Error(`Furni ${raw.id}: mirrors a direction it has no pictures for`);
      }
      const { off: _off, ...rest } = raw;
      defs.set(raw.id, { ...rest, source: raw.source ?? pack.source, dirs } as FurniDef);
    }
  }
  return defs;
}

/** Bump to rebuild every sheet (when the sheet format changes). */
const SHEET_FORMAT = 1;
const ALPHA = 16;

/**
 * Builds the sprite sheets for every definition whose pictures are there and returns their frame
 * lists; furni whose pictures are missing are skipped (the game draws nothing for them).
 */
export function buildFurniSheets(defs: Map<string, FurniDef>, spritesDir: string, log: (msg: string) => void = () => {}): Map<string, FurniSheet> {
  const out = join(spritesDir, 'built', 'furni');
  const sheets = new Map<string, FurniSheet>();
  let ready = 0;
  let built = 0;
  let missing = 0;
  for (const def of defs.values()) {
    const srcDir = join(spritesDir, def.source);
    const pictures = Object.values(def.dirs).flatMap((d) => ('frames' in d ? d.frames : []));
    const files = pictures.map((p) => join(srcDir, `${p}.png`));
    if (!files.every((f) => existsSync(f))) {
      missing++;
      continue;
    }
    const version = hashOf(def, files);
    const jsonFile = join(out, `${def.id}.json`);
    if (existsSync(jsonFile)) {
      try {
        const sheet = JSON.parse(readFileSync(jsonFile, 'utf8')) as FurniSheet;
        if (sheet.version === version) {
          sheets.set(def.id, sheet);
          ready++;
          continue;
        }
      } catch {
        // rebuild it
      }
    }
    mkdirSync(out, { recursive: true });
    const { png, sheet } = buildSheet(def, srcDir, version);
    writeFileSync(join(out, `${def.id}.png`), PNG.sync.write(png));
    writeFileSync(jsonFile, JSON.stringify(sheet));
    sheets.set(def.id, sheet);
    ready++;
    built++;
  }
  log(`Furni: ${ready} of ${defs.size} have sprite sheets${built ? ` (${built} built now)` : ''}${missing ? `, ${missing} without their pictures in ${spritesDir}` : ''}`);
  return sheets;
}

function hashOf(def: FurniDef, files: string[]): number {
  const h = createHash('sha1').update(JSON.stringify({ SHEET_FORMAT, size: def.size, dirs: def.dirs }));
  for (const f of files) h.update(`${f}:${statSync(f).size}:${statSync(f).mtimeMs}`);
  return parseInt(h.digest('hex').slice(0, 12), 16);
}

function buildSheet(def: FurniDef, srcDir: string, version: number): { png: PNG; sheet: FurniSheet } {
  // Each direction's frames, trimmed to one shared box (so animations don't wobble).
  const parts: { dir: FurniDir; images: PNG[]; box: [number, number, number, number] }[] = [];
  for (const [d, images] of Object.entries(def.dirs)) {
    if (!('frames' in images)) continue;
    const pngs = images.frames.map((f) => PNG.sync.read(readFileSync(join(srcDir, `${f}.png`))));
    let box: [number, number, number, number] = [Infinity, Infinity, -Infinity, -Infinity];
    for (const p of pngs) {
      const b = visibleBox(p);
      if (b) box = [Math.min(box[0], b[0]), Math.min(box[1], b[1]), Math.max(box[2], b[2]), Math.max(box[3], b[3])];
    }
    if (box[0] === Infinity) box = [0, 0, 1, 1];
    parts.push({ dir: Number(d) as FurniDir, images: pngs, box });
  }
  // Lay the frames out in rows, at most ~1024 px wide.
  const cells: { dir: FurniDir; img: PNG; box: [number, number, number, number]; x: number; y: number }[] = [];
  let x = 0;
  let y = 0;
  let rowH = 0;
  let width = 0;
  for (const part of parts) {
    const w = part.box[2] - part.box[0];
    const h = part.box[3] - part.box[1];
    for (const img of part.images) {
      if (x > 0 && x + w > 1024) {
        x = 0;
        y += rowH + 1;
        rowH = 0;
      }
      cells.push({ dir: part.dir, img, box: part.box, x, y });
      x += w + 1;
      rowH = Math.max(rowH, h);
      width = Math.max(width, x);
    }
  }
  const png = new PNG({ width: Math.max(1, width), height: Math.max(1, y + rowH) });
  const sheet: FurniSheet = { version, dirs: {} };
  for (const c of cells) {
    const [l, t, r, b] = c.box;
    PNG.bitblt(c.img, png, l, t, r - l, b - t, c.x, c.y);
    // The anchor: the footprint's front corner. Seen from the camera a footprint of fx tiles
    // along x and fy along y is (fx + fy) * 32 px wide with its front corner fx * 32 px from the
    // left, so it sits at that share of the picture's width, at the bottom.
    const [fx, fy] = furniFootprint(def, c.dir);
    const frame: FurniFrame = { x: c.x, y: c.y, w: r - l, h: b - t, ax: Math.round(((r - l) * fx) / (fx + fy)), ay: b - t };
    (sheet.dirs[c.dir] ??= []).push(frame);
  }
  return { png, sheet };
}

function visibleBox(png: PNG): [number, number, number, number] | null {
  let l = png.width;
  let t = png.height;
  let r = -1;
  let b = -1;
  for (let y = 0; y < png.height; y++) {
    for (let x = 0; x < png.width; x++) {
      if (png.data[(y * png.width + x) * 4 + 3]! > ALPHA) {
        if (x < l) l = x;
        if (x > r) r = x;
        if (y < t) t = y;
        if (y > b) b = y;
      }
    }
  }
  return r < 0 ? null : [l, t, r + 1, b + 1];
}
