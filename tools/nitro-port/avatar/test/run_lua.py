#!/usr/bin/env python3
"""Runs the Lua port (avatar.lua, LuaJIT) on the same cases as run_js.js, reading the XML with the
addon's own xml.lua as the game does; writes out/lua.json.   run_lua.py <avatar.lua> <data folder>"""
import json, os, subprocess, sys
from lupa import luajit21 as lj
HERE = os.path.dirname(os.path.abspath(__file__))
XML = os.path.join(HERE, "..", "..", "..", "..", "addons", "bobba_habbo", "lua", "bobbahotel", "addons", "bobba_habbo", "lib", "xml.lua")
L = lj.LuaRuntime(unpack_returned_tuples=True, encoding=None)
A = L.execute(open(sys.argv[1], "rb").read())
X = L.execute(open(XML, "rb").read())
d = sys.argv[2]
def read(f): return X.parse(open(os.path.join(d, "data", f), "rb").read())
def py(v):
    if lj.lua_type(v) == "table":
        keys = list(v.keys())
        if all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [py(v[k]) for k in range(1, len(keys) + 1)]
        return {(k.decode() if isinstance(k, bytes) else k): py(v[k]) for k in keys}
    if isinstance(v, bytes): return v.decode("latin1")
    return v
assets = json.load(open(os.path.join(d, "assets.json")))
lassets = L.table_from({k.encode(): L.table_from({b"offsetX": a["offsetX"], b"offsetY": a["offsetY"], b"width": a["width"], b"height": a["height"]}) for k, a in assets.items()})
L.globals().ASSETS = lassets
source = L.eval(b"{ get = function(name) return ASSETS[name] end }")
data = L.table_from({b"geometry": read("geometry.txt"), b"partSets": read("partsets.txt"), b"animation": read("animation.txt"),
    b"actions": read("actions.xml"), b"offsets": L.table_from({b"lay": read("offset_lay.txt"), b"swim": read("offset_swim.txt")}),
    b"figureData": L.table_from([read("figure.txt")])})
r = A.createRenderer(data, source)
# as the game does it (bobba_habbo's avatars.lua): figuredata a settype at a time
L.globals().BOBBA = L.table_from({b"habbo": L.table_from({b"xml": X})})
piece_code = open(os.path.join(os.path.dirname(XML), "avatardata.lua"), "rb").read().split(b"-- figuredata in pieces")[1]
L.execute(b"local H = BOBBA.habbo\n-- figuredata in pieces" + piece_code)
pieces = L.eval(b"BOBBA.habbo.figureDataPieces")(read("figuredata.xml"))
for i in range(1, len(pieces) + 1):
    r.appendFigureData(r, pieces[i])
cases = json.loads(subprocess.check_output(["node", "-e", "process.stdout.write(JSON.stringify(require(process.argv[1]).cases))", os.path.join(HERE, "cases.js")]))
def state(c):
    t = {k.encode(): (v.encode() if isinstance(v, str) else v) for k, v in c.items()}
    return L.table_from(t)
out = []
for c in cases:
    av = r.createImage(r, c["figure"].encode(), c["scale"].encode())
    A.setState(av, state(c))
    frames = []
    for _ in range(c["frames"]):
        frames.append(py(A.frame(av)))
        A.next(av)
    out.append(frames)
json.dump(out, open(os.path.join(HERE, "..", "out", "lua.json"), "w"))
print("lua: %d cases" % len(out))
