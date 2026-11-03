// [bobba] JavaScript's idea of true/false, for TypeScriptToLua: in Lua 0, "" and NaN are true. Used
// where Nitro tests a number or string directly (tools/nitro-port/test/truthiness.js finds those).
export function truthy(v: any): boolean
{
    return !((v === undefined) || (v === null) || (v === false) || (v === 0) || (v === '') || (v !== v));
}
