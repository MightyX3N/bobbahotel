-- The game's half of GMod's functions: drawing (surface, draw, render, Material, fonts), panels
-- (vgui: EditablePanel, DPanel, DLabel, DButton, DTextEntry and registered ones), input, sound.
-- require("bobba.gmod_client")(G) after bobba.gmod; then G.update(dt), G.draw() and the G.mouse*,
-- G.key*, G.text* functions take Love's events.

local FS = require("bobba.fs")
local ffi = require("ffi")
local lg = love.graphics

return function(G)
	local cfg = G.cfg

	-- --- numbers GMod gives names --------------------------------------------------------------
	TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, TEXT_ALIGN_BOTTOM = 0, 1, 2, 3, 4
	TEXFILTER = { NONE = 0, POINT = 1, LINEAR = 2, ANISOTROPIC = 3 }
	BLEND_ZERO, BLEND_ONE, BLEND_DST_COLOR, BLEND_ONE_MINUS_DST_COLOR, BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA = 0, 1, 2, 3, 4, 5
	BLEND_DST_ALPHA, BLEND_ONE_MINUS_DST_ALPHA, BLEND_SRC_ALPHA_SATURATE, BLEND_SRC_COLOR, BLEND_ONE_MINUS_SRC_COLOR = 6, 7, 8, 9, 10
	BLENDFUNC_ADD, BLENDFUNC_SUBTRACT, BLENDFUNC_REVERSE_SUBTRACT, BLENDFUNC_MIN, BLENDFUNC_MAX = 0, 1, 2, 3, 4
	NODOCK, FILL, LEFT, RIGHT, TOP, BOTTOM = 0, 1, 2, 3, 4, 5
	MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE, MOUSE_4, MOUSE_5, MOUSE_WHEEL_UP, MOUSE_WHEEL_DOWN = 107, 108, 109, 110, 111, 112, 113

	-- GMod's key numbers and Love's names for the keys
	local KEYS = {
		{ "KEY_0", 1, "0" }, { "KEY_1", 2, "1" }, { "KEY_2", 3, "2" }, { "KEY_3", 4, "3" }, { "KEY_4", 5, "4" },
		{ "KEY_5", 6, "5" }, { "KEY_6", 7, "6" }, { "KEY_7", 8, "7" }, { "KEY_8", 9, "8" }, { "KEY_9", 10, "9" },
		{ "KEY_PAD_0", 37, "kp0" }, { "KEY_PAD_1", 38, "kp1" }, { "KEY_PAD_2", 39, "kp2" }, { "KEY_PAD_3", 40, "kp3" },
		{ "KEY_PAD_4", 41, "kp4" }, { "KEY_PAD_5", 42, "kp5" }, { "KEY_PAD_6", 43, "kp6" }, { "KEY_PAD_7", 44, "kp7" },
		{ "KEY_PAD_8", 45, "kp8" }, { "KEY_PAD_9", 46, "kp9" }, { "KEY_PAD_DIVIDE", 47, "kp/" }, { "KEY_PAD_MULTIPLY", 48, "kp*" },
		{ "KEY_PAD_MINUS", 49, "kp-" }, { "KEY_PAD_PLUS", 50, "kp+" }, { "KEY_PAD_ENTER", 51, "kpenter" }, { "KEY_PAD_DECIMAL", 52, "kp." },
		{ "KEY_LBRACKET", 53, "[" }, { "KEY_RBRACKET", 54, "]" }, { "KEY_SEMICOLON", 55, ";" }, { "KEY_APOSTROPHE", 56, "'" },
		{ "KEY_BACKQUOTE", 57, "`" }, { "KEY_COMMA", 58, "," }, { "KEY_PERIOD", 59, "." }, { "KEY_SLASH", 60, "/" },
		{ "KEY_BACKSLASH", 61, "\\" }, { "KEY_MINUS", 62, "-" }, { "KEY_EQUAL", 63, "=" }, { "KEY_ENTER", 64, "return" },
		{ "KEY_SPACE", 65, "space" }, { "KEY_BACKSPACE", 66, "backspace" }, { "KEY_TAB", 67, "tab" }, { "KEY_CAPSLOCK", 68, "capslock" },
		{ "KEY_NUMLOCK", 69, "numlock" }, { "KEY_ESCAPE", 70, "escape" }, { "KEY_SCROLLLOCK", 71, "scrolllock" },
		{ "KEY_INSERT", 72, "insert" }, { "KEY_DELETE", 73, "delete" }, { "KEY_HOME", 74, "home" }, { "KEY_END", 75, "end" },
		{ "KEY_PAGEUP", 76, "pageup" }, { "KEY_PAGEDOWN", 77, "pagedown" }, { "KEY_BREAK", 78, "pause" },
		{ "KEY_LSHIFT", 79, "lshift" }, { "KEY_RSHIFT", 80, "rshift" }, { "KEY_LALT", 81, "lalt" }, { "KEY_RALT", 82, "ralt" },
		{ "KEY_LCONTROL", 83, "lctrl" }, { "KEY_RCONTROL", 84, "rctrl" }, { "KEY_LWIN", 85, "lgui" }, { "KEY_RWIN", 86, "rgui" },
		{ "KEY_APP", 87, "menu" }, { "KEY_UP", 88, "up" }, { "KEY_LEFT", 89, "left" }, { "KEY_DOWN", 90, "down" }, { "KEY_RIGHT", 91, "right" },
		{ "KEY_F1", 92, "f1" }, { "KEY_F2", 93, "f2" }, { "KEY_F3", 94, "f3" }, { "KEY_F4", 95, "f4" }, { "KEY_F5", 96, "f5" },
		{ "KEY_F6", 97, "f6" }, { "KEY_F7", 98, "f7" }, { "KEY_F8", 99, "f8" }, { "KEY_F9", 100, "f9" }, { "KEY_F10", 101, "f10" },
		{ "KEY_F11", 102, "f11" }, { "KEY_F12", 103, "f12" },
	}
	local codeToLove, loveToCode = {}, {}
	for i = 0, 25 do
		local ch = string.char(97 + i)
		KEYS[#KEYS + 1] = { "KEY_" .. ch:upper(), 11 + i, ch }
	end
	for _, k in ipairs(KEYS) do
		_G[k[1]] = k[2]
		codeToLove[k[2]] = k[3]
		loveToCode[k[3]] = k[2]
	end
	KEY_NONE, KEY_FIRST = 0, 0
	KEY_LBRACE, KEY_RBRACE = KEY_LBRACKET, KEY_RBRACKET
	G.loveToCode = loveToCode

	-- --- the screen -----------------------------------------------------------------------------
	-- (as GMod: while a render target is drawn into, the "screen" is that target)
	local rtStack = {}
	ScrW = function() local rt = rtStack[#rtStack] return rt and rt.w or lg.getWidth() end
	ScrH = function() local rt = rtStack[#rtStack] return rt and rt.h or lg.getHeight() end
	ScreenScale = function(n) return n * (lg.getWidth() / 640) end
	ScreenScaleH = function(n) return n * (lg.getHeight() / 480) end

	-- --- drawing state ------------------------------------------------------------------------------
	local S = {
		color = { 1, 1, 1, 1 },
		textColor = { 1, 1, 1, 1 },
		textX = 0, textY = 0,
		font = nil,
		material = nil, -- (a Material, or nil: no texture)
		filterMag = {}, filterMin = {},
		clip = nil, -- the panel being drawn's clip on screen: { x0, y0, x1, y1 }
		alpha = 1,
	}
	G.drawState = S

	local function setColor(r, g, b, a)
		if type(r) == "table" then r, g, b, a = r.r, r.g, r.b, r.a end
		S.color[1], S.color[2], S.color[3], S.color[4] = (r or 255) / 255, (g or 255) / 255, (b or 255) / 255, (a or 255) / 255
	end
	local function useColor(c)
		c = c or S.color
		lg.setColor(c[1], c[2], c[3], c[4] * S.alpha)
	end

	local function applyScissor(x0, y0, x1, y1)
		if not x0 then lg.setScissor() return end
		if x1 <= x0 or y1 <= y0 then lg.setScissor(0, 0, 0, 0) return end
		lg.setScissor(x0, y0, x1 - x0, y1 - y0)
	end
	G.applyScissor = applyScissor

	-- --- fonts ----------------------------------------------------------------------------------
	local fonts = {} -- name -> { font = LoveFont, bold, italic, size, h }
	local fileData = {}
	local cellRatio = {}
	local defaultFontData

	local function readFontFile(path)
		if fileData[path] ~= nil then return fileData[path] end
		local bytes = FS.read(path)
		fileData[path] = bytes and love.filesystem.newFileData(bytes, path:match("[^/]+$")) or false
		return fileData[path]
	end
	local windir = (os.getenv("WINDIR") or "C:/Windows"):gsub("\\", "/") .. "/Fonts/"
	local function systemFont(file)
		if FS.windows then return windir .. file end
		for _, d in ipairs({ "/usr/share/fonts/truetype/dejavu/", "/usr/share/fonts/TTF/", "/usr/share/fonts/dejavu/" }) do
			local p = d .. (file:find("b%.ttf$") and "DejaVuSans-Bold.ttf" or "DejaVuSans.ttf")
			if FS.exists(p) then return p end
		end
	end
	-- the file for a face name; bold: whether that file is bold already
	local function fontFile(face, bold)
		face = tostring(face or ""):lower()
		-- the phone's font: its weights are families of their own (as Windows sees them)
		local jakarta = { ["plus jakarta sans medium"] = "Medium", ["plus jakarta sans"] = bold and "Bold" or "Medium",
			["plus jakarta sans bold"] = "Bold", ["plus jakarta sans extrabold"] = "ExtraBold" }
		if jakarta[face] then
			local w = jakarta[face]
			local p = G.findPath("resource/fonts/PlusJakartaSans-" .. w .. ".ttf", "GAME")
			if p then return p, w ~= "Medium", false, true end
		end
		if face == "ubuntu condensed" or face == "ubuntu-c" then
			local p = G.findPath("resource/fonts/UbuntuCondensed-Regular.ttf", "GAME")
			if p then return p, false end
			return love.filesystem.getSource() .. "/fonts/UbuntuCondensed-Regular.ttf", false, true
		end
		local sys = {
			verdana = { "verdana.ttf", "verdanab.ttf" }, tahoma = { "tahoma.ttf", "tahomabd.ttf" },
			arial = { "arial.ttf", "arialbd.ttf" }, ["trebuchet ms"] = { "trebuc.ttf", "trebucbd.ttf" },
			["segoe ui"] = { "segoeui.ttf", "segoeuib.ttf" }, ["courier new"] = { "cour.ttf", "courbd.ttf" },
			roboto = { "arial.ttf", "arialbd.ttf" }, dermadefault = { "tahoma.ttf", "tahomabd.ttf" },
		}
		local s = sys[face] or { face .. ".ttf", face .. "bd.ttf" }
		if bold then
			local p = systemFont(s[2])
			if p and FS.exists(p) then return p, true end
		end
		local p = systemFont(s[1])
		if p and FS.exists(p) then return p, false end
		return nil, false
	end

	-- a font's whole height as Windows measures it (GMod's size is that): the OS/2 table's
	-- usWinAscent + usWinDescent over the em (FreeType's own ascent/descent can be smaller)
	local function winCell(bytes)
		if type(bytes) ~= "string" or #bytes < 12 then return nil end
		local function u16(o) return bytes:byte(o + 1) * 256 + bytes:byte(o + 2) end
		local function u32(o) return u16(o) * 65536 + u16(o + 2) end
		local n, head, os2 = u16(4), nil, nil
		for i = 0, n - 1 do
			local rec = 12 + i * 16
			local tag = bytes:sub(rec + 1, rec + 4)
			if tag == "head" then head = u32(rec + 8) elseif tag == "OS/2" then os2 = u32(rec + 8) end
		end
		if not head or not os2 then return nil end
		local em = u16(head + 18)
		if em == 0 then return nil end
		return (u16(os2 + 74) + u16(os2 + 76)) / em, u16(os2 + 74) / em
	end

	local function makeFont(path, gsize, fromGame, useWin)
		local data = path and (fromGame and nil or readFontFile(path))
		if fromGame then
			local ok, d = pcall(love.filesystem.newFileData, "fonts/UbuntuCondensed-Regular.ttf")
			data = ok and d or nil
		end
		local key = path or "default"
		if not cellRatio[key] then
			local ok, probe = pcall(function() return data and lg.newFont(data, 100) or lg.newFont(100) end)
			if ok then cellRatio[key] = (probe:getAscent() - probe:getDescent()) / 100 else cellRatio[key] = 1.2 end
			if useWin and path then cellRatio[key] = (winCell(FS.read(path))) or cellRatio[key] end
		end
		local em = math.max(1, math.floor(gsize / cellRatio[key] + 0.5))
		local ok, f = pcall(function()
			if data then return lg.newFont(data, em) end
			return lg.newFont(em)
		end)
		if not ok then f = lg.newFont(em) end
		return require("bobba.fallback").apply(f, em)
	end

	local surfaceFonts = {}
	local function createFont(name, data)
		data = data or {}
		local weight = data.weight or 500
		local wantBold = weight >= 600
		local path, isBold, fromGame, useWin = fontFile(data.font, wantBold)
		local size = math.max(4, math.floor(tonumber(data.size) or 13))
		local f = makeFont(path, size, fromGame, useWin)
		f:setFilter("linear", "linear")
		fonts[name] = {
			font = f,
			-- (no bold file: drawn twice, a pixel apart, like Windows makes bold)
			bold = (wantBold and not isBold) and 1 or 0,
			italic = data.italic and true or false,
			outline = data.outline and true or false,
			size = size,
		}
		-- (Windows' measure: the whole height is the size, the letters as far down as its ascent)
		if useWin and path then
			local cell, asc = winCell(FS.read(path))
			if cell then
				local em = size / cell
				fonts[name].h = size
				fonts[name].dy = math.floor(asc * em - f:getAscent() + 0.5)
			end
		end
	end
	local defaultFont
	local function fontOf(name)
		local f = fonts[name or "DermaDefault"]
		if f then return f end
		if not defaultFont then
			createFont("DermaDefault", { font = "Tahoma", size = 13, weight = 500 })
			createFont("DermaDefaultBold", { font = "Tahoma", size = 13, weight = 800 })
			createFont("DermaLarge", { font = "Roboto", size = 32, weight = 500 })
			createFont("Default", { font = "Tahoma", size = 13, weight = 500 })
			defaultFont = fonts.DermaDefault
		end
		return fonts[name] or defaultFont
	end
	G.fontOf = fontOf

	-- width and height of text in a font (several lines: the widest, all lines' height)
	local function textSize(text, fname)
		local f = fontOf(fname)
		text = tostring(text or "")
		local h = f.h or f.font:getHeight()
		if not text:find("\n", 1, true) then
			if text == "" then return 0, h end
			return f.font:getWidth(text) + f.bold, h
		end
		local w, n = 0, 0
		for line in (text .. "\n"):gmatch("(.-)\n") do
			n = n + 1
			local lw = f.font:getWidth(line)
			if lw > w then w = lw end
		end
		return w + f.bold, h * n
	end
	G.textSize = textSize

	local function printText(text, fname, x, y, c)
		local f = fontOf(fname)
		useColor(c)
		lg.setFont(f.font)
		if f.italic then
			lg.push()
			lg.translate(x, y + f.font:getHeight())
			lg.shear(-0.2, 0)
			lg.print(text, 0, -f.font:getHeight())
			if f.bold > 0 then lg.print(text, f.bold, -f.font:getHeight()) end
			lg.pop()
			return
		end
		y = y + (f.dy or 0)
		lg.print(text, x, y)
		for i = 1, f.bold do lg.print(text, x + i, y) end
	end
	G.printText = printText

	-- --- materials --------------------------------------------------------------------------------
	local matMeta = {}
	matMeta.__index = matMeta
	local materials = {}
	-- where a material's picture is on the computer
	local function materialPath(name)
		name = name:gsub("\\", "/")
		if name:sub(1, 8) == "../data/" then return G.dataPath(name:sub(9)) end
		if name:sub(1, 3) == "../" then return G.findPath(name:sub(4), "GAME") end
		if not name:find("%.%w+$") then name = name .. ".png" end
		return G.findPath("materials/" .. name, "GAME")
	end
	function matMeta:load()
		if self.image then return self.image end
		local now = love.timer.getTime()
		if self.tried and now - self.tried < 1 then return nil end
		self.tried = now
		local p = materialPath(self.name)
		local bytes = p and FS.read(p)
		if not bytes then return nil end
		local ok, img = pcall(function()
			local data = love.image.newImageData(love.filesystem.newFileData(bytes, "m.png"))
			return lg.newImage(data)
		end)
		if not ok then return nil end
		if self.flags:find("noclamp", 1, true) then img:setWrap("repeat", "repeat") else img:setWrap("clamp", "clamp") end
		self.smooth = self.flags:find("smooth", 1, true) ~= nil
		local f = self.smooth and "linear" or "nearest"
		img:setFilter(f, f)
		self.filter = f .. f
		self.image = img
		return img
	end
	function matMeta:Width() local i = self:load() return i and i:getWidth() or 0 end
	function matMeta:Height() local i = self:load() return i and i:getHeight() or 0 end
	function matMeta:IsError() return self:load() == nil end
	function matMeta:GetName() return self.name end
	function matMeta:GetTexture() return setmetatable({}, { __index = function(_, k) return function() return k == "Width" and self:Width() or (k == "Height" and self:Height() or nil) end end }) end
	function matMeta:GetInt() return 0 end
	function matMeta:GetFloat() return 0 end
	function matMeta:GetString() return "" end
	function matMeta:SetInt() end
	function matMeta:SetFloat() end
	function matMeta:SetTexture() end
	function matMeta:Recompute() end
	function matMeta:GetShader() return "UnlitGeneric" end
	Material = function(name, flags)
		name = tostring(name or "")
		local key = name .. "|" .. tostring(flags or "")
		local m = materials[key]
		if not m then
			m = setmetatable({ name = name, flags = tostring(flags or "") }, matMeta)
			materials[key] = m
		end
		m:load()
		return m, 0
	end
	-- (pictures change on disk while the game runs: a new download replaces one)
	function G.forgetMaterial(name)
		for k, m in pairs(materials) do if m.name == name then materials[k] = nil end end
	end

	local function currentImage()
		local m = S.material
		if not m then return nil end
		local img = m:load()
		if not img then return nil end
		local mag = S.filterMag[#S.filterMag]
		local min = S.filterMin[#S.filterMin]
		local base = m.smooth and "linear" or "nearest"
		local fMag = mag == TEXFILTER.POINT and "nearest" or ((mag == TEXFILTER.LINEAR or mag == TEXFILTER.ANISOTROPIC) and "linear" or base)
		local fMin = min == TEXFILTER.POINT and "nearest" or ((min == TEXFILTER.LINEAR or min == TEXFILTER.ANISOTROPIC) and "linear" or base)
		local want = fMin .. fMag
		if m.filter ~= want then img:setFilter(fMin, fMag) m.filter = want end
		return img
	end

	-- --- blending (GL's own blend functions, for the furni's ink and the mood light) -------------
	local glBlend
	do
		ffi.cdef [[ void* SDL_GL_GetProcAddress(const char* proc); ]]
		local ok, fn = pcall(function()
			local sdl = ffi.os == "Windows" and ffi.load("SDL2") or ffi.C
			local p = sdl.SDL_GL_GetProcAddress("glBlendFuncSeparate")
			if p == nil then return nil end
			return ffi.cast("void (*)(uint32_t, uint32_t, uint32_t, uint32_t)", p)
		end)
		if ok and fn then glBlend = fn end
	end
	local GL = { [0] = 0, 1, 0x0306, 0x0307, 0x0302, 0x0303, 0x0304, 0x0305, 0x0308, 0x0300, 0x0301 }
	local blendOverride = false

	-- --- surface -----------------------------------------------------------------------------------
	local quad = lg.newQuad(0, 0, 1, 1, 1, 1)
	local mesh, meshSize
	local function polyMesh(n)
		if not mesh or meshSize < n then
			meshSize = math.max(64, n)
			mesh = lg.newMesh(meshSize, "fan", "stream")
		end
		return mesh
	end

	surface = {}
	surface.SetDrawColor = setColor
	surface.GetDrawColor = function() return Color(S.color[1] * 255, S.color[2] * 255, S.color[3] * 255, S.color[4] * 255) end
	surface.SetAlphaMultiplier = function(a) S.alpha = a end
	surface.GetAlphaMultiplier = function() return S.alpha end
	surface.SetMaterial = function(m) S.material = m end
	surface.SetTexture = function(id) S.material = nil end
	surface.GetTextureID = function() return 0 end
	surface.DrawRect = function(x, y, w, h)
		w, h = math.floor(w), math.floor(h)
		if w <= 0 or h <= 0 then return end
		useColor()
		lg.rectangle("fill", math.floor(x), math.floor(y), w, h)
	end
	surface.DrawOutlinedRect = function(x, y, w, h, t)
		t = t or 1
		surface.DrawRect(x, y, w, t)
		surface.DrawRect(x, y + h - t, w, t)
		surface.DrawRect(x, y + t, t, h - 2 * t)
		surface.DrawRect(x + w - t, y + t, t, h - 2 * t)
	end
	surface.DrawLine = function(x0, y0, x1, y1)
		useColor()
		lg.setLineWidth(1)
		lg.setLineStyle("rough")
		lg.line(math.floor(x0) + 0.5, math.floor(y0) + 0.5, math.floor(x1) + 0.5, math.floor(y1) + 0.5)
	end
	surface.DrawTexturedRectUV = function(x, y, w, h, u0, v0, u1, v1)
		local img = currentImage()
		if not img then
			if not S.material then surface.DrawRect(x, y, w, h) end
			return
		end
		x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
		if w == 0 or h == 0 then return end
		local iw, ih = img:getDimensions()
		local fx, fy = u0 > u1, v0 > v1
		local ua, ub = math.min(u0, u1), math.max(u0, u1)
		local va, vb = math.min(v0, v1), math.max(v0, v1)
		local vw, vh = (ub - ua) * iw, (vb - va) * ih
		if vw <= 0 or vh <= 0 then return end
		quad:setViewport(ua * iw, va * ih, vw, vh, iw, ih)
		useColor()
		local sx, sy = w / vw, h / vh
		lg.draw(img, quad, fx and (x + w) or x, fy and (y + h) or y, 0, fx and -sx or sx, fy and -sy or sy)
	end
	surface.DrawTexturedRect = function(x, y, w, h) surface.DrawTexturedRectUV(x, y, w, h, 0, 0, 1, 1) end
	surface.DrawTexturedRectRotated = function(x, y, w, h, rot)
		local img = currentImage()
		useColor()
		if not img then
			lg.push()
			lg.translate(x, y)
			lg.rotate(-math.rad(rot or 0))
			lg.rectangle("fill", -w / 2, -h / 2, w, h)
			lg.pop()
			return
		end
		local iw, ih = img:getDimensions()
		lg.draw(img, x, y, -math.rad(rot or 0), w / iw, h / ih, iw / 2, ih / 2)
	end
	-- (GMod only fills polygons given clockwise on screen)
	surface.DrawPoly = function(pts)
		local n = #pts
		if n < 3 then return end
		local area = 0
		for i = 1, n do
			local a, b = pts[i], pts[i % n + 1]
			area = area + (a.x * b.y - b.x * a.y)
		end
		if area <= 0 then return end
		local img = currentImage()
		if S.material and not img then return end
		local c = S.color
		local r, g, b, a = c[1], c[2], c[3], c[4] * S.alpha
		local verts = {}
		for i = 1, n do
			local p = pts[i]
			verts[i] = { p.x, p.y, p.u or 0, p.v or 0, r, g, b, a }
		end
		local m = polyMesh(n)
		m:setVertices(verts)
		m:setDrawRange(1, n)
		if img then m:setTexture(img) else m:setTexture() end
		lg.setColor(1, 1, 1, 1)
		lg.draw(m)
	end
	surface.CreateFont = createFont
	surface.SetFont = function(name) S.font = name end
	surface.GetTextSize = function(t) return textSize(t, S.font) end
	surface.SetTextColor = function(r, g, b, a)
		if type(r) == "table" then r, g, b, a = r.r, r.g, r.b, r.a end
		S.textColor = { (r or 255) / 255, (g or 255) / 255, (b or 255) / 255, (a or 255) / 255 }
	end
	surface.SetTextPos = function(x, y) S.textX, S.textY = math.ceil(x), math.ceil(y) end
	surface.GetTextPos = function() return S.textX, S.textY end
	surface.DrawText = function(t)
		t = tostring(t or "")
		printText(t, S.font, S.textX, S.textY, S.textColor)
		S.textX = S.textX + textSize(t, S.font)
	end
	surface.PlaySound = function(path)
		if sound and sound.PlayFile then sound.PlayFile("sound/" .. path, "", function(ch) if IsValid(ch) then ch:Play() end end) end
	end
	surface.ScreenWidth = ScrW
	surface.ScreenHeight = ScrH
	surface.DisableClipping = function() return false end

	-- --- draw ---------------------------------------------------------------------------------------
	-- rounded corners: a quarter circle with soft edges, stretched to the corner's size (like GMod's
	-- gui/cornerN textures)
	local cornerImage
	local function corner()
		if cornerImage then return cornerImage end
		local N = 64
		local d = love.image.newImageData(N, N)
		for y = 0, N - 1 do
			for x = 0, N - 1 do
				-- the circle's centre is at the image's bottom-right
				local dx, dy = N - (x + 0.5), N - (y + 0.5)
				local dist = math.sqrt(dx * dx + dy * dy)
				local a = math.min(1, math.max(0, N - dist + 0.5))
				d:setPixel(x, y, 1, 1, 1, a)
			end
		end
		cornerImage = lg.newImage(d)
		cornerImage:setFilter("linear", "linear")
		return cornerImage
	end
	draw = {}
	draw.NoTexture = function() S.material = nil end
	draw.RoundedBoxEx = function(r, x, y, w, h, c, tl, tr, bl, br)
		x, y, w, h = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(w + 0.5), math.floor(h + 0.5)
		if w <= 0 or h <= 0 then return end
		setColor(c)
		useColor()
		r = math.min(math.floor(r + 0.5), math.floor(w / 2), math.floor(h / 2))
		if r <= 0 then lg.rectangle("fill", x, y, w, h) return end
		lg.rectangle("fill", x + r, y, w - r * 2, h)
		lg.rectangle("fill", x, y + r, r, h - r * 2)
		lg.rectangle("fill", x + w - r, y + r, r, h - r * 2)
		local img = corner()
		local s = r / img:getWidth()
		if tl then lg.draw(img, x, y, 0, s, s) else lg.rectangle("fill", x, y, r, r) end
		if tr then lg.draw(img, x + w, y, 0, -s, s) else lg.rectangle("fill", x + w - r, y, r, r) end
		if bl then lg.draw(img, x, y + h, 0, s, -s) else lg.rectangle("fill", x, y + h - r, r, r) end
		if br then lg.draw(img, x + w, y + h, 0, -s, -s) else lg.rectangle("fill", x + w - r, y + h - r, r, r) end
	end
	draw.RoundedBox = function(r, x, y, w, h, c) draw.RoundedBoxEx(r, x, y, w, h, c, true, true, true, true) end
	local function colorArr(c)
		if not c then return { 1, 1, 1, 1 } end
		return { (c.r or 255) / 255, (c.g or 255) / 255, (c.b or 255) / 255, (c.a or 255) / 255 }
	end
	draw.SimpleText = function(text, font, x, y, c, xa, ya)
		text = tostring(text or "")
		font = font or "DermaDefault"
		local w, h = textSize(text, font)
		x, y = x or 0, y or 0
		if xa == TEXT_ALIGN_CENTER then x = x - w / 2 elseif xa == TEXT_ALIGN_RIGHT then x = x - w end
		if ya == TEXT_ALIGN_CENTER then y = y - h / 2 elseif ya == TEXT_ALIGN_BOTTOM then y = y - h end
		printText(text, font, math.ceil(x), math.ceil(y), colorArr(c))
		return w, h
	end
	draw.Text = function(t)
		return draw.SimpleText(t.text, t.font, t.pos and t.pos[1], t.pos and t.pos[2], t.color, t.xalign, t.yalign)
	end
	draw.SimpleTextOutlined = function(text, font, x, y, c, xa, ya, ow, oc)
		ow = math.floor(ow or 1)
		for dx = -ow, ow do
			for dy = -ow, ow do
				if dx ~= 0 or dy ~= 0 then draw.SimpleText(text, font, x + dx, y + dy, oc, xa, ya) end
			end
		end
		return draw.SimpleText(text, font, x, y, c, xa, ya)
	end
	draw.DrawText = function(text, font, x, y, c, xa)
		text = tostring(text or "")
		local f = fontOf(font)
		local lh = f.h or f.font:getHeight()
		local i = 0
		for line in (text .. "\n"):gmatch("(.-)\n") do
			draw.SimpleText(line, font, x, y + i * lh, c, xa, TEXT_ALIGN_TOP)
			i = i + 1
		end
	end
	draw.GetFontHeight = function(font) local f = fontOf(font) return f.h or f.font:getHeight() end
	draw.WordBox = function(b, x, y, text, font, bc, tc)
		local w, h = textSize(text, font)
		draw.RoundedBox(4, x, y, w + b * 2, h + b * 2, bc)
		draw.SimpleText(text, font, x + b, y + b, tc)
		return w + b * 2, h + b * 2
	end

	-- --- render -----------------------------------------------------------------------------------
	render = {}
	render.SetScissorRect = function(x0, y0, x1, y1, on)
		local c = S.clip
		if not on then
			if c then applyScissor(c[1], c[2], c[3], c[4]) else applyScissor() end
			return
		end
		if c then x0, y0, x1, y1 = math.max(x0, c[1]), math.max(y0, c[2]), math.min(x1, c[3]), math.min(y1, c[4]) end
		applyScissor(x0, y0, x1, y1)
	end
	render.PushFilterMag = function(f) S.filterMag[#S.filterMag + 1] = f end
	render.PushFilterMin = function(f) S.filterMin[#S.filterMin + 1] = f end
	render.PopFilterMag = function() S.filterMag[#S.filterMag] = nil end
	render.PopFilterMin = function() S.filterMin[#S.filterMin] = nil end
	render.OverrideBlend = function(on, src, dst, op, srcA, dstA)
		lg.flushBatch()
		if not on then
			if blendOverride then
				-- (Love sends its blend state again only when it changes)
				lg.setBlendMode("replace")
				lg.setBlendMode("alpha")
				blendOverride = false
			end
			return
		end
		blendOverride = true
		if glBlend then
			lg.setBlendMode("alpha", "premultiplied")
			glBlend(GL[src] or 1, GL[dst] or 0, GL[srcA or src] or 1, GL[dstA or dst] or 0)
			return
		end
		-- (without GL: Love's own nearest ones)
		if src == BLEND_DST_COLOR then lg.setBlendMode("multiply", "premultiplied")
		elseif dst == BLEND_ONE then lg.setBlendMode("add")
		else lg.setBlendMode("screen", "premultiplied") end
	end
	render.Clear = function(r, g, b, a) lg.clear((r or 0) / 255, (g or 0) / 255, (b or 0) / 255, (a or 255) / 255) end
	render.ClearDepth = function() end
	-- render targets, as GMod's (the camera's pictures draw into one, after the frame: PostRender)
	local rts = {}
	GetRenderTargetEx = function(name, w, h)
		local rt = rts[name]
		if not rt then rt = { name = name, w = w, h = h, canvas = lg.newCanvas(w, h) } rts[name] = rt end
		return rt
	end
	GetRenderTarget = function(name, w, h) return GetRenderTargetEx(name, w, h) end
	render.PushRenderTarget = function(rt)
		lg.flushBatch()
		lg.push("all")
		rtStack[#rtStack + 1] = { rt = rt, w = rt.w, h = rt.h, clip = S.clip }
		S.clip = nil
		lg.setCanvas(rt.canvas)
		lg.origin()
		lg.setScissor()
	end
	render.PopRenderTarget = function()
		local top = table.remove(rtStack)
		lg.pop()
		if top then S.clip = top.clip end
	end
	render.Capture = function(opts)
		local top = rtStack[#rtStack]
		if not top then return nil end
		local c = top.rt.canvas
		lg.setCanvas()
		local data = c:newImageData(nil, 1, opts.x or 0, opts.y or 0, opts.w or top.w, opts.h or top.h)
		lg.setCanvas(c)
		return data:encode("png"):getString()
	end
	render.OverrideAlphaWriteEnable = function() end
	render.SetStencilEnable = function() end
	Vector = Vector or function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
	Matrix = Matrix or function()
		local m = { t = love.math.newTransform() }
		function m:Translate(v) self.t:translate(v.x, v.y) end
		function m:Scale(v) self.t:scale(v.x, v.y) end
		return m
	end

	render.SetColorModulation = function() end
	render.SetBlend = function() end
	render.GetBlend = function() return 1 end
	render.SetMaterial = surface.SetMaterial
	render.SupportsHDR = function() return false end
	cam = { Start2D = function() end, End2D = function() end, Start3D = function() end, End3D = function() end, IgnoreZ = function() end,
		PushModelMatrix = function(m) lg.push() lg.applyTransform(m.t) end, PopModelMatrix = function() lg.pop() end }

	-- --- input ------------------------------------------------------------------------------------
	local mouseButtons = { [MOUSE_LEFT] = 1, [MOUSE_RIGHT] = 2, [MOUSE_MIDDLE] = 3, [MOUSE_4] = 4, [MOUSE_5] = 5 }
	input = {}
	input.GetCursorPos = function() return love.mouse.getPosition() end
	input.SetCursorPos = function(x, y) love.mouse.setPosition(x, y) end
	input.IsMouseDown = function(code) local b = mouseButtons[code] return b and love.mouse.isDown(b) or false end
	input.IsKeyDown = function(code)
		local k = codeToLove[code]
		if not k then return false end
		local ok, d = pcall(love.keyboard.isDown, k)
		return ok and d or false
	end
	input.IsButtonDown = function(code) return input.IsKeyDown(code) or input.IsMouseDown(code) end
	input.IsShiftDown = function() return love.keyboard.isDown("lshift", "rshift") end
	input.IsControlDown = function() return love.keyboard.isDown("lctrl", "rctrl") end
	input.WasKeyPressed = function() return false end
	input.LookupBinding = function() return nil end
	input.GetKeyName = function(code) return codeToLove[code] end
	gui = {}
	gui.EnableScreenClicker = function() end
	gui.IsGameUIVisible = function() return false end
	gui.IsConsoleVisible = function() return G.consoleOpen and G.consoleOpen() or false end
	gui.MousePos = function() return love.mouse.getPosition() end
	gui.MouseX = function() return (love.mouse.getX()) end
	gui.MouseY = function() return (love.mouse.getY()) end
	gui.OpenURL = function(url) love.system.openURL(url) end
	gui.ActivateGameUI = function() end
	gui.HideGameUI = function() end

	-- --- sound --------------------------------------------------------------------------------------
	local chMeta = {}
	chMeta.__index = chMeta
	function chMeta:IsValid() return self.src ~= nil end
	function chMeta:Play() if self.src then pcall(self.src.play, self.src) end end
	function chMeta:Pause() if self.src then self.src:pause() end end
	function chMeta:Stop() if self.src then self.src:stop() end end
	function chMeta:SetVolume(v) if self.src then self.src:setVolume(math.max(0, math.min(1, v))) end end
	function chMeta:GetVolume() return self.src and self.src:getVolume() or 0 end
	function chMeta:SetPlaybackRate(r) if self.src and r > 0 then self.src:setPitch(r) end end
	function chMeta:GetPlaybackRate() return self.src and self.src:getPitch() or 1 end
	function chMeta:EnableLooping(on) if self.src then self.src:setLooping(on) end end
	function chMeta:GetState() if not self.src then return 0 end return self.src:isPlaying() and 1 or 0 end
	function chMeta:GetLength() return self.src and self.src:getDuration() or 0 end
	function chMeta:GetTime() return self.src and self.src:tell() or 0 end
	function chMeta:SetTime(t) if self.src then self.src:seek(t) end end
	function chMeta:Set3DEnabled() end
	function chMeta:SetPos() end
	local function channelFrom(bytes, name, flags, cb)
		local ok, src = pcall(function()
			return love.audio.newSource(love.filesystem.newFileData(bytes, name), "static")
		end)
		local ch = ok and setmetatable({ src = src }, chMeta) or nil
		timer.Simple(0, function()
			if ch then
				if not tostring(flags or ""):find("noplay", 1, true) then ch:Play() end
				cb(ch)
			else
				cb(nil, 2, "can't play " .. name)
			end
		end)
	end
	sound = {}
	sound.PlayFile = function(path, flags, cb)
		cb = cb or function() end
		local p = G.findPath(path, "GAME")
		if not p and path:lower():sub(1, 5) == "data/" then p = G.dataPath(path:sub(6)) end
		local bytes = p and FS.read(p)
		if not bytes then timer.Simple(0, function() cb(nil, 2, "no file " .. path) end) return end
		channelFrom(bytes, path:match("[^/]+$") or "sound.mp3", flags, cb)
	end
	sound.PlayURL = function(url, flags, cb)
		cb = cb or function() end
		http.Fetch(url, function(body) channelFrom(body, url:match("[^/?]+%.%w+") or "sound.mp3", flags, cb) end, function(err) cb(nil, 2, err) end)
	end
	sound.Add = function() end
	sound.Play = function() end

	chat = {
		AddText = function(...)
			local color, parts = nil, {}
			for i = 1, select("#", ...) do
				local v = select(i, ...)
				if type(v) == "table" and v.r then color = v else parts[#parts + 1] = tostring(v) end
			end
			G.out(table.concat(parts) .. "\n", color)
		end,
		PlaySound = function() end,
		GetChatBoxPos = function() return 0, 0 end,
		GetChatBoxSize = function() return 0, 0 end,
		Open = function() end, Close = function() end,
	}
	notification = { AddLegacy = function(t) G.out(tostring(t) .. "\n") end, AddProgress = function() end, Kill = function() end }
	LocalPlayer = function() if G.player.valid then return G.player end return NULL end
	language = { GetPhrase = function(s) return s end, Add = function() end }

	require("bobba.vgui")(G)
	return G
end
