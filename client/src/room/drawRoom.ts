// Draws a room: floor tiles, walls and the door, as pieces that are depth-sorted together with
// avatars, so nothing is ever drawn over something standing in front of it.
//
// - Walls come from Nitro's room parser (vendored in ./nitro, GPL-3) and are shown by Nitro's own
//   visibility rule. Where Nitro stops a wall because the outline turns, connecting pieces keep
//   the wall one solid piece. Faces are coloured by the way they face: no darker strips.
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
/**
 * Nitro gives every wall the same top: the highest floor plus WALL_STEPS. In rooms with floors on
 * very different levels that makes walls next to low floors tower over everything. A wall is
 * kept that high only when its own floor is at most this many steps lower; otherwise it ends
 * WALL_STEPS above the floor next to it, so rooms with levels stay usable.
 */
const WALL_TOP_SLACK = 1;
/** Door opening height: just taller than the avatar (88 px), so its head fits under the lintel. */
export const DOOR_HEIGHT = 2.9 * STEP_PX;

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
  /** Floor pieces are drawn below everything (furni and avatars always stand on top, like Habbo);
   *  wall pieces are depth-sorted with furni and avatars (so the doorway hides who's in it). */
  layer: 'floor' | 'wall';
}

/** Nitro's camera direction (RoomGeometry(64, (-135, 30, 0), (11, 11, 5)).directionAxis). */
const VIEW = { x: -0.6123724356957945, y: -0.6123724356957946, z: -0.5 };

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
  const floorByDepth = new Map<number, Graphics>();
  const at = (depth: number, map = byDepth) => {
    const key = depthToZIndex(depth);
    let g = map.get(key);
    if (!g) map.set(key, (g = new Graphics()));
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
  const maxZ = Math.max(0, ...grid.flat());
  // Nitro's wall top (RoomPlaneParser: wallHeight + min(MAX_WALL_ADDITIONAL_HEIGHT = 20, floorHeight)).
  const highTop = Math.min(20, maxZ) + WALL_STEPS;
  /** Wall top at grid point (gx, gy): see WALL_TOP_SLACK. */
  const topAt = (gx: number, gy: number) => {
    let near = -1;
    for (let ty = Math.floor(gy - 0.5); ty <= Math.floor(gy + 0.5); ty++) {
      for (let tx = Math.floor(gx - 0.5); tx <= Math.floor(gx + 0.5); tx++) near = Math.max(near, heightAt(grid, tx, ty));
    }
    if (near < 0) return highTop;
    const own = near + WALL_STEPS;
    return highTop - own > WALL_TOP_SLACK ? own : highTop;
  };
  const lowerTop = (v: V3): V3 => (Math.abs(v.z - highTop) < 1e-3 ? { ...v, z: topAt(v.x, v.y) } : v);
  const doorTop = heightAt(grid, doorX, doorY) + DOOR_HEIGHT / STEP_PX;

  // Which wall planes are seen: Nitro's own rule (RoomPlane.update). A plane is drawn only when
  // it and all its secondary normals face the camera, so walls along the front of the room,
  // their tops and end pieces are left out exactly like Habbo.
  const cos = (n: V3) => (n.x * VIEW.x + n.y * VIEW.y + n.z * VIEW.z) / (Math.hypot(n.x, n.y, n.z) || 1);
  const seen = (i: number) => [parser.getPlaneNormal(i) as V3, ...((parser.getPlaneSecondaryNormals(i) ?? []) as V3[])].every((n) => cos(n) < -0.001);
  // Wall faces Nitro drew, by grid line and tile: "x<gx>,<y>" (left walls) and "y<gy>,<x>" (back walls).
  const nitroFaces = new Set<string>();
  for (let i = 0; i < parser.planeCount; i++) {
    if (parser.getPlaneType(i) !== RoomPlaneData.PLANE_WALL || !seen(i)) continue;
    const n = parser.getPlaneNormal(i) as V3;
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
      const corners = [a, b, add(b, side), add(a, side)].map(lowerTop);
      const depth = corners.reduce((s, v) => s + v.x + v.y, 0) / 4;
      // The door opening: the left-wall face in front of the door tile is cut out below the door height.
      const midY = corners.reduce((s, v) => s + v.y, 0) / 4;
      const inFrontOfDoor = color === COLORS.wallLeft && corners.every((v) => Math.abs(v.x - (doorX + 1)) < 0.01) && midY > doorY && midY < doorY + 1;
      const shown = inFrontOfDoor ? corners.map((v) => ({ ...v, z: Math.max(v.z, doorTop) })) : corners;
      // The wall above the opening (the lintel) is drawn over anyone standing in the doorway.
      poly(inFrontOfDoor ? tileDepth(doorX, doorY) + 0.7 : depth, shown.map(project), color);
      if (color === COLORS.wallLeft) nitroFaces.add(`x${Math.round(a.x)},${Math.floor(Math.min(...corners.map((v) => v.y)) + 0.01)}`);
      if (color === COLORS.wallRight) nitroFaces.add(`y${Math.round(a.y)},${Math.floor(Math.min(...corners.map((v) => v.x)) + 0.01)}`);
    }
  }

  // ---- connecting pieces ----
  // Nitro only draws the walls along the room's outline as far as it keeps stepping away from the
  // camera; where the outline turns (a left wall that steps right further down, the Lobby's
  // back-right corner) it stops. Like a 3D model with only its camera-facing sides shown, the
  // missing pieces are added here so the walls stay one connected, solid wall:
  //   - inside faces (+x or +y) on floor whose left or back neighbour is outside, if Nitro left them out;
  //   - outside faces where the outline steps forward, with floor further along to connect to.
  // Holes inside the room (with floor before them in their row and column) get no walls, and only
  // pieces that join up with Nitro's walls are drawn.
  const T = 0.25;
  const solid = (x: number, y: number) => isFloor(grid, x, y) && !(x === doorX && y === doorY);
  /** Empty tile outside the back of the room: no floor before it in its row, or in its column. */
  const isBehind = (x: number, y: number) => {
    if (isFloor(grid, x, y)) return false;
    let rowOpen = true;
    let colOpen = true;
    for (let i = 0; i < x && rowOpen; i++) if (isFloor(grid, i, y)) rowOpen = false;
    for (let j = 0; j < y && colOpen; j++) if (isFloor(grid, x, j)) colOpen = false;
    return rowOpen || colOpen;
  };
  // Candidate pieces, by the grid line they stand on (from point a to point b). Only pieces that
  // connect to Nitro's walls (directly or through other added pieces) are drawn, so separate parts
  // of a room and floor further down don't get walls of their own standing in front of things.
  const candidates: { a: [number, number]; b: [number, number]; draw: () => void }[] = [];
  const piece = (a: [number, number], b: [number, number], draw: () => void) => candidates.push({ a, b, draw });
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      if (!solid(x, y)) continue;
      const z = heightAt(grid, x, y);
      const depth = tileDepth(x, y) - 0.6;
      // Inside face on the tile's left edge (grid line x), facing +x.
      if (isBehind(x - 1, y) && !nitroFaces.has(`x${x},${y}`)) piece([x, y], [x, y + 1], () => {
        const y0 = isBehind(x, y - 1) ? y - T : y;
        poly(depth, [corner(x, y, z), corner(x, y + 1, z), corner(x, y + 1, topAt(x, y + 1)), corner(x, y, topAt(x, y))], COLORS.wallLeft);
        poly(depth, [corner(x - T, y0, topAt(x - T, y0)), corner(x - T, y + 1, topAt(x - T, y + 1)), corner(x, y + 1, topAt(x, y + 1)), corner(x, y0, topAt(x, y0))], COLORS.wallTop);
        // Where this wall ends (no wall continues on the next tile), its end shows its thickness.
        if (!solid(x, y + 1) && isBehind(x - 1, y + 1)) {
          poly(depth, [corner(x - T, y + 1, z - T), corner(x, y + 1, z - T), corner(x, y + 1, topAt(x, y + 1)), corner(x - T, y + 1, topAt(x - T, y + 1))], COLORS.wallRight);
        }
      });
      // Inside face on the tile's back edge (grid line y), facing +y.
      if (isBehind(x, y - 1) && !nitroFaces.has(`y${y},${x}`)) piece([x, y], [x + 1, y], () => {
        const x0 = isBehind(x - 1, y) ? x - T : x;
        poly(depth, [corner(x, y, z), corner(x + 1, y, z), corner(x + 1, y, topAt(x + 1, y)), corner(x, y, topAt(x, y))], COLORS.wallRight);
        poly(depth, [corner(x0, y - T, topAt(x0, y - T)), corner(x + 1, y - T, topAt(x + 1, y - T)), corner(x + 1, y, topAt(x + 1, y)), corner(x0, y, topAt(x0, y))], COLORS.wallTop);
        if (!solid(x + 1, y) && isBehind(x + 1, y - 1)) {
          poly(depth, [corner(x + 1, y - T, z - T), corner(x + 1, y, z - T), corner(x + 1, y, topAt(x + 1, y)), corner(x + 1, y - T, topAt(x + 1, y - T))], COLORS.wallLeft);
        }
      });
      const base = z - T;
      // Nothing to the right, but floor further down that empty column: the back wall steps
      // forward here. Outside face along grid x+1, facing +x.
      let frontInColumn = false;
      for (let j = y + 1; j < rows && !frontInColumn; j++) if (solid(x + 1, j)) frontInColumn = true;
      if (isBehind(x + 1, y) && frontInColumn) piece([x + 1, y], [x + 1, y + 1], () => {
        const y0 = isBehind(x, y - 1) || isBehind(x + 1, y - 1) ? y - T : y;
        const gx = x + 1 + T;
        const d = tileDepth(x + 1, y) - 0.2;
        poly(d, [corner(gx, y0, base), corner(gx, y + 1, base), corner(gx, y + 1, topAt(gx, y + 1)), corner(gx, y0, topAt(gx, y0))], COLORS.wallLeft);
        poly(d, [corner(x + 1, y0, topAt(x + 1, y0)), corner(x + 1, y + 1, topAt(x + 1, y + 1)), corner(gx, y + 1, topAt(gx, y + 1)), corner(gx, y0, topAt(gx, y0))], COLORS.wallTop);
      });
      // Nothing below, but floor further right in that empty row: the left wall steps right here.
      // Outside face along grid y+1, facing +y.
      let frontInRow = false;
      for (let i = x + 1; i < cols && !frontInRow; i++) if (solid(i, y + 1)) frontInRow = true;
      if (isBehind(x, y + 1) && frontInRow) piece([x, y + 1], [x + 1, y + 1], () => {
        const x0 = isBehind(x - 1, y) || isBehind(x - 1, y + 1) ? x - T : x;
        const gy = y + 1 + T;
        const d = tileDepth(x, y + 1) - 0.2;
        poly(d, [corner(x0, gy, base), corner(x + 1, gy, base), corner(x + 1, gy, topAt(x + 1, gy)), corner(x0, gy, topAt(x0, gy))], COLORS.wallRight);
        poly(d, [corner(x0, y + 1, topAt(x0, y + 1)), corner(x + 1, y + 1, topAt(x + 1, y + 1)), corner(x + 1, gy, topAt(x + 1, gy)), corner(x0, gy, topAt(x0, gy))], COLORS.wallTop);
      });
    }
  }

  const wallPoints = new Set<string>();
  for (const key of nitroFaces) {
    const [g, t] = key.slice(1).split(',').map(Number) as [number, number];
    if (key[0] === 'x') wallPoints.add(`${g},${t}`).add(`${g},${t + 1}`);
    else wallPoints.add(`${t},${g}`).add(`${t + 1},${g}`);
  }
  const point = (p: [number, number]) => `${p[0]},${p[1]}`;
  const left = new Set(candidates);
  for (let grown = true; grown; ) {
    grown = false;
    for (const c of left) {
      if (!wallPoints.has(point(c.a)) && !wallPoints.has(point(c.b))) continue;
      wallPoints.add(point(c.a)).add(point(c.b));
      left.delete(c);
      c.draw();
      grown = true;
    }
  }

  // ---- floor, from Nitro's floor planes ----
  // Nitro gives the floor's top, its thickness where it meets empty space, the sides between two
  // levels and, where the floor goes one step down, stairs (like Habbo). Each plane is cut into
  // one-tile pieces so it sorts with the tile it belongs to.
  interface Cell {
    depth: number;
    order: number;
    pts: Point[];
    color: number;
    lines: [Point, Point][];
  }
  const cells: Cell[] = [];
  for (let i = 0; i < parser.planeCount; i++) {
    if (parser.getPlaneType(i) !== RoomPlaneData.PLANE_FLOOR || !seen(i)) continue;
    const n = parser.getPlaneNormal(i) as V3;
    const flat = n.z > 0.001;
    const color = flat ? COLORS.floor : n.y > 0.001 ? COLORS.floorLeft : n.x > 0.001 ? COLORS.floorRight : null;
    if (color === null) continue;
    const loc = ours(parser.getPlaneLocation(i) as V3);
    const left = parser.getPlaneLeftSide(i) as V3;
    const right = parser.getPlaneRightSide(i) as V3;
    const corners = [loc, add(loc, left), add(add(loc, left), right), add(loc, right)];
    const lo = (k: 'x' | 'y' | 'z') => Math.min(...corners.map((v) => v[k]));
    const hi = (k: 'x' | 'y' | 'z') => Math.max(...corners.map((v) => v[k]));
    // Cut points: the plane's own ends plus every whole grid line in between.
    const cuts = (a: number, b: number) => {
      const out = [a];
      for (let g = Math.floor(a + 1e-6) + 1; g < b - 1e-6; g++) out.push(g);
      out.push(b);
      return out;
    };
    const xs = cuts(lo('x'), hi('x'));
    const ys = cuts(lo('y'), hi('y'));
    for (let a = 0; a + 1 < xs.length; a++) {
      for (let b = 0; b + 1 < ys.length; b++) {
        const x0 = xs[a]!;
        const x1 = xs[a + 1]!;
        const y0 = ys[b]!;
        const y1 = ys[b + 1]!;
        let pts: Point[];
        if (flat) {
          const z = lo('z');
          pts = [corner(x0, y0, z), corner(x1, y0, z), corner(x1, y1, z), corner(x0, y1, z)];
        } else {
          // A side: x0 == x1 (facing +x) or y0 == y1 (facing +y), from its bottom to its top.
          const [z0, z1] = [lo('z'), hi('z')];
          pts = [corner(x0, y0, z1), corner(x1, y1, z1), corner(x1, y1, z0), corner(x0, y0, z0)];
        }
        // The tile this piece belongs to: a side belongs to the tile it is the edge of.
        const cx = (x0 + x1) / 2 - n.x * 0.01;
        const cy = (y0 + y1) / 2 - n.y * 0.01;
        const depth = tileDepth(Math.floor(cx), Math.floor(cy)) - 0.1;
        // Tile lines only along whole grid lines: stairs don't add extra lines to the floor.
        const lines: [Point, Point][] = [];
        if (flat) {
          const z = lo('z');
          const whole = (v: number) => Math.abs(v - Math.round(v)) < 1e-6;
          if (whole(y0)) lines.push([corner(x0, y0, z), corner(x1, y0, z)]);
          if (whole(x1)) lines.push([corner(x1, y0, z), corner(x1, y1, z)]);
          if (whole(y1)) lines.push([corner(x1, y1, z), corner(x0, y1, z)]);
          if (whole(x0)) lines.push([corner(x0, y1, z), corner(x0, y0, z)]);
        }
        cells.push({ depth, order: cx + cy + (flat ? 0 : 0.001), pts, color, lines });
      }
    }
  }
  // Darkness behind the door opening, drawn before the door tile's floor.
  {
    const z = heightAt(grid, doorX, doorY);
    const dl = corner(doorX + 1, doorY + 1, z);
    const dt = corner(doorX + 1, doorY, z);
    at(tileDepth(doorX, doorY) - 0.15, floorByDepth)
      .poly([down(dl, FLOOR_THICKNESS), down(dt, FLOOR_THICKNESS), down(dt, -DOOR_HEIGHT), down(dl, -DOOR_HEIGHT)].flat())
      .fill(COLORS.doorway);
  }
  cells.sort((a, b) => a.depth - b.depth || a.order - b.order);
  for (const c of cells) {
    const g = at(c.depth, floorByDepth).poly(c.pts.flat()).fill(c.color);
    for (const [a, b] of c.lines) g.moveTo(a[0], a[1]).lineTo(b[0], b[1]);
    if (c.lines.length > 0) g.stroke({ color: COLORS.floorLine, width: 2, alignment: 0.5 });
  }

  return [
    ...[...floorByDepth.entries()].map(([key, graphics]) => ({ graphics, depth: key / 1000, layer: 'floor' as const })),
    ...[...byDepth.entries()].map(([key, graphics]) => ({ graphics, depth: key / 1000, layer: 'wall' as const })),
  ];
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
