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

// PlaneRasterizer.getGeometry(size, 45, 30): the geometry the plane textures are worked out in
const planeGeometries: { [size: number]: RoomGeometry } = {};
function planeGeometry(size: number): RoomGeometry
{
    let g = planeGeometries[size];
    if(!g)
    {
        g = new RoomGeometry(size, new Vector3d(45, 30), new Vector3d(-10, 0, 0));
        planeGeometries[size] = g;
    }
    return g;
}

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

            // the size of the plane's texture and where its pattern starts (RoomPlane.getTexture,
            // FloorPlane.render / WallPlane.render with PlaneRasterizer.getGeometry(size, 45, 30))
            const width = (leftSide.length * scale);
            const height = (rightSide.length * scale);
            const pg = planeGeometry(scale);
            let textureWidth = width;
            let textureHeight = height;
            let textureX = 0;
            let textureY = 0;
            if(p.type === PLANE_FLOOR)
            {
                const _local_10 = pg.getScreenPoint(new Vector3d(0, 0, 0));
                const _local_11 = pg.getScreenPoint(new Vector3d(0, (height / pg.scale), 0));
                const _local_12 = pg.getScreenPoint(new Vector3d((width / pg.scale), 0, 0));
                if(_local_10 && _local_11 && _local_12)
                {
                    textureWidth = Math.round(Math.abs((_local_10.x - _local_12.x)));
                    textureHeight = Math.round(Math.abs((_local_10.x - _local_11.x)));
                    const _local_15 = (_local_10.x - pg.getScreenPoint(new Vector3d(1, 0, 0)).x);
                    textureX = (textureOffsetX * Math.trunc(Math.abs(_local_15)));
                    textureY = (textureOffsetY * Math.trunc(Math.abs(_local_15)));
                }
            }
            else
            {
                const _local_8 = pg.getScreenPoint(new Vector3d(0, 0, 0));
                const _local_9 = pg.getScreenPoint(new Vector3d(0, 0, (height / pg.scale)));
                const _local_10 = pg.getScreenPoint(new Vector3d(0, (width / pg.scale), 0));
                if(_local_8 && _local_9 && _local_10)
                {
                    textureWidth = Math.round(Math.abs((_local_8.x - _local_10.x)));
                    textureHeight = Math.round(Math.abs((_local_8.y - _local_9.y)));
                }
            }
            if(textureWidth < 1) textureWidth = 1;
            if(textureHeight < 1) textureHeight = 1;
            // (RoomPlane keeps its normal at length 1)
            const unit = new Vector3d(normal.x, normal.y, normal.z);
            if(unit.length > 0) unit.multiply(1 / unit.length);
            const n = geometry.getCoordinatePosition(unit);

            out.push({
                textureWidth, textureHeight, textureX, textureY, normal: [ n.x, n.y, n.z ],
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
