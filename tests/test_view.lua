-- client/view.lua against stand-ins for GMod's drawing, panel and input functions: checks it
-- calls them correctly (clockwise polygons, the room in the middle, working out positions only when needed).
local T = {}

local function fakeGmod()
	local G = { polys = {}, lines = {}, rects = 0, rtDraws = 0, hooks = {}, cmds = {}, cursor = { 960, 540 }, clicker = false }
	_G.ScrW = function() return 1920 end
	_G.ScrH = function() return 1080 end
	_G.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
	_G.color_white = Color(255, 255, 255)
	_G.RT_SIZE_LITERAL, _G.MATERIAL_RT_DEPTH_NONE, _G.IMAGE_FORMAT_RGBA8888, _G.MOUSE_LEFT = 1, 2, 3, 107
	_G.GetRenderTargetEx = function(name) return { GetName = function() return name end } end
	_G.CreateMaterial = function(name) return { name = name } end
	_G.surface = {
		CreateFont = function() end,
		SetDrawColor = function(r, g, b) G.color = type(r) == "table" and { r.r, r.g, r.b } or { r, g, b } end,
		DrawPoly = function(pts) G.polys[#G.polys + 1] = { pts = pts, color = G.color } end,
		DrawLine = function(x1, y1, x2, y2) G.lines[#G.lines + 1] = { x1, y1, x2, y2 } end,
		SetMaterial = function() end,
		DrawTexturedRect = function() G.rects = G.rects + 1 end,
		DrawRect = function() G.rects = G.rects + 1 end,
	}
	_G.draw = { NoTexture = function() end, SimpleText = function() end }
	_G.render = {
		PushRenderTarget = function() G.rtDraws = G.rtDraws + 1 G.inRT = true end,
		PopRenderTarget = function() G.inRT = false end,
		Clear = function() end,
	}
	_G.cam = { Start2D = function() end, End2D = function() end }
	_G.math.Clamp = function(v, a, b) return math.min(math.max(v, a), b) end
	_G.math.Round = function(v) return math.floor(v + 0.5) end
	_G.string.Trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	_G.KEY_LCONTROL, _G.KEY_RCONTROL = 1, 2
	G.cvars = {}
	_G.CreateClientConVar = function(name, default)
		G.cvars[name] = default
		return { GetBool = function() return G.cvars[name] == "1" end }
	end
	G.keys = {}
	_G.input = { GetCursorPos = function() return G.cursor[1], G.cursor[2] end, IsKeyDown = function(k) return G.keys[k] == true end }
	_G.gui = { EnableScreenClicker = function(b) G.clicker = b end }
	_G.hook = { Add = function(name, id, fn) G.hooks[name] = fn end }
	_G.concommand = { Add = function(name, fn) G.cmds[name] = fn end }
	_G.IsValid = function(p) return p ~= nil and p.valid end
	local registered = {}
	_G.vgui = {
		Register = function(name, tbl) registered[name] = tbl end,
		Create = function(name)
			local p = setmetatable({ valid = true, w = 0, h = 0 }, { __index = registered[name] })
			p.SetMouseInputEnabled = function() end
			p.SetKeyboardInputEnabled = function() end
			p.SetPos = function() end
			p.SetSize = function(self, w, h) self.w, self.h = w, h end
			p.GetWide = function(self) return self.w end
			p.GetTall = function(self) return self.h end
			p.SetVisible = function(self, v) self.visible = v end
			p.MouseCapture = function() end
			p:Init()
			return p
		end,
	}
	_G.print = function() end
	assert(loadfile(GM_ROOT .. "/client/view.lua"))()
	return G
end

local function area(pts)
	local a = 0
	for i = 1, #pts do
		local p, q = pts[i], pts[i % #pts + 1]
		a = a + (p.x * q.y - q.x * p.y)
	end
	return a
end

T["shows a room: clockwise polygons, in the middle of the screen, worked out once"] = function()
	local G = fakeGmod()
	local V = BOBBA.view
	G.cmds.bobba_preview(nil, nil, { "model_a" })
	eq(V.room ~= nil, true, "room shown")
	eq(G.clicker, true, "mouse visible")
	eq(G.hooks.RenderScene(), true, "GMod's world not drawn")
	V.panel:Paint(1920, 1080)
	local n = #G.polys
	local expected = 0
	local holes = BOBBA.rooms.holes(V.room)
	for _, p in ipairs(BOBBA.rooms.view(V.room, 64)) do
		expected = expected + (holes[p.index] and #BOBBA.rooms.planePieces(V.room, p.index) or 1)
	end
	eq(n, expected, "one polygon per visible plane, walls with the door hole in pieces")
	assert(expected > #BOBBA.rooms.view(V.room, 64), "model_a has a door hole")
	local minX, maxX, minY, maxY = 1e9, -1e9, 1e9, -1e9
	for _, p in ipairs(G.polys) do
		assert(area(p.pts) > 0, "clockwise")
		for _, q in ipairs(p.pts) do
			minX, maxX, minY, maxY = math.min(minX, q.x), math.max(maxX, q.x), math.min(minY, q.y), math.max(maxY, q.y)
		end
	end
	assert(math.abs((minX + maxX) / 2 - 960) <= 1 and math.abs((minY + maxY) / 2 - 540) <= 1, "centred: " .. minX .. " " .. maxX .. " " .. minY .. " " .. maxY)
	assert(maxX - minX > 1000, "zoomed in (double size) by default")
	-- the next frames draw the same polygons without working them out again
	V.panel:Paint(1920, 1080)
	V.panel:Paint(1920, 1080)
	eq(V.builds, 1, "positions worked out once")
	eq(#G.polys, n * 3, "drawn every frame")
	eq(G.rtDraws, 0, "no render target (GMod brightens those on HDR maps)")
end

T["mouse: hover a tile, click it, drag moves the room, scroll zooms"] = function()
	local G = fakeGmod()
	local V = BOBBA.view
	G.cmds.bobba_preview(nil, nil, { "model_a" })
	V.panel:Paint(1920, 1080)
	-- put the mouse on tile 5,6 of model_a
	local z = V.ZOOMS[V.zoom]
	local s = BOBBA.nitro.create(z.scale).screen(5, 6, 0)
	local b = V.bounds[z.scale]
	local ox = math.floor(960 - (b.minX + b.maxX) / 2 * z.mult)
	local oy = math.floor(540 - (b.minY + b.maxY) / 2 * z.mult)
	G.cursor = { ox + s[1] * z.mult, oy + s[2] * z.mult }
	V.panel:OnCursorMoved()
	eq(V.hover and (V.hover.tileX .. "," .. V.hover.tileY), "5,6", "hover")
	G.lines = {}
	V.panel:Paint(1920, 1080)
	eq(#G.lines, 4, "tile cursor drawn")
	local clicked
	BOBBA.events.on("roomClick", "test", function(h) clicked = h end)
	V.panel:OnMousePressed(MOUSE_LEFT)
	V.panel:OnMouseReleased(MOUSE_LEFT)
	eq(clicked and (clicked.tileX .. "," .. clicked.tileY), "5,6", "click")
	-- drag
	clicked = nil
	V.panel:OnMousePressed(MOUSE_LEFT)
	G.cursor = { G.cursor[1] + 100, G.cursor[2] + 40 }
	V.panel:OnCursorMoved()
	V.panel:OnMouseReleased(MOUSE_LEFT)
	eq(clicked, nil, "a drag is not a click")
	eq(V.panX .. "," .. V.panY, "100,40", "moved")
	eq(V.hover and (V.hover.tileX .. "," .. V.hover.tileY), "5,6", "same tile under the mouse after moving the room with it")
	local builds = V.builds
	V.panel:Paint(1920, 1080)
	eq(V.builds, builds + 1, "worked out again after moving")
	-- plain scrolling doesn't zoom (Habbo: Ctrl + scroll)
	V.panel:OnMouseWheeled(-1)
	eq(V.zoom, 3, "no zoom without Ctrl")
	G.keys[KEY_LCONTROL] = true
	-- zoom out twice, then no further
	V.panel:OnMouseWheeled(-1)
	V.panel:OnMouseWheeled(-1)
	V.panel:OnMouseWheeled(-1)
	eq(V.zoom, 1, "zoomed out")
	eq(V.panX .. "," .. V.panY, "25,10", "kept the same spot in the middle")
	V.panel:OnMouseWheeled(1)
	eq(V.zoom, 2)
	-- the player setting: scrolling alone zooms
	G.keys[KEY_LCONTROL] = nil
	G.cvars.bobba_zoom_with_ctrl = "0"
	V.panel:OnMouseWheeled(1)
	eq(V.zoom, 3, "plain scroll zooms when the setting is off")
end

T["preview next/prev go through every layout, off hides"] = function()
	local G = fakeGmod()
	local V = BOBBA.view
	local seen = {}
	G.cmds.bobba_preview(nil, nil, { "next" })
	for i = 1, 59 do
		seen[V.previewId] = true
		V.panel:Paint(1920, 1080)
		G.cmds.bobba_preview(nil, nil, { "next" })
	end
	local n = 0
	for _ in pairs(seen) do n = n + 1 end
	eq(n, 59, "all layouts shown")
	G.cmds.bobba_preview(nil, nil, { "off" })
	eq(V.room, nil, "hidden")
	eq(G.clicker, false, "mouse back to the game")
	eq(G.hooks.RenderScene(), nil, "GMod's world drawn again")
end

return T
