#!/usr/bin/env python3
"""out/js.json (Nitro's TypeScript) against out/lua.json (the port): every sprite of every update."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
js = json.load(open(os.path.join(HERE, "..", "out", "js.json")))
lua = json.load(open(os.path.join(HERE, "..", "out", "lua.json")))
def norm(v):
    if isinstance(v, dict): return {k: norm(x) for k, x in v.items()}
    if isinstance(v, list): return [norm(x) for x in v]
    if isinstance(v, float):
        if v == int(v): return int(v)
        return round(v, 9)
    return v
bad = frames = sprites = 0
kinds = {}
for a, b in zip(js, lua):
    kinds[a.get("visualizationType")] = kinds.get(a.get("visualizationType"), 0) + 1
    if a.get("failed") or b.get("failed"):
        if a.get("failed") != b.get("failed"): bad += 1; print("%s: loads in one, not the other" % a["name"])
        continue
    shown = 0
    for i, (fa, fb) in enumerate(zip(a["frames"], b["frames"])):
        frames += 1
        sprites += len(fa)
        if norm(fa) != norm(fb):
            bad += 1
            if shown < 2: print("%s update %d differs:\n  js  %s\n  lua %s" % (a["name"], i, json.dumps(norm(fa))[:600], json.dumps(norm(fb))[:600])); shown += 1
    if len(a["frames"]) != len(b["frames"]): bad += 1; print("%s: %d vs %d updates" % (a["name"], len(a["frames"]), len(b["frames"])))
print("%d furni (%s), %d updates, %d sprites, %d differ" % (len(js), ", ".join("%s %d" % kv for kv in sorted(kinds.items(), key=str)), frames, sprites, bad))
sys.exit(1 if bad or len(js) != len(lua) else 0)
