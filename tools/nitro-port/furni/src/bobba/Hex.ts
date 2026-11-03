// [bobba] parseInt(s, 16) as JavaScript does it, for TypeScriptToLua (whose parseInt misreads
// capital letters, and Habbo's colours are written in capitals): leading "0x", then hex digits.
export function parseHex(s: string): number
{
    let i = 0;
    if((s.length >= 2) && (s[0] === '0') && ((s[1] === 'x') || (s[1] === 'X'))) i = 2;
    let v = 0;
    let any = false;
    for(; i < s.length; i++)
    {
        const c = s.charCodeAt(i);
        let d = -1;
        if((c >= 48) && (c <= 57)) d = c - 48;
        else if((c >= 65) && (c <= 70)) d = c - 55;
        else if((c >= 97) && (c <= 102)) d = c - 87;
        if(d < 0) break;
        v = (v * 16) + d;
        any = true;
    }
    return any ? v : NaN;
}
