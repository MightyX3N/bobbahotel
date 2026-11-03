#!/usr/bin/env python3
"""The whole way a room gets to the screen, without GMod: the server code (with a database that
answers like GMod's: everything as text) makes a player enter, the room.load message goes through
JSON like GMod's net messages, and the client code draws it.
    python3 tools/preview/e2e.py [layout] [--walk x,y --steps n]   -> out/preview/e2e.png

With --habbo <folder>, the bobba_habbo addon draws the people: its real code (avatar data, figure
libraries, SWF unpacking, Nitro's avatar renderer) runs on files a game already downloaded, copied
from garrysmod/data/bobbahotel/habbo/ into <folder> (raw/ and avatar/), as if from the cache."""
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
    ap.add_argument("--zoom", type=float, default=2)
    ap.add_argument("--size", default="1600x900")
    ap.add_argument("--habbo")
    ap.add_argument("--at", help="draw the player at x,y[,dir] (e.g. halfway through a step)")
    ap.add_argument("--time", type=float, default=0, help="seconds after the room loaded (animation)")
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
    if a.at:
        parts = [float(v) for v in a.at.split(",")]
        for unit in msg["units"]:
            unit["x"], unit["y"] = parts[0], parts[1]
            if len(parts) > 2: unit["dir"] = int(parts[2])
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
    images = None
    if a.habbo:
        images = habbo(L, a.habbo)
    L.eval("BOBBA.platform.receivers['room.load']")(None, tbl(msg))
    if a.habbo:
        # the first paint asks for the clothes (they load from the cache at once here), then time runs
        V0 = L.eval("BOBBA.view")
        V0.zoomNow = a.zoom
        V0.zoomTarget = a.zoom
        V0.panel.Paint(V0.panel, w, h)
        t = 0
        while t < a.time:
            t += 0.041
            L.execute("SetFakeTime(%f)" % (100 + t))
            V0.panel.Paint(V0.panel, w, h)
        G.ops = L.table()
    V = L.eval("BOBBA.view")
    V.zoomNow = a.zoom
    V.zoomTarget = a.zoom
    V.dirty = True
    V.panel.Paint(V.panel, w, h)
    out = os.path.join(ROOT, "out", "preview", "e2e.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    render.paint(G, w, h, images).save(out)
    print(out, "| wall height", V.room.wallHeight, "| units", [(x["name"], x["x"], x["y"]) for x in msg["units"]])

def habbo(L, folder):
    """Loads bobba_habbo (shared + avatars) with the platform's data folder in memory, seeded with the
    files in <folder> as the game's cache; returns the PNG pictures it writes, by path."""
    import io
    from PIL import Image
    files = {}
    for dirpath, _, names in os.walk(folder):
        for n in names:
            rel = os.path.relpath(os.path.join(dirpath, n), folder).replace(os.sep, "/")
            files["habbo/" + rel] = open(os.path.join(dirpath, n), "rb").read()
    store = L.table()
    L.globals().PY_STORE = store
    for k, v in files.items(): store[k] = v  # bytes go into Lua as they are
    settings = (b"x=1\nflash.client.url=https://images.habbo.com/gordon/" + SETTINGS_REV + b"/\n"
                b"flash.dynamic.download.url=//images.habbo.com/dcr/hof_furni/\n"
                b"external.figurepartlist.txt=https://www.habbo.com/gamedata/figuredata/" + FIGUREDATA_REV + b"\n")
    served = {"https://www.habbo.com/gamedata/external_variables/1": settings,
              "https://www.habbo.com/gamedata/clienturls": b'{"flash-windows-version":"35","flash-windows":"https://x/HabboWin.zip"}'}
    asked = []
    def http(url, ok, fail):
        u = url.decode() if isinstance(url, bytes) else url
        asked.append(u)
        if u in served: ok(served[u])
        else: fail("not in the test cache: " + u)
    L.globals().PY_HTTP = http
    L.globals().ADDON_DIR = os.path.join(ROOT, "addons", "bobba_habbo", "lua", "bobbahotel", "addons", "bobba_habbo") + "/"
    L.execute("""
        local P = BOBBA.platform
        P.httpGet = function(url, ok, fail) PY_HTTP(url, ok, fail) end
        P.writeData = function(path, bytes) PY_STORE[path] = bytes end
        P.readData = function(path) return PY_STORE[path] end
        P.dataExists = function(path) return PY_STORE[path] ~= nil end
        P.dataMaterial = function(path, flags) return { path = path, flags = flags } end
        P.runAddonFile = function(folder, name) return dofile(ADDON_DIR .. name) end
        bit = bit or require("bit")
        dofile(ADDON_DIR .. "shared.lua")
        dofile(ADDON_DIR .. "avatars.lua")
        BOBBA.habbo.preloadAvatars() -- what its timer does as the game starts
        -- the bytes of a stored file as hex (this Lua runtime hands strings to Python as UTF-8 text)
        function STORE_HEX(path)
            local d = PY_STORE[path]
            if not d then return nil end
            return (d:gsub(".", function(c) return string.format("%02x", c:byte()) end))
        end
    """)
    class Images(dict):
        def __missing__(self, key):
            data = L.eval("STORE_HEX")(key)
            if data is None: raise KeyError(key)
            self[key] = Image.open(io.BytesIO(bytes.fromhex(data)))
            return self[key]
        def __contains__(self, key):
            try: self[key]; return True
            except KeyError: return False
    habbo.asked = asked
    return Images()

SETTINGS_REV = b"flash-assets-PRODUCTION-202610210900-108929075"
FIGUREDATA_REV = b"bc45c6fd6b284b5bf43af4b295b3ac7b85ece5ee"

if __name__ == "__main__":
    main()
