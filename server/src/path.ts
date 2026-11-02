export type Grid = number[][]; // -1 = no floor, otherwise height

const D = [[0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1]];

/** A* over the room grid, 8 directions, no cutting corners. Returns the tiles to step on (excluding start). */
export function findPath(g: Grid, sx: number, sy: number, tx: number, ty: number, blocked: Set<string>): [number, number][] | null {
  const ok = (x: number, y: number) => (g[y]?.[x] ?? -1) >= 0;
  if (!ok(tx, ty) || !ok(sx, sy) || blocked.has(tx + ',' + ty) || (sx === tx && sy === ty)) return null;
  const key = (x: number, y: number) => y * 1000 + x;
  const open = new Map<number, { x: number; y: number; g: number; f: number; p: number }>();
  const closed = new Map<number, number>();
  const h = (x: number, y: number) => Math.max(Math.abs(x - tx), Math.abs(y - ty));
  open.set(key(sx, sy), { x: sx, y: sy, g: 0, f: h(sx, sy), p: -1 });
  while (open.size) {
    let cur: { x: number; y: number; g: number; f: number; p: number } | undefined;
    for (const n of open.values()) if (!cur || n.f < cur.f) cur = n;
    const c = cur!; const ck = key(c.x, c.y);
    open.delete(ck); closed.set(ck, c.p);
    if (c.x === tx && c.y === ty) {
      const out: [number, number][] = []; let k = ck;
      while (k !== key(sx, sy)) { out.push([k % 1000, Math.floor(k / 1000)]); k = closed.get(k)!; }
      return out.reverse();
    }
    for (const [dx, dy] of D) {
      const nx = c.x + dx, ny = c.y + dy, nk = key(nx, ny);
      if (!ok(nx, ny) || closed.has(nk) || blocked.has(nx + ',' + ny)) continue;
      if (Math.abs(g[ny][nx] - g[c.y][c.x]) > 1) continue;
      if (dx && dy && (!ok(c.x + dx, c.y) || !ok(c.x, c.y + dy))) continue;
      const gg = c.g + (dx && dy ? 1.4 : 1);
      const ex = open.get(nk);
      if (!ex || gg < ex.g) open.set(nk, { x: nx, y: ny, g: gg, f: gg + h(nx, ny), p: ck });
    }
  }
  return null;
}
