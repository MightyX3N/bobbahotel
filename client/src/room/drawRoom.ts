// Draws a room: floor tiles, walls and the door, as pieces that are depth-sorted together with
// avatars, so nothing is ever drawn over something standing in front of it.
//
// - Walls come from Nitro's room parser (vendored in ./nitro, GPL-3), so every layout gets
//   exactly the wall pieces, top edges and end pieces Habbo would give it, also where the
//   outline steps in or out. Faces are coloured by the way they face: no darker strips.
// - The floor is drawn per tile with a thin outline. A floor edge facing empty space shows only
//   the floor's thickness; the tall sides appear only between two floor levels (steps).
// - The door tile sticks out of the left wall: the wall runs straight past it with a door
//   opening in front of it, through which the door tile and anyone on it are seen.
import { Graphics } from 'pixi.js';
import { heightAt, isFloor, type Grid } from '@bobba/shared';
import { STEP_PX, TILE_H, TILE_W, tileCorners, type Point } from './iso.ts';
import { RoomPlaneData } from './nitro/RoomPlaneData';
import { RoomPlaneParser } from './nitro/RoomPlaneParser';

const COLORS = {
  floor: 0xa47a52,
  floorLine: 0x8c6644,
  floorLeft: 0x8a6544,
  floorRight: 0x6d4f35,
  wallLeft: 0xf2c665,
  wallRight: 0xdfa64c,
  wallTop: 0xf9dd9c,
  doorway: 0x0c0c0c,
};

/** Floor thickness (a quarter tile), shown where the floor's edge faces empty space. */
const FLOOR_THICKNESS = 0.25 * STEP_PX;
/** Wall top, in height steps above the highest floor (measured from Habbo: ~144 px on 64 px tiles). */
const WALL_STEPS = 4.5;
/** Door opening height (measured from Habbo: ~85 px, about the avatar's height). */
export const DOOR_HEIGHT = 2.65 * STEP_PX;

/** Sort depth of things standing on tile (x, y). Floor and walls use the same scale. */
export const tileDepth = (x: number, y: number) => x + y + 1;
export const depthToZIndex = (depth: number) => Math.round(depth * 1000);

/** Screen point of grid corner (gx, gy) at height z (fractions allowed). Tile (x, y) spans x..x+1. */
export function corner(gx: number, gy: number, z: number): Point {
  return [(gx - gy) * (TILE_W / 2), (gx + gy) * (TILE_H / 2) - z * STEP_PX];
}

export interface RoomPiece {
  graphics: Graphics;
  depth: number;
}

interface V3 {
  x: number;
  y: number;
  z: number;
}

export function drawRoom(grid: Grid, door: [number, number]): RoomPiece[] {
  const rows = grid.length;
  const cols = Math.max(...grid.map((r) => r.length));
  const [doorX, doorY] = door;

  // Pieces with the same depth share one Graphics.
  const byDepth = new Map<number, Graphics>();
  const at = (depth: number) => {
    const key = depthToZIndex(depth);
    let g = byDepth.get(key);
    if (!g) byDepth.set(key, (g = new Graphics()));
    return g;
  };
  const poly = (depth: number, pts: Point[], color: number) => at(depth).poly(pts.flat()).fill(color);
  const down = (p: Point, px: number): Point => [p[0], p[1] + px];

  // ---- walls, from Nitro's parser ----
  const parser = new RoomPlaneParser();
  parser.initializeTileMap(cols, rows);
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) parser.setTileHeight(x, y, isFloor(grid, x, y) ? heightAt(grid, x, y) : RoomPlaneParser.TILE_BLOCKED);
  }
  parser.wallHeight = WALL_STEPS;
  parser.initializeFromTileData();

  const add = (a: V3, b: V3, k = 1): V3 => ({ x: a.x + b.x * k, y: a.y + b.y * k, z: a.z + b.z * k });
  // Nitro puts tile centres on whole numbers; our tile (x, y) spans x..x+1.
  const ours = (v: V3): V3 => ({ x: v.x + 0.5, y: v.y + 0.5, z: v.z });
  const project = (v: V3): Point => corner(v.x, v.y, v.z);
  const doorTop = heightAt(grid, doorX, doorY) + DOOR_HEIGHT / STEP_PX;

  // Nitro adds each wall as: its face (followed by a copy for the landscape layer), then its top
  // edge and end pieces. A wall's top and ends are only drawn when its face is seen: walls along
  // the front of the room face away from the camera and are left out completely, like Habbo.
  const sameLoc = (a: V3, b: V3) => Math.abs(a.x - b.x) < 1e-6 && Math.abs(a.y - b.y) < 1e-6 && Math.abs(a.z - b.z) < 1e-6;
  const facesCamera = (n: V3) => n.x > 0.001 || n.y > 0.001;
  let wallSeen = false;
  for (let i = 0; i < parser.planeCount; i++) {
    const type = parser.getPlaneType(i);
    if (type !== RoomPlaneData.PLANE_WALL) continue;
    const n = parser.getPlaneNormal(i) as V3;
    const isFace = parser.getPlaneType(i + 1) === RoomPlaneData.PLANE_LANDSCAPE && sameLoc(parser.getPlaneLocation(i) as V3, parser.getPlaneLocation(i + 1) as V3);
    if (isFace) wallSeen = facesCamera(n);
    if (!wallSeen) continue;
    // Only sides facing the camera are seen (like a 3D model).
    const color = n.z > 0.001 ? COLORS.wallTop : n.x > 0.001 ? COLORS.wallLeft : n.y > 0.001 ? COLORS.wallRight : null;
    if (color === null) continue;
    const loc = ours(parser.getPlaneLocation(i) as V3);
    const left = parser.getPlaneLeftSide(i) as V3;
    const right = parser.getPlaneRightSide(i) as V3;
    // Cut long walls into one-tile pieces, so each piece sorts with the tile it stands at.
    const flatLong = (v: V3) => Math.abs(v.z) < 0.001 && Math.hypot(v.x, v.y) > 1.001;
    const long = flatLong(left) ? left : flatLong(right) ? right : null;
    const other = long === left ? right : left;
    const count = long ? Math.round(Math.hypot(long.x, long.y)) : 1;
    const step = long ? { x: long.x / count, y: long.y / count, z: 0 } : left;
    const side = long ? other : right;
    for (let k = 0; k < count; k++) {
      const a = add(loc, step, k);
      const b = add(a, step);
      const corners = [a, b, add(b, side), add(a, side)];
      const depth = corners.reduce((s, v) => s + v.x + v.y, 0) / 4;
      // The door opening: the left-wall face in front of the door tile is cut out below the door height.
      const midY = corners.reduce((s, v) => s + v.y, 0) / 4;
      const inFrontOfDoor = color === COLORS.wallLeft && corners.every((v) => Math.abs(v.x - (doorX + 1)) < 0.01) && midY > doorY && midY < doorY + 1;
      const shown = inFrontOfDoor ? corners.map((v) => ({ ...v, z: Math.max(v.z, doorTop) })) : corners;
      poly(depth, shown.map(project), color);
    }
  }

  // ---- step pieces ----
  // Where the back outline steps forward (like the Lobby's back-right corner, or a left wall that
  // steps right further down), Nitro leaves out the short piece between the two walls because its
  // room side faces away. Its outside faces the camera, though, so like a 3D model it is drawn:
  // outside face plus top, making one solid, connected wall. Walls along the very front of the
  // room stay out (there is no floor beyond them).
  const T = 0.25;
  const maxZ = Math.max(0, ...grid.flat());
  const top = maxZ + WALL_STEPS;
  const solid = (x: number, y: number) => isFloor(grid, x, y) && !(x === doorX && y === doorY);
  // Empty tiles that are part of the outside behind the room: connected to the back (top) or left
  // edge of the layout. Holes inside the room and gaps open to the front get no walls.
  const behind = new Set<number>();
  const stack: [number, number][] = [];
  for (let x = 0; x < cols; x++) stack.push([x, 0]);
  for (let y = 0; y < rows; y++) stack.push([0, y]);
  while (stack.length > 0) {
    const [x, y] = stack.pop()!;
    const key = y * cols + x;
    if (x < 0 || y < 0 || x >= cols || y >= rows || behind.has(key) || isFloor(grid, x, y)) continue;
    behind.add(key);
    stack.push([x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]);
  }
  const isBehind = (x: number, y: number) => x >= 0 && y >= 0 && x < cols && y < rows && behind.has(y * cols + x);
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      if (!solid(x, y)) continue;
      const base = heightAt(grid, x, y) - T;
      // Floor (x, y), nothing to its right, but floor further down that empty column: the right
      // wall stepped forward here. Piece along grid x+1, outside towards +x.
      let frontInColumn = false;
      for (let j = y + 1; j < rows; j++) if (solid(x + 1, j)) frontInColumn = true;
      if (isBehind(x + 1, y) && frontInColumn) {
        const backWall = !isFloor(grid, x, y - 1) || !isFloor(grid, x + 1, y - 1);
        const y0 = backWall ? y - T : y;
        const gx = x + 1 + T;
        const depth = tileDepth(x + 1, y) - 0.2;
        poly(depth, [corner(gx, y0, base), corner(gx, y + 1, base), corner(gx, y + 1, top), corner(gx, y0, top)], COLORS.wallLeft);
        poly(depth, [corner(x + 1, y0, top), corner(x + 1, y + 1, top), corner(gx, y + 1, top), corner(gx, y0, top)], COLORS.wallTop);
      }
      // Floor (x, y), nothing below it, but floor further right in that empty row: the left wall
      // stepped right here. Piece along grid y+1, outside towards +y.
      let frontInRow = false;
      for (let i = x + 1; i < cols; i++) if (solid(i, y + 1)) frontInRow = true;
      if (isBehind(x, y + 1) && frontInRow) {
        const leftWall = !isFloor(grid, x - 1, y) || !isFloor(grid, x - 1, y + 1);
        const x0 = leftWall ? x - T : x;
        const gy = y + 1 + T;
        const depth = tileDepth(x, y + 1) - 0.2;
        poly(depth, [corner(x0, gy, base), corner(x + 1, gy, base), corner(x + 1, gy, top), corner(x0, gy, top)], COLORS.wallRight);
        poly(depth, [corner(x0, y + 1, top), corner(x + 1, y + 1, top), corner(x + 1, gy, top), corner(x0, gy, top)], COLORS.wallTop);
      }
    }
  }

  // ---- floor, per tile ----
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      if (!isFloor(grid, x, y)) continue;
      const z = heightAt(grid, x, y);
      const depth = tileDepth(x, y) - 0.1;
      const [top, right, bottom, left] = tileCorners(x, y, z);
      if (x === doorX && y === doorY) {
        // Darkness behind the door opening, then the door tile's floor in front of it.
        const dl = corner(x + 1, y + 1, z);
        const dt = corner(x + 1, y, z);
        poly(depth - 0.05, [down(dl, FLOOR_THICKNESS), down(dt, FLOOR_THICKNESS), down(dt, -DOOR_HEIGHT), down(dl, -DOOR_HEIGHT)], COLORS.doorway);
      }
      // Sides facing down-left (+y) and down-right (+x): only the floor's thickness towards empty
      // space, a full step down towards a lower floor, nothing towards a floor as high or higher.
      const drop = (nx: number, ny: number) => {
        const nz = heightAt(grid, nx, ny);
        return nz < 0 ? FLOOR_THICKNESS : z > nz ? (z - nz) * STEP_PX : 0;
      };
      const dropLeft = drop(x, y + 1);
      const dropRight = drop(x + 1, y);
      if (dropLeft > 0) poly(depth, [left, bottom, down(bottom, dropLeft), down(left, dropLeft)], COLORS.floorLeft);
      if (dropRight > 0) poly(depth, [bottom, right, down(right, dropRight), down(bottom, dropRight)], COLORS.floorRight);
      at(depth)
        .poly([...top, ...right, ...bottom, ...left])
        .fill(COLORS.floor)
        .stroke({ color: COLORS.floorLine, width: 1, alignment: 1 });
    }
  }

  return [...byDepth.entries()].map(([key, graphics]) => ({ graphics, depth: key / 1000 }));
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
