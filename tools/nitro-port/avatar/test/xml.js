// The same XML tree as addons/bobba_habbo/.../lib/xml.lua makes ({ name, attrs, children, text }),
// so Nitro's TypeScript and the Lua port read exactly the same input.
const ENTITIES = { lt: '<', gt: '>', amp: '&', quot: '"', apos: "'" };

function unescape(s)
{
    return s.replace(/&(#?x?)(\w+);/g, (m, kind, v) =>
    {
        if(kind === '#') return String.fromCharCode(parseInt(v, 10) % 256);
        if(kind === '#x') return String.fromCharCode(parseInt(v, 16) % 256);
        return (ENTITIES[v] !== undefined) ? ENTITIES[v] : m;
    });
}

function attrs(s)
{
    const out = {};
    const re = /([\w:\-.]+)\s*=\s*(["'])([\s\S]*?)\2/g;
    let m;
    while((m = re.exec(s)) !== null) out[m[1]] = unescape(m[3]);
    return out;
}

// text is a "binary" string (one char per byte), as Lua strings are
function parse(text)
{
    if(text.startsWith('\xef\xbb\xbf')) text = text.substring(3);
    const root = { name: '#document', attrs: {}, children: [] };
    const stack = [ root ];
    let pos = 0;
    for(;;)
    {
        const s = text.indexOf('<', pos);
        if(s < 0) break;
        const top = stack[stack.length - 1];
        if(s > pos)
        {
            const t = text.substring(pos, s);
            if(/\S/.test(t)) top.text = (top.text || '') + unescape(t);
        }
        if(text.startsWith('<!--', s))
        {
            const e = text.indexOf('-->', s + 4);
            pos = ((e < 0) ? text.length - 1 : e) + 3;
        }
        else if(text.startsWith('<![CDATA[', s))
        {
            const e = text.indexOf(']]>', s + 9);
            top.text = (top.text || '') + text.substring(s + 9, (e < 0) ? text.length : e);
            pos = ((e < 0) ? text.length - 1 : e) + 3;
        }
        else if(text.startsWith('<?', s) || text.startsWith('<!', s))
        {
            const e = text.indexOf('>', s);
            pos = ((e < 0) ? text.length - 1 : e) + 1;
        }
        else if(text.startsWith('</', s))
        {
            const e = text.indexOf('>', s);
            if(stack.length > 1) stack.pop();
            pos = ((e < 0) ? text.length - 1 : e) + 1;
        }
        else
        {
            const e = text.indexOf('>', s);
            if(e < 0) break;
            let inner = text.substring(s + 1, e);
            const selfClosing = inner.endsWith('/');
            if(selfClosing) inner = inner.substring(0, inner.length - 1);
            const m = /^([\w:\-.]+)([\s\S]*)$/.exec(inner);
            if(m)
            {
                const el = { name: m[1], attrs: attrs(m[2] || ''), children: [] };
                top.children.push(el);
                if(!selfClosing) stack.push(el);
            }
            pos = e + 1;
        }
    }
    return root;
}

module.exports = { parse };
