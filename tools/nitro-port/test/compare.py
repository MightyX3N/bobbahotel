import json, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
a = json.load(open(os.path.join(HERE, '..', 'out', 'js.json'))); b = json.load(open(os.path.join(HERE, '..', 'out', 'lua.json')))
def same(x, y, path):
    if isinstance(x, (int, float)) and isinstance(y, (int, float)) and not isinstance(x, bool) and not isinstance(y, bool):
        if x == y or (math.isnan(x) and math.isnan(y)) or abs(x - y) < 1e-9: return None
        return path + ': %r vs %r' % (x, y)
    if x is None and isinstance(y, float) and math.isnan(y): return None  # JSON writes NaN as null
    if isinstance(x, list) and isinstance(y, dict) and not y: y = []
    if isinstance(y, list) and isinstance(x, dict) and not x: x = []
    if type(x) != type(y): return path + ': %r vs %r' % (x, y)
    if isinstance(x, list):
        if len(x) != len(y): return path + ': length %d vs %d' % (len(x), len(y))
        for i, (p, q) in enumerate(zip(x, y)):
            r = same(p, q, path + '[%d]' % i)
            if r: return r
        return None
    if isinstance(x, dict):
        if set(x) != set(y): return path + ': keys %s vs %s' % (sorted(set(x) ^ set(y)), '')
        for k in x:
            r = same(x[k], y[k], path + '.' + k)
            if r: return r
        return None
    return None if x == y else path + ': %r vs %r' % (x, y)
bad = 0; planes = 0
for k in a:
    r = same(a[k], b.get(k), k)
    planes += len(a[k]['planes']); points = globals().get('points', 0) + len(a[k]['camera']['64']) * 2; globals()['points'] = points
    if r: bad += 1; print('DIFF', r) if bad < 15 else None
picks = sum(len(r['picks']['64']) + len(r['picks']['32']) for r in a.values()); hits = sum(1 for r in a.values() for s in ('64', '32') for p in r['picks'][s] if p)
print('%d cases, %d planes, %d camera points, %d mouse positions (%d on the room), %d differ' % (len(a), planes, points, picks, hits, bad))
sys.exit(1 if bad else 0)
