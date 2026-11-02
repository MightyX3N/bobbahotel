import { FW, FH, layerPaths, type Look } from '../avatar';
import { loadImg } from './state';

export type Layers = (HTMLImageElement | null)[];
export const loadLayers = (look: Look, anim: string, only?: string) => Promise.all(layerPaths(look, anim, only).map(loadImg));

/** Draw one frame of loaded layers; (cx,cy,cw,ch) crops the 64x80 frame and the result is scaled by `scale`. */
export function drawFrame(c: HTMLCanvasElement, layers: Layers, row: number, frame: number, scale: number, crop: [number, number, number, number] = [0, 0, FW, FH]) {
  const ctx = c.getContext('2d')!; ctx.imageSmoothingEnabled = false;
  c.width = crop[2] * scale; c.height = crop[3] * scale; ctx.clearRect(0, 0, c.width, c.height);
  for (const im of layers) if (im) ctx.drawImage(im, frame * FW + crop[0], row * FH + crop[1], crop[2], crop[3], 0, 0, c.width, c.height);
}

/** Crops (x, y, w, h in frame pixels) that show each piece well. */
export const CROPS: Record<string, [number, number, number, number]> = {
  body: [0, 0, FW, FH], hair: [16, 2, 32, 32], top: [16, 26, 32, 32], bottom: [16, 44, 32, 32], shoes: [16, 52, 32, 28],
};

/** A small picture of one piece worn on a bare body. */
export async function pieceThumb(look: Look, slot: string, n: number) {
  const c = document.createElement('canvas');
  const l: Look = { sex: look.sex, body: look.body, hair: 0, top: 0, bottom: 0, shoes: 0 };
  if (slot === 'body') l.body = n; else (l as any)[slot] = n;
  drawFrame(c, await loadLayers(l, 'idle'), 0, 0, slot === 'body' ? 1 : 2, CROPS[slot]);
  return c;
}

/** Draw a room layout as a small isometric picture (height shown as shade). */
export function drawLayout(c: HTMLCanvasElement, map: string[], door?: [number, number] | null) {
  const h = map.length, w = Math.max(...map.map(r => r.length));
  const tw = Math.max(2, Math.floor(2 * (Math.min(c.width, c.height) - 4) / (w + h)));
  const th = tw / 2, ox = c.width / 2, oy = (c.height - (w + h) * th) / 2 + th / 2;
  const ctx = c.getContext('2d')!; ctx.clearRect(0, 0, c.width, c.height);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const ch = map[y][x]; if (!ch || ch === 'x') continue;
    const z = parseInt(ch, 36), cx = ox + (x - y) * tw / 2, cy = oy + (x + y) * th / 2 - z * th * 0.6;
    ctx.fillStyle = door && door[0] === x && door[1] === y ? '#d9473a' : `hsl(30 ${30 + z * 4}% ${64 - z * 5}%)`;
    ctx.beginPath(); ctx.moveTo(cx, cy - th / 2); ctx.lineTo(cx + tw / 2, cy); ctx.lineTo(cx, cy + th / 2); ctx.lineTo(cx - tw / 2, cy); ctx.closePath(); ctx.fill();
  }
}
