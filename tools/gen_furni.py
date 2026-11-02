"""Builds data/furni.json from the old Garry's Mod gamemode's furniture/shop Lua files and the sprite PNGs.
Usage: python3 tools/gen_furni.py <gamemode/content dir> <materials/bobbahotel/furni dir> <out data/furni.json>
The measuring follows the gamemode's sh_furnishape.lua: where the picture touches the floor decides how many tiles it covers."""
import sys, re, json, os
from PIL import Image

src, sprites, out = sys.argv[1:4]

# ---- tiny Lua table reader -------------------------------------------------------
class P:
    def __init__(s, t): s.t, s.i = t, 0
    def ws(s):
        while True:
            while s.i < len(s.t) and s.t[s.i] in ' \t\r\n': s.i += 1
            if s.t.startswith('--', s.i):
                while s.i < len(s.t) and s.t[s.i] != '\n': s.i += 1
            else: break
    def val(s):
        s.ws(); c = s.t[s.i]
        if c == '{': return s.table()
        if c in '"\'':
            j = s.i + 1; r = ''
            while s.t[j] != c:
                if s.t[j] == '\\': j += 1
                r += s.t[j]; j += 1
            s.i = j + 1; return r
        m = re.match(r'-?\d+(\.\d+)?', s.t[s.i:])
        if m: s.i += m.end(); n = float(m.group()); return int(n) if n == int(n) else n
        m = re.match(r'[A-Za-z_][A-Za-z_0-9.]*', s.t[s.i:])
        w = m.group(); s.i += m.end()
        return {'true': True, 'false': False, 'nil': None}.get(w, w)
    def table(s):
        s.i += 1; arr, obj = [], {}
        while True:
            s.ws()
            if s.t[s.i] == '}': s.i += 1; break
            if s.t[s.i] == ',': s.i += 1; continue
            m = re.match(r'([A-Za-z_][A-Za-z_0-9]*)\s*=(?!=)', s.t[s.i:]); m2 = re.match(r'\[\s*(-?\d+)\s*\]\s*=', s.t[s.i:])
            if m: s.i += m.end(); obj[m.group(1)] = s.val()
            elif m2: s.i += m2.end(); obj[m2.group(1)] = s.val()
            else: arr.append(s.val())
        return obj if obj and not arr else (arr if not obj else {**obj, '_': arr})

def registrations(path, var):
    t = open(path, encoding='utf8').read()
    for m in re.finditer(var + r':Register\(\s*"([^"]+)"\s*,\s*', t):
        p = P(t); p.i = m.end(); yield m.group(1), p.val()

def short(i): return i.split(':', 1)[-1]
def fpath(p): return os.path.basename(p) if p else None

# ---- sprite measuring ------------------------------------------------------------
def measure(file, T=32):
    im = Image.open(os.path.join(sprites, file)).convert('RGBA'); W, H = im.size; px = im.load()
    def solid(x, y):
        r, g, b, a = px[x, y]
        return a >= 128 and not (0 < a < 235 and (0.3*r + 0.59*g + 0.11*b) < 80)
    bottom, minc, maxc = {}, None, None
    for x in range(W):
        for y in range(H-1, -1, -1):
            if solid(x, y): bottom[x] = y; break
        if x in bottom:
            minc = x if minc is None else minc; maxc = x
    if minc is None: return None
    yf, c0, c1 = -1, None, None
    for x in range(minc, maxc+1):
        b = bottom.get(x)
        if b is not None:
            if b > yf: yf, c0, c1 = b, x, x
            elif b == yf: c1 = x
    xf = (c0 + c1) / 2
    a, b = xf + 0.5 - minc, maxc + 1 - (xf + 0.5)
    mdx = mdy = 0
    for x in range(minc, maxc+1):
        bt = bottom.get(x)
        if bt is not None:
            u, v = (x - xf) / T, (bt - yf) / (T / 2)
            mdx, mdy = max(mdx, (u + v) / 2), max(mdy, (v - u) / 2)
    wf = int(mdx + 0.5) if mdx >= 0.5 else 0
    df = int(mdy + 0.5) if mdy >= 0.5 else 0
    rx = max(0.01, a / T - (mdy if df > 0 else 0)); ry = max(0.01, b / T - (mdx if wf > 0 else 0))
    wb, db = int(rx + 0.5), int(ry + 0.5)
    if wb + wf < 1: wb = 1
    if db + df < 1: db = 1
    top = H
    for x in range(minc, maxc+1):
        for y in range(0, bottom.get(x, -1) + 1):
            if solid(x, y):
                top = min(top, y); break
    return dict(w=wb + wf, d=db + df, wf=wf, df=df, rx=round(rx, 3), ry=round(ry, 3), T=T,
                fx=round(xf + 0.5, 2), fy=yf + 1, top=top, sw=W, sh=H)

# ---- furniture -------------------------------------------------------------------
furni, skipped = {}, 0
for f in ['sh_tinyhouse_furni.lua', 'sh_tinyhouse_more.lua']:
    for id_, d in registrations(os.path.join(src, 'furni', f), 'F'):
        if not isinstance(d, dict) or not d.get('sprite'): continue
        e = {'name': d['name'], 'pages': d.get('pages') or ['misc'], 'price': d.get('price', 5), 'file': fpath(d['sprite'])}
        for k in ['seat', 'faces', 'stack', 'top', 'walkable', 'flat', 'stairs', 'rail', 'fps', 'sit', 'gift', 'scale', 'w', 'd']:
            if k in d: e['sitTop' if False else k] = d[k]
        if 'top' in e: e['htop'] = e.pop('top')  # height of the top in steps (the picture's own pixel top is "ptop")
        if d.get('anim'): e['anim'] = [fpath(a) for a in d['anim']]
        if d.get('off'): e['off'] = fpath(d['off'])
        if d.get('wall'):
            for k in ['sw', 'sh', 'wcx', 'wby', 'wty', 'half', 'wdir']: e[k] = d[k]
            e['wall'] = True
        else:
            m = measure(e['file'], d.get('tilepx', 32))
            if not m: skipped += 1; continue
            e['art'] = m
            e.setdefault('w', m['w']); e.setdefault('d', m['d'])
        furni[short(id_)] = e

# ---- shop pages ------------------------------------------------------------------
pages = []
for id_, d in registrations(os.path.join(src, 'shop', 'sh_shop_pages.lua'), 'P'):
    if not isinstance(d, dict): continue
    pg = {'id': short(id_), 'title': d.get('title'), 'parent': short(d['parent']) if d.get('parent') else None, 'kind': d.get('kind', 'page'),
          'icon': short(d['icon']) if d.get('icon') else None, 'order': d.get('order', 50), 'desc': d.get('desc', '')}
    if d.get('items'): pg['items'] = [[short(a), b] for a, b in d['items']]; pg['price'] = d.get('price')
    pages.append(pg)
pages.sort(key=lambda p: (p['order'], p['title']))
json.dump({'furni': furni, 'pages': pages}, open(out, 'w'), separators=(',', ':'))
print(len(furni), 'furni,', len(pages), 'pages,', skipped, 'unreadable;', sum(1 for f in furni.values() if f.get('wall')), 'wall items')
