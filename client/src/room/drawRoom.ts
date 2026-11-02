// Draws a room's floor and walls in flat colours: brown floor with tile outlines, yellow/orange
// walls with thickness, and a door hole in the left wall.
//
// Follows how Habbo (and Nitro's RoomPlaneParser, GPL-3) builds rooms:
// - The door tile sticks out of the left wall. Walls are worked out as if it weren't there, so the
//   wall passes behind it, and the wall in front of it gets a door-shaped hole.
// - Walls stand on the back edges of the room only, are a quarter tile thick, reach from just
//   below the floor (floor thickness) up to a fixed top 3.6 steps above the highest floor.
// - Everything is drawn tile by tile from back to front, each tile's walls together with the
//   tile, so whatever stands in front always covers what is behind it.
import { Graphics } from 'pixi.js';
import { heightAt, isFloor, type Grid } from '@bobba/shared';
import { STEP_PX, TILE_H, TILE_W, tileCorners, type Point } from './iso.ts';

const COLORS = {
  floor: 0xa47a52,
  floorLine: 0x8c6644,
  floorLeft: 0x8a6544,
  floorRight: 0x6d4f35,
  wallLeft: 0xf2c665,
  wallRight: 0xdfa64c,
  wallTop: 0xf9dd9c,
  wallEndLeft: 0xc98f3a,
  wallEndRight: 0xb57e2e,
  doorJamb: 0xb07a2c,
};

/** Floor thickness (a quarter tile), shown at the room's front edges and under the walls. */
const FLOOR_THICKNESS = 8;
/** Wall top, in height steps above the highest floor. */
const WALL_STEPS = 3.6;
/** Wall thickness: the top strip leans this far away from the room. */
const T = 8;
/** Door hole height. Habbo's avatar about fills the doorway. */
export const DOOR_HEIGHT = 3.15 * STEP_PX;

export function drawRoom(grid: Grid, door: [number, number]): Graphics {
  const g = new Graphics();
  const rows = grid.length;
  const cols = Math.max(...grid.map((r) => r.length));
  const maxZ = Math.max(0, ...grid.flat());
  const [doorX, doorY] = door;
  const isDoor = (x: number, y: number) => x === doorX && y === doorY;

  // Walls are worked out without the door tile.
  const solid = (x: number, y: number) => isFloor(grid, x, y) && !isDoor(x, y);
  const hasLeftWall = (x: number, y: number) => {
    if (!solid(x, y)) return false;
    for (let i = 0; i < x; i++) if (solid(i, y)) return false;
    return true;
  };
  const hasRightWall = (x: number, y: number) => {
    if (!solid(x, y)) return false;
    for (let j = 0; j < y; j++) if (solid(x, j)) return false;
    return true;
  };
  const wallTop = (gx: number, gy: number) => corner(gx, gy, maxZ + WALL_STEPS)[1];
  /** The part of the left wall at grid x that is open for the door, as [from y, to y], or null. */
  const doorHole = (x: number, y: number): [number, number] | null => {
    if (x !== doorX + 1) return null;
    const h: [number, number] = [doorY + 0.5, doorY + 1.5];
    return h[1] > y && h[0] < y + 1 ? h : null;
  };
  const quad = (a: Point, b: Point, c: Point, d: Point, color: number) => g.poly([...a, ...b, ...c, ...d]).fill(color);
  const down = (p: Point, px: number): Point => [p[0], p[1] + px];
  const out = (p: Point, dx: number): Point => [p[0] + dx, p[1] - T / 2];

  const tiles: [number, number][] = [];
  for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) if (isFloor(grid, x, y)) tiles.push([x, y]);
  tiles.sort((a, b) => a[0] + a[1] - (b[0] + b[1]) || a[1] - b[1]);

  for (const [x, y] of tiles) {
    const z = heightAt(grid, x, y);
    const [top, right, bottom, left] = tileCorners(x, y, z);
    const leftWall = hasLeftWall(x, y);
    const rightWall = hasRightWall(x, y);

    // ---- left wall, along the tile's top-left edge (from grid y+1 back to y) ----
    if (leftWall) {
      // The door hole is centred on the door tile as seen from the camera: half a tile further
      // forward than the door tile itself, so it can straddle two wall pieces.
      const hole = doorHole(x, y);
      const spans: [number, number, boolean][] = hole
        ? ([[y, hole[0], false], [hole[0], hole[1], true], [hole[1], y + 1, false]] as [number, number, boolean][]).filter(([a, b]) => b - a > 1e-6)
        : [[y, y + 1, false]];
      for (const [a, b, open] of spans) {
        const pa = corner(x, a, z);
        const pb = corner(x, b, z);
        const ta: Point = [pa[0], wallTop(x, a)];
        const tb: Point = [pb[0], wallTop(x, b)];
        if (open) {
          quad(down(pb, -DOOR_HEIGHT), down(pa, -DOOR_HEIGHT), ta, tb, COLORS.wallLeft);
          quad(pb, down(pb, FLOOR_THICKNESS), down(pa, FLOOR_THICKNESS), pa, COLORS.wallLeft);
        } else {
          quad(down(pb, FLOOR_THICKNESS), down(pa, FLOOR_THICKNESS), ta, tb, COLORS.wallLeft);
        }
      }
      // The hole's back edge shows the wall's thickness.
      if (hole && hole[0] >= y && hole[0] < y + 1) {
        const p = corner(x, hole[0], z);
        const pt = down(p, -DOOR_HEIGHT);
        quad(p, pt, out(pt, -T), out(p, -T), COLORS.doorJamb);
      }
      const lTop: Point = [left[0], wallTop(x, y + 1)];
      const tTop: Point = [top[0], wallTop(x, y)];
      quad(lTop, tTop, out(tTop, -T), out(lTop, -T), COLORS.wallTop);
      // End piece where the wall stops at the front.
      const lBase = down(left, FLOOR_THICKNESS);
      if (!hasLeftWall(x, y + 1)) quad(lBase, lTop, out(lTop, -T), out(lBase, -T), COLORS.wallEndLeft);
    }

    // ---- right wall, along the tile's top-right edge (top corner -> right corner) ----
    if (rightWall) {
      const tTop: Point = [top[0], wallTop(x, y)];
      const rTop: Point = [right[0], wallTop(x + 1, y)];
      const tBase = down(top, FLOOR_THICKNESS);
      const rBase = down(right, FLOOR_THICKNESS);
      quad(tBase, rBase, rTop, tTop, COLORS.wallRight);
      quad(tTop, rTop, out(rTop, T), out(tTop, T), COLORS.wallTop);
      if (!hasRightWall(x + 1, y)) quad(rBase, rTop, out(rTop, T), out(rBase, T), COLORS.wallEndRight);
      // A right wall that starts here without a left wall next to it gets an end piece on its back side too.
      if (!leftWall && !hasRightWall(x - 1, y)) quad(tBase, tTop, out(tTop, T), out(tBase, T), COLORS.wallEndLeft);
    }

    // Back corner where a left and a right wall meet: fill the gap between the two top strips.
    if (leftWall && rightWall) {
      const c: Point = [top[0], wallTop(x, y)];
      g.poly([...c, ...out(c, -T), c[0], c[1] - T, ...out(c, T)]).fill(COLORS.wallTop);
    }

    // ---- floor ----
    if (isDoor(x, y)) {
      // The door tile's floor reaches half a tile further forward, so the whole door opening shows
      // floor (it is behind the wall, so only the part seen through the hole is visible).
      g.poly([...corner(x, y, z), ...corner(x + 1, y, z), ...corner(x + 1, y + 1.5, z), ...corner(x, y + 1.5, z)])
        .fill(COLORS.floor)
        .stroke({ color: COLORS.floorLine, width: 1, alignment: 1 });
      continue;
    }
    // Side facing down-left (towards +y): visible if the tile in front is lower or missing.
    const frontY = heightAt(grid, x, y + 1);
    const dropLeft = frontY < 0 ? z * STEP_PX + FLOOR_THICKNESS : (z - frontY) * STEP_PX;
    if (dropLeft > 0) quad(left, bottom, down(bottom, dropLeft), down(left, dropLeft), COLORS.floorLeft);
    // Side facing down-right (towards +x).
    const frontX = heightAt(grid, x + 1, y);
    const dropRight = frontX < 0 ? z * STEP_PX + FLOOR_THICKNESS : (z - frontX) * STEP_PX;
    if (dropRight > 0) quad(bottom, right, down(right, dropRight), down(bottom, dropRight), COLORS.floorRight);
    // Top, with a thin outline so the tiles can be told apart.
    g.poly([...top, ...right, ...bottom, ...left])
      .fill(COLORS.floor)
      .stroke({ color: COLORS.floorLine, width: 1, alignment: 1 });
  }
  return g;
}

/** Screen point of grid corner (gx, gy) at height z (fractions allowed). */
export function corner(gx: number, gy: number, z: number): Point {
  return [(gx - gy) * (TILE_W / 2), (gx + gy) * (TILE_H / 2) - z * STEP_PX];
}

/** The door hole's outline (for clipping avatars that are still behind the wall). */
export function doorHolePolygon(grid: Grid, door: [number, number]): number[] {
  const [dx, dy] = door;
  const z = heightAt(grid, dx + 1, dy);
  const a = corner(dx + 1, dy + 0.5, z);
  const b = corner(dx + 1, dy + 1.5, z);
  return [a[0], a[1] + 12, b[0], b[1] + 12, b[0], b[1] - DOOR_HEIGHT, a[0], a[1] - DOOR_HEIGHT];
}

/** Outline shown on the tile under the mouse. */
export function drawTileOutline(g: Graphics, x: number, y: number, z: number): void {
  const c = tileCorners(x, y, z).flat();
  g.clear()
    .poly(c)
    .stroke({ color: 0x000000, width: 2, alpha: 0.35, alignment: 0.5 })
    .poly(c)
    .stroke({ color: 0xffffff, width: 1, alpha: 0.7, alignment: 0.5 });
}
