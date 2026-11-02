// @ts-nocheck
// From nitro-renderer (https://github.com/billsonnn/nitro-renderer, commit 9e9a62385b61957645d0899518a9e1293e865fe8), src/nitro/room/object/RoomFloorHole.ts.
// GPL-3.0. Only the import lines are changed. See ./README.md.
export class RoomFloorHole
{
    private _x: number;
    private _y: number;
    private _width: number;
    private _height: number;

    constructor(x: number, y: number, width: number, height: number)
    {
        this._x = x;
        this._y = y;
        this._width = width;
        this._height = height;
    }

    public get x(): number
    {
        return this._x;
    }

    public get y(): number
    {
        return this._y;
    }

    public get width(): number
    {
        return this._width;
    }

    public get height(): number
    {
        return this._height;
    }
}