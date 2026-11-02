// Loads sprite pictures from /sprites/ once and cuts sheet frames out of them.
import { Assets, Rectangle, Texture } from 'pixi.js';

const loading = new Map<string, Promise<Texture | null>>();
const loaded = new Map<string, Texture>();
const frames = new Map<string, Texture>();

/** Loads /sprites/<path>. Resolves to null if the file is missing (the game keeps going). */
export function loadSprite(path: string): Promise<Texture | null> {
  let p = loading.get(path);
  if (!p) {
    p = Assets.load<Texture>(`/sprites/${path}`)
      .then((t) => {
        t.source.scaleMode = 'nearest';
        loaded.set(path, t);
        return t;
      })
      .catch(() => {
        console.warn(`Missing sprite: ${path}`);
        return null;
      });
    loading.set(path, p);
  }
  return p;
}

/** A frame of an already-loaded sheet, or null if the sheet isn't loaded (yet). */
export function sheetFrame(path: string, col: number, row: number, w: number, h: number): Texture | null {
  const base = loaded.get(path);
  if (!base) return null;
  const key = `${path}|${col}|${row}`;
  let t = frames.get(key);
  if (!t) {
    t = new Texture({ source: base.source, frame: new Rectangle(col * w, row * h, w, h) });
    frames.set(key, t);
  }
  return t;
}
