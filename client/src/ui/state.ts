import type { Look } from '../avatar';
export type RoomInfo = { id: string; name: string; users: number; max: number; pub: boolean; owner: string; mine: boolean; desc: string };
export type LayoutInfo = { id: string; name: string; max: number; tiles: number; map: string[]; door: [number, number] | null };
export const S = {
  http: '', send: (_: object) => {}, logout: () => {},
  rooms: [] as RoomInfo[], layouts: [] as LayoutInfo[], roomId: '',
  me: null as null | { id: number; name: string; look: Look; steam: boolean },
  listeners: new Set<() => void>(),
};
export const changed = () => S.listeners.forEach(f => f());

// ---- images for canvas drawing (avatar thumbnails etc.) ------------------------
const imgs = new Map<string, Promise<HTMLImageElement | null>>();
export function loadImg(path: string) {
  let p = imgs.get(path);
  if (!p) p = (imgs.set(path, new Promise(res => { const i = new Image(); i.crossOrigin = 'anonymous'; i.onload = () => res(i); i.onerror = () => res(null); i.src = S.http + '/sprites/' + path; })), imgs.get(path)!);
  return p;
}
