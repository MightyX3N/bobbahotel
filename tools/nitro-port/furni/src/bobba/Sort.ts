// [bobba] Array.prototype.sort as JavaScript does it: stable (equal items keep their order).
// TypeScriptToLua's sort is Lua's table.sort, which is not, and avatar parts at the same depth
// would come out in a different order. An insertion sort: the lists are short.
export function stableSort<T>(list: T[], compare: (a: T, b: T) => number): T[]
{
    for(let i = 1; i < list.length; i++)
    {
        const item = list[i];
        let j = i - 1;
        while((j >= 0) && (compare(list[j], item) > 0))
        {
            list[j + 1] = list[j];
            j--;
        }
        list[j + 1] = item;
    }
    return list;
}
