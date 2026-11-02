// Draws a room's floor and walls in flat colours: brown floor, yellow/orange walls, door opening.
// Walls run along the back edges only (like Habbo): a tile gets a left wall if there is no floor
// anywhere to its left in its row, and a right wall if there is none above it in its column.
import { Graphics } from 'pixi.js';
import { heightAt, isFloor, type Grid } from '@bobba/shared';
import { STEP_PX, TILE_H, TILE_W, tileCorners } from './iso.ts';

const COLORS = {
  floor: 0xa47a52,
  floorLeft: 0x8a6544,
  floorRight: 0x6d4f35,
  wallLeft: 0xf0c060,
  wallRight: 0xdca04a,
  wallTop: 0xf7d895,
  wallEdge: 0xb9822f,
  doorway: 0x111111,
};

/** Floor thickness shown at the room's front edges. */
const FLOOR_THICKNESS = 8;
/** Wall height above the highest floor. */
const WALL_HEIGHT = 3.6 * STEP_PX;
const WALL_THICKNESS = 8;
const DOOR_HEIGHT = 2.7 * STEP_PX;

export function drawRoom(grid: Grid, door: [number, number]): Graphics {
  const g = new Graphics();
  const rows = grid.length;
  const cols = Math.max(...grid.map((r) => r.length));
  const maxZ = Math.max(0, ...grid.flat());
  const wallTopY = (x: number, y: number) => tileCorners(x, y, 0)[0][1] - maxZ * STEP_PX - WALL_HEIGHT;

  const leftWall = (x: number, y: number) => {
    for (let i = 0; i < x; i++) if (isFloor(grid, i, y)) return false;
    return true;
  };
  const rightWall = (x: number, y: number) => {
    for (let j = 0; j < y; j++) if (isFloor(grid, x, j)) return false;
    return true;
  };

  // ---- walls (behind everything) ----
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      if (!isFloor(grid, x, y)) continue;
      const z = heightAt(grid, x, y);
      const [top, right, , left] = tileCorners(x, y, z);
      const isDoor = door[0] === x && door[1] === y;

      if (leftWall(x, y)) {
        // Along the tile's top-left edge (left corner -> top corner).
        const lTop = wallTopY(x, y + 1);
        const tTop = wallTopY(x, y);
        if (isDoor) {
          const dl = left[1] - DOOR_HEIGHT;
          const dt = top[1] - DOOR_HEIGHT;
          g.poly([left[0], dl, top[0], dt, top[0], tTop, left[0], lTop]).fill(COLORS.wallLeft);
          g.poly([left[0], left[1], top[0], top[1], top[0], dt, left[0], dl]).fill(COLORS.doorway);
        } else {
          g.poly([left[0], left[1], top[0], top[1], top[0], tTop, left[0], lTop]).fill(COLORS.wallLeft);
        }
        // Thickness on top, leaning away from the room.
        g.poly([left[0], lTop, top[0], tTop, top[0] - WALL_THICKNESS, tTop - WALL_THICKNESS / 2, left[0] - WALL_THICKNESS, lTop - WALL_THICKNESS / 2]).fill(COLORS.wallTop);
        // Outer end where the wall stops at the front.
        if (!isFloor(grid, x, y + 1) || !leftWall(x, y + 1)) {
          g.poly([left[0], left[1], left[0], lTop, left[0] - WALL_THICKNESS, lTop - WALL_THICKNESS / 2, left[0] - WALL_THICKNESS, left[1] + FLOOR_THICKNESS - WALL_THICKNESS / 2]).fill(COLORS.wallEdge);
        }
      }

      if (rightWall(x, y)) {
        // Along the tile's top-right edge (top corner -> right corner).
        const tTop = wallTopY(x, y);
        const rTop = wallTopY(x + 1, y);
        g.poly([top[0], top[1], right[0], right[1], right[0], rTop, top[0], tTop]).fill(COLORS.wallRight);
        g.poly([top[0], tTop, right[0], rTop, right[0] + WALL_THICKNESS, rTop - WALL_THICKNESS / 2, top[0] + WALL_THICKNESS, tTop - WALL_THICKNESS / 2]).fill(COLORS.wallTop);
        if (!isFloor(grid, x + 1, y) || !rightWall(x + 1, y)) {
          g.poly([right[0], right[1], right[0], rTop, right[0] + WALL_THICKNESS, rTop - WALL_THICKNESS / 2, right[0] + WALL_THICKNESS, right[1] + FLOOR_THICKNESS - WALL_THICKNESS / 2]).fill(COLORS.wallEdge);
        }
      }
    }
  }

  // ---- floor, back to front ----
  const tiles: [number, number][] = [];
  for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) if (isFloor(grid, x, y)) tiles.push([x, y]);
  tiles.sort((a, b) => a[0] + a[1] - (b[0] + b[1]));

  for (const [x, y] of tiles) {
    const z = heightAt(grid, x, y);
    const [top, right, bottom, left] = tileCorners(x, y, z);
    // Side facing down-left (towards +y): visible if the tile in front is lower or missing.
    const frontY = heightAt(grid, x, y + 1);
    const dropLeft = frontY < 0 ? z * STEP_PX + FLOOR_THICKNESS : (z - frontY) * STEP_PX;
    if (dropLeft > 0) g.poly([left[0], left[1], bottom[0], bottom[1], bottom[0], bottom[1] + dropLeft, left[0], left[1] + dropLeft]).fill(COLORS.floorLeft);
    // Side facing down-right (towards +x).
    const frontX = heightAt(grid, x + 1, y);
    const dropRight = frontX < 0 ? z * STEP_PX + FLOOR_THICKNESS : (z - frontX) * STEP_PX;
    if (dropRight > 0) g.poly([bottom[0], bottom[1], right[0], right[1], right[0], right[1] + dropRight, bottom[0], bottom[1] + dropRight]).fill(COLORS.floorRight);
    g.poly([...top, ...right, ...bottom, ...left]).fill(COLORS.floor);
  }
  return g;
}

/** Outline shown on the tile under the mouse. */
export function drawTileOutline(g: Graphics, x: number, y: number, z: number): void {
  const c = tileCorners(x, y, z);
  g.clear()
    .poly(c.flat())
    .stroke({ color: 0x000000, width: 2, alpha: 0.35, alignment: 0.5 })
    .poly(c.flat())
    .stroke({ color: 0xffffff, width: 1, alpha: 0.6, alignment: 0.5 });
}

export const ROOM_SIZE = { TILE_W, TILE_H };
