import { stableSort } from './Sort';

// [bobba] The keys of an object in JavaScript's order: whole numbers first, from small to large,
// then the rest (here alphabetically; in Nitro's data they are "1_1", "1_2" after "1", which is the
// order they were added in). Lua's pairs() has no order, and some of Nitro's loops depend on it
// (an animation's frame sequences and frames).
function index(k: string): number
{
    if(k.length === 0 || k.length > 9) return -1;
    for(let i = 0; i < k.length; i++)
    {
        const c = k.charCodeAt(i);
        if(c < 48 || c > 57) return -1;
    }
    if(k.length > 1 && k.charCodeAt(0) === 48) return -1;
    return parseInt(k);
}

export function jsKeys(obj: any): string[]
{
    if(obj === null || obj === undefined) return [];
    const keys: string[] = [];
    for(const k in obj) keys.push((k as any).toString());
    return stableSort(keys, (a, b) =>
    {
        const ia = index(a);
        const ib = index(b);
        if(ia >= 0 && ib >= 0) return ia - ib;
        if(ia >= 0) return -1;
        if(ib >= 0) return 1;
        return (a < b) ? -1 : ((a > b) ? 1 : 0);
    });
}
