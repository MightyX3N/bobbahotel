#!/usr/bin/env python3
"""Runs the Lua port (furni.lua, LuaJIT) on the same furni and steps as run_js.js, reading the XML with
the addon's own xml.lua as the game does; writes out/lua.json.     run_lua.py <furni.lua>"""
import json, os, subprocess, sys
from lupa import luajit21 as lj
HERE = os.path.dirname(os.path.abspath(__file__))
XML = os.path.join(HERE, "..", "..", "..", "..", "addons", "bobba_habbo", "lua", "bobbahotel", "addons", "bobba_habbo", "lib", "xml.lua")
L = lj.LuaRuntime(unpack_returned_tuples=True, encoding=None)
# Math.random -> math.random(): the same Park-Miller numbers as run_js.js
L.execute(b"local s = 1 math.random = function() s = (s * 16807) % 2147483647 return s / 2147483647 end")
F = L.execute(open(sys.argv[1], "rb").read())
X = L.execute(open(XML, "rb").read())
cases = json.loads(subprocess.check_output(["node", "-e", "const c = require(process.argv[1]); process.stdout.write(JSON.stringify({ STEP_MS: c.STEP_MS, START_MS: c.START_MS }))", os.path.join(HERE, "cases.js")]))
def timeline(states):
    return [{"direction": d * 45, "state": s, "color": s % 3, "updates": 24} for d in (0, 2, 4, 6, 1) for s in range(states + 1)]
def py(v):
    if lj.lua_type(v) == "table":
        keys = list(v.keys())
        if all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [py(v[k]) for k in range(1, len(keys) + 1)]
        return {(k.decode() if isinstance(k, bytes) else k): py(v[k]) for k in keys}
    if isinstance(v, bytes): return v.decode("latin1")
    return v
import re
def state_count(text):
    top = -1
    for m in re.finditer(r'<animation(\s[^>]*)>', text):
        i = re.search(r'\sid="(\d+)"', m.group(1))
        if i and "transition" not in m.group(1) and int(i.group(1)) < 1000 and int(i.group(1)) > top: top = int(i.group(1))
    return max(1, top + 1)
furni = json.load(open(os.path.join(HERE, "..", "out", "furni.json")))
out = []
for f in furni:
    lib = f["name"]
    trees = L.table_from({k.encode(): X.parse(v.encode("latin1")) for k, v in f["xml"].items()})
    L.globals().SIZES = L.table_from({k.encode(): L.table_from({b"width": s[0], b"height": s[1]}) for k, s in f["sizes"].items()})
    L.globals().LIB = lib.encode()
    source = L.eval(b"{ get = function(name) return SIZES[LIB .. '_' .. name] end }")
    t = F.loadType(trees, source)
    if t is None: out.append({"name": lib, "failed": True}); continue
    obj = F.create(t)
    frames, time = [], cases["START_MS"]
    for step in timeline(state_count(f["xml"]["visualization"])):
        F.setState(obj, L.table_from({b"direction": step["direction"], b"state": step["state"], b"color": step["color"], b"time": time}))
        for _ in range(step["updates"]):
            F.update(obj, time)
            s = py(F.sprites(obj))
            frames.append(s if isinstance(s, list) else [])
            time += cases["STEP_MS"]
    out.append({"name": lib, "visualizationType": t.visualizationType.decode(), "frames": frames})
json.dump(out, open(os.path.join(HERE, "..", "out", "lua.json"), "w"))
print("lua: %d furni, %d frames" % (len(out), sum(len(f.get("frames", [])) for f in out)))
