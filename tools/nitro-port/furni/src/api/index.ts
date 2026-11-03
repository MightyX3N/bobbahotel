// [bobba] The parts of Nitro's api the furniture visualizations use: the real enums, and the
// interfaces as the classes behind them or as 'any' (JSON data).
export * from './AlphaTolerance';
export * from './RoomObjectVariable';
export * from './RoomObjectVisualizationType';
export * from './RoomObjectSpriteType';
export * from './RoomObjectSpriteData';
export type IRoomObjectSprite = import('../room/object/visualization/RoomObjectSprite').RoomObjectSprite;
export type IRoomObjectSpriteVisualization = import('../room/object/visualization/RoomObjectSpriteVisualization').RoomObjectSpriteVisualization;
export type IObjectVisualizationData = import('../nitro/room/object/visualization/furniture/FurnitureVisualizationData').FurnitureVisualizationData;
export interface IGraphicAsset
{
    name: string;
    source: string;
    texture: any;
    x: number;
    y: number;
    width: number;
    height: number;
    offsetX: number;
    offsetY: number;
    flipH: boolean;
    flipV: boolean;
    rectangle: any;
}
export interface IGraphicAssetCollection
{
    getAsset(name: string): IGraphicAsset;
    addReference?(): void;
    removeReference?(): void;
}
export interface IRoomGeometry
{
    scale: number;
    direction: { x: number, y: number, z: number };
}
export interface IRoomObjectModel
{
    updateCounter: number;
    getValue<T>(key: string): T;
}
export interface IRoomObjectController
{
    instanceId: number;
    updateCounter: number;
    model: IRoomObjectModel;
    getDirection(): { x: number, y: number, z: number };
    getState(index: number): number;
}
export type IAssetData = any;
export type IAssetVisualizationData = any;
export type IAssetColor = any;
export type IAssetVisualizationDirection = any;
export type IAssetVisualizationLayer = any;
export type IAssetVisualAnimation = any;
export type IAssetVisualAnimationLayer = any;
export type IAssetVisualAnimationSequenceFrame = any;
