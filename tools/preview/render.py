#!/usr/bin/env python3
"""Runs the gamemode's client/view.lua on LuaJIT with stand-ins for GMod's drawing functions that
paint into a picture, so rooms can be looked at without starting Garry's Mod.

    pip install lupa pillow
    python3 tools/preview/render.py model_a model_h        # -> out/preview/model_a.png ...
    python3 tools/preview/render.py --all --zoom 2          # every layout, zoom 1 = out, 2 = normal, 3 = double
"""
import argparse, os, sys
from lupa import luajit21 as lj
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GM = os.path.join(ROOT, "gamemodes", "bobbahotel", "gamemode")

STUBS = r"""
local G = { ops = {} }
local function op(...) G.ops[#G.ops + 1] = { ... } end
ScrW = function() return SCREEN_W end
ScrH = function() return SCREEN_H end
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
color_white = Color(255, 255, 255)
RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, IMAGE_FORMAT_RGBA8888, MOUSE_LEFT = 1, 2, 3, 107
GetRenderTargetEx = function(name) return { GetName = function() return name end } end
CreateMaterial = function(name) return { name = name } end
local col = { 255, 255, 255, 255 }
surface = {
	CreateFont = function() end,
	SetDrawColor = function(r, g, b, a) if type(r) == "table" then col = { r.r, r.g, r.b, r.a or 255 } else col = { r, g, b, a or 255 } end end,
	DrawPoly = function(pts) local t = {} for i, p in ipairs(pts) do t[i] = { p.x, p.y } end op("poly", t, { col[1], col[2], col[3] }) end,
	DrawLine = function(x1, y1, x2, y2) op("line", x1, y1, x2, y2, { col[1], col[2], col[3] }) end,
	SetMaterial = function() end,
	DrawTexturedRect = function() end,
	DrawRect = function(x, y, w, h) op("rect", x, y, w, h, { col[1], col[2], col[3] }) end,
}
draw = { NoTexture = function() end, SimpleText = function(t, f, x, y) op("text", t, x, y) end }
render = { PushRenderTarget = function() op("clear") end, PopRenderTarget = function() end, Clear = function() end }
cam = { Start2D = function() end, End2D = function() end }
math.Clamp = function(v, a, b) return math.min(math.max(v, a), b) end
math.Round = function(v) return math.floor(v + 0.5) end
string.Trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local cursor = { 0, 0 }
input = { GetCursorPos = function() return cursor[1], cursor[2] end }
gui = { EnableScreenClicker = function() end }
local hooks, cmds = {}, {}
hook = { Add = function(name, id, fn) hooks[name] = fn end }
concommand = { Add = function(name, fn) cmds[name] = fn end }
IsValid = function(p) return p ~= nil and p.valid end
local registered = {}
vgui = {
	Register = function(name, tbl) registered[name] = tbl end,
	Create = function(name)
		local p = setmetatable({ valid = true, w = 0, h = 0 }, { __index = registered[name] })
		for _, f in ipairs({ "SetMouseInputEnabled", "SetKeyboardInputEnabled", "SetPos", "MouseCapture" }) do p[f] = function() end end
		p.SetSize = function(self, w, h) self.w, self.h = w, h end
		p.GetWide = function(self) return self.w end
		p.GetTall = function(self) return self.h end
		p.SetVisible = function(self, v) self.visible = v end
		p:Init()
		return p
	end,
}
G.cmds, G.hooks, G.cursor = cmds, hooks, cursor
return G
"""

def boot(w, h):
    L = lj.LuaRuntime(unpack_returned_tuples=True)
    L.globals().SCREEN_W, L.globals().SCREEN_H = w, h
    L.execute("BOBBA = {}")
    files = L.execute(open(os.path.join(GM, "hotel", "files.lua")).read())
    for i in range(1, len(files) + 1):
        f = files[i]
        if f == "PLATFORM":
            L.execute("""BOBBA.platform = { name = "preview", isClient = true, log = function() end, time = os.time,
                definePermission = function() end, hasPermission = function() return true end, permissionBackend = function() return "-" end,
                addonFolders = function() return {} end, disabledAddons = function() return "" end }""")
        else:
            L.execute(open(os.path.join(GM, f)).read())
    G = L.execute(STUBS)
    L.execute(open(os.path.join(GM, "client", "view.lua")).read())
    return L, G

def paint(G, w, h):
    im = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(im)
    ops = G.ops
    for i in range(1, len(ops) + 1):
        o = ops[i]
        kind = o[1]
        if kind == "clear":
            d.rectangle([0, 0, w, h], fill=(0, 0, 0))
        elif kind == "poly":
            pts = [(o[2][j][1], o[2][j][2]) for j in range(1, len(o[2]) + 1)]
            d.polygon(pts, fill=tuple(o[3][j] for j in (1, 2, 3)))
        elif kind == "rect":
            d.rectangle([o[2], o[3], o[2] + o[4] - 1, o[3] + o[5] - 1], fill=tuple(o[6][j] for j in (1, 2, 3)))
        elif kind == "line":
            d.line([(o[2], o[3]), (o[4], o[5])], fill=tuple(o[6][j] for j in (1, 2, 3)))
        elif kind == "text":
            d.text((o[3], o[4]), o[2], fill=(255, 255, 255))
    return im

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("layouts", nargs="*")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--zoom", type=int, default=3)
    ap.add_argument("--size", default="1920x1080")
    ap.add_argument("--hover", help="x,y tile to put the mouse on")
    ap.add_argument("--out", default=os.path.join(ROOT, "out", "preview"))
    a = ap.parse_args()
    w, h = map(int, a.size.split("x"))
    os.makedirs(a.out, exist_ok=True)
    L, G = boot(w, h)
    ids = a.layouts
    if a.all:
        lst = L.eval("BOBBA.registry.list('layout')")
        ids = [lst[i].id for i in range(1, len(lst) + 1)]
    for lid in ids:
        G.ops = L.table()
        G.cmds.bobba_preview(None, None, L.table(lid))
        V = L.eval("BOBBA.view")
        V.zoom = a.zoom
        V.dirty = True
        if a.hover:
            tx, ty = map(int, a.hover.split(","))
            room = V.room
            hgt = L.eval("BOBBA.rooms.tileHeight")(room, tx, ty) or 0
            z = V.ZOOMS[V.zoom]
            s = L.eval("BOBBA.nitro.create")(z.scale).screen(tx, ty, hgt)
            b = V.bounds[z.scale]
            ox = (w // 2) - (b.minX + b.maxX) / 2 * z.mult
            oy = (h // 2) - (b.minY + b.maxY) / 2 * z.mult
            G.cursor[1], G.cursor[2] = int(ox + s[1] * z.mult), int(oy + s[2] * z.mult)
            V.panel.OnCursorMoved(V.panel)
        V.panel.Paint(V.panel, w, h)
        p = os.path.join(a.out, lid + ".png")
        paint(G, w, h).save(p)
        print(p)

if __name__ == "__main__":
    main()
