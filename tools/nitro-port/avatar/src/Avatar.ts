/** @noSelfInFile */
// [bobba] Entry point of the avatar port: Nitro's avatar code (AvatarStructure, AvatarImage and
// everything under them, copied from Nitro) driven the way Nitro's AvatarRenderManager and
// AvatarVisualization drive it. Instead of a picture, frame() gives the list of pictures Nitro would
// have put together: which asset, where, mirrored or not, and its colour.
//
//   const r = createRenderer(data, assets)        data: the XML trees (see Convert.ts)
//   const avatar = r.createImage('hd-180-1.ch-210-66', 'h')
//   setState(avatar, { direction: 2, posture: 'mv', ... })
//   const f = frame(avatar)                       { width, height, sprites: [...], canvasOffsets }
//   next(avatar)                                  one animation frame on

import { AvatarAction, AvatarSetType } from './api';
import { AssetAliasCollection } from './nitro/avatar/alias';
import { AvatarFigureContainer } from './nitro/avatar/AvatarFigureContainer';
import { AvatarImage } from './nitro/avatar/AvatarImage';
import { AvatarStructure } from './nitro/avatar/AvatarStructure';
import { Container, Rectangle, Sprite, Texture } from './pixi';
import * as Convert from './bobba/Convert';

// What the game knows about a picture: Habbo's offset from the manifest and the picture's size
export interface AssetInfo
{
    offsetX: number;
    offsetY: number;
    width: number;
    height: number;
}

export interface AssetSource
{
    // a picture by its Habbo name ("h_std_bd_1_2_0"), or null when it isn't loaded
    get: (this: void, name: string) => AssetInfo;
}

// Nitro's GraphicAsset, as much as the avatar code uses (its x/y are the manifest offset negated)
class GraphicAsset
{
    public name: string;
    public texture: Texture;
    public x: number;
    public y: number;
    public rectangle: Rectangle;
    public width: number;
    public height: number;

    constructor(name: string, info: AssetInfo)
    {
        this.name = name;
        this.texture = new Texture(name, info.width, info.height);
        this.x = -info.offsetX;
        this.y = -info.offsetY;
        this.width = info.width;
        this.height = info.height;
        this.rectangle = new Rectangle(0, 0, info.width, info.height);
    }
}

class AssetManager
{
    public collections: Map<string, any> = new Map();
    private _source: AssetSource;
    private _made: Map<string, GraphicAsset> = new Map();

    constructor(source: AssetSource)
    {
        this._source = source;
    }

    public getAsset(name: string): GraphicAsset
    {
        const made = this._made.get(name);
        if(made !== undefined) return made;
        const info = this._source.get(name);
        if(info === undefined || info === null) return null;
        const asset = new GraphicAsset(name, info);
        this._made.set(name, asset);
        return asset;
    }

    public getCollection(_name: string): any
    {
        return null;
    }
}

// effects come later: none is ever ready
const NO_EFFECTS = {
    isAvatarEffectReady: (_id: number): boolean => false,
    downloadAvatarEffect: (_id: number, _listener: any): void => {}
};

export interface AvatarData
{
    geometry: Convert.XmlNode;
    partSets: Convert.XmlNode;
    animation: Convert.XmlNode;
    actions: Convert.XmlNode;
    offsets: { [state: string]: Convert.XmlNode };
    figureData: Convert.XmlNode[]; // HabboAvatarFigure first, then the figuredata from gamedata
}

export class Renderer
{
    public structure: AvatarStructure;
    public assets: AssetManager;
    public aliases: AssetAliasCollection;

    constructor(data: AvatarData, source: AssetSource)
    {
        this.structure = new AvatarStructure(null);
        this.assets = new AssetManager(source);
        // as AvatarRenderManager: geometry, part sets, actions, animations, figure data
        this.structure.initGeometry(Convert.jsArrays(Convert.geometry(data.geometry)));
        this.structure.initPartSets(Convert.jsArrays(Convert.partSets(data.partSets)));
        this.structure.initActions(this.assets, Convert.jsArrays(Convert.actions(data.actions, data.offsets)));
        this.structure.initAnimation(Convert.jsArrays(Convert.animations(data.animation)));
        let first = true;
        for(const doc of data.figureData)
        {
            const fd = Convert.jsArrays(Convert.figureData(doc));
            if(first) this.structure.initFigureData(fd);
            else this.structure.figureData.appendJSON(fd);
            first = false;
        }
        this.structure.init();
        this.aliases = new AssetAliasCollection(null, this.assets);
        this.aliases.init();
    }

    // more figure data (as AvatarStructureDownload appends the downloaded figuredata): can be given
    // a piece at a time, e.g. one settype per call, so the game needn't do it all in one frame
    public appendFigureData(doc: Convert.XmlNode): void
    {
        this.structure.figureData.appendJSON(Convert.jsArrays(Convert.figureData(doc)));
    }

    public createImage(figure: string, scale: string): AvatarImage
    {
        return new AvatarImage(this.structure, this.aliases, new AvatarFigureContainer(figure), scale, NO_EFFECTS, null);
    }

    // the libraries (figuremap names come from these) a figure needs: [ [type, id], ... ]
    public figureParts(figure: string): any[]
    {
        const out: any[] = [];
        const container = new AvatarFigureContainer(figure);
        for(const type of container.getPartTypeIds())
        {
            const setType = this.structure.figureData.getSetType(type);
            if(!setType) continue;
            const partSet = setType.getPartSet(container.getPartSetId(type));
            if(!partSet) continue;
            for(const part of partSet.parts) out.push([ part.type, part.id ]);
        }
        return out;
    }
}

export function createRenderer(data: AvatarData, source: AssetSource): Renderer
{
    return new Renderer(data, source);
}

// What the room tells an avatar (AvatarVisualization's model values)
export interface AvatarState
{
    direction: number;      // 0..7
    headDirection: number;  // 0..7
    posture: string;        // 'std', 'mv', 'sit', 'lay', ...
    postureParameter: string;
    gesture: number;
    dance: number;
    sign: number;           // -1 = none
    carryObject: number;
    useObject: number;
    talk: boolean;
    sleep: boolean;
    blink: boolean;
    expression: number;
    effect: number;
}

// AvatarVisualization.processActionsForAvatar and its direction handling
export function setState(avatar: AvatarImage, s: AvatarState): void
{
    avatar.setDirectionAngle(AvatarSetType.FULL, s.direction * 45);
    avatar.setDirectionAngle(AvatarSetType.HEAD, s.headDirection * 45);
    avatar.initActionAppends();
    avatar.appendAction(AvatarAction.POSTURE, s.posture, s.postureParameter);
    if(s.gesture > 0) avatar.appendAction(AvatarAction.GESTURE, AvatarAction.getGesture(s.gesture));
    if(s.dance > 0) avatar.appendAction(AvatarAction.DANCE, s.dance);
    if(s.sign > -1) avatar.appendAction(AvatarAction.SIGN, s.sign);
    if(s.carryObject > 0) avatar.appendAction(AvatarAction.CARRY_OBJECT, s.carryObject);
    if(s.useObject > 0) avatar.appendAction(AvatarAction.USE_OBJECT, s.useObject);
    if(s.talk) avatar.appendAction(AvatarAction.TALK);
    if(s.sleep || s.blink) avatar.appendAction(AvatarAction.SLEEP);
    if(s.expression > 0)
    {
        const expression = AvatarAction.getExpression(s.expression);
        if(expression !== '')
        {
            if(expression === AvatarAction.DANCE) avatar.appendAction(AvatarAction.DANCE, 2);
            else avatar.appendAction(expression);
        }
    }
    if(s.effect > 0) avatar.appendAction(AvatarAction.EFFECT, s.effect);
    avatar.endActionAppends();
}

export function next(avatar: AvatarImage): void
{
    avatar.updateAnimationByFrames(1);
}

export function isAnimating(avatar: AvatarImage): boolean
{
    return avatar.isAnimating();
}

// One picture to draw: the asset, its top-left corner in the avatar's canvas, mirrored or not,
// and the colour to multiply it with (0xRRGGBB)
export interface DrawSprite
{
    name: string;
    x: number;
    y: number;
    width: number;
    height: number;
    flipH: boolean;
    color: number;
}

// The pictures Nitro's getImage(FULL) puts on its canvas, back to front. head = true: only the
// head (getImage(HEAD), as the chat bubbles show it)
export function frame(avatar: AvatarImage, head: boolean = false): any
{
    const texture: any = avatar.getImage(head ? AvatarSetType.HEAD : AvatarSetType.FULL, false);
    const sprites: DrawSprite[] = [];
    const out: any = { width: 0, height: 0, sprites: sprites, canvasOffsets: avatar.getCanvasOffsets() };
    if(texture === null || texture === undefined) return out;
    out.width = texture.width;
    out.height = texture.height;
    const walk = (o: any, a: number, tx: number, ty: number): void =>
    {
        if(o instanceof Sprite)
        {
            const s: Sprite = o;
            if(s.texture.name === null || s.texture.name === undefined) return; // the empty sizing sprite
            const flipH = a < 0;
            sprites.push({ name: s.texture.name, x: flipH ? (tx - s.texture.width) : tx, y: ty, width: s.texture.width, height: s.texture.height, flipH: flipH, color: s.tint });
        }
        else if(o instanceof Container)
        {
            for(const child of o.children)
            {
                const m = child.localMatrix();
                walk(child, a * m.a, tx + a * m.tx, ty + m.ty);
            }
        }
    };
    if(texture.container) walk(texture.container, 1, 0, 0);
    return out;
}

// The colour of a part of the figure, e.g. 'ch' (the shirt: Habbo's chat bubbles have it), 0xRRGGBB
export function partColor(avatar: AvatarImage, partType: string): number
{
    const color: any = avatar.getPartColor(partType);
    if(color === null || color === undefined) return 0xFFFFFF;
    return color.rgb;
}
