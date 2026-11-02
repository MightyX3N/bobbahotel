// Pathfinding (A*) over a room grid, used by the server to move avatars.
// Rules, as in Habbo: 8 directions, no cutting corners past missing floor or blocked tiles,
// at most one height step at a time.
import { DIRS, heightAt, type Grid } from './room.ts';

export const MAX_STEP_HEIGHT = 1;

export interface PathOptions {
  /** Tiles nobody may step on, e.g. other avatars. Keyed by `tileKey`. */
  blocked?: ReadonlySet<number>;
  /** Give up after visiting this many tiles. */
  maxNodes?: number;
}

export const tileKey = (x: number, y: number): number => y * 4096 + x;

/** The tiles to step on from (sx, sy) to (tx, ty), excluding the start. null if there is no way. */
export function findPath(grid: Grid, sx: number, sy: number, tx: number, ty: number, opts: PathOptions = {}): [number, number][] | null {
  const blocked = opts.blocked ?? new Set<number>();
  const maxNodes = opts.maxNodes ?? 10000;
  const free = (x: number, y: number) => heightAt(grid, x, y) >= 0 && !blocked.has(tileKey(x, y));
  if (sx === tx && sy === ty) return [];
  if (heightAt(grid, sx, sy) < 0 || !free(tx, ty)) return null;

  const h = (x: number, y: number) => {
    const dx = Math.abs(x - tx);
    const dy = Math.abs(y - ty);
    return Math.max(dx, dy) + 0.4 * Math.min(dx, dy);
  };

  interface Node {
    x: number;
    y: number;
    g: number;
    f: number;
    parent: number;
  }
  const open = new Heap<Node>((a, b) => a.f - b.f || b.g - a.g);
  const best = new Map<number, number>();
  const parents = new Map<number, number>();
  const start = tileKey(sx, sy);
  open.push({ x: sx, y: sy, g: 0, f: h(sx, sy), parent: -1 });
  best.set(start, 0);
  let visited = 0;

  while (open.size > 0) {
    const cur = open.pop()!;
    const ck = tileKey(cur.x, cur.y);
    if (parents.has(ck)) continue;
    parents.set(ck, cur.parent);
    if (cur.x === tx && cur.y === ty) {
      const path: [number, number][] = [];
      for (let k = ck; k !== start; k = parents.get(k)!) path.push([k % 4096, Math.floor(k / 4096)]);
      return path.reverse();
    }
    if (++visited > maxNodes) return null;

    const ch = heightAt(grid, cur.x, cur.y);
    for (const [dx, dy] of DIRS) {
      const nx = cur.x + dx;
      const ny = cur.y + dy;
      const nk = tileKey(nx, ny);
      if (parents.has(nk) || !free(nx, ny)) continue;
      if (Math.abs(heightAt(grid, nx, ny) - ch) > MAX_STEP_HEIGHT) continue;
      if (dx !== 0 && dy !== 0 && (!free(cur.x + dx, cur.y) || !free(cur.x, cur.y + dy))) continue;
      const g = cur.g + (dx !== 0 && dy !== 0 ? 1.4 : 1);
      if (g >= (best.get(nk) ?? Infinity)) continue;
      best.set(nk, g);
      open.push({ x: nx, y: ny, g, f: g + h(nx, ny), parent: ck });
    }
  }
  return null;
}

/** A small binary min-heap. */
class Heap<T> {
  private items: T[] = [];
  private readonly less: (a: T, b: T) => number;
  constructor(less: (a: T, b: T) => number) {
    this.less = less;
  }
  get size(): number {
    return this.items.length;
  }
  push(item: T): void {
    const a = this.items;
    a.push(item);
    let i = a.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (this.less(a[i]!, a[p]!) >= 0) break;
      [a[i], a[p]] = [a[p]!, a[i]!];
      i = p;
    }
  }
  pop(): T | undefined {
    const a = this.items;
    const top = a[0];
    const last = a.pop();
    if (a.length > 0 && last !== undefined) {
      a[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let m = i;
        if (l < a.length && this.less(a[l]!, a[m]!) < 0) m = l;
        if (r < a.length && this.less(a[r]!, a[m]!) < 0) m = r;
        if (m === i) break;
        [a[i], a[m]] = [a[m]!, a[i]!];
        i = m;
      }
    }
    return top;
  }
}
