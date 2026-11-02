import type { Look } from '../avatar';
import type { Defs, Item } from '../../../shared/furni';
export type Page = { id: string; title: string; parent: string | null; kind: string; icon: string | null; order: number; desc: string; items?: [string, number][]; price?: number };
export type InvItem = { id: number; furni: string };
export type RoomInfo = { id: string; name: string; users: number; max: number; pub: boolean; owner: string; mine: boolean; desc: string };
export type LayoutInfo = { id: string; name: string; max: number; tiles: number; map: string[]; door: [number, number] | null };
export const S = {
  http: '', send: (_: object) => {}, logout: () => {},
  rooms: [] as RoomInfo[], layouts: [] as LayoutInfo[], roomId: '',
  me: null as null | { id: number; name: string; look: Look; steam: boolean },
  listeners: new Set<() => void>(),
  defs: {} as Defs, pages: [] as Page[], inv: [] as InvItem[], silver: 0, gold: 0, edit: false,
  /** the placed piece the player clicked in the room */
  selected: null as Item | null,
  /** set by the room view: start putting an inventory piece down / do something with the selected piece */
  startPlace: (_id: number) => {}, itemAction: (_a: string) => {},
};
export const changed = () => S.listeners.forEach(f => f());

// ---- images for canvas drawing (avatar thumbnails etc.) ------------------------
const imgs = new Map<string, Promise<HTMLImageElement | null>>();
export function loadImg(path: string) {
  let p = imgs.get(path);
  if (!p) p = (imgs.set(path, new Promise(res => { const i = new Image(); i.crossOrigin = 'anonymous'; i.onload = () => res(i); i.onerror = () => res(null); i.src = S.http + '/sprites/' + path; })), imgs.get(path)!);
  return p;
}

/** A small picture of a furniture sprite, fitted into a box. */
export async function furniThumb(file: string, box = 48): Promise<HTMLCanvasElement> {
  const c = document.createElement('canvas'), im = await loadImg('furni/' + file);
  c.width = c.height = box; if (!im) return c;
  const k = Math.min(box / im.width, box / im.height, 2), w = Math.max(1, Math.round(im.width * k)), hh = Math.max(1, Math.round(im.height * k));
  const x = c.getContext('2d')!; x.imageSmoothingEnabled = false; x.drawImage(im, (box - w) >> 1, (box - hh) >> 1, w, hh);
  return c;
}
