// Draws a room's floor and walls in flat colours: brown floor with tile outlines, yellow/orange
// walls with thickness, and a dark door opening.
//
// Walls run along the back edges only (like Habbo): a tile gets a left wall if there is no floor
// anywhere to its left in its row, and a right wall if there is none above it in its column.
// Everything is drawn tile by tile from back to front, each tile's walls together with the tile,
// so a wall standing in front of a floor tile always covers it (and never the other way round).
import { Graphics } from 'pixi.js';
import { heightAt, isFloor, type Grid } from '@bobba/shared';
import { STEP_PX, tileCorners, type Point } from './iso.ts';

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
  doorway: 0x141414,
};

/** Floor thickness shown at the room's front edges. */
const FLOOR_THICKNESS = 8;
/** Wall height above the highest floor. */
const WALL_HEIGHT = 3.6 * STEP_PX;
/** Wall thickness: the top strip leans this far away from the room. */
const T = 8;
const DOOR_HEIGHT = 2.6 * STEP_PX;

export function drawRoom(grid: Grid, door: [number, number]): Graphics {
  const g = new Graphics();
  const rows = grid.length;
  const cols = Math.max(...grid.map((r) => r.length));
  const maxZ = Math.max(0, ...grid.flat());
  const topY = (gx: number, gy: number) => tileCorners(gx, gy, 0)[0][1] - maxZ * STEP_PX - WALL_HEIGHT;

  const hasLeftWall = (x: number, y: number) => {
    if (!isFloor(grid, x, y)) return false;
    for (let i = 0; i < x; i++) if (isFloor(grid, i, y)) return false;
    return true;
  };
  const hasRightWall = (x: number, y: number) => {
    if (!isFloor(grid, x, y)) return false;
    for (let j = 0; j < y; j++) if (isFloor(grid, x, j)) return false;
    return true;
  };
  const quad = (a: Point, b: Point, c: Point, d: Point, color: number) => g.poly([...a, ...b, ...c, ...d]).fill(color);

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
      const lTop: Point = [left[0], topY(x, y + 1)];
      const tTop: Point = [top[0], topY(x, y)];
      if (door[0] === x && door[1] === y) {
        const dl: Point = [left[0], left[1] - DOOR_HEIGHT];
        const dt: Point = [top[0], top[1] - DOOR_HEIGHT];
        quad(dl, dt, tTop, lTop, COLORS.wallLeft);
        quad(left, top, dt, dl, COLORS.doorway);
      } else {
        quad(left, top, tTop, lTop, COLORS.wallLeft);
      }
      // Top strip, leaning away from the room.
      quad(lTop, tTop, [tTop[0] - T, tTop[1] - T / 2], [lTop[0] - T, lTop[1] - T / 2], COLORS.wallTop);
      // End piece where the wall stops at the front.
      if (!hasLeftWall(x, y + 1)) {
        quad([left[0], left[1] + FLOOR_THICKNESS], lTop, [lTop[0] - T, lTop[1] - T / 2], [left[0] - T, left[1] + FLOOR_THICKNESS - T / 2], COLORS.wallEndLeft);
      }
    }

    // ---- right wall, along the tile's top-right edge (top corner -> right corner) ----
    if (rightWall) {
      const tTop: Point = [top[0], topY(x, y)];
      const rTop: Point = [right[0], topY(x + 1, y)];
      quad(top, right, rTop, tTop, COLORS.wallRight);
      quad(tTop, rTop, [rTop[0] + T, rTop[1] - T / 2], [tTop[0] + T, tTop[1] - T / 2], COLORS.wallTop);
      if (!hasRightWall(x + 1, y)) {
        quad([right[0], right[1] + FLOOR_THICKNESS], rTop, [rTop[0] + T, rTop[1] - T / 2], [right[0] + T, right[1] + FLOOR_THICKNESS - T / 2], COLORS.wallEndRight);
      }
      // A right wall that starts here without a left wall next to it gets an end piece on its back side too.
      if (!leftWall && !hasRightWall(x - 1, y)) {
        quad([top[0], top[1]], tTop, [tTop[0] + T, tTop[1] - T / 2], [top[0] + T, top[1] - T / 2], COLORS.wallEndLeft);
      }
    }

    // Back corner where a left and a right wall meet: fill the gap between the two top strips.
    if (leftWall && rightWall) {
      const c: Point = [top[0], topY(x, y)];
      g.poly([...c, c[0] - T, c[1] - T / 2, c[0], c[1] - T, c[0] + T, c[1] - T / 2]).fill(COLORS.wallTop);
    }

    // ---- floor ----
    // Side facing down-left (towards +y): visible if the tile in front is lower or missing.
    const frontY = heightAt(grid, x, y + 1);
    const dropLeft = frontY < 0 ? z * STEP_PX + FLOOR_THICKNESS : (z - frontY) * STEP_PX;
    if (dropLeft > 0) quad(left, bottom, [bottom[0], bottom[1] + dropLeft], [left[0], left[1] + dropLeft], COLORS.floorLeft);
    // Side facing down-right (towards +x).
    const frontX = heightAt(grid, x + 1, y);
    const dropRight = frontX < 0 ? z * STEP_PX + FLOOR_THICKNESS : (z - frontX) * STEP_PX;
    if (dropRight > 0) quad(bottom, right, [right[0], right[1] + dropRight], [bottom[0], bottom[1] + dropRight], COLORS.floorRight);
    // Top, with a thin outline so the tiles can be told apart.
    g.poly([...top, ...right, ...bottom, ...left])
      .fill(COLORS.floor)
      .stroke({ color: COLORS.floorLine, width: 1, alignment: 1 });
  }
  return g;
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
