/** @noSelfInFile */
// Bobba Hotel room geometry: Nitro's own code path from a room model to the room's planes.
//   parseModel     = FloorHeightMapMessageParser.parseExplicitly
//   door + map     = RoomMessageHandler.onRoomModelEvent
//   planes         = RoomVisualization.initializeRoomPlanes (a second parser fed the map data)
// Translated to Lua with TypeScriptToLua; tests compare the Lua output with this file run in Node.
import { RoomPlaneParser } from './RoomPlaneParser';
import { RoomPlaneData } from './RoomPlaneData';
import { RoomMapData } from './RoomMapData';
import { Vector3d } from './Vector3d';

const TILE_BLOCKED = -110;

// parseInt(char, 36) for one character, written out (TypeScriptToLua's parseInt misreads capitals)
function base36(char: string): number
{
    const code = char.charCodeAt(0);
    if((code >= 48) && (code <= 57)) return code - 48;
    if((code >= 97) && (code <= 122)) return code - 87;
    if((code >= 65) && (code <= 90)) return code - 55;
    return NaN;
}

function parseModel(modelString: string): { width: number, height: number, heightMap: number[][] }
{
    const model = modelString.split('\r');
    const modelRows = model.length;
    let width = 0;
    let iterator = 0;

    while(iterator < modelRows)
    {
        const row = model[iterator];
        if(row.length > width) width = row.length;
        iterator++;
    }

    const heightMap: number[][] = [];
    iterator = 0;

    while(iterator < modelRows)
    {
        const row: number[] = [];
        let subIterator = 0;
        while(subIterator < width)
        {
            row.push(TILE_BLOCKED);
            subIterator++;
        }
        heightMap.push(row);
        iterator++;
    }

    iterator = 0;

    while(iterator < modelRows)
    {
        const row = heightMap[iterator];
        const text = model[iterator];

        if(text.length > 0)
        {
            let subIterator = 0;
            while(subIterator < text.length)
            {
                const char = text.charAt(subIterator);
                let height = TILE_BLOCKED;
                if((char !== 'x') && (char !== 'X')) height = base36(char);
                row[subIterator] = height;
                subIterator++;
            }
        }
        iterator++;
    }

    return { width, height: modelRows, heightMap };
}

function getHeight(map: { width: number, height: number, heightMap: number[][] }, x: number, y: number): number
{
    if((x < 0) || (x >= map.width) || (y < 0) || (y >= map.height)) return -110;
    const row = map.heightMap[y];
    if(row === undefined) return -110;
    const height = row[x];
    if(height === undefined) return -110;
    return height;
}

function vec(v: { x: number, y: number, z: number }): number[]
{
    if(!v) return null;
    return [ v.x, v.y, v.z ];
}

// model: rows separated by "\r" like Habbo/Arcturus; entry: the room's door tile from the server (or null)
export function build(modelString: string, wallHeight: number, scaleIs32: boolean, entryX: number, entryY: number, floorThickness: number, wallThickness: number)
{
    const parser = parseModel(modelString);
    const planeParser = new RoomPlaneParser();
    const width = parser.width;
    const height = parser.height;

    planeParser.reset();
    planeParser.initializeTileMap(width, height);

    const hasEntry = (entryX >= 0);
    let doorX = -1;
    let doorY = -1;
    let doorZ = 0;
    let doorDirection = 0;
    let y = 0;

    while(y < height)
    {
        let x = 0;
        while(x < width)
        {
            const tileHeight = getHeight(parser, x, y);

            if(((((y > 0) && (y < (height - 1))) || ((x > 0) && (x < (width - 1)))) && (!(tileHeight == RoomPlaneParser.TILE_BLOCKED))) && ((!hasEntry) || ((x == entryX) && (y == entryY))))
            {
                if(((getHeight(parser, x, (y - 1)) == RoomPlaneParser.TILE_BLOCKED) && (getHeight(parser, (x - 1), y) == RoomPlaneParser.TILE_BLOCKED)) && (getHeight(parser, x, (y + 1)) == RoomPlaneParser.TILE_BLOCKED))
                {
                    doorX = (x + 0.5);
                    doorY = y;
                    doorZ = tileHeight;
                    doorDirection = 90;
                }

                if(((getHeight(parser, x, (y - 1)) == RoomPlaneParser.TILE_BLOCKED) && (getHeight(parser, (x - 1), y) == RoomPlaneParser.TILE_BLOCKED)) && (getHeight(parser, (x + 1), y) == RoomPlaneParser.TILE_BLOCKED))
                {
                    doorX = x;
                    doorY = (y + 0.5);
                    doorZ = tileHeight;
                    doorDirection = 180;
                }
            }

            planeParser.setTileHeight(x, y, tileHeight);
            x++;
        }
        y++;
    }

    planeParser.setTileHeight(Math.floor(doorX), Math.floor(doorY), doorZ);
    planeParser.initializeFromTileData(wallHeight);
    planeParser.setTileHeight(Math.floor(doorX), Math.floor(doorY), (doorZ + planeParser.wallHeight));

    if(!scaleIs32)
    {
        planeParser.restrictsDragging = true;
        planeParser.restrictsScaling = true;
        planeParser.restrictedScale = 0.5;
    }
    else
    {
        planeParser.restrictsDragging = false;
        planeParser.restrictsScaling = false;
        planeParser.restrictedScale = 1;
    }

    const mapData: RoomMapData = planeParser.getMapData();
    mapData.doors.push({ x: doorX, y: doorY, z: doorZ, dir: doorDirection });

    // what RoomVisualization does with the map data
    const visual = new RoomPlaneParser();
    visual.floorThicknessMultiplier = floorThickness;
    visual.wallThicknessMultiplier = wallThickness;
    visual.initializeFromMapData(mapData);

    const planes = [];
    let index = 0;

    while(index < visual.planeCount)
    {
        const location = visual.getPlaneLocation(index);
        const leftSide = visual.getPlaneLeftSide(index);
        const rightSide = visual.getPlaneRightSide(index);
        const type = visual.getPlaneType(index);
        const normal = Vector3d.crossProduct(leftSide, rightSide);
        const masks = [];
        let m = 0;
        while(m < visual.getPlaneMaskCount(index))
        {
            masks.push([ visual.getPlaneMaskLeftSideLoc(index, m), visual.getPlaneMaskRightSideLoc(index, m), visual.getPlaneMaskLeftSideLength(index, m), visual.getPlaneMaskRightSideLength(index, m) ]);
            m++;
        }
        const secondary = [];
        for(const n of visual.getPlaneSecondaryNormals(index)) secondary.push(vec(n));
        planes.push({ type, loc: vec(location), left: vec(leftSide), right: vec(rightSide), normal: vec(normal), normalDirection: vec(visual.getPlaneNormalDirection(index)), secondary, masks });
        index++;
    }

    const tiles = [];
    for(const row of mapData.tileMap)
    {
        const r = [];
        for(const t of row) r.push(t.height);
        tiles.push(r);
    }

    return {
        width: mapData.width,
        height: mapData.height,
        wallHeight: visual.wallHeight,
        floorHeight: visual.floorHeight,
        fixedWallsHeight: mapData.fixedWallsHeight,
        dimensions: [ mapData.dimensions.minX, mapData.dimensions.maxX, mapData.dimensions.minY, mapData.dimensions.maxY ],
        restrictsScaling: mapData.restrictsScaling,
        restrictedScale: mapData.restrictedScale,
        door: mapData.doors[0],
        tiles,
        planes,
        // after the room is set up, the door tile is raised by the wall height (Nitro does this so
        // furniture can't be dropped there); walking code reads heights from here
        heights: (() => { const out = []; let yy = 0; while(yy < height) { const r = []; let xx = 0; while(xx < width) { r.push(planeParser.getTileHeight(xx, yy)); xx++; } out.push(r); yy++; } return out; })(),
        PLANE_FLOOR: RoomPlaneData.PLANE_FLOOR,
        PLANE_WALL: RoomPlaneData.PLANE_WALL,
        PLANE_LANDSCAPE: RoomPlaneData.PLANE_LANDSCAPE
    };
}
