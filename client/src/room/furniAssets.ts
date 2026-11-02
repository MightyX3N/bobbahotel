// Furni definitions and their sprite sheets' frame lists (both from /api/furni, loaded once), and
// the sheet pictures (built by the server from the licensed pictures, served at /api/furni/<id>.png).
import { Rectangle, Texture } from 'pixi.js';
import type { FurniDef, FurniDir, FurniSheet } from '@bobba/shared';
import { loadTexture } from '../sprites.ts';

interface FurniData {
  defs: Map<string, FurniDef>;
  sheets: Map<string, FurniSheet>;
}

let dataPromise: Promise<FurniData> | null = null;

function furniData(): Promise<FurniData> {
  dataPromise ??= fetch('/api/furni')
    .then((r) => (r.ok ? (r.json() as Promise<{ furni: FurniDef[]; sheets: Record<string, FurniSheet> }>) : { furni: [], sheets: {} }))
    .then((body) => ({ defs: new Map(body.furni.map((d) => [d.id, d])), sheets: new Map(Object.entries(body.sheets)) }))
    .catch(() => ({ defs: new Map(), sheets: new Map() }));
  return dataPromise;
}

/** All furni definitions. */
export async function furniDefs(): Promise<Map<string, FurniDef>> {
  return (await furniData()).defs;
}

/** One frame ready to draw: its texture and anchor (the footprint's front corner) in pixels. */
export interface FurniTexture {
  texture: Texture;
  ax: number;
  ay: number;
}

/** A furni's frames per direction it has pictures for (mirrored directions are drawn flipped), per state. */
export type FurniFrames = Partial<Record<FurniDir, FurniTexture[][]>>;

const frames = new Map<string, Promise<FurniFrames | null>>();

/** Loads a furni's sprite sheet; null if it isn't there (the furni is then not drawn). */
export function furniFrames(id: string): Promise<FurniFrames | null> {
  let p = frames.get(id);
  if (!p) {
    p = (async () => {
      const sheet = (await furniData()).sheets.get(id);
      if (!sheet) return null;
      // The version busts the browser cache when a sheet is rebuilt.
      const base = await loadTexture(`/api/furni/${id}.png?v=${sheet.version}`);
      if (!base) return null;
      const out: FurniFrames = {};
      for (const [dir, states] of Object.entries(sheet.dirs)) {
        out[Number(dir) as FurniDir] = states.map((list) =>
          list.map((f) => ({
            texture: new Texture({ source: base.source, frame: new Rectangle(f.x, f.y, f.w, f.h) }),
            ax: f.ax,
            ay: f.ay,
          })),
        );
      }
      return out;
    })();
    frames.set(id, p);
  }
  return p;
}
