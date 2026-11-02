// Isometric maths. Tiles are 64x32 on screen; one height step is 32 px.
export const TILE_W = 64;
export const TILE_H = 32;
export const STEP_PX = 32;

/** Screen position of the middle of tile (x, y) at height z. Works with fractions while walking. */
export function tileCenter(x: number, y: number, z: number): { x: number; y: number } {
  return { x: (x - y) * (TILE_W / 2), y: (x + y) * (TILE_H / 2) + TILE_H / 2 - z * STEP_PX };
}

/** The four corners of a tile's top (top, right, bottom, left). */
export type Point = [number, number];

export function tileCorners(x: number, y: number, z: number): [top: Point, right: Point, bottom: Point, left: Point] {
  const c = tileCenter(x, y, z);
  return [
    [c.x, c.y - TILE_H / 2],
    [c.x + TILE_W / 2, c.y],
    [c.x, c.y + TILE_H / 2],
    [c.x - TILE_W / 2, c.y],
  ];
}

/** Is the screen point inside the top of tile (x, y) at height z? */
export function pointInTile(px: number, py: number, x: number, y: number, z: number): boolean {
  const c = tileCenter(x, y, z);
  return Math.abs(px - c.x) / (TILE_W / 2) + Math.abs(py - c.y) / (TILE_H / 2) <= 1;
}

/** Draw order for things standing on the floor: further back = smaller. */
export function depthOf(x: number, y: number, z: number): number {
  return (x + y) * 100 + z;
}
