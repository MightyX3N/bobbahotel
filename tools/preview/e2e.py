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
    ap.add_argument("--furni", help="furni to place first (needs --habbo): kind,x,y,dir[,state];...")
    ap.add_argument("--out", default="e2e.png")
    ap.add_argument("--floor", help="the room's floor id")
    ap.add_argument("--wallpaper", help="the room's wallpaper id")
    ap.add_argument("--say", help="what the player says, then what happens: text[|kind[|seconds later]];... (kind talk/shout/whisper)")
    ap.add_argument("--editor", action="store_true", help="open the avatar editor over the room (needs --habbo)")
    ap.add_argument("--editor-clicks", help="then click in it: x,y in CSS pixels from its corner; wheel:x,y,n scrolls;...")
    ap.add_argument("--editor-frames", type=int, default=40, help="paints before the picture (clothes load in between)")
    ap.add_argument("--click", help="after drawing, click at screen x,y[;x,y...] and print what the client sends")
    a = ap.parse_args()
    S = server()
    me = S.table_from({"key": "76561198000000001", "name": "Saint MightyX3N"})
    room_id = S.eval("BOBBA.live.homeRoom")() if a.layout == "model_a" else S.eval("BOBBA.live.create")("1", "Mia", a.layout, "Test room")
    if a.furni or a.editor:
        habbo_server(S, a.habbo)
        # (the addon loads Habbo's figuredata a moment after the server starts: its timer)
        S.execute("BOBBA.platform.now = BOBBA.platform.now + 2; BOBBA.platform.runTimers()")
    if a.furni:
        r = S.eval("function(id) return BOBBA.live.rooms[id] end")
        S.eval("BOBBA.live.enter")(me, room_id)
        for spec in a.furni.split(";"):
            p = spec.split(",")
            res = S.eval("""function(id, kind, x, y, dir, state)
                local out
                BOBBA.items.place(BOBBA.live.rooms[id], nil, kind, x, y, dir, function(it, why) out = it and "ok" or why if it and state > 0 then it.state = state BOBBA.store.query("UPDATE bobbahotel_items SET state = ? WHERE id = ?", { state, it.id }) end end)
                for _ = 1, 200 do if out then break end BOBBA.platform.runTimers() end
                return out end""")(room_id, p[0], int(p[1]), int(p[2]), int(p[3]), int(p[4]) if len(p) > 4 else 0)
            print("furni", spec, "->", res)
    for what in ("floor", "wallpaper"):
        if getattr(a, what): S.eval("BOBBA.live.setLook")(room_id, what, getattr(a, what))
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
            if unit["id"] == u.id: unit.update({"x": u.x, "y": u.y, "z": u.z, "dir": u.dir, "posture": u.posture, "height": u.height}); unit.pop("to", None)
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
    if a.say:
        # through the server: the message the client sends, the one everyone gets back
        t = 0
        for spec in a.say.split(";"):
            p = spec.split("|")
            t += float(p[2]) if len(p) > 2 else 0.5
            L.execute("SetFakeTime(%f)" % (100 + t))
            S.execute("BOBBA.platform.now = BOBBA.platform.now + 2")
            count = S.eval("function(p, n) return #BOBBA.platform.inbox(p, n) end")
            before, errs = count(me, "room.chat"), count(me, "room.error")
            S.eval("BOBBA.platform.fromPlayer")(me, "room.chat", S.table_from({"text": p[0], "kind": p[1] if len(p) > 1 else "talk", "to": p[3] if len(p) > 3 else None}))
            if count(me, "room.chat") == before:
                why = S.eval("function(p) local b = BOBBA.platform.inbox(p, 'room.error') return b[#b] and b[#b].message end")(me) if count(me, "room.error") > errs else "nothing"
                print("said", repr(p[0]), "-> not sent:", why)
                continue
            got = S.eval("function(p) local b = BOBBA.platform.inbox(p, 'room.chat') return b[#b] end")(me)
            print("said", repr(p[0]), "->", tojson(S, got))
            L.eval("BOBBA.platform.receivers['room.chat']")(None, tbl(json.loads(tojson(S, got))))
            for _ in range(30): L.eval("BOBBA.room.chatState.draw")()
        G.ops = L.table()
    V = L.eval("BOBBA.view")
    V.zoomNow = a.zoom
    V.zoomTarget = a.zoom
    V.dirty = True
    V.panel.Paint(V.panel, w, h)
    out = os.path.join(ROOT, "out", "preview", a.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    picture = render.paint(G, w, h, images)
    if a.editor:
        L.execute("BOBBA.avatarEditor.open()")
        win = L.eval("BOBBA.ui.windows['avatar-editor']")
        if win is None: raise SystemExit("the editor didn't open")
        panel = win.panel
        scale = L.eval("BOBBA.ui.scale()")
        def paint_window():
            G.ops = L.table()
            panel.Paint(panel, panel.w, panel.h)
        for _ in range(a.editor_frames):
            paint_window()
        for c in (a.editor_clicks or "").split(";"):
            if not c: continue
            if c.startswith("wheel:"):
                x, y, n = map(float, c[6:].split(","))
                panel.mouse[1], panel.mouse[2] = x * scale, y * scale
                paint_window()
                panel.OnMouseWheeled(panel, n)
            else:
                x, y = map(float, c.split(","))
                panel.mouse[1], panel.mouse[2] = x * scale, y * scale
                paint_window()
                panel.OnMousePressed(panel, 107)
            for _ in range(a.editor_frames):
                paint_window()
        paint_window()
        layer = render.paint(G, int(panel.w), int(panel.h), images, transparent=True)
        sent = [x for x in L.eval("BOBBA.platform.sent").values() if x.name == "user.figure"]
        if sent:
            # saved: through the server (its check), and what it sends back to the room
            before = S.eval("function(p) return #BOBBA.platform.inbox(p, 'room.units') end")(me)
            S.eval("BOBBA.platform.fromPlayer")(me, "user.figure", S.table_from({"figure": sent[-1].data.figure, "gender": sent[-1].data.gender}))
            box = S.eval("function(p) return BOBBA.platform.inbox(p, 'room.units') end")(me)
            err = S.eval("function(p) local b = BOBBA.platform.inbox(p, 'room.error') return b[#b] and b[#b].message end")(me)
            print("server:", "saved" if len(box) > before else "refused (%s)" % err, "| stored", S.eval("BOBBA.looks.get")(me.key))
            if len(box) > before:
                L.eval("BOBBA.platform.receivers['room.units']")(None, tbl(json.loads(tojson(S, box[len(box)]))))
                for _ in range(a.editor_frames + 3):
                    G.ops = L.table()
                    V.dirty = True
                    V.panel.Paint(V.panel, w, h)
                picture = render.paint(G, w, h, images)
        picture = picture.convert("RGBA")
        if L.eval("BOBBA.ui.windows['avatar-editor']") is not None:
            picture.alpha_composite(layer, (int(panel.x), int(panel.y)))
        print("editor: figure", L.eval("BOBBA.avatarEditor.editor.figure:getFigureString()"), "| gender", L.eval("BOBBA.avatarEditor.editor.figure.gender"),
              "| sent", [dict(x.data) for x in L.eval("BOBBA.platform.sent").values() if x.name == "user.figure"])
    picture.convert("RGB").save(out)
    if a.click:
        for c in a.click.split(";"):
            cx, cy = map(int, c.split(","))
            L.execute("BOBBA.platform.sent = {}")
            G.cursor[1], G.cursor[2] = cx, cy
            V.updateHover(cx, cy)
            L.execute("BOBBA.events.emit('roomClick', BOBBA.view.hover or { floor = false })")
            sent = L.eval("BOBBA.platform.sent")
            print("click", c, "->", [(sent[i].name, dict(sent[i].data)) for i in range(1, len(sent) + 1)], "| selected", L.eval("BOBBA.room.selected"))
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
                b"external.figurepartlist.txt=https://www.habbo.com/gamedata/figuredata/" + FIGUREDATA_REV + b"\n"
                b"furnidata.load.url=https://www.habbo.com/gamedata/furnidata_xml/" + FURNIDATA_REV + b"\n")
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
        dofile(ADDON_DIR .. "furni.lua")
        dofile(ADDON_DIR .. "planes.lua")
        dofile(ADDON_DIR .. "chat.lua")
        dofile(ADDON_DIR .. "editor.lua")
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

def habbo_server(S, folder):
    """The bobba_habbo addon on the server side (says what furni are), on the same cache files."""
    S.globals().SERVER = True
    S.globals().AddCSLuaFile = lambda *a: None
    files = {}
    for dirpath, _, names in os.walk(folder):
        for n in names:
            rel = os.path.relpath(os.path.join(dirpath, n), folder).replace(os.sep, "/")
            files["habbo/" + rel] = open(os.path.join(dirpath, n), "rb").read()
    store = S.table()
    for k, v in files.items(): store[k] = v
    S.globals().PY_STORE = store
    settings = (b"x=1\nflash.client.url=https://images.habbo.com/gordon/" + SETTINGS_REV + b"/\n"
                b"flash.dynamic.download.url=//images.habbo.com/dcr/hof_furni/\n"
                b"furnidata.load.url=https://www.habbo.com/gamedata/furnidata_xml/" + FURNIDATA_REV + b"\n"
                b"external.figurepartlist.txt=https://www.habbo.com/gamedata/figuredata/" + FIGUREDATA_REV + b"\n")
    def http(url, ok, fail):
        u = url.decode() if isinstance(url, bytes) else url
        if u == "https://www.habbo.com/gamedata/external_variables/1": ok(settings)
        else: fail("not in the test cache: " + u)
    S.globals().PY_HTTP = http
    S.globals().ADDON_DIR = os.path.join(ROOT, "addons", "bobba_habbo", "lua", "bobbahotel", "addons", "bobba_habbo") + "/"
    S.execute("""
        local P = BOBBA.platform
        P.httpGet = function(url, ok, fail) PY_HTTP(url, ok, fail) end
        P.writeData = function(path, bytes) PY_STORE[path] = bytes end
        P.readData = function(path) return PY_STORE[path] end
        P.dataExists = function(path) return PY_STORE[path] ~= nil end
        P.runAddonFile = function(folder, name) return dofile(ADDON_DIR .. name) end
        dofile(ADDON_DIR .. "shared.lua")
    """)

FURNIDATA_REV = b"345cedafe14d7703a394dee44c00fd9af9935279"
SETTINGS_REV = b"flash-assets-PRODUCTION-202610210900-108929075"
FIGUREDATA_REV = b"bc45c6fd6b284b5bf43af4b295b3ac7b85ece5ee"

if __name__ == "__main__":
    main()
