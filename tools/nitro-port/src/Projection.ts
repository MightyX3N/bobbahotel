/** @noSelfInFile */
// Bobba Hotel: Nitro's room camera (RoomGeometry), the way RoomSpriteCanvas sets it up.
// Turns room coordinates (x, y, height) into screen pixels and back.
import { RoomGeometry } from './RoomGeometry';
import { Vector3d } from './Vector3d';
import { Point } from './Point';

export function create(scale: number)
{
    const g = new RoomGeometry(scale, new Vector3d(-135, 30, 0), new Vector3d(11, 11, 5), new Vector3d(-135, 0.5, 0));

    return {
        // screen x, screen y (pixels from the camera's centre) and depth; nil when clipped
        screen: (x: number, y: number, z: number) =>
        {
            const p = g.getScreenPosition(new Vector3d(x, y, z));
            if(!p) return null;
            return [ p.x, p.y, p.z ];
        },
        // where a screen point hits a plane (plane location, left side, right side): position along both sides
        planePosition: (sx: number, sy: number, loc: number[], left: number[], right: number[]) =>
        {
            const p = g.getPlanePosition(new Point(sx, sy), new Vector3d(loc[0], loc[1], loc[2]), new Vector3d(left[0], left[1], left[2]), new Vector3d(right[0], right[1], right[2]));
            if(!p) return null;
            return [ p.x, p.y ];
        },
        scale: () => g.scale,
        setScale: (s: number) => { g.scale = s; },
        directionAxis: () => { const d = g.directionAxis; return [ d.x, d.y, d.z ]; }
    };
}
