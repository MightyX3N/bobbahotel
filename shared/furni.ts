// Furniture rules shared by the server (what is allowed) and the client (previews, drawing).
export type Art = { w: number; d: number; wf: number; df: number; rx: number; ry: number; T: number; fx: number; fy: number; top: number; sw: number; sh: number };
export type Def = {
  name: string; pages: string[]; price: number; file: string; w: number; d: number; art?: Art;
  seat?: boolean; faces?: number; stack?: boolean; htop?: number; walkable?: boolean; flat?: boolean; stairs?: boolean; rail?: boolean;
  sit?: number; fps?: number; anim?: string[]; off?: string; scale?: number; gift?: boolean;
  wall?: boolean; sw?: number; sh?: number; wcx?: number; wby?: number; wty?: number; half?: number; wdir?: string;
};
/** A placed (or carried) piece. room/x/y are null while it is in an inventory. */
export type Item = { id: number; furni: string; x: number; y: number; flip: number; z: number; state: number };
export type Defs = Record<string, Def>;

export const size = (d: Def, flip: number): [number, number] => (flip ? [d.d, d.w] : [d.w, d.d]);

/** Direction an avatar faces on a seat (server direction numbers, 0 = -y clockwise). */
export function seatDir(d: Def, flip: number) {
  let f = Math.floor(d.faces ?? 1) % 8; if (flip) f = (8 - f) % 8;
  return (f + 3) % 8;
}
/** Does the seat face away from the viewer (its back is in front of whoever sits)? */
export function seatFacesAway(d: Def, flip: number) {
  let f = Math.floor(d.faces ?? 1) % 8; if (flip) f = (8 - f) % 8;
  return f >= 3 && f <= 5;
}

/** How much the picture is drawn bigger or smaller so it fits inside its tiles (never bigger than the art). */
export function artScale(d: Def, flip: number): number {
  const A = d.art; if (!A) return 1;
  if (d.scale) return d.scale;
  const [w, dd] = size(d, flip);
  const rx = flip ? A.ry : A.rx, ry = flip ? A.rx : A.ry, wf = flip ? A.df : A.wf, df = flip ? A.wf : A.df;
  let kx = (w - wf) / rx, ky = (dd - df) / ry;
  if (d.seat) { // armrests may hang over the ends of a seat
    const f = Math.floor(d.faces ?? 1) % 8, fl = flip ? (8 - f) % 8 : f;
    if (fl === 1 || fl === 5) kx = Infinity; else ky = Infinity;
  }
  return Math.min(1, kx, ky) * 32 / A.T;
}
/** Where the picture's front corner stands in its tiles, counted from the back corner (tile units). */
export function artCorner(d: Def, flip: number): [number, number] {
  const A = d.art; const [w, dd] = size(d, flip);
  if (!A) return [w, dd];
  const k = artScale(d, flip) * A.T / 32;
  const rx = (flip ? A.ry : A.rx) * k, ry = (flip ? A.rx : A.ry) * k;
  const wf = flip ? A.df : A.wf, df = flip ? A.wf : A.df;
  let fx = Math.min(w - wf, rx), fy = Math.min(dd - df, ry);
  if (d.seat) {
    const f = Math.floor(d.faces ?? 1) % 8, fl = flip ? (8 - f) % 8 : f, longX = fl === 1 || fl === 5;
    const place = (len: number, tiles: number, long: boolean) => (long || len < 0.75 * tiles ? (tiles + len) / 2 : Math.min(tiles, len));
    fx = place(rx, w, longX); fy = place(ry, dd, !longX);
  }
  return [fx + wf, fy + df];
}
export const covers = (d: Def, it: Item, tx: number, ty: number) => {
  const [w, dd] = size(d, it.flip);
  return tx >= it.x && tx < it.x + w && ty >= it.y && ty < it.y + dd;
};
export function seatHeight(d: Def): number {
  if (typeof d.sit === 'number') return d.sit;
  const A = d.art; if (!A) return 0.5;
  const tall = (A.fy - A.top) - (A.rx + A.ry) * A.T / 2; // how far the picture stands above its floor tiles, in pixels
  return Math.max(0.1, Math.min(1, tall * 0.2 * artScale(d, 0) / 16)); // in height steps (16px each)
}
/** How high stairs climb on a tile: one step per tile towards the back end. */
export function stairStep(d: Def, it: Item, tx: number, ty: number) {
  const [w, dd] = size(d, it.flip);
  return w >= dd ? w - (tx - it.x) : dd - (ty - it.y);
}

/** Height (in steps above the floor) a floor piece would stand at with its back corner on (x, y), or null if blocked. */
export function standHeight(items: Iterable<Item>, defs: Defs, d: Def, x: number, y: number, flip: number, except = -1): number | null {
  if (d.flat) return 0;
  const [w, dd] = size(d, flip); const list = [...items].filter(i => i.id !== except && i.x != null);
  let z: number | null = null;
  for (let i = 0; i < w; i++) for (let j = 0; j < dd; j++) {
    let top = 0;
    for (const it of list) {
      const od = defs[it.furni]; if (!od || od.wall || od.flat || !covers(od, it, x + i, y + j)) continue;
      if ((d.rail && od.stairs) || (od.rail && d.stairs)) continue;
      if (od.walkable && !od.stack) continue;
      if (!od.stack) return null;
      top = Math.max(top, it.z + (od.htop ?? 1));
    }
    if (z === null) z = top; else if (Math.abs(z - top) > 0.01) return null;
  }
  if (d.seat && (z ?? 0) > 0) return null;
  return z ?? 0;
}
/** Is anything standing on this piece? (then it can't be picked up) */
export function hasOnTop(items: Iterable<Item>, defs: Defs, it: Item): boolean {
  const d = defs[it.furni]; if (!d?.stack) return false;
  for (const o of items) {
    const od = defs[o.furni]; if (o.id === it.id || !od || od.wall || od.flat || o.z <= it.z + 0.01) continue;
    const [w, dd] = size(od, o.flip);
    for (let i = 0; i < w; i++) for (let j = 0; j < dd; j++) if (covers(d, it, o.x + i, o.y + j)) return true;
  }
  return false;
}
