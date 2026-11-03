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
	CreateFont = function(name, data) PY_CREATE_FONT(name, data.font or "", data.size or 13, data.weight or 500, data.italic and true or false) end,
	SetDrawColor = function(r, g, b, a) if type(r) == "table" then col = { r.r, r.g, r.b, r.a or 255 } else col = { r, g, b, a or 255 } end end,
	DrawPoly = function(pts)
		-- like GMod: only polygons given clockwise on screen are filled
		local area = 0
		for i = 1, #pts do local a, b = pts[i], pts[i % #pts + 1] area = area + (a.x * b.y - b.x * a.y) end
		if area <= 0 then op("skipped") return end
		local t = {} for i, p in ipairs(pts) do t[i] = { p.x, p.y, p.u, p.v } end
		op("poly", t, { col[1], col[2], col[3], col[4] }, (pts[1].u ~= nil and G.material) and G.material.path or nil)
	end,
	DrawLine = function(x1, y1, x2, y2) op("line", x1, y1, x2, y2, { col[1], col[2], col[3] }) end,
	SetMaterial = function(m) G.material = m end,
	DrawTexturedRect = function() end,
	DrawTexturedRectUV = function(x, y, w, h, u0, v0, u1, v1) op("image", G.material and G.material.path, x, y, w, h, { u0, v0, u1, v1 }, { col[1], col[2], col[3], col[4] }, G.filter, G.blend) end,
	DrawRect = function(x, y, w, h) op("rect", x, y, w, h, { col[1], col[2], col[3], col[4] }) end,
}
draw = { NoTexture = function() G.material = nil end, SimpleText = function(t, f, x, y, c, ax, ay) op("text", t, x, y, c and { c.r, c.g, c.b, c.a or 255 } or nil, f, ay, ax) end,
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
ErrorNoHalt = function(msg) print("ErrorNoHalt: " .. tostring(msg)) end
LocalPlayer = function() return nil end
TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM = 1, 4
render = { SetScissorRect = function(x0, y0, x1, y1, on) op("clip", x0, y0, x1, y1, on) end, PushRenderTarget = function() op("clear") end, PopRenderTarget = function() end, Clear = function() end,
	PushFilterMag = function(f) G.filter = f end, PushFilterMin = function() end, PopFilterMag = function() G.filter = nil end, PopFilterMin = function() end,
	-- blending: only "add" (light) is painted differently
	OverrideBlend = function(on, src, dst) G.blend = (on and dst == BLEND_ONE) and "add" or nil end }
BLEND_ZERO, BLEND_ONE, BLEND_DST_COLOR, BLEND_ONE_MINUS_DST_COLOR, BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLEND_SRC_COLOR, BLEND_ONE_MINUS_SRC_COLOR = 0, 1, 2, 3, 4, 5, 6, 7
BLENDFUNC_ADD = 0
KEY_R, MOUSE_RIGHT = 28, 108
bit = bit or require("bit")
draw.RoundedBox = function(r, x, y, w, h, c) op("rrect", x, y, w, h, { c.r, c.g, c.b, c.a or 255 }, r, true, true, true, true) end
draw.RoundedBoxEx = function(r, x, y, w, h, c, tl, tr, bl, br) op("rrect", x, y, w, h, { c.r, c.g, c.b, c.a or 255 }, r, tl or false, tr or false, bl or false, br or false) end
-- text: measured with the real font (see pil_font)
local font = "BobbaChat"
surface.SetFont = function(f) font = f end
surface.GetTextSize = function(t) return PY_TEXT_SIZE(font, t) end
utf8 = utf8 or { len = function(t) local n = 0 for _ in t:gmatch("[^\128-\191]") do n = n + 1 end return n end }
TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, TEXT_ALIGN_RIGHT = 0, 3, 2
KEY_ENTER, KEY_PAD_ENTER = 64, 65
TEXFILTER = { POINT = "point", LINEAR = "linear" }
cam = { Start2D = function() end, End2D = function() end }
math.Clamp = function(v, a, b) return math.min(math.max(v, a), b) end
math.Round = function(v) return math.floor(v + 0.5) end
string.Trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local cursor = { 0, 0 }
KEY_LCONTROL, KEY_RCONTROL = 1, 2
CreateClientConVar = function(name, default) return { GetBool = function() return default == "1" end, GetInt = function() return tonumber(default) or 0 end, GetFloat = function() return tonumber(default) or 0 end, GetString = function() return default end, GetName = function() return name end } end
input = { GetCursorPos = function() return cursor[1], cursor[2] end, IsKeyDown = function() return false end, IsShiftDown = function() return false end, IsMouseDown = function() return false end }
gui = { EnableScreenClicker = function() end, IsGameUIVisible = function() return false end, IsConsoleVisible = function() return false end }
local hooks, cmds = {}, {}
-- (every hook by name and id, like GMod; G.run(name, ...) calls them)
local hookIds = {}
hook = { Add = function(name, id, fn) hooks[name] = fn hookIds[name] = hookIds[name] or {} hookIds[name][id] = fn end, Remove = function(name, id) if hookIds[name] then hookIds[name][id] = nil end end }
function G.run(name, ...) for _, fn in pairs(hookIds[name] or {}) do fn(...) end end
concommand = { Add = function(name, fn) cmds[name] = fn end }
IsValid = function(p) return p ~= nil and p.valid end
local registered = {}
-- a plain panel (EditablePanel and the like): where it is, how big, the mouse on it
local function plainPanel()
	local p = { valid = true, x = 0, y = 0, w = 0, h = 0, mouse = { 0, 0 }, visible = true }
	function p:SetVisible(v) self.visible = v and true or false end
	function p:IsVisible() return self.visible end
	function p:IsHovered() return self.hovered or false end
	function p:IsChildHovered() return false end
	function p:SetSize(w, h) self.w, self.h = w, h end
	function p:GetWide() return self.w end
	function p:GetTall() return self.h end
	function p:SetPos(x, y) self.x, self.y = x, y end
	function p:GetPos() return self.x, self.y end
	function p:Center() self.x, self.y = math.floor((SCREEN_W - self.w) / 2), math.floor((SCREEN_H - self.h) / 2) end
	function p:CursorPos() return self.mouse[1], self.mouse[2] end
	function p:LocalToScreen(x, y) return x, y end
	function p:Remove() self.valid = false end
	return setmetatable(p, { __index = function() return function() end end })
end
-- a text entry: what's typed (value), its placeholder, its margins inside its parent (Dock FILL)
local function textEntry(parent)
	local e = plainPanel()
	e.value, e.margin = "", { 0, 0, 0, 0 }
	function e:GetValue() return self.value end
	function e:SetText(t) self.value = t end
	function e:SetPlaceholderText(t) self.placeholder = t end
	function e:GetPlaceholderText() return self.placeholder or "" end
	function e:SetFont(f) self.font = f end
	function e:DockMargin(l, t, r, b) self.margin = { l, t, r, b } end
	function e:DrawTextEntryText(c) if self.value ~= "" then draw.SimpleText(self.value, self.font, 0, self.h / 2, c, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end end
	if parent then rawset(parent, "children", rawget(parent, "children") or {}) table.insert(rawget(parent, "children"), e) end
	e.isEntry = true
	-- (only methods GMod's DTextEntry has: calling anything else fails here as it does in the game)
	local GMOD = { SetMultiline = true, IsMultiline = true, SetUpdateOnType = true, SetPaintBackground = true, SetCaretPos = true,
		HasFocus = true, RequestFocus = true, KillFocus = true, Dock = true, SetMouseInputEnabled = true, SetKeyboardInputEnabled = true,
		SetDrawLanguageID = true, SetEditable = true, SetTextColor = true, SetCursorColor = true, SetHighlightColor = true, SelectAllOnFocus = true }
	setmetatable(e, { __index = function(_, k)
		if GMOD[k] then return function() end end
		error("DTextEntry has no " .. tostring(k), 2)
	end })
	return e
end
vgui = {
	GetKeyboardFocus = function() return nil end,
	Register = function(name, tbl) registered[name] = tbl end,
	Create = function(name, parent)
		if name == "EditablePanel" or name == "DPanel" then return plainPanel() end
		if name == "DTextEntry" then return textEntry(parent) end
		-- Derma's own panels (windows, buttons): they take any call and draw nothing here
		if not registered[name] then return setmetatable({ valid = true }, { __index = function() return function() return 0 end end }) end
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

# Fonts like GMod's: surface.CreateFont's size is the height of the font's letters from the top
# of its tallest to the bottom of its lowest (ascent + descent, Windows' cell height), so the font is
# drawn at size / (ascent + descent) em. Ubuntu Condensed comes from $BOBBA_FONTS (Ubuntu-C.ttf) when
# set; otherwise DejaVu Sans stands in.
FONTS = {}
_pil_cache = {}
def pil_font(name):
    from PIL import ImageFont
    f = FONTS.get(name, ("", 13, 500, False))
    key = f
    if key in _pil_cache: return _pil_cache[key]
    family, size, weight, italic = f
    files = []
    d = os.environ.get("BOBBA_FONTS")
    if d and family.lower() == "ubuntu condensed":
        # (the only file: bold is made from it, a pixel wider, like Windows does when a font has no bold)
        files.append(os.path.join(d, "Ubuntu-C.ttf"))
    elif d and family.lower() == "ubuntu":
        files.append(os.path.join(d, "Ubuntu-b.ttf" if weight >= 700 else ("Ubuntu-i.ttf" if italic else "Ubuntu.ttf")))
    files.append("DejaVuSans-Bold.ttf" if weight >= 700 else "DejaVuSans.ttf")
    font = None
    for path in files:
        try:
            probe = ImageFont.truetype(path, 1000)
            a, dsc = probe.getmetrics()
            font = ImageFont.truetype(path, max(1, round(size * 1000 / (a + dsc))))
            break
        except OSError:
            continue
    _pil_cache[key] = (font, size)
    return _pil_cache[key]

def faux_bold(name):
    f = FONTS.get(name)
    return f is not None and f[0].lower() == "ubuntu condensed" and f[2] >= 700

def text_size(name, t):
    font, size = pil_font(name)
    if font is None: return len(t) * 7, size
    return round(font.getlength(t)) + (1 if faux_bold(name) and t else 0), size

def boot(w, h):
    L = lj.LuaRuntime(unpack_returned_tuples=True)
    L.globals().PY_CREATE_FONT = lambda name, fam, size, weight, italic: FONTS.__setitem__(name, (fam, size, weight, italic))
    L.globals().PY_TEXT_SIZE = text_size
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
    L.execute(open(os.path.join(GM, "client", "chat.lua")).read())
    L.execute(open(os.path.join(GM, "client", "ui.lua")).read())
    L.execute(open(os.path.join(GM, "client", "avatareditor.lua")).read())
    L.execute(open(os.path.join(GM, "client", "loading.lua")).read())
    L.execute(open(os.path.join(GM, "client", "hud.lua")).read())
    L.execute(open(os.path.join(GM, "client", "navigator.lua")).read())
    L.execute(open(os.path.join(GM, "client", "windows.lua")).read())
    L.execute(open(os.path.join(GM, "client", "shop.lua")).read())
    L.execute(open(os.path.join(GM, "client", "furniwidgets.lua")).read())
    return L, G

def hud_click(L, G, spec):
    """Clicks on the toolbar, purse, room tools, "me" menu or a window: "name:x,y" in CSS px from its
    corner (name: toolbar, purse, roomtools, me, or a window's id)."""
    L.execute("if BOBBA.loading then BOBBA.loading.active = false end")
    name, xy = spec.split(":")
    x, y = map(float, xy.split(","))
    w = L.eval("BOBBA.ui.huds")[name] or L.eval("BOBBA.ui.windows")[name]
    if w is None: raise SystemExit("nothing called " + name + " to click")
    p = w.panel
    G.run("Think")
    s = L.eval("BOBBA.ui.scale()")
    p.mouse[1], p.mouse[2] = x * s, y * s
    G.ops = L.table()
    p.Paint(p, p.w, p.h)
    p.OnMousePressed(p, 107)
    G.ops = L.table()

def hud_type(L, G, win, box, text):
    """Types into a window's text box (its id in the window, e.g. navigator's "search" or "name")."""
    w = L.eval("BOBBA.ui.windows")[win]
    if w is None: raise SystemExit("no window " + win)
    p = w.panel
    G.ops = L.table()
    p.Paint(p, p.w, p.h)
    e = w.inputs[box] if w.inputs is not None else None
    if e is None: raise SystemExit("no text box " + box + " in " + win)
    e.value = text
    if e.OnValueChange: e.OnValueChange(e, text)
    G.ops = L.table()

def compose(L, G, picture, images):
    """What's over the room, like GMod's panels: the toolbar, purse, room tools and "me" menu
    (BOBBA.ui.huds), the chat input, then the windows; each painted on its own and put where it is."""
    picture = picture.convert("RGBA")
    def put(panel):
        if panel is None or not panel.valid or panel.visible is False: return
        G.ops = L.table()
        panel.Paint(panel, panel.w, panel.h)
        # text entries docked to fill it, inside their margins
        kids = panel.children
        if kids is not None:
            for i in range(1, len(kids) + 1):
                e = kids[i]
                if e.isEntry and e.Paint:
                    if e.visible is False: continue
                    m = e.margin
                    # (docked inside its margins, or put somewhere with SetPos)
                    if e.x or e.y:
                        ox, oy = e.x, e.y
                    else:
                        ox, oy = m[1], m[2]
                        e.w, e.h = panel.w - m[1] - m[3], panel.h - m[2] - m[4]
                    n = len(G.ops)
                    e.Paint(e, e.w, e.h)
                    for j in range(n + 1, len(G.ops) + 1):
                        o = G.ops[j]
                        if o[1] == "text": o[3], o[4] = o[3] + ox, o[4] + oy
        if panel.w and panel.h and panel.w > 0 and panel.h > 0:
            layer = paint(G, int(panel.w), int(panel.h), images, transparent=True)
            picture.alpha_composite(layer, (int(panel.x), int(panel.y)))
    # (a preview shows the room after the hotel's loading screen)
    L.execute("if BOBBA.loading then BOBBA.loading.active = false end")
    # (the room's name, shown by the room tools for 5 s after coming in: a second in)
    L.execute("BOBBA.hud.roomInfoShown = SysTime() - 1")
    G.run("Think")
    huds = L.eval("BOBBA.ui.huds")
    for name in ("roomtools", "purse", "toolbar", "me"):
        h = huds[name]
        if h is not None:
            # (laid out by the Think hook, as in GMod; a hidden panel's own Think never runs)
            # (a few frames: what it draws may load on the first)
            if h.panel.visible:
                for _ in range(3): h.panel.Paint(h.panel, h.panel.w, h.panel.h)
            put(h.panel)
    chat = L.eval("BOBBA.room.chatState")
    inp = L.eval("BOBBA.room.chatState.input") if chat is not None else None
    if inp is not None: put(inp)
    wins = L.eval("BOBBA.ui.windows")
    for k in list(wins.keys()):
        # (a few frames: what it draws may load on the first, like a furni's icon)
        pn = wins[k].panel
        for _ in range(3):
            G.ops = L.table()
            pn.Paint(pn, pn.w, pn.h)
        put(pn)
    return picture

def paint(G, w, h, images=None, transparent=False):
    base = Image.new("RGBA" if transparent else "RGB", (w, h), (0, 0, 0, 0) if transparent else (0, 0, 0))
    im = base
    d = ImageDraw.Draw(im, "RGBA")
    clip = None
    ops = G.ops
    for i in range(1, len(ops) + 1):
        o = ops[i]
        kind = o[1]
        if kind == "clip":
            # render.SetScissorRect: what's drawn until it's switched off (or another rectangle is
            # set, which replaces it) is kept inside the rectangle
            if clip:
                layer = im
                im = base
                d = ImageDraw.Draw(im, "RGBA")
                if clip[2] > clip[0] and clip[3] > clip[1]:
                    part = layer.crop(clip)
                    if im.mode == "RGBA": im.alpha_composite(part, (clip[0], clip[1]))
                    else: im.paste(part, (clip[0], clip[1]), part)
                clip = None
            if o[6]:
                clip = (int(o[2]), int(o[3]), int(o[4]), int(o[5]))
                im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
                d = ImageDraw.Draw(im, "RGBA")
            continue
        if kind == "rrect":
            x, y, rw, rh = o[2], o[3], o[4], o[5]
            if rw > 0 and rh > 0:
                r = max(0, min(int(o[7]), int(rw // 2), int(rh // 2)))
                col = tuple(o[6][j] for j in (1, 2, 3, 4))
                corners = (bool(o[8]), bool(o[9]), bool(o[11]), bool(o[10]))
                if im.mode == "RGBA" or col[3] < 255:
                    layer = Image.new("RGBA", (int(rw) + 1, int(rh) + 1), (0, 0, 0, 0))
                    ImageDraw.Draw(layer).rounded_rectangle([0, 0, int(rw) - 1, int(rh) - 1], radius=r, fill=col, corners=corners)
                    if im.mode == "RGBA": im.alpha_composite(layer, (int(x), int(y)))
                    else: im.paste(layer, (int(x), int(y)), layer)
                else:
                    d.rounded_rectangle([x, y, x + rw - 1, y + rh - 1], radius=r, fill=col, corners=corners)
            continue
        if kind == "clear":
            d.rectangle([0, 0, w, h], fill=(0, 0, 0))
        elif kind == "poly" and o[4] is not None and images is not None and o[4] in images:
            # a textured polygon: the picture mapped by its corners' u, v (pixel-sharp), times the colour
            n = len(o[2])
            P = [(o[2][j][1], o[2][j][2], o[2][j][3], o[2][j][4]) for j in range(1, n + 1)]
            pic = images[o[4]].convert("RGBA")
            (x0, y0, u0, v0), (x1, y1, u1, v1), (x2, y2, u2, v2) = P[0], P[1], P[2]
            det = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
            if det == 0: continue
            def solve(a0, a1, a2):
                # a = A*x + B*y + C through the three corners
                A = ((a1 - a0) * (y2 - y0) - (a2 - a0) * (y1 - y0)) / det
                B = ((x1 - x0) * (a2 - a0) - (x2 - x0) * (a1 - a0)) / det
                return A, B, a0 - A * x0 - B * y0
            Au, Bu, Cu = solve(u0 * pic.width, u1 * pic.width, u2 * pic.width)
            Av, Bv, Cv = solve(v0 * pic.height, v1 * pic.height, v2 * pic.height)
            bx0, by0 = int(min(p[0] for p in P)), int(min(p[1] for p in P))
            bx1, by1 = int(max(p[0] for p in P)) + 1, int(max(p[1] for p in P)) + 1
            bw, bh = bx1 - bx0, by1 - by0
            if bw <= 0 or bh <= 0: continue
            # sample at pixel centres, wrapping like a repeating texture
            import math
            out = Image.new("RGBA", (bw, bh))
            src = pic.load(); dst = out.load()
            c = o[3]
            for yy in range(bh):
                for xx in range(bw):
                    sx, sy = bx0 + xx + 0.5, by0 + yy + 0.5
                    tu = Au * sx + Bu * sy + Cu; tv = Av * sx + Bv * sy + Cv
                    r_, g_, b_, a_ = src[int(math.floor(tu)) % pic.width, int(math.floor(tv)) % pic.height]
                    dst[xx, yy] = ((r_ * c[1] + 127) // 255, (g_ * c[2] + 127) // 255, (b_ * c[3] + 127) // 255, a_)
            mask = Image.new("L", (bw, bh), 0)
            ImageDraw.Draw(mask).polygon([(p[0] - bx0, p[1] - by0) for p in P], fill=255)
            from PIL import ImageChops
            out.putalpha(ImageChops.multiply(out.getchannel("A"), mask))
            im.paste(out, (bx0, by0), out)
        elif kind == "poly":
            pts = [(o[2][j][1], o[2][j][2]) for j in range(1, len(o[2]) + 1)]
            d.polygon(pts, fill=tuple(o[3][j] for j in (1, 2, 3, 4)))
        elif kind == "rect":
            col = tuple(o[6][j] for j in (1, 2, 3, 4))
            if im.mode == "RGBA" and col[3] < 255 and o[4] > 0 and o[5] > 0:
                # (see-through over a see-through layer: blended, as GMod does)
                layer = Image.new("RGBA", (int(o[4]) + 1, int(o[5]) + 1), (0, 0, 0, 0))
                ImageDraw.Draw(layer).rectangle([0, 0, int(o[4]) - 1, int(o[5]) - 1], fill=col)
                im.alpha_composite(layer, (int(o[2]), int(o[3])))
            else:
                d.rectangle([o[2], o[3], o[2] + o[4] - 1, o[3] + o[5] - 1], fill=col)
        elif kind == "line":
            d.line([(o[2], o[3]), (o[4], o[5])], fill=tuple(o[6][j] for j in (1, 2, 3)))
        elif kind == "text":
            col = tuple(o[5][j] for j in (1, 2, 3, 4)) if o[5] is not None else (255, 255, 255, 255)
            fnt, size = pil_font(o[6]) if o[6] in FONTS else (None, 12)
            # GMod puts the top of the letters' cell at y (TEXT_ALIGN_TOP) or its middle (CENTER), x at
            # their left (LEFT), middle (CENTER) or right (RIGHT)
            y = o[4] - size / 2 if o[7] == 1 else (o[4] - size if o[7] == 4 else o[4])
            x = o[3]
            if o[8] in (1, 2):
                tw = text_size(o[6], o[2])[0] if o[6] in FONTS else len(o[2]) * 7
                x = x - tw / 2 if o[8] == 1 else x - tw
            d.text((x, y), o[2], fill=col, font=fnt, anchor="la")
            if o[6] in FONTS and faux_bold(o[6]): d.text((x + 1, y), o[2], fill=col, font=fnt, anchor="la")
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
                if o[10] == "add":
                    from PIL import ImageChops
                    a = pic.getchannel("A")
                    lit = Image.merge("RGB", [ImageChops.multiply(ch, a) for ch in pic.convert("RGB").split()])
                    box = (int(o[3]), int(o[4]), int(o[3]) + pw, int(o[4]) + ph)
                    im.paste(ImageChops.add(im.crop(box), lit), box)
                else:
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
