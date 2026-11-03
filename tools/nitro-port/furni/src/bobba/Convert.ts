/** @noSelfInFile */
// [bobba] Habbo's furni XML (from the furni's SWF: index, visualization, assets, logic) into the JSON
// shapes Nitro's furniture code reads, the way nitro-converter's IndexMapper, VisualizationMapper,
// AssetMapper and LogicMapper make them. The XML comes as the tree bobba_habbo's xml.lua makes:
// { name, attrs, children, text }.
//
// One difference from nitro-converter, on purpose: a layer's z is read as a decimal (Habbo writes
// some as "-0.5"; the converter's parseInt drops the fraction, Habbo's own client doesn't).
//
// In Lua, the arrays in the result answer .length and [0] the way JavaScript arrays do (jsArrays).

import { parseHex } from './Hex';

export interface XmlNode
{
    name: string;
    attrs: { [key: string]: string };
    children: XmlNode[];
    text?: string;
}

function push(list: any[], value: any): void
{
    list.push(value);
}

function kids(node: XmlNode, name: string): XmlNode[]
{
    const out: XmlNode[] = [];
    if(node === undefined || node === null) return out;
    for(const c of node.children) if(c.name === name) out.push(c);
    return out;
}

// the first element with that name, at any depth (the node itself counts)
export function find(node: XmlNode, name: string): XmlNode
{
    if(node === undefined || node === null) return null;
    if(node.name === name) return node;
    for(const c of node.children)
    {
        const f = find(c, name);
        if(f !== null) return f;
    }
    return null;
}

function has(node: XmlNode, key: string): boolean
{
    return node.attrs[key] !== undefined;
}

// parseInt as JavaScript does it (NaN stays NaN: the converter writes what parseInt gives)
function int(node: XmlNode, key: string): number
{
    return parseInt(node.attrs[key]);
}

function float(node: XmlNode, key: string): number
{
    return parseFloat(node.attrs[key]);
}

// children of every <parent> child, as nitro-converter's xml2js arrays see them
function grandKids(node: XmlNode, parent: string, name: string): XmlNode[]
{
    const out: XmlNode[] = [];
    for(const p of kids(node, parent)) for(const c of kids(p, name)) out.push(c);
    return out;
}

// --- index.xml ----------------------------------------------------------------------------------------
export function index(xml: XmlNode): any
{
    const out: any = {};
    const o = find(xml, 'object');
    if(o === null) return out;
    if(has(o, 'type')) out.name = o.attrs.type;
    if(has(o, 'logic')) out.logicType = o.attrs.logic;
    if(has(o, 'visualization')) out.visualizationType = o.attrs.visualization;
    return out;
}

// --- visualization.xml -------------------------------------------------------------------------------
function layer(l: XmlNode): any
{
    const out: any = {};
    if(has(l, 'x')) out.x = int(l, 'x');
    if(has(l, 'y')) out.y = int(l, 'y');
    if(has(l, 'z')) out.z = float(l, 'z');
    if(has(l, 'alpha')) out.alpha = int(l, 'alpha');
    if(has(l, 'ink')) out.ink = l.attrs.ink;
    if(has(l, 'tag')) out.tag = l.attrs.tag;
    if(has(l, 'ignoreMouse')) out.ignoreMouse = (l.attrs.ignoreMouse === '1');
    return out;
}

function layers(list: XmlNode[]): any
{
    const out: any = {};
    for(const l of list) out[(int(l, 'id')).toString()] = layer(l);
    return out;
}

function nextAnimationId(id: number, output: any): string
{
    let key = (id).toString();
    if(output[key] === undefined) return key;
    let i = 1;
    while(i < 6)
    {
        key += '_' + i;
        if(output[key] === undefined) return key;
        i++;
    }
    return null;
}

function animations(list: XmlNode[]): any
{
    const out: any = {};
    for(const a of list)
    {
        const animation: any = {};
        if(has(a, 'transitionTo')) animation.transitionTo = int(a, 'transitionTo');
        if(has(a, 'transitionFrom')) animation.transitionFrom = int(a, 'transitionFrom');
        if(has(a, 'immediateChangeFrom')) animation.immediateChangeFrom = a.attrs.immediateChangeFrom;
        if(has(a, 'randomStart')) animation.randomStart = (a.attrs.randomStart === '1');
        const animationLayers = kids(a, 'animationLayer');
        if(animationLayers.length > 0)
        {
            animation.layers = {};
            for(const al of animationLayers)
            {
                const animationLayer: any = {};
                if(has(al, 'frameRepeat')) animationLayer.frameRepeat = int(al, 'frameRepeat');
                if(has(al, 'loopCount')) animationLayer.loopCount = int(al, 'loopCount');
                if(has(al, 'random')) animationLayer.random = int(al, 'random');
                const sequences = kids(al, 'frameSequence');
                if(sequences.length > 0)
                {
                    animationLayer.frameSequences = {};
                    let si = 0;
                    for(const fs of sequences)
                    {
                        const sequence: any = {};
                        if(has(fs, 'loopCount')) sequence.loopCount = int(fs, 'loopCount');
                        if(has(fs, 'random')) sequence.random = int(fs, 'random');
                        const frames = kids(fs, 'frame');
                        if(frames.length > 0)
                        {
                            sequence.frames = {};
                            let fi = 0;
                            for(const f of frames)
                            {
                                const frame: any = {};
                                if(!has(f, 'id') || f.attrs.id === 'NaN') frame.id = 0;
                                else frame.id = int(f, 'id');
                                if(has(f, 'x')) frame.x = int(f, 'x');
                                if(has(f, 'y')) frame.y = int(f, 'y');
                                if(has(f, 'randomX')) frame.randomX = int(f, 'randomX');
                                if(has(f, 'randomY')) frame.randomY = int(f, 'randomY');
                                const offsets = grandKids(f, 'offsets', 'offset');
                                if(offsets.length > 0)
                                {
                                    frame.offsets = {};
                                    let oi = 0;
                                    for(const o of offsets)
                                    {
                                        const offset: any = {};
                                        if(has(o, 'direction')) offset.direction = int(o, 'direction');
                                        if(has(o, 'x')) offset.x = int(o, 'x');
                                        if(has(o, 'y')) offset.y = int(o, 'y');
                                        frame.offsets[(oi).toString()] = offset;
                                        oi++;
                                    }
                                }
                                sequence.frames[(fi).toString()] = frame;
                                fi++;
                            }
                        }
                        animationLayer.frameSequences[(si).toString()] = sequence;
                        si++;
                    }
                }
                animation.layers[(int(al, 'id')).toString()] = animationLayer;
            }
        }
        const key = nextAnimationId(int(a, 'id'), out);
        if(key === null) continue;
        out[key] = animation;
    }
    return out;
}

export function visualizations(xml: XmlNode): any[]
{
    const out: any[] = [];
    const root = find(xml, 'visualizationData');
    if(root === null) return out;
    for(const v of grandKids(root, 'graphics', 'visualization'))
    {
        if(has(v, 'size') && int(v, 'size') === 32) continue;
        const data: any = {};
        if(has(v, 'angle')) data.angle = int(v, 'angle');
        if(has(v, 'layerCount')) data.layerCount = int(v, 'layerCount');
        if(has(v, 'size')) data.size = int(v, 'size');
        const ls = grandKids(v, 'layers', 'layer');
        if(ls.length > 0) data.layers = layers(ls);
        const ds = grandKids(v, 'directions', 'direction');
        if(ds.length > 0)
        {
            data.directions = {};
            for(const d of ds)
            {
                const direction: any = {};
                const dl = kids(d, 'layer');
                if(dl.length > 0) direction.layers = layers(dl);
                data.directions[(int(d, 'id')).toString()] = direction;
            }
        }
        const cs = grandKids(v, 'colors', 'color');
        if(cs.length > 0)
        {
            data.colors = {};
            for(const c of cs)
            {
                const color: any = {};
                const cl = kids(c, 'colorLayer');
                if(cl.length > 0)
                {
                    color.layers = {};
                    for(const l of cl)
                    {
                        const colorLayer: any = {};
                        if(has(l, 'color')) colorLayer.color = parseHex(l.attrs.color);
                        color.layers[(int(l, 'id')).toString()] = colorLayer;
                    }
                }
                data.colors[(int(c, 'id')).toString()] = color;
            }
        }
        const as = grandKids(v, 'animations', 'animation');
        if(as.length > 0) data.animations = animations(as);
        const postureParents = kids(v, 'postures');
        if(postureParents.length > 0)
        {
            const parent = postureParents[0];
            data.postures = {};
            if(has(parent, 'defaultPosture')) data.postures.defaultPosture = parent.attrs.defaultPosture;
            const ps = kids(parent, 'posture');
            if(ps.length > 0)
            {
                data.postures.postures = [];
                for(const p of ps)
                {
                    const posture: any = {};
                    if(has(p, 'id')) posture.id = p.attrs.id;
                    if(has(p, 'animationId')) posture.animationId = int(p, 'animationId');
                    push(data.postures.postures, posture);
                }
            }
        }
        const gs = grandKids(v, 'gestures', 'gesture');
        if(gs.length > 0)
        {
            data.gestures = [];
            for(const g of gs)
            {
                const gesture: any = {};
                if(has(g, 'id')) gesture.id = g.attrs.id;
                if(has(g, 'animationId')) gesture.animationId = int(g, 'animationId');
                push(data.gestures, gesture);
            }
        }
        push(out, data);
    }
    return out;
}

// --- assets.xml ----------------------------------------------------------------------------------------
// { name: { source?, x?, y?, flipH?, flipV?, usesPalette? } } plus the names in the file's order
export interface Assets
{
    assets: any;
    names: string[];
}

export function assets(xml: XmlNode): Assets
{
    const out: Assets = { assets: {}, names: [] };
    const root = find(xml, 'assets');
    if(root === null) return out;
    for(const a of kids(root, 'asset'))
    {
        if(!has(a, 'name')) continue;
        const name = a.attrs.name;
        if(name.startsWith('sh_')) continue;
        if(name.indexOf('_32_') >= 0) continue;
        const asset: any = {};
        if(has(a, 'source')) asset.source = a.attrs.source;
        if(has(a, 'x')) asset.x = int(a, 'x');
        if(has(a, 'x')) asset.y = int(a, 'y');
        if(has(a, 'flipH')) asset.flipH = (a.attrs.flipH === '1');
        if(has(a, 'flipV')) asset.flipV = (a.attrs.flipV === '1');
        if(has(a, 'usesPalette')) asset.usesPalette = (a.attrs.usesPalette === '1');
        if(out.assets[name] === undefined) out.names.push(name);
        out.assets[name] = asset;
    }
    return out;
}

// --- logic.xml: the furni's size and the directions it can face ---------------------------------------
export function logic(xml: XmlNode): any
{
    const out: any = { x: 1, y: 1, z: 1, directions: [] };
    const d = find(xml, 'dimensions');
    if(d !== null)
    {
        if(has(d, 'x')) out.x = int(d, 'x');
        if(has(d, 'y')) out.y = int(d, 'y');
        if(has(d, 'z')) out.z = float(d, 'z');
    }
    const ds = find(xml, 'directions');
    if(ds !== null) for(const dir of kids(ds, 'direction')) push(out.directions, int(dir, 'id'));
    return out;
}

// --- JSON arrays in Lua (see the avatar port's Convert.ts) ---------------------------------------------
const G: { rawget: (this: void, t: any, k: any) => any; setmetatable: (this: void, t: any, m: any) => any } = globalThis as any;
const JS_ARRAY: any = {
    __index: (t: any, k: any): any =>
    {
        if(k === 'length') return (t as any[]).length;
        if(typeof k === 'number') return G.rawget(t, k + 1);
        return undefined;
    }
};

export function jsArrays(value: any): any
{
    if(value === null || value === undefined || typeof value !== 'object') return value;
    if(Array.isArray(value))
    {
        for(const v of value) jsArrays(v);
        if(G.setmetatable !== undefined) G.setmetatable(value, JS_ARRAY);
        return value;
    }
    for(const key in value) jsArrays(value[key]);
    return value;
}
