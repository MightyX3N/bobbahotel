/** @noSelfInFile */
// Bobba Hotel: what is under the mouse. Nitro finds the front-most room sprite under the mouse and
// RoomLogic.mouseEvent turns the screen point into a position on that plane; this does the same
// with the planes from View.planes (the sprite test is a point-in-quad test on the plane's corners).
import { RoomGeometry } from './RoomGeometry';
import { Vector3d } from './Vector3d';
import { Point } from './Point';

const PLANE_FLOOR = 1;

function side(px: number, py: number, a: number[], b: number[]): number
{
    return ((b[0] - a[0]) * (py - a[1])) - ((b[1] - a[1]) * (px - a[0]));
}

function inside(px: number, py: number, p: { a: number[], b: number[], c: number[], d: number[] }): boolean
{
    const s1 = side(px, py, p.a, p.b);
    const s2 = side(px, py, p.b, p.c);
    const s3 = side(px, py, p.c, p.d);
    const s4 = side(px, py, p.d, p.a);
    const neg = (s1 < 0) || (s2 < 0) || (s3 < 0) || (s4 < 0);
    const pos = (s1 > 0) || (s2 > 0) || (s3 > 0) || (s4 > 0);
    return !(neg && pos);
}

// sx, sy: mouse position in pixels from the room's screen origin (same space as View.planes corners)
export function pick(room: { planes: { type: number, loc: number[], left: number[], right: number[], normalDirection: number[] }[] }, view: { index: number, a: number[], b: number[], c: number[], d: number[] }[], scale: number, sx: number, sy: number)
{
    const geometry = new RoomGeometry(scale, new Vector3d(-135, 30, 0), new Vector3d(11, 11, 5), new Vector3d(-135, 0.5, 0));
    let i = view.length - 1;

    while(i >= 0)
    {
        const vp = view[i];

        if(inside(sx, sy, vp))
        {
            const p = room.planes[vp.index];
            const planeLocation = new Vector3d(p.loc[0], p.loc[1], p.loc[2]);
            const planeLeftSide = new Vector3d(p.left[0], p.left[1], p.left[2]);
            const planeRightSide = new Vector3d(p.right[0], p.right[1], p.right[2]);
            const leftSideLength = planeLeftSide.length;
            const rightSideLength = planeRightSide.length;

            if((leftSideLength === 0) || (rightSideLength === 0)) return null;

            const planePosition = geometry.getPlanePosition(new Point(sx, sy), planeLocation, planeLeftSide, planeRightSide);

            if(planePosition === null) return null;

            const _local_18 = Vector3d.product(planeLeftSide, (planePosition.x / leftSideLength));
            _local_18.add(Vector3d.product(planeRightSide, (planePosition.y / rightSideLength)));
            _local_18.add(planeLocation);

            if(!((planePosition.x >= 0) && (planePosition.x < leftSideLength) && (planePosition.y >= 0) && (planePosition.y < rightSideLength))) return null;

            let direction = 90;
            if(p.normalDirection !== null)
            {
                direction = (p.normalDirection[0] + 90);
                if(direction > 360) direction -= 360;
            }

            return {
                plane: vp.index, type: p.type, floor: (p.type === PLANE_FLOOR),
                x: _local_18.x, y: _local_18.y, z: _local_18.z,
                // RoomObjectTileMouseEvent.tileXAsInt / tileYAsInt / tileZAsInt
                tileX: Math.trunc(_local_18.x + 0.499), tileY: Math.trunc(_local_18.y + 0.499), tileZ: Math.trunc(_local_18.z + 0.499),
                // for walls: where on the wall, and which way it faces (RoomObjectWallMouseEvent)
                wallX: ((planeLeftSide.length * planePosition.x) / leftSideLength), wallY: ((planeRightSide.length * planePosition.y) / rightSideLength), direction
            };
        }
        i--;
    }

    return null;
}
