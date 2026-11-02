// Room layouts: a heightmap of strings. "x" = no floor, "0"-"9"/"a"-"z" = floor height (base 36).

/** grid[y][x] = floor height, or -1 where there is no floor. */
export type Grid = number[][];

/** Who may build a room with a layout: anyone, Bobba Club members, or staff only (public rooms). */
export type LayoutAccess = 'free' | 'club' | 'admin';

export interface Layout {
  id: string;
  name: string;
  map: string[];
  door: [number, number];
  maxUsers?: number;
  access?: LayoutAccess;
}

/** Number of floor tiles in a layout (shown when choosing one). */
export function tileCount(map: string[]): number {
  return map.reduce((n, row) => n + [...row].filter((c) => c !== 'x' && c !== 'X').length, 0);
}

export function parseMap(map: string[]): Grid {
  return map.map((row) => [...row].map((c) => (c === 'x' || c === 'X' ? -1 : parseInt(c, 36))));
}

export function heightAt(grid: Grid, x: number, y: number): number {
  return grid[y]?.[x] ?? -1;
}

export function isFloor(grid: Grid, x: number, y: number): boolean {
  return heightAt(grid, x, y) >= 0;
}

/**
 * The 8 directions, clockwise, as grid steps. On screen +x goes down-right and +y down-left,
 * so 0 = up-right, 2 = down-right, 4 = down-left, 6 = up-left.
 */
export const DIRS: readonly (readonly [number, number])[] = [
  [0, -1],
  [1, -1],
  [1, 0],
  [1, 1],
  [0, 1],
  [-1, 1],
  [-1, 0],
  [-1, -1],
];

/** Direction (0-7) for a step of dx, dy; for longer distances, the closest of the 8. */
export function dirTowards(dx: number, dy: number): number {
  const sx = Math.sign(dx);
  const sy = Math.sign(dy);
  const i = DIRS.findIndex(([x, y]) => x === sx && y === sy);
  return i < 0 ? 2 : i;
}

/** The direction someone entering through the door faces: towards the floor tile next to it. */
export function doorFacing(grid: Grid, door: [number, number]): number {
  const [x, y] = door;
  for (const d of [2, 4, 0, 6]) {
    const [dx, dy] = DIRS[d]!;
    if (isFloor(grid, x + dx, y + dy)) return d;
  }
  return 2;
}
