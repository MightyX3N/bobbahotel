#!/usr/bin/env python3
"""out/js.json (Nitro's TypeScript) against out/lua.json (the port): every sprite of every frame."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
js = json.load(open(os.path.join(HERE, "..", "out", "js.json")))
lua = json.load(open(os.path.join(HERE, "..", "out", "lua.json")))
def norm(v):
    if isinstance(v, dict): return {k: norm(x) for k, x in v.items()}
    if isinstance(v, list): return [norm(x) for x in v]
    if isinstance(v, float) and v == int(v): return int(v)
    return v
bad = sprites = 0
for i, (a, b) in enumerate(zip(js, lua)):
    for f, (fa, fb) in enumerate(zip(a, b)):
        fa, fb = norm(fa), norm(fb)
        fb.setdefault("sprites", [])
        if isinstance(fb["sprites"], dict): fb["sprites"] = []
        if isinstance(fb.get("canvasOffsets"), dict): fb["canvasOffsets"] = []
        sprites += len(fa["sprites"])
        if fa != fb:
            bad += 1
            if bad <= 5: print("case %d frame %d differs:\n  js  %s\n  lua %s" % (i, f, json.dumps(fa)[:400], json.dumps(fb)[:400]))
print("%d cases, %d sprites, %d frames differ" % (len(js), sprites, bad))
sys.exit(1 if bad or len(js) != len(lua) else 0)
