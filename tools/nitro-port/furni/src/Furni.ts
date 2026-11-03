/** @noSelfInFile */
// [bobba] Entry point of the furniture port: Nitro's FurnitureVisualization and
// FurnitureAnimatedVisualization (copied from Nitro) driven the way Nitro's room engine drives them.
// Instead of drawing, sprites() gives the pictures Nitro would put on screen for the furni: which
// asset, where (relative to the furni's spot on screen), mirrored or not, colour, alpha, blend and
// relative depth.
//
//   const type = loadType({ index, visualization, assets, logic }, source)   the furni's XML trees
//   const furni = create(type)
//   setState(furni, { direction: 90, state: 0, color: 0 })     direction in degrees (as Habbo's 0..7 * 45)
//   update(furni, timeInMs)                                    as often as the game draws
//   const list = sprites(furni)

import { RoomObjectVariable } from './api';
import { FurnitureAnimatedVisualization } from './nitro/room/object/visualization/furniture/FurnitureAnimatedVisualization';
import { FurnitureAnimatedVisualizationData } from './nitro/room/object/visualization/furniture/FurnitureAnimatedVisualizationData';
import { FurnitureVisualization } from './nitro/room/object/visualization/furniture/FurnitureVisualization';
import { FurnitureVisualizationData } from './nitro/room/object/visualization/furniture/FurnitureVisualizationData';
import { Rectangle, Texture } from './pixi';
import * as Convert from './bobba/Convert';
import { truthy } from './bobba/Truthy';

export { find, index, logic } from './bobba/Convert';

// What the game knows about a picture: its size
export interface PictureInfo
{
    width: number;
    height: number;
}

export interface PictureSource
{
    // a picture by its Habbo name ("throne_64_a_2_0"), or null when the furni has no such picture
    get: (this: void, name: string) => PictureInfo;
}

// Nitro's GraphicAsset, as much as the furniture code uses
class GraphicAsset
{
    public name: string;
    public source: string;
    public texture: Texture;
    public x: number;
    public y: number;
    public width: number;
    public height: number;
    public flipH: boolean;
    public flipV: boolean;
    public usesPalette: boolean;
    public rectangle: Rectangle;

    constructor(name: string, source: string, texture: Texture, x: number, y: number, flipH: boolean, flipV: boolean, usesPalette: boolean)
    {
        this.name = name;
        this.source = source;
        this.texture = texture;
        this.x = x;
        this.y = y;
        this.width = texture.width;
        this.height = texture.height;
        this.flipH = flipH;
        this.flipV = flipV;
        this.usesPalette = usesPalette;
        this.rectangle = new Rectangle(0, 0, this.width, this.height);
    }

    public get offsetX(): number
    {
        if(!this.flipH) return this.x;
        return -this.x;
    }

    public get offsetY(): number
    {
        if(!this.flipV) return this.y;
        return -this.y;
    }
}

// Nitro's GraphicAssetCollection.defineAssets (no palettes: those are for pets)
class GraphicAssetCollection
{
    private _assets: Map<string, GraphicAsset> = new Map();

    constructor(data: Convert.Assets, source: PictureSource)
    {
        const textures: Map<string, Texture> = new Map();
        const texture = (name: string): Texture =>
        {
            const made = textures.get(name);
            if(made !== undefined) return made;
            const info = source.get(name);
            if(info === undefined || info === null) return null;
            const t = new Texture(name, info.width, info.height);
            textures.set(name, t);
            return t;
        };
        for(const name of data.names)
        {
            const asset = data.assets[name];
            // const x = -asset.x || 0 (a missing or NaN number is 0)
            const ax: number = (asset.x === undefined) ? NaN : -asset.x;
            const ay: number = (asset.y === undefined) ? NaN : -asset.y;
            const x = truthy(ax) ? ax : 0;
            const y = truthy(ay) ? ay : 0;
            let source: string = (asset.source === undefined) ? '' : (asset.source as string);
            const flipH = (asset.flipH === true) && (source.length > 0);
            const usesPalette = asset.usesPalette === true;
            if(source.length === 0) source = name;
            const t = texture(source);
            if(t === null) continue;
            if(this._assets.get(name) !== undefined) continue;
            this._assets.set(name, new GraphicAsset(name, source, t, x, y, flipH, false, usesPalette));
        }
    }

    public addReference(): void
    {
    }

    public removeReference(): void
    {
    }

    public getAsset(name: string): GraphicAsset
    {
        if(!truthy(name)) return null;
        const existing = this._assets.get(name);
        if(existing === undefined) return null;
        return existing;
    }
}

// The room object and its model, as much as the visualizations read
class FurniModel
{
    public updateCounter: number = 0;
    private _values: Map<string, any> = new Map();

    public getValue<T>(key: string): T
    {
        return this._values.get(key);
    }

    public setValue(key: string, value: any): void
    {
        if(this._values.get(key) === value) return;
        this._values.set(key, value);
        this.updateCounter++;
    }
}

let instances = 0;

class FurniObject
{
    public instanceId: number;
    public updateCounter: number = 0;
    public model: FurniModel = new FurniModel();
    private _direction = { x: 0, y: 0, z: 0 };
    private _state: number = 0;

    constructor()
    {
        this.instanceId = instances++;
    }

    public getDirection(): { x: number, y: number, z: number }
    {
        return this._direction;
    }

    public getState(_index: number): number
    {
        return this._state;
    }

    public setDirection(degrees: number): void
    {
        if(this._direction.x === degrees) return;
        this._direction = { x: degrees, y: 0, z: 0 };
        this.updateCounter++;
    }

    public setState(state: number): void
    {
        if(this._state === state) return;
        this._state = state;
        this.updateCounter++;
    }
}

// A kind of furni, loaded once (Nitro's RoomContentLoader + visualization data)
export class FurniType
{
    public name: string;
    public visualizationType: string;
    public logicType: string;
    public logic: any;
    public data: FurnitureVisualizationData;
    public assets: GraphicAssetCollection;
    public animated: boolean;
}

export interface FurniXml
{
    index: Convert.XmlNode;
    visualization: Convert.XmlNode;
    assets: Convert.XmlNode;
    logic: Convert.XmlNode;
}

// Nitro's RoomObjectVisualizationFactory: furniture_static is the plain visualization; the other
// furniture visualizations are all animated ones
export function loadType(xml: FurniXml, source: PictureSource): FurniType
{
    const type = new FurniType();
    const idx = Convert.index(xml.index);
    type.name = idx.name;
    type.visualizationType = (idx.visualizationType === undefined) ? 'furniture_static' : idx.visualizationType;
    type.logicType = idx.logicType;
    type.logic = Convert.jsArrays(Convert.logic(xml.logic));
    type.animated = type.visualizationType !== 'furniture_static';
    const asset: any = Convert.jsArrays({ name: idx.name, visualizations: Convert.visualizations(xml.visualization) });
    type.data = type.animated ? new FurnitureAnimatedVisualizationData() : new FurnitureVisualizationData();
    if(!type.data.initialize(asset)) return null;
    type.assets = new GraphicAssetCollection(Convert.assets(xml.assets), source);
    return type;
}

export class Furni
{
    public type: FurniType;
    public object: FurniObject;
    public visualization: FurnitureVisualization;
    public geometry: any;
}

// Nitro's room camera: looking from direction -135 (so a furni's direction is its picture's direction)
export function create(type: FurniType, scale: number = 64): Furni
{
    const f = new Furni();
    f.type = type;
    f.object = new FurniObject();
    f.object.model.setValue(RoomObjectVariable.FURNITURE_COLOR, 0);
    f.object.model.setValue(RoomObjectVariable.FURNITURE_ALPHA_MULTIPLIER, 1);
    f.object.model.setValue(RoomObjectVariable.FURNITURE_STATE_UPDATE_TIME, 0);
    f.object.model.setValue(RoomObjectVariable.FURNITURE_AUTOMATIC_STATE_INDEX, NaN);
    f.object.model.setValue(RoomObjectVariable.FURNITURE_LIFT_AMOUNT, 0);
    f.object.model.setValue(RoomObjectVariable.FURNITURE_AD_URL, '');
    f.visualization = type.animated ? new FurnitureAnimatedVisualization() : new FurnitureVisualization();
    f.visualization.initialize(type.data);
    f.visualization.asset = type.assets as any;
    f.visualization.object = f.object as any;
    f.geometry = { scale: scale, direction: { x: -135, y: 30, z: 0 } };
    return f;
}

export interface FurniState
{
    direction: number;   // degrees: 0, 45, ... 315
    state: number;
    color: number;       // the furni's colour id (from furnidata's colour index), 0 = default
    time: number;        // when the state changed (ms), so a state's animation starts from its beginning
}

export function setState(f: Furni, s: FurniState): void
{
    f.object.setDirection(s.direction);
    if(f.object.getState(0) !== s.state)
    {
        f.object.model.setValue(RoomObjectVariable.FURNITURE_STATE_UPDATE_TIME, s.time);
        f.object.setState(s.state);
    }
    f.object.model.setValue(RoomObjectVariable.FURNITURE_COLOR, s.color);
}

// Nitro's RoomSpriteCanvas: every visualization is updated each frame with the time in ms
export function update(f: Furni, time: number): void
{
    f.visualization.update(f.geometry, time, true, false);
}

export interface DrawSprite
{
    name: string;        // the asset (what the layer shows)
    source: string;      // the picture it is drawn from
    x: number;           // the picture's top-left corner, from the furni's spot on screen
    y: number;
    width: number;
    height: number;
    flipH: boolean;
    alpha: number;       // 0..255
    color: number;       // 0xRRGGBB
    blend: number;       // PixiJS blend mode: 0 normal, 1 add, ...
    relativeDepth: number;
    tag: string;
    ignoreMouse: boolean;
}

// The furni's pictures, in layer order (the room sorts them by depth)
export function sprites(f: Furni): DrawSprite[]
{
    const out: DrawSprite[] = [];
    const total = f.visualization.totalSprites;
    for(let i = 0; i < total; i++)
    {
        const s: any = f.visualization.getSprite(i);
        if(s === null || !s.visible || s.texture === null || s.texture === undefined || s.alpha <= 0) continue;
        const w = s.texture.width;
        const h = s.texture.height;
        out.push({
            name: s.name, source: s.libraryAssetName,
            x: s.flipH ? (s.offsetX - w) : s.offsetX, y: s.offsetY, width: w, height: h, flipH: s.flipH,
            alpha: s.alpha, color: s.color, blend: s.blendMode, relativeDepth: s.relativeDepth, tag: s.tag,
            ignoreMouse: s.alphaTolerance === 256
        });
    }
    return out;
}
