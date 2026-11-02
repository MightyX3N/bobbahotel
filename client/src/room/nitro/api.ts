// @ts-nocheck
// Small stand-ins for the nitro-renderer imports the room parser needs (see ./README.md).
export { Vector3d } from './Vector3d';
export type { IVector3D } from './IVector3D';

export class Point {
  x: number;
  y: number;
  constructor(x = 0, y = 0) {
    this.x = x;
    this.y = y;
  }
  clone(): Point {
    return new Point(this.x, this.y);
  }
  set(x = 0, y = x): void {
    this.x = x;
    this.y = y;
  }
}

/** Shape of the map data object (only used for its type). */
export interface IRoomMapData {
  width: number;
  height: number;
  wallHeight: number;
  fixedWallsHeight: number;
  tileMap: { height: number }[][];
  holeMap: unknown[];
  doors: unknown[];
  dimensions: { minX: number; maxX: number; minY: number; maxY: number };
}
