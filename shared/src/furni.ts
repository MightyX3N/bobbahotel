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
  /** Picture size multiplier (1 = the pack's own size, which matches our 64x32 tiles). */
  scale?: number;
  /** Fine-tuning of where the picture sits, in screen pixels at scale 1. */
  offset?: [number, number];
  /** How high its top is, in height steps (things stacked on it stand there). Default: measured from the picture. */
  height?: number;
  /** Seats: how high you sit, in height steps (default SIT_HEIGHT). */
  sitHeight?: number;
  /** Avatars can sit on it. */
  sit?: boolean;
  /** Avatars can walk over it (rugs, mats). */
  walk?: boolean;
  /** Other furni can be put on top of it (tables, cabinets). */
  stack?: boolean;
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
