#!/usr/bin/env python3
"""The whole way a room gets to the screen, without GMod: the server code (with a database that
answers like GMod's: everything as text) makes a player enter, the room.load message goes through
JSON like GMod's net messages, and the client code draws it.
    python3 tools/preview/e2e.py [layout] [--walk x,y --steps n]   -> out/preview/e2e.png"""
import argparse, json, os, sqlite3, sys
from lupa import luajit21 as lj
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import render

def server():
    lua = lj.LuaRuntime(unpack_returned_tuples=True)
    db = sqlite3.connect(":memory:", isolation_level=None)
    def query(s):
        try:
            cur = db.execute(s)
            cols = [d[0] for d in cur.description] if cur.description else []
            return lua.table_from([lua.table_from({c: str(v) for c, v in zip(cols, r) if v is not None}) for r in cur.fetchall()])
        except sqlite3.Error as e:
            return False, str(e)
    lua.globals().TEST_DB_QUERY = query
    lua.globals().GM_ROOT = os.path.join(ROOT, "gamemodes", "bobbahotel", "gamemode")
    lua.globals().TEST_ROOT = os.path.join(ROOT, "tests")
    lua.execute(open(os.path.join(ROOT, "tests", "boot.lua")).read())
    lua.execute("BOBBA.live.start()")
    return lua

def tojson(lua, v):
    # Lua table -> Python (arrays become lists) -> JSON text, like util.TableToJSON
    def py(x):
        if lj.lua_type(x) == "table":
            keys = list(x.keys())
            if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
                return [py(x[k]) for k in sorted(keys)]
            return {str(k): py(x[k]) for k in keys}
        return x
    return json.dumps(py(v))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("layout", nargs="?", default="model_a")
    ap.add_argument("--walk")
    ap.add_argument("--steps", type=int, default=0)
    ap.add_argument("--zoom", type=int, default=2)
    ap.add_argument("--size", default="1600x900")
    a = ap.parse_args()
    S = server()
    me = S.table_from({"key": "76561198000000001", "name": "Saint MightyX3N"})
    room_id = S.eval("BOBBA.live.homeRoom")() if a.layout == "model_a" else S.eval("BOBBA.live.create")("1", "Mia", a.layout, "Test room")
    S.eval("BOBBA.platform.fromPlayer")(me, "room.enter", S.table_from({"id": room_id}))
    if a.walk:
        x, y = map(int, a.walk.split(","))
        S.execute("BOBBA.platform.now = BOBBA.platform.now + 1")
        S.eval("BOBBA.platform.fromPlayer")(me, "room.walk", S.table_from({"x": x, "y": y}))
        for _ in range(a.steps):
            S.execute("BOBBA.platform.now = BOBBA.platform.now + 0.5; BOBBA.platform.runTimers()")
    load = S.eval("function(p) local b = BOBBA.platform.inbox(p, 'room.load') return b[#b] end")(me)
    msg = json.loads(tojson(S, load))
    u = S.eval("function(p) return BOBBA.live.byPlayer[p] end")(me)
    if u is not None:  # where the server has the player now (as the client would after the steps)
        for unit in msg["units"]:
            if unit["id"] == u.id: unit.update({"x": u.x, "y": u.y, "z": u.z, "dir": u.dir}); unit.pop("to", None)
    w, h = map(int, a.size.split("x"))
    L, G = render.boot(w, h)
    G.ops = L.table()
    L.execute("SetFakeTime(100)")
    def tbl(v):
        if isinstance(v, dict):
            t = L.table()
            for k, x in v.items(): t[k] = tbl(x)
            return t
        if isinstance(v, list):
            t = L.table()
            for i, x in enumerate(v): t[i + 1] = tbl(x)
            return t
        return v
    L.eval("BOBBA.platform.receivers['room.load']")(None, tbl(msg))
    V = L.eval("BOBBA.view")
    V.zoom = a.zoom
    V.dirty = True
    V.panel.Paint(V.panel, w, h)
    out = os.path.join(ROOT, "out", "preview", "e2e.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    render.paint(G, w, h).save(out)
    print(out, "| wall height", V.room.wallHeight, "| units", [(x["name"], x["x"], x["y"]) for x in msg["units"]])

if __name__ == "__main__":
    main()
