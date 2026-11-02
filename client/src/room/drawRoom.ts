// Draws a room's floor and walls in flat colours: brown floor with tile outlines, yellow/orange
// walls with thickness, and the door.
//
// How Habbo builds a room (checked against Nitro's RoomPlaneParser, GPL-3, and measured from a
// Habbo screenshot):
// - The door tile sticks out of the left wall. The wall runs straight past it, and has a door
//   opening exactly in front of the door tile: one tile wide, lined up with the door tile's row.
//   Someone standing on the door tile is seen through that opening (see RoomView's door clip).
// - Walls stand on the back edges of the room, are a quarter tile thick and reach a little
//   below the floor. Where the back outline steps forward (a notch), the wall goes around it.
// - Everything is drawn tile by tile from back to front, each tile's walls together with the
//   tile, so whatever stands in front covers what is behind it.
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
  doorway: 0x0c0c0c,
};

/** Floor thickness (a quarter tile), shown at the room's front edges and under the walls. */
const FLOOR_THICKNESS = 8;
/** Wall top, in height steps above the highest floor (measured from Habbo: ~144 px on 64 px tiles). */
const WALL_STEPS = 4.5;
/** Wall thickness: how far the top strip and the end pieces stick out. */
const T = 8;
/** Door opening height (measured from Habbo: ~85 px, about the avatar's height). */
export const DOOR_HEIGHT = 2.65 * STEP_PX;

/** Screen point of grid corner (gx, gy) at height z (fractions allowed). */
export function corner(gx: number, gy: number, z: number): Point {
  return [(gx - gy) * (TILE_W / 2), (gx + gy) * (TILE_H / 2) - z * STEP_PX];
}

export function drawRoom(grid: Grid, door: [number, number]): Graphics {
  const g = new Graphics();
  const rows = grid.length;
  const cols = Math.max(...grid.map((r) => r.length));
  const maxZ = Math.max(0, ...grid.flat());
  const [doorX, doorY] = door;
  const isDoor = (x: number, y: number) => x === doorX && y === doorY;
  const wallTop = (gx: number, gy: number) => corner(gx, gy, maxZ + WALL_STEPS)[1];

  // Walls are worked out without the door tile, so the wall runs straight past it.
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
  /** Where a right wall at (x, y) starts after a notch: the row of the right wall it continues from, or -1. */
  const notchFrom = (x: number, y: number) => {
    if (!hasRightWall(x, y) || hasLeftWall(x, y) || hasRightWall(x - 1, y)) return -1;
    for (let j = 0; j < y; j++) if (solid(x - 1, j)) return hasRightWall(x - 1, j) ? j : -1;
    return -1;
  };
  /** Does the right wall ending at grid x on row y continue as a notch wall further forward? */
  const turnsForward = (x: number, y: number) => {
    for (let j = y + 1; j < rows; j++) if (notchFrom(x, j) === y) return true;
    return false;
  };

  const quad = (a: Point, b: Point, c: Point, d: Point, color: number) => g.poly([...a, ...b, ...c, ...d]).fill(color);
  const down = (p: Point, px: number): Point => [p[0], p[1] + px];
  /** Offsets for wall thickness: a quarter tile in grid direction -x, -y or +x. */
  const minusX = (p: Point): Point => [p[0] - T, p[1] - T / 2];
  const minusY = (p: Point): Point => [p[0] + T, p[1] - T / 2];
  const plusX = (p: Point): Point => [p[0] + T, p[1] + T / 2];

  const tiles: [number, number][] = [];
  for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) if (isFloor(grid, x, y)) tiles.push([x, y]);
  tiles.sort((a, b) => a[0] + a[1] - (b[0] + b[1]) || a[1] - b[1]);

  for (const [x, y] of tiles) {
    const z = heightAt(grid, x, y);
    const [top, right, bottom, left] = tileCorners(x, y, z);
    const leftWall = hasLeftWall(x, y);
    const rightWall = hasRightWall(x, y);

    // ---- left wall, along the tile's top-left edge (left corner -> top corner) ----
    if (leftWall) {
      const lTop: Point = [left[0], wallTop(x, y + 1)];
      const tTop: Point = [top[0], wallTop(x, y)];
      const lBase = down(left, FLOOR_THICKNESS);
      const tBase = down(top, FLOOR_THICKNESS);
      if (isDoor(x - 1, y)) {
        // Door opening across this whole tile edge: the wall is cut out below DOOR_HEIGHT, so the
        // dark doorway and the door tile's floor (drawn earlier, behind the wall) show through.
        quad(down(left, -DOOR_HEIGHT), down(top, -DOOR_HEIGHT), tTop, lTop, COLORS.wallLeft);
      } else {
        quad(lBase, tBase, tTop, lTop, COLORS.wallLeft);
      }
      quad(lTop, tTop, minusX(tTop), minusX(lTop), COLORS.wallTop);
      // End piece where the wall stops at the front.
      if (!hasLeftWall(x, y + 1)) quad(lBase, lTop, minusX(lTop), minusX(lBase), COLORS.wallEndLeft);
    }

    // ---- right wall, along the tile's top-right edge (top corner -> right corner) ----
    if (rightWall) {
      const tTop: Point = [top[0], wallTop(x, y)];
      const rTop: Point = [right[0], wallTop(x + 1, y)];
      const tBase = down(top, FLOOR_THICKNESS);
      const rBase = down(right, FLOOR_THICKNESS);

      // Coming out of a notch: the wall turns the corner. The short piece runs forward along this
      // tile's left edge, from the earlier wall's row to here, and faces the camera.
      const from = notchFrom(x, y);
      if (from >= 0) {
        const zBack = heightAt(grid, x - 1, from);
        const a = corner(x, from, zBack);
        const b = corner(x, y, z);
        const aTop: Point = [a[0], wallTop(x, from)];
        const bTop: Point = [b[0], tTop[1]];
        quad(down(a, FLOOR_THICKNESS), down(b, FLOOR_THICKNESS), bTop, aTop, COLORS.wallLeft);
        quad(aTop, bTop, plusX(bTop), plusX(aTop), COLORS.wallTop);
        // Outer corner where it meets the earlier wall's top.
        g.poly([...aTop, ...minusY(aTop), aTop[0] + 2 * T, aTop[1], ...plusX(aTop)]).fill(COLORS.wallTop);
      }

      quad(tBase, rBase, rTop, tTop, COLORS.wallRight);
      quad(tTop, rTop, minusY(rTop), minusY(tTop), COLORS.wallTop);
      // End piece where the wall stops, unless the wall turns forward into a notch here.
      if (!hasRightWall(x + 1, y) && !turnsForward(x + 1, y)) quad(rBase, rTop, minusY(rTop), minusY(rBase), COLORS.wallEndRight);
    }

    // Back corner where a left and a right wall meet: fill the gap between the two top strips.
    if (leftWall && rightWall) {
      const c: Point = [top[0], wallTop(x, y)];
      g.poly([...c, ...minusX(c), c[0], c[1] - T, ...minusY(c)]).fill(COLORS.wallTop);
    }

    // ---- floor ----
    if (isDoor(x, y)) {
      // Behind the door opening: darkness first, then the door tile's floor in front of it.
      const [dl, dt] = [corner(x + 1, y + 1, z), corner(x + 1, y, z)];
      quad(down(dl, FLOOR_THICKNESS), down(dt, FLOOR_THICKNESS), down(dt, -DOOR_HEIGHT), down(dl, -DOOR_HEIGHT), COLORS.doorway);
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

/** The door opening's outline, for clipping avatars standing in the doorway. */
export function doorOpening(grid: Grid, door: [number, number]): number[] {
  const [dx, dy] = door;
  const z = heightAt(grid, dx + 1, dy);
  const a = corner(dx + 1, dy, z);
  const b = corner(dx + 1, dy + 1, z);
  // A little below the floor line so feet and shadow aren't cut off.
  return [a[0], a[1] + 14, b[0], b[1] + 14, b[0], b[1] - DOOR_HEIGHT, a[0], a[1] - DOOR_HEIGHT];
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
