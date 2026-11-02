// @ts-nocheck
// From nitro-renderer (https://github.com/billsonnn/nitro-renderer, commit 9e9a62385b61957645d0899518a9e1293e865fe8), src/api/room/IVector3D.ts.
// GPL-3.0. Only the import lines are changed. See ./README.md.
export interface IVector3D
{
    assign(vector: IVector3D): void;
    add(vector: IVector3D): void;
    subtract(vector: IVector3D): void;
    x: number;
    y: number;
    z: number;
    length: number;
}
