// Furni: what a piece of furniture is (its definition) and where one stands in a room.
//
// Definitions live in content/furni/<pack>.json (in git). Their pictures are the pack's own image
// files (licensed, never in git); the server turns each definition into one sprite sheet with
// a frame list (sprites/built/furni/<id>.png + .json), like Habbo's furni packages.

/** Directions a furni can face, as in Habbo: 0 up-right, 2 down-right, 4 down-left, 6 up-left. */
export type FurniDir = 0 | 2 | 4 | 6;
export const FURNI_DIRS: readonly FurniDir[] = [4, 2, 6, 0];

/**
 * The pictures for one direction: per state (switched off/on, closed/open…) its frames (more than
 * one: animated), or another direction's pictures mirrored.
 */
export type FurniDirImages = { states: string[][] } | { mirror: FurniDir };

export interface FurniDef {
  /** Unique id, e.g. "salvaje_chair_2". */
  id: string;
  name: string;
  /** Pack folder its images come from (under sprites/). */
  source: string;
  kind: 'floor' | 'wall';
  /** Tiles it covers facing direction 4: [along x, along y]. Turned 90° (2 and 6) they swap. */
  size: [number, number];
  /** Pictures per direction. The first listed direction is the one it is placed in by default. */
  dirs: Partial<Record<FurniDir, FurniDirImages>>;
  /** Frames per second for states with more than one frame. */
  fps?: number;
  /** Animations play once and then stay on their last frame (a present opening). */
  once?: boolean;
  /** Picture size multiplier (1 = the pack's own size, which matches our 64x32 tiles). */
  scale?: number;
  /** Fine-tuning of where the picture sits, in screen pixels at scale 1 (mirrored with the picture). */
  offset?: [number, number];
  /** How high its top is, in height steps (things stacked on it stand there). Default: measured from the picture. */
  height?: number;
  /** Seats: how high you sit, in height steps (default SIT_HEIGHT). */
  sitHeight?: number;
  /** Avatars can sit on it. */
  sit?: boolean;
  /** Avatars lie down on it (beds): on its head end, along its length. */
  lay?: boolean;
  /** Avatars can walk over it (rugs, mats). */
  walk?: boolean;
  /** Other furni can be put on top of it (tables, cabinets). */
  stack?: boolean;
  /**
   * Hangs this many height steps above its floor (kitchen wall cabinets, wall shelves): it blocks
   * nobody, and other furni can stand under it on the same tiles.
   */
  hang?: number;
}

/** One built frame in a furni's sprite sheet. ax/ay: the anchor (the footprint's front corner) inside the frame. */
export interface FurniFrame {
  x: number;
  y: number;
  w: number;
  h: number;
  ax: number;
  ay: number;
}

/** A built sprite sheet's frame list: per direction, per state, its frames (mirrored directions are left out). */
export interface FurniSheet {
  version: number;
  dirs: Partial<Record<FurniDir, FurniFrame[][]>>;
}

/**
 * A furni in a room. Floor furni: standing on tile (x, y) (its back corner) at height z.
 * Wall furni: hanging on the wall at the edge of floor tile (x, y), `off` (0-1) along that edge
 * and z height steps above that floor; direction 4 = on a left wall (the tile's x edge),
 * 2 = on a back wall (the tile's y edge).
 */
export interface RoomFurni {
  /** Unique within the room. */
  uid: number;
  def: string;
  x: number;
  y: number;
  z: number;
  dir: FurniDir;
  /** Which of its states it shows (0 = the first). */
  state: number;
  off?: number | undefined;
}

/**
 * How high you sit on a seat that doesn't say, in height steps above where it stands. The Cozy
 * sitting pictures are drawn with the feet on the floor and the seat at chair height, so for an
 * ordinary chair this is 0.
 */
export const SIT_HEIGHT = 0;
/** How high you lie on a bed that doesn't say (its mattress), in height steps above where it stands. */
export const LAY_HEIGHT = 0.5;
/** Wall furni hang between these heights above the floor (height steps). */
export const WALL_ITEM_MIN_Z = 0.3;
export const WALL_ITEM_MAX_Z = 4.2;

/** How high a furni's top is (height steps): its own `height`, or measured from its sheet. */
export function furniHeight(def: FurniDef, sheet?: FurniSheet): number {
  if (def.height !== undefined) return def.height;
  if (def.walk) return 0;
  const [dir, states] = Object.entries(sheet?.dirs ?? {})[0] ?? [];
  const frame = states?.[0]?.[0];
  if (!frame) return 1;
  const [fx, fy] = furniFootprint(def, Number(dir) as FurniDir);
  // The picture's height above the footprint's diamond, in steps (32 px each).
  return Math.max(0, Math.round(((frame.h - (fx + fy) * 16) / 32) * 10) / 10);
}

/** How high a placed furni's top is (height steps): where it stands, plus how high it hangs, plus its height. */
export function furniTop(def: FurniDef, f: Pick<RoomFurni, 'z'>, sheet?: FurniSheet): number {
  return f.z + (def.hang ?? 0) + furniHeight(def, sheet);
}

/** Furni higher than this above their floor stand on hanging furni (a shelf) and block nobody. */
export const ABOVE_HEADS = 1.5;

/** A floor furni already on a tile, for working out where another one can go. */
export interface FurniBelow {
  def: FurniDef;
  /** Its top (furniTop). */
  top: number;
}

/**
 * Where a floor furni would stand on one tile (the same rules on the server and in the game):
 * on the floor, or on top of the highest furni there if things can go on it (tables, rugs, wall
 * shelves). Hanging furni hang over anything, and things stand under them. null: it can't go there.
 */
export function standHeight(def: FurniDef, floorZ: number, below: FurniBelow[]): number | null {
  if (def.hang !== undefined) return floorZ;
  const under = below.filter((b) => b.def.hang === undefined || b.def.stack);
  if (under.length === 0) return floorZ;
  const highest = under.reduce((a, b) => (b.top > a.top ? b : a));
  if (!(highest.def.stack || highest.def.walk)) return null;
  return Math.max(floorZ, highest.top);
}

/** Does a furni standing at z on a floor at floorZ keep avatars off its tiles? */
export function furniBlocks(def: FurniDef, z: number, floorZ: number): boolean {
  if (def.kind !== 'floor' || def.walk || def.sit || def.lay || def.hang !== undefined) return false;
  return z - floorZ < ABOVE_HEADS;
}

/** How many states a furni has (switched off/on, closed/open…). */
export function furniStateCount(def: Pick<FurniDef, 'dirs'>): number {
  return Math.max(1, ...Object.values(def.dirs).map((d) => ('states' in d ? d.states.length : 1)));
}

/** The tiles a furni covers facing `dir`: [along x, along y]. */
export function furniFootprint(def: Pick<FurniDef, 'size'>, dir: FurniDir): [number, number] {
  const [w, l] = def.size;
  return dir === 2 || dir === 6 ? [l, w] : [w, l];
}

/** The directions a furni can face, default first. */
export function furniDirs(def: Pick<FurniDef, 'dirs'>): FurniDir[] {
  return (Object.keys(def.dirs).map(Number) as FurniDir[]).sort((a, b) => FURNI_DIRS.indexOf(a) - FURNI_DIRS.indexOf(b));
}

/** Every tile (x, y) a placed furni covers. */
export function furniTiles(def: Pick<FurniDef, 'size'>, f: Pick<RoomFurni, 'x' | 'y' | 'dir'>): [number, number][] {
  const [w, l] = furniFootprint(def, f.dir);
  const out: [number, number][] = [];
  for (let dy = 0; dy < l; dy++) for (let dx = 0; dx < w; dx++) out.push([f.x + dx, f.y + dy]);
  return out;
}

/** Half a wall furni's picture width, in tiles along its wall (a tile's edge is 32 px wide on screen). */
export function wallHalfWidth(def: FurniDef, sheet: FurniSheet | undefined, dir: FurniDir): number {
  const images = def.dirs[dir];
  const source = images && 'mirror' in images ? images.mirror : dir;
  const frame = sheet?.dirs[source]?.[0]?.[0];
  return frame ? (frame.w * (def.scale ?? 1)) / 2 / 32 : 0.5;
}

/**
 * Does a wall furni fit on its wall: is there wall all along its picture? `wallAt(x, y)` says if
 * floor tile (x, y) has a wall on the side the furni hangs on (direction 4: its x edge, 2: its y edge).
 */
export function wallItemFits(
  def: FurniDef,
  sheet: FurniSheet | undefined,
  spot: Pick<RoomFurni, 'x' | 'y' | 'dir'> & { off: number },
  wallAt: (x: number, y: number) => boolean,
): boolean {
  // A little overhang is fine (pictures have a soft edge); a quarter tile or more is not.
  const half = Math.max(0, wallHalfWidth(def, sheet, spot.dir) - 0.15);
  const from = Math.floor(spot.off - half);
  const to = Math.floor(spot.off + half - 1e-6);
  for (let k = from; k <= to; k++) {
    const [x, y] = spot.dir === 4 ? [spot.x, spot.y + k] : [spot.x + k, spot.y];
    if (!wallAt(x, y)) return false;
  }
  return true;
}
