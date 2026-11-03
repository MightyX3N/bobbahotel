import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
def norm(x):
    if isinstance(x, dict): return {k: norm(v) for k, v in x.items()}
    if isinstance(x, list): return [norm(v) for v in x]
    return x
bad = 0
for i, (x, y) in enumerate(zip(a, b)):
    x, y = norm(x), norm(y)
    if x != y:
        bad += 1
        if bad <= 3:
            print("step", i, "differs")
            if 'error' in x or 'error' in y: print("  js:", x.get('error'), "lua:", y.get('error')); continue
            if x['figure'] != y['figure']: print("  figure js", x['figure'], "\n         lua", y['figure'])
            for m in x['models']:
                for c in x['models'][m]:
                    cx, cy = x['models'][m][c], y['models'].get(m, {}).get(c)
                    if cx != cy:
                        for k in cx:
                            if cy is None or cx[k] != cy.get(k): print("  ", m, c, k, "js", str(cx[k])[:150], "\n           lua", str(cy and cy.get(k))[:150])
print("%d states, %d differ" % (len(a), bad) + ("" if len(a) == len(b) else " (counts %d vs %d)" % (len(a), len(b))))
sys.exit(1 if bad or len(a) != len(b) else 0)
