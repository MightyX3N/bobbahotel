// Habbo's figuredata.xml in the shapes Nitro's avatar structure has (FigureSetData, SetType,
// FigurePartSet, FigurePart, Palette, PartColor), with Nitro's AdvancedMap's methods.
class AdvancedMap<T> {
    private keys: string[] = []; private values: T[] = []; private map = new Map<string, T>();
    add(k: string, v: T) { if (this.map.has(k)) return; this.map.set(k, v); this.keys.push(k); this.values.push(v); }
    getValue(k: string) { return this.map.get(k); }
    getWithIndex(i: number) { return this.values[i]; }
    getValues() { return this.values.concat(); }
    get length() { return this.values.length; }
}
const attrs = (s: string) => { const o: any = {}; s.replace(/([\w:-]+)="([^"]*)"/g, (_m, k, v) => (o[k] = v, '')); return o; };
const bool = (v: string) => v === '1' || v === 'true';
export function loadFigureData(xml: string)
{
    const palettes = new Map<number, any>();
    const setTypes = new Map<string, any>();
    const order: string[] = [];
    for (const pm of xml.matchAll(/<palette\s([^>]*)>([\s\S]*?)<\/palette>/g)) {
        const pa = attrs(pm[1]);
        const colors = new AdvancedMap<any>();
        for (const cm of pm[2].matchAll(/<color\s([^>]*)>\s*([0-9a-fA-F]*)\s*<\/color>/g)) {
            const c = attrs(cm[1]);
            colors.add(c.id, { id: parseInt(c.id), index: parseInt(c.index), clubLevel: parseInt(c.club) || 0, isSelectable: bool(c.selectable), rgb: parseInt('0x' + cm[2], 16) });
        }
        palettes.set(parseInt(pa.id), { id: parseInt(pa.id), colors });
    }
    for (const sm of xml.matchAll(/<settype\s([^>]*)>([\s\S]*?)<\/settype>/g)) {
        const sa = attrs(sm[1]);
        const partSets = new AdvancedMap<any>();
        for (const se of sm[2].matchAll(/<set\s([^>]*?)(\/>|>([\s\S]*?)<\/set>)/g)) {
            const a = attrs(se[1]);
            const parts: any[] = [];
            for (const p of (se[3] || '').matchAll(/<part\s([^>]*?)\/?>/g)) {
                const pa = attrs(p[1]);
                parts.push({ id: parseInt(pa.id), type: pa.type, index: parseInt(pa.index), colorLayerIndex: parseInt(pa.colorindex) });
            }
            partSets.add(a.id, { id: parseInt(a.id), type: sa.type, gender: (a.gender || 'U').toUpperCase(), clubLevel: parseInt(a.club) || 0, isColorable: bool(a.colorable),
                isSelectable: bool(a.selectable), isPreSelectable: bool(a.preselectable), isSellable: bool(a.sellable), parts });
        }
        const mandatory: any = { F: [bool(sa.mand_f_0), bool(sa.mand_f_1)], M: [bool(sa.mand_m_0), bool(sa.mand_m_1)] };
        setTypes.set(sa.type, { type: sa.type, paletteID: parseInt(sa.paletteid), partSets,
            isMandatory: (g: string, level: number) => mandatory[g.toUpperCase()][Math.min(level, 1)] });
        order.push(sa.type);
    }
    return {
        getSetType: (t: string) => setTypes.get(t),
        getPalette: (id: number) => palettes.get(id),
        getMandatorySetTypeIds: (g: string, level: number) => order.filter(t => setTypes.get(t).isMandatory(g, level)),
    };
}
