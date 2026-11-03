#!/usr/bin/env python3
"""Runs the gamemode's client/view.lua on LuaJIT with stand-ins for GMod's drawing functions that
paint into a picture, so rooms can be looked at without starting Garry's Mod.

    pip install lupa pillow
    python3 tools/preview/render.py model_a model_h        # -> out/preview/model_a.png ...
    python3 tools/preview/render.py --all --zoom 2          # every layout, at size 1 (Habbo zoomed in)
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
	DrawPoly = function(pts)
		-- like GMod: only polygons given clockwise on screen are filled
		local area = 0
		for i = 1, #pts do local a, b = pts[i], pts[i % #pts + 1] area = area + (a.x * b.y - b.x * a.y) end
		if area <= 0 then op("skipped") return end
		local t = {} for i, p in ipairs(pts) do t[i] = { p.x, p.y } end op("poly", t, { col[1], col[2], col[3], col[4] })
	end,
	DrawLine = function(x1, y1, x2, y2) op("line", x1, y1, x2, y2, { col[1], col[2], col[3] }) end,
	SetMaterial = function(m) G.material = m end,
	DrawTexturedRect = function() end,
	DrawTexturedRectUV = function(x, y, w, h, u0, v0, u1, v1) op("image", G.material and G.material.path, x, y, w, h, { u0, v0, u1, v1 }, { col[1], col[2], col[3], col[4] }, G.filter) end,
	DrawRect = function(x, y, w, h) op("rect", x, y, w, h, { col[1], col[2], col[3], col[4] }) end,
}
draw = { NoTexture = function() end, SimpleText = function(t, f, x, y) op("text", t, x, y) end,
	SimpleTextOutlined = function(t, f, x, y, c, ax, ay) op("text", t, x - 3 * #t, y - 12) end }
local fakeTime = 100
SysTime = function() return fakeTime end
RealFrameTime = function() return 1 / 60 end
SetFakeTime = function(t) fakeTime = t end
HSVToColor = function(h, s, v)
	local c = v * s; local x = c * (1 - math.abs((h / 60) % 2 - 1)); local m = v - c
	local r, g, b = 0, 0, 0
	if h < 60 then r, g, b = c, x, 0 elseif h < 120 then r, g, b = x, c, 0 elseif h < 180 then r, g, b = 0, c, x
	elseif h < 240 then r, g, b = 0, x, c elseif h < 300 then r, g, b = x, 0, c else r, g, b = c, 0, x end
	return Color(math.floor((r + m) * 255), math.floor((g + m) * 255), math.floor((b + m) * 255))
end
chat = { AddText = function() end }
LocalPlayer = function() return nil end
TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM = 1, 4
render = { PushRenderTarget = function() op("clear") end, PopRenderTarget = function() end, Clear = function() end,
	PushFilterMag = function(f) G.filter = f end, PushFilterMin = function() end, PopFilterMag = function() G.filter = nil end, PopFilterMin = function() end }
TEXFILTER = { POINT = "point", LINEAR = "linear" }
cam = { Start2D = function() end, End2D = function() end }
math.Clamp = function(v, a, b) return math.min(math.max(v, a), b) end
math.Round = function(v) return math.floor(v + 0.5) end
string.Trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local cursor = { 0, 0 }
KEY_LCONTROL, KEY_RCONTROL = 1, 2
CreateClientConVar = function(name, default) return { GetBool = function() return default == "1" end } end
input = { GetCursorPos = function() return cursor[1], cursor[2] end, IsKeyDown = function() return false end }
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
                addonFolders = function() return {} end, disabledAddons = function() return "" end,
                receivers = {}, receive = function(n, fn) BOBBA.platform.receivers[n] = fn end,
                sent = {}, send = function(n, d) table.insert(BOBBA.platform.sent, { name = n, data = d }) end }""")
        else:
            L.execute(open(os.path.join(GM, f)).read())
    G = L.execute(STUBS)
    L.execute(open(os.path.join(GM, "client", "view.lua")).read())
    L.execute(open(os.path.join(GM, "client", "room.lua")).read())
    return L, G

def paint(G, w, h, images=None):
    im = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(im, "RGBA")
    ops = G.ops
    for i in range(1, len(ops) + 1):
        o = ops[i]
        kind = o[1]
        if kind == "clear":
            d.rectangle([0, 0, w, h], fill=(0, 0, 0))
        elif kind == "poly":
            pts = [(o[2][j][1], o[2][j][2]) for j in range(1, len(o[2]) + 1)]
            d.polygon(pts, fill=tuple(o[3][j] for j in (1, 2, 3, 4)))
        elif kind == "rect":
            d.rectangle([o[2], o[3], o[2] + o[4] - 1, o[3] + o[5] - 1], fill=tuple(o[6][j] for j in (1, 2, 3, 4)))
        elif kind == "line":
            d.line([(o[2], o[3]), (o[4], o[5])], fill=tuple(o[6][j] for j in (1, 2, 3)))
        elif kind == "text":
            d.text((o[3], o[4]), o[2], fill=(255, 255, 255))
        elif kind == "image" and images is not None and o[2] in images:
            # a picture: the part of the texture the UVs pick (mirrored when u0 > u1), multiplied by
            # the draw colour (rounded like Habbo), scaled with GMod's filter (point = pixel-sharp)
            pic = images[o[2]].convert("RGBA")
            u0, v0, u1, v1 = (o[7][j] for j in (1, 2, 3, 4))
            flip = u0 > u1
            if flip: u0, u1 = u1, u0
            pic = pic.crop((round(u0 * pic.width), round(v0 * pic.height), round(u1 * pic.width), round(v1 * pic.height)))
            c = o[8]
            if (c[1], c[2], c[3]) != (255, 255, 255):
                r, g, b, al = pic.split()
                r = r.point(lambda v, m=c[1]: (v * m + 127) // 255)
                g = g.point(lambda v, m=c[2]: (v * m + 127) // 255)
                b = b.point(lambda v, m=c[3]: (v * m + 127) // 255)
                pic = Image.merge("RGBA", (r, g, b, al))
            if c[4] != 255:
                al = pic.getchannel("A").point(lambda v, m=c[4]: v * m // 255)
                pic.putalpha(al)
            if flip: pic = pic.transpose(Image.FLIP_LEFT_RIGHT)
            pw, ph = int(o[5]), int(o[6])
            if pw > 0 and ph > 0:
                pic = pic.resize((pw, ph), Image.NEAREST if o[9] == "point" else Image.BILINEAR)
                im.paste(pic, (int(o[3]), int(o[4])), pic)
    return im

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("layouts", nargs="*")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--zoom", type=float, default=2, help="size: 1 = Habbo zoomed in, 2 = double (the default in game)")
    ap.add_argument("--size", default="1920x1080")
    ap.add_argument("--hover", help="x,y tile to put the mouse on")
    ap.add_argument("--out", default=os.path.join(ROOT, "out", "preview"))
    ap.add_argument("--room", help="show as a room with people: JSON list of units [{id,name,x,y,z,dir,to:{x,y,z}}]")
    ap.add_argument("--t", type=float, default=0.25, help="seconds into the current step")
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
        if a.room:
            import json as _j
            L.execute("SetFakeTime(100)")
            units = _j.loads(a.room)
            hm = L.eval("BOBBA.registry.get")("layout", lid).heightmap
            msg = L.eval("function(hm, units) return { id = 1, name = 'Preview room', owner = 'test', layout = '%s', heightmap = hm, wallHeight = -1, you = 1, units = units } end" % lid)
            def tbl(v):
                if isinstance(v, dict):
                    t = L.table()
                    for k2, v2 in v.items(): t[k2] = tbl(v2)
                    return t
                if isinstance(v, list):
                    t = L.table()
                    for i2, v2 in enumerate(v): t[i2 + 1] = tbl(v2)
                    return t
                return v
            L.eval("BOBBA.platform.receivers['room.load']")(None, msg(hm, tbl(units)))
            L.execute("SetFakeTime(%f)" % (100 + a.t))
        else:
            G.cmds.bobba_preview(None, None, L.table(lid))
        V = L.eval("BOBBA.view")
        V.zoomNow = a.zoom
        V.zoomTarget = a.zoom
        V.dirty = True
        if a.hover:
            tx, ty = map(int, a.hover.split(","))
            room = V.room
            hgt = L.eval("BOBBA.rooms.tileHeight")(room, tx, ty) or 0
            z = L.table_from({"scale": 64, "mult": V.zoomNow})
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
