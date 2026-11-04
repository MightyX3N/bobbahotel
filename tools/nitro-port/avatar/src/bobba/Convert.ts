/** @noSelfInFile */
// [bobba] Habbo's avatar XML into the shapes Nitro's avatar code reads (Nitro reads JSON that its
// converter, or its own built-in copies, made from these same XML files). The XML comes as the tree
// bobba_habbo's xml.lua makes: { name, attrs, children, text }.
//
// Field names and types follow Nitro's readers (AvatarModelGeometry, PartSetsData, AnimationAction,
// ActionDefinition, SetType...) and nitro-converter's FigureDataMapper.

export interface XmlNode
{
    name: string;
    attrs: { [key: string]: string };
    children: XmlNode[];
    text?: string;
}

// arrays held in 'any' objects: Lua needs to know they are arrays
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

function kid(node: XmlNode, name: string): XmlNode
{
    if(node === undefined || node === null) return null;
    for(const c of node.children) if(c.name === name) return c;
    return null;
}

// the first element with that name, at any depth
function find(node: XmlNode, name: string): XmlNode
{
    if(node === undefined || node === null) return null;
    for(const c of node.children)
    {
        if(c.name === name) return c;
        const f = find(c, name);
        if(f !== null) return f;
    }
    return null;
}

function has(node: XmlNode, key: string): boolean
{
    return node.attrs[key] !== undefined;
}

function str(node: XmlNode, key: string): string
{
    return node.attrs[key];
}

// JavaScript's parseFloat / parseInt on a Habbo attribute (missing -> 0)
function num(node: XmlNode, key: string): number
{
    const v = node.attrs[key];
    if(v === undefined) return 0;
    const n = parseFloat(v);
    return (n !== n) ? 0 : n;
}

function int(node: XmlNode, key: string): number
{
    const v = node.attrs[key];
    if(v === undefined) return 0;
    const n = parseInt(v);
    return (n !== n) ? 0 : n;
}

// "1" and "true" are yes
function bool(node: XmlNode, key: string): boolean
{
    const v = node.attrs[key];
    return (v === '1') || (v === 'true');
}

function list(node: XmlNode, key: string): string[]
{
    const v = node.attrs[key];
    if(v === undefined || v === '') return [];
    return v.split(',');
}

function textNum(node: XmlNode): number
{
    if(node === null || node.text === undefined) return 0;
    return parseFloat(node.text);
}

// --- HabboAvatarGeometry ---------------------------------------------------------------------------

function avatarSet(node: XmlNode): any
{
    const out: any = { id: str(node, 'id'), avatarSets: [], bodyParts: [] };
    if(has(node, 'main')) out.main = bool(node, 'main');
    for(const c of kids(node, 'avatarset')) push(out.avatarSets, avatarSet(c));
    for(const c of kids(node, 'bodypart')) push(out.bodyParts, { id: str(c, 'id') });
    return out;
}

export function geometry(doc: XmlNode): any
{
    const root = find(doc, 'geometry');
    const out: any = { direction: num(root, 'direction'), camera: null, canvases: [], avatarSets: [], types: [] };
    const camera = kid(root, 'camera');
    if(camera !== null) out.camera = { x: textNum(kid(camera, 'x')), y: textNum(kid(camera, 'y')), z: textNum(kid(camera, 'z')) };
    for(const canvas of kids(root, 'canvas'))
    {
        const c: any = { scale: str(canvas, 'scale'), geometries: [] };
        for(const g of kids(canvas, 'geometry'))
        {
            push(c.geometries, { id: str(g, 'id'), width: num(g, 'width'), height: num(g, 'height'), dx: num(g, 'dx'), dy: num(g, 'dy') });
        }
        push(out.canvases, c);
    }
    for(const s of kids(root, 'avatarset')) push(out.avatarSets, avatarSet(s));
    for(const type of kids(root, 'type'))
    {
        const t: any = { id: str(type, 'id'), bodyParts: [] };
        for(const bp of kids(type, 'bodypart'))
        {
            const b: any = { id: str(bp, 'id'), x: num(bp, 'x'), y: num(bp, 'y'), z: num(bp, 'z'), radius: num(bp, 'radius'), items: [] };
            for(const it of kids(bp, 'item'))
            {
                push(b.items, { id: str(it, 'id'), x: num(it, 'x'), y: num(it, 'y'), z: num(it, 'z'), radius: num(it, 'radius'), nx: num(it, 'nx'), ny: num(it, 'ny'), nz: num(it, 'nz'), double: bool(it, 'double') });
            }
            push(t.bodyParts, b);
        }
        push(out.types, t);
    }
    return out;
}

// --- HabboAvatarPartSets ---------------------------------------------------------------------------

export function partSets(doc: XmlNode): any
{
    const root = find(doc, 'partSets');
    const out: any = { partSet: [], activePartSets: [] };
    for(const p of kids(kid(root, 'partSet'), 'part'))
    {
        const d: any = { setType: str(p, 'set-type') };
        if(has(p, 'flipped-set-type')) d.flippedSetType = str(p, 'flipped-set-type');
        if(has(p, 'remove-set-type')) d.removeSetType = str(p, 'remove-set-type');
        if(has(p, 'swim')) d.swim = str(p, 'swim');
        push(out.partSet, d);
    }
    for(const a of kids(root, 'activePartSet'))
    {
        const d: any = { id: str(a, 'id'), activeParts: [] };
        for(const p of kids(a, 'activePart')) push(d.activeParts, { setType: str(p, 'set-type') });
        push(out.activePartSets, d);
    }
    return out;
}

// --- HabboAvatarAnimation --------------------------------------------------------------------------

export function animations(doc: XmlNode): any[]
{
    const root = find(doc, 'animationSet');
    const out: any[] = [];
    for(const a of kids(root, 'action'))
    {
        const action: any = { id: str(a, 'id'), parts: [] };
        for(const p of kids(a, 'part'))
        {
            const part: any = { setType: str(p, 'set-type'), frames: [] };
            for(const f of kids(p, 'frame'))
            {
                const frame: any = { number: int(f, 'number'), assetPartDefinition: str(f, 'assetpartdefinition') };
                if(has(f, 'repeats')) frame.repeats = int(f, 'repeats');
                push(part.frames, frame);
            }
            push(action.parts, part);
        }
        const offsets = kid(a, 'offsets');
        if(offsets !== null)
        {
            action.offsets = { frames: [] };
            for(const f of kids(offsets, 'frame'))
            {
                const frame: any = { id: int(f, 'id'), directions: [] };
                if(has(f, 'repeats')) frame.repeats = int(f, 'repeats');
                for(const d of kids(kid(f, 'directions'), 'direction'))
                {
                    const dir: any = { id: int(d, 'id'), bodyParts: [] };
                    for(const b of kids(d, 'bodypart'))
                    {
                        const bp: any = { id: str(b, 'id') };
                        if(has(b, 'dx')) bp.dx = num(b, 'dx');
                        if(has(b, 'dy')) bp.dy = num(b, 'dy');
                        push(dir.bodyParts, bp);
                    }
                    push(frame.directions, dir);
                }
                push(action.offsets.frames, frame);
            }
        }
        out.push(action);
    }
    return out;
}

// --- HabboAvatarActions (+ the lay and swim offsets) ------------------------------------------------

// --- an effect library's animation (Dance1, Spotlight, ...): nitro-converter's AnimationMapper --------------

function effectFrames(nodes: XmlNode[]): any[]
{
    const out: any[] = [];
    for(const f of nodes)
    {
        const frame: any = {};
        if(has(f, 'repeats')) frame.repeats = int(f, 'repeats');
        const parts = (name: string): any[] =>
        {
            const list: any[] = [];
            for(const p of kids(f, name))
            {
                const part: any = {};
                if(has(p, 'id')) part.id = str(p, 'id');
                if(has(p, 'frame')) part.frame = int(p, 'frame');
                if(has(p, 'base')) part.base = str(p, 'base');
                if(has(p, 'action')) part.action = str(p, 'action');
                if(has(p, 'dx')) part.dx = int(p, 'dx');
                if(has(p, 'dy')) part.dy = int(p, 'dy');
                if(has(p, 'dz')) part.dz = int(p, 'dz');
                if(has(p, 'dd')) part.dd = int(p, 'dd');
                const items = kids(p, 'item');
                if(items.length > 0)
                {
                    part.items = [];
                    for(const i of items)
                    {
                        const item: any = {};
                        if(has(i, 'id')) item.id = str(i, 'id');
                        if(has(i, 'base')) item.base = str(i, 'base');
                        push(part.items, item);
                    }
                }
                push(list, part);
            }
            return list;
        };
        const fxs = parts('fx');
        if(fxs.length > 0) frame.fxs = fxs;
        const bodyparts = parts('bodypart');
        if(bodyparts.length > 0) frame.bodyparts = bodyparts;
        push(out, frame);
    }
    return out;
}

// { [desc]: animation }, as the converter writes it into the library's JSON (animations)
export function effectAnimation(doc: XmlNode): any
{
    const a = (doc.name === 'animation') ? doc : find(doc, 'animation');
    if(a === null) return null;
    const anim: any = {};
    if(has(a, 'name')) anim.name = str(a, 'name');
    if(has(a, 'desc')) anim.desc = str(a, 'desc');
    if(has(a, 'resetOnToggle')) anim.resetOnToggle = (str(a, 'resetOnToggle') === 'true');
    const directions = kids(a, 'direction');
    if(directions.length > 0)
    {
        anim.directions = [];
        for(const d of directions)
        {
            const dir: any = {};
            if(has(d, 'offset')) dir.offset = int(d, 'offset');
            push(anim.directions, dir);
        }
    }
    const simple = (name: string, field: string, read: (n: XmlNode) => any): void =>
    {
        const nodes = kids(a, name);
        if(nodes.length === 0) return;
        anim[field] = [];
        for(const n of nodes) push(anim[field], read(n));
    };
    simple('shadow', 'shadows', (n) => { const o: any = {}; if(has(n, 'id')) o.id = str(n, 'id'); return o; });
    simple('add', 'adds', (n) =>
    {
        const o: any = {};
        if(has(n, 'id')) o.id = str(n, 'id');
        if(has(n, 'align')) o.align = str(n, 'align');
        if(has(n, 'blend')) o.blend = str(n, 'blend');
        if(has(n, 'ink')) o.ink = int(n, 'ink');
        if(has(n, 'base')) o.base = str(n, 'base');
        return o;
    });
    simple('remove', 'removes', (n) => { const o: any = {}; if(has(n, 'id')) o.id = str(n, 'id'); return o; });
    simple('sprite', 'sprites', (n) =>
    {
        const o: any = {};
        if(has(n, 'id')) o.id = str(n, 'id');
        if(has(n, 'directions')) o.directions = int(n, 'directions');
        if(has(n, 'member')) o.member = str(n, 'member');
        if(has(n, 'ink')) o.ink = int(n, 'ink');
        if(has(n, 'staticY')) o.staticY = int(n, 'staticY');
        const dl = kids(n, 'direction');
        if(dl.length > 0)
        {
            o.directionList = [];
            for(const d of dl)
            {
                const dir: any = {};
                if(has(d, 'id')) dir.id = int(d, 'id');
                if(has(d, 'dx')) dir.dx = int(d, 'dx');
                if(has(d, 'dy')) dir.dy = int(d, 'dy');
                if(has(d, 'dz')) dir.dz = int(d, 'dz');
                push(o.directionList, dir);
            }
        }
        return o;
    });
    const frames = effectFrames(kids(a, 'frame'));
    if(frames.length > 0) anim.frames = frames;
    simple('avatar', 'avatars', (n) =>
    {
        const o: any = {};
        if(has(n, 'background')) o.background = str(n, 'background');
        if(has(n, 'foreground')) o.foreground = str(n, 'foreground');
        if(has(n, 'ink')) o.ink = int(n, 'ink');
        return o;
    });
    simple('override', 'overrides', (n) =>
    {
        const o: any = {};
        if(has(n, 'name')) o.name = str(n, 'name');
        if(has(n, 'override')) o.override = str(n, 'override');
        const fr = effectFrames(kids(n, 'frame'));
        if(fr.length > 0) o.frames = fr;
        return o;
    });
    const out: any = {};
    out[anim.desc !== undefined ? anim.desc : (anim.name !== undefined ? anim.name : 'animation')] = anim;
    return out;
}

export function actions(doc: XmlNode, offsetDocs: { [state: string]: XmlNode }): any
{
    const root = find(doc, 'actions');
    const out: any = { actions: [], actionOffsets: [] };
    for(const a of kids(root, 'action'))
    {
        const d: any = { id: str(a, 'id'), state: str(a, 'state'), precedence: int(a, 'precedence') };
        if(has(a, 'main')) d.main = bool(a, 'main');
        if(has(a, 'isdefault')) d.isDefault = bool(a, 'isdefault');
        if(has(a, 'geometrytype')) d.geometryType = str(a, 'geometrytype');
        if(has(a, 'activepartset')) d.activePartSet = str(a, 'activepartset');
        if(has(a, 'assetpartdefinition')) d.assetPartDefinition = str(a, 'assetpartdefinition');
        if(has(a, 'lay')) d.lay = str(a, 'lay');
        if(has(a, 'animation')) d.animation = bool(a, 'animation');
        if(has(a, 'startfromframezero')) d.startFromFrameZero = bool(a, 'startfromframezero');
        if(has(a, 'preventheadturn')) d.preventHeadTurn = bool(a, 'preventheadturn');
        if(has(a, 'prevents')) d.prevents = list(a, 'prevents');
        const params = kids(a, 'param');
        if(params.length > 0)
        {
            d.params = [];
            for(const p of params) push(d.params, { id: str(p, 'id'), value: str(p, 'value') });
        }
        const types = kids(a, 'type');
        if(types.length > 0)
        {
            d.types = [];
            for(const t of types)
            {
                const type: any = { id: str(t, 'id') };
                if(has(t, 'animated')) type.animated = bool(t, 'animated');
                if(has(t, 'prevents')) type.prevents = list(t, 'prevents');
                if(has(t, 'preventheadturn')) type.preventHeadTurn = bool(t, 'preventheadturn');
                push(d.types, type);
            }
        }
        push(out.actions, d);
    }
    for(const state in offsetDocs)
    {
        const offsets = find(offsetDocs[state], 'offsets');
        if(offsets === null) continue;
        const o: any = { action: state, offsets: [] };
        for(const e of kids(offsets, 'offset'))
        {
            push(o.offsets, { size: str(e, 'size'), direction: int(e, 'direction'), x: num(e, 'x'), y: num(e, 'y'), z: num(e, 'z') });
        }
        push(out.actionOffsets, o);
    }
    return out;
}

// --- figuredata (as nitro-converter's FigureDataMapper) --------------------------------------------

export function figureData(doc: XmlNode): any
{
    const root = find(doc, 'figuredata');
    const out: any = { palettes: [], setTypes: [] };
    for(const p of kids(kid(root, 'colors'), 'palette'))
    {
        const palette: any = { id: int(p, 'id'), colors: [] };
        for(const c of kids(p, 'color'))
        {
            push(palette.colors, { id: int(c, 'id'), index: int(c, 'index'), club: int(c, 'club'), selectable: int(c, 'selectable') === 1, hexCode: (c.text !== undefined) ? c.text : '' });
        }
        push(out.palettes, palette);
    }
    for(const st of kids(kid(root, 'sets'), 'settype'))
    {
        const setType: any = {
            type: has(st, 'type') ? str(st, 'type') : '',
            paletteId: has(st, 'paletteid') ? int(st, 'paletteid') : 1,
            mandatory_f_0: int(st, 'mand_f_0') === 1,
            mandatory_f_1: int(st, 'mand_f_1') === 1,
            mandatory_m_0: int(st, 'mand_m_0') === 1,
            mandatory_m_1: int(st, 'mand_m_1') === 1,
            sets: []
        };
        for(const s of kids(st, 'set'))
        {
            const set: any = {
                id: int(s, 'id'),
                gender: has(s, 'gender') ? str(s, 'gender') : '',
                club: int(s, 'club'),
                colorable: int(s, 'colorable') === 1,
                selectable: int(s, 'selectable') === 1,
                preselectable: int(s, 'preselectable') === 1,
                sellable: int(s, 'sellable') === 1,
                parts: []
            };
            for(const p of kids(s, 'part'))
            {
                push(set.parts, { id: int(p, 'id'), type: has(p, 'type') ? str(p, 'type') : '', colorable: int(p, 'colorable') === 1, index: int(p, 'index'), colorindex: int(p, 'colorindex') });
            }
            const hidden = kid(s, 'hiddenlayers');
            if(hidden !== null)
            {
                set.hiddenLayers = [];
                for(const l of kids(hidden, 'layer')) push(set.hiddenLayers, { partType: has(l, 'parttype') ? str(l, 'parttype') : '' });
            }
            push(setType.sets, set);
        }
        push(out.setTypes, setType);
    }
    return out;
}

// --- JSON arrays in Lua ------------------------------------------------------------------------------
// Nitro reads its JSON data untyped ('any'): data.parts.length, data.avatarSets[0]. TypeScriptToLua
// can only turn those into Lua's # and 1-based indexes when it knows the value is an array, so in Lua
// the arrays in converted data answer .length and [0] the way JavaScript arrays do. (In JavaScript
// nothing changes.)
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
