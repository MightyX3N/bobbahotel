/** @noSelfInFile */
// Bobba Hotel: the parts of Nitro's RoomVisualization.initializeRoomPlanes / updatePlanes and
// RoomPlane.update / updateCorners that decide where each plane is on screen, whether it can be
// seen, how it is shaded and how deep it is (sprites are drawn deepest first, like RoomSpriteCanvas).
// Textures are drawn by the game; this only gives the numbers.
import { RoomGeometry } from './RoomGeometry';
import { Vector3d } from './Vector3d';

const FLOOR_COLOR = 0xFFFFFF;
const FLOOR_COLOR_LEFT = 0xDDDDDD;
const FLOOR_COLOR_RIGHT = 0xBBBBBB;
const WALL_COLOR_TOP = 0xFFFFFF;
const WALL_COLOR_SIDE = 0xCCCCCC;
const WALL_COLOR_BOTTOM = 0x999999;
const WALL_COLOR_BORDER = 0x999999;
const LANDSCAPE_COLOR_TOP = 0xFFFFFF;
const LANDSCAPE_COLOR_SIDE = 0xCCCCCC;
const LANDSCAPE_COLOR_BOTTOM = 0x999999;
const ROOM_DEPTH_OFFSET = 1000;
const PLANE_FLOOR = 1;
const PLANE_WALL = 2;
const PLANE_LANDSCAPE = 3;

function v(a: number[]): Vector3d { return new Vector3d(a[0], a[1], a[2]); }

export function planes(room: { planes: { type: number, loc: number[], left: number[], right: number[], secondary: number[][] }[] }, scale: number)
{
    const geometry = new RoomGeometry(scale, new Vector3d(-135, 30, 0), new Vector3d(11, 11, 5), new Vector3d(-135, 0.5, 0));
    const origin = new Vector3d(0, 0, 0);
    const out = [];
    let index = 0;

    for(const p of room.planes)
    {
        const location = v(p.loc);
        const leftSide = v(p.left);
        const rightSide = v(p.right);
        const normal = Vector3d.crossProduct(leftSide, rightSide);

        // colour (initializeRoomPlanes)
        let color = 0;
        let texture = true;
        let textureOffsetX = 0;
        let textureOffsetY = 0;

        if(p.type === PLANE_FLOOR)
        {
            const _local_15 = ((location.x + leftSide.x) + 0.5);
            const _local_16 = ((location.y + rightSide.y) + 0.5);
            textureOffsetX = -(Math.trunc(_local_15) - _local_15);
            textureOffsetY = -(Math.trunc(_local_16) - _local_16);
            if(normal.z !== 0) color = FLOOR_COLOR;
            else color = ((normal.x !== 0) ? FLOOR_COLOR_RIGHT : FLOOR_COLOR_LEFT);
        }
        else if(p.type === PLANE_WALL)
        {
            if((leftSide.length < 1) || (rightSide.length < 1)) texture = false;
            if((normal.x === 0) && (normal.y === 0)) color = WALL_COLOR_BORDER;
            else if(normal.y > 0) color = WALL_COLOR_TOP;
            else if(normal.y === 0) color = WALL_COLOR_SIDE;
            else color = WALL_COLOR_BOTTOM;
        }
        else if(p.type === PLANE_LANDSCAPE)
        {
            if(normal.y > 0) color = LANDSCAPE_COLOR_TOP;
            else if(normal.y === 0) color = LANDSCAPE_COLOR_SIDE;
            else color = LANDSCAPE_COLOR_BOTTOM;
        }

        // can the camera see it (RoomPlane.update)
        let visible = true;
        if(Vector3d.cosAngle(geometry.directionAxis, normal) > -0.001) visible = false;
        for(const n of p.secondary)
        {
            if(Vector3d.cosAngle(geometry.directionAxis, v(n)) > -0.001) visible = false;
        }

        if(visible)
        {
            // corners (updateCorners)
            const a = geometry.getScreenPosition(location);
            const b = geometry.getScreenPosition(Vector3d.sum(location, rightSide));
            const c = geometry.getScreenPosition(Vector3d.sum(Vector3d.sum(location, leftSide), rightSide));
            const d = geometry.getScreenPosition(Vector3d.sum(location, leftSide));
            const originZ = geometry.getScreenPosition(origin).z;

            let relativeDepth = (Math.max(a.z, b.z, c.z, d.z) - originZ);
            if(p.type === PLANE_FLOOR) relativeDepth = (relativeDepth - ((location.z + Math.min(0, leftSide.z, rightSide.z)) * 8));
            if(p.type === PLANE_LANDSCAPE) relativeDepth = (relativeDepth + 0.02);

            // depth (updatePlanes)
            let depth = ((relativeDepth + (ROOM_DEPTH_OFFSET + 0.1)) + (index / 1000));
            if(p.type !== PLANE_FLOOR)
            {
                depth = ((relativeDepth + (ROOM_DEPTH_OFFSET + 0.5)) + (index / 1000));
                if((leftSide.length < 1) || (rightSide.length < 1)) depth = (depth + (ROOM_DEPTH_OFFSET * 0.5));
            }

            out.push({
                index, type: p.type, color, texture, textureOffsetX, textureOffsetY, depth,
                a: [ Math.round(a.x), Math.round(a.y) ], b: [ Math.round(b.x), Math.round(b.y) ],
                c: [ Math.round(c.x), Math.round(c.y) ], d: [ Math.round(d.x), Math.round(d.y) ]
            });
        }
        index++;
    }

    out.sort((x, y) => (y.depth - x.depth));

    return out;
}
