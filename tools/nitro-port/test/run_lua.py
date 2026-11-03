import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
from lupa import luajit21 as lj
L = lj.LuaRuntime(unpack_returned_tuples=True)
L.execute('BOBBA = {}')
L.execute(open(sys.argv[1]).read())
n = L.eval('BOBBA.nitro')
def py(v):
    if lj.lua_type(v) == 'table':
        keys = list(v.keys())
        if all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [py(v[k]) for k in range(1, len(keys) + 1)]
        return {k: py(v[k]) for k in keys}
    return v
out = {}
for c in json.loads(subprocess.check_output(['node', '-e', 'process.stdout.write(JSON.stringify(require(process.argv[1])))', os.path.join(HERE, 'cases.js')])):
    room = py(n.build(c['model'], c['wallHeight'], True, c['ex'], c['ey'], c['ft'], c['wt']))
    cam = {}
    for s in (64, 32):
        g = n.create(s); pts = []
        for p in room['planes']:
            for a, b in ((0,0),(1,0),(0,1),(1,1)):
                pts.append(py(g.screen(*[p['loc'][i] + p['left'][i]*a + p['right'][i]*b for i in range(3)])))
            mid = g.screen(*[p['loc'][i] + (p['left'][i] + p['right'][i]) / 3 for i in range(3)])
            pts.append(py(g.planePosition(mid[1], mid[2], L.table_from(p['loc']), L.table_from(p['left']), L.table_from(p['right']))) if mid else None)
        cam[str(s)] = pts
    room['camera'] = cam
    lr = n.build(c['model'], c['wallHeight'], True, c['ex'], c['ey'], c['ft'], c['wt'])
    room['view'] = {'64': py(n.planes(lr, 64)), '32': py(n.planes(lr, 32))}
    room['picks'] = {}
    for s in (64, 32):
        v = n.planes(lr, s); pv = room['view'][str(s)]; res = []
        if pv and c['ft'] == 1 and c['wt'] == 1:
            xs = [p[k][0] for p in pv for k in 'abcd']; ys = [p[k][1] for p in pv for k in 'abcd']
            for y in range(min(ys) - 3, max(ys) + 4, 7):
                for x in range(min(xs) - 3, max(xs) + 4, 9):
                    res.append(py(n.pick(lr, v, s, x + 0.25, y + 0.5)))
        room['picks'][str(s)] = res
    out[c['name']] = room
json.dump(out, open(os.path.join(HERE, '..', 'out', 'lua.json'), 'w'))
