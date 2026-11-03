-- The room on screen (client). The planes come from BOBBA.rooms (Nitro's own geometry, camera and
-- sorting); this file only draws them and handles the mouse:
--   scroll = zoom (Habbo's 32 and 64, and 64 shown at double size), drag = move the room,
--   click = a tile (walking comes with the server rooms).
-- The planes' screen positions and colours are worked out once and only again when something
-- changes (moving, zooming, another room); each frame just draws them (a room has 60-350 planes).
-- (Not drawn through a render target: GMod brightens those on HDR maps, and colours must be exact.)

BOBBA.view = BOBBA.view or {}
local V = BOBBA.view

V.ZOOMS = {
	{ scale = 32, mult = 1 },
	{ scale = 64, mult = 1 },
	{ scale = 64, mult = 2 },
}
V.zoom = V.zoom or #V.ZOOMS -- rooms open fully zoomed in
V.panX, V.panY = V.panX or 0, V.panY or 0

local BACKGROUND = Color(0, 0, 0)
local CURSOR = Color(255, 255, 255)

surface.CreateFont("BobbaViewLabel", { font = "Tahoma", size = 13, weight = 700 })

-- ---------------------------------------------------------------------------------------------
-- Where things are

local function zoomInfo()
	return V.ZOOMS[V.zoom]
end

-- the room's origin on screen (pixel), so the room's middle is in the middle of the screen
local function origin()
	local z = zoomInfo()
	local b = V.bounds[z.scale]
	local cx = (b.minX + b.maxX) / 2 * z.mult
	local cy = (b.minY + b.maxY) / 2 * z.mult
	return math.floor(ScrW() / 2 - cx + V.panX), math.floor(ScrH() / 2 - cy + V.panY)
end

local function boundsOf(view)
	local b = { minX = 0, maxX = 0, minY = 0, maxY = 0 }
	local first = true
	for _, p in ipairs(view) do
		for _, c in ipairs({ p.a, p.b, p.c, p.d }) do
			if first then
				b.minX, b.maxX, b.minY, b.maxY = c[1], c[1], c[2], c[2]
				first = false
			else
				b.minX, b.maxX = math.min(b.minX, c[1]), math.max(b.maxX, c[1])
				b.minY, b.maxY = math.min(b.minY, c[2]), math.max(b.maxY, c[2])
			end
		end
	end
	return b
end

-- the screen point (mouse) in the room's pixel space at the current zoom
local function toRoom(sx, sy)
	local ox, oy = origin()
	local m = zoomInfo().mult
	return (sx - ox) / m, (sy - oy) / m
end

-- ---------------------------------------------------------------------------------------------
-- Drawing

-- surface.DrawPoly only fills polygons given clockwise on screen
local function clockwise(pts)
	local area = 0
	for i = 1, #pts do
		local a, b = pts[i], pts[i % #pts + 1]
		area = area + (a.x * b.y - b.x * a.y)
	end
	if area < 0 then
		local r = {}
		for i = #pts, 1, -1 do r[#r + 1] = pts[i] end
		return r
	end
	return pts
end

local STYLE_FOR = { [1] = "floor", [2] = "wall", [3] = "landscape" }

function V.styleFor(kind)
	local id = (V.styles and V.styles[kind]) or ("default_" .. kind)
	return BOBBA.registry.get("plane_style", id) or BOBBA.registry.get("plane_style", "default_" .. kind)
end

-- the planes as screen polygons with their colours, deepest first (like Nitro's RoomSpriteCanvas)
local function buildPolys()
	local z = zoomInfo()
	local view = BOBBA.rooms.view(V.room, z.scale)
	local ox, oy = origin()
	local m = z.mult
	local polys = {}
	for i, p in ipairs(view) do
		local style = V.styleFor(STYLE_FOR[p.type])
		local r, g, b = BOBBA.rooms.planeColor(style, p.color)
		polys[i] = {
			r = r, g = g, b = b,
			pts = clockwise({
				{ x = ox + p.a[1] * m, y = oy + p.a[2] * m },
				{ x = ox + p.b[1] * m, y = oy + p.b[2] * m },
				{ x = ox + p.c[1] * m, y = oy + p.c[2] * m },
				{ x = ox + p.d[1] * m, y = oy + p.d[2] * m },
			}),
		}
	end
	V.polys = polys
	V.builds = (V.builds or 0) + 1
end

local function drawPlanes()
	draw.NoTexture()
	for _, p in ipairs(V.polys) do
		surface.SetDrawColor(p.r, p.g, p.b, 255)
		surface.DrawPoly(p.pts)
	end
end

-- the outline of the tile under the mouse, at its floor height
local function drawCursor()
	local h = V.hover
	if not h or not h.floor then return end
	local z = zoomInfo()
	local camera = V.cameras[z.scale]
	local ox, oy = origin()
	local m = z.mult
	local pts = {}
	for _, c in ipairs({ { -0.5, -0.5 }, { 0.5, -0.5 }, { 0.5, 0.5 }, { -0.5, 0.5 } }) do
		local s = camera.screen(h.tileX + c[1], h.tileY + c[2], h.tileZ)
		if not s then return end
		pts[#pts + 1] = { x = ox + math.Round(s[1]) * m, y = oy + math.Round(s[2]) * m }
	end
	surface.SetDrawColor(CURSOR)
	for i = 1, 4 do
		local a, b = pts[i], pts[i % 4 + 1]
		surface.DrawLine(a.x, a.y, b.x, b.y)
	end
end

-- ---------------------------------------------------------------------------------------------
-- The panel over the whole screen that shows the room and gets the mouse

local PANEL = {}

function PANEL:Init()
	self:SetMouseInputEnabled(true)
	self:SetKeyboardInputEnabled(false)
	self:SetPos(0, 0)
	self:SetSize(ScrW(), ScrH())
end

function PANEL:Think()
	if self:GetWide() ~= ScrW() or self:GetTall() ~= ScrH() then self:SetSize(ScrW(), ScrH()) end
end

function PANEL:Paint(w, h)
	if not V.room then return end
	if V.dirty or not V.polys then
		buildPolys()
		V.dirty = false
	end
	surface.SetDrawColor(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, 255)
	surface.DrawRect(0, 0, w, h)
	drawPlanes()
	drawCursor()
	if V.label then
		draw.SimpleText(V.label, "BobbaViewLabel", 12, 12, color_white)
	end
end

function PANEL:OnMousePressed(code)
	if code ~= MOUSE_LEFT then return end
	self:MouseCapture(true)
	local x, y = input.GetCursorPos()
	V.press = { x = x, y = y, panX = V.panX, panY = V.panY, dragging = false }
end

function PANEL:OnMouseReleased(code)
	if code ~= MOUSE_LEFT or not V.press then return end
	self:MouseCapture(false)
	local wasDrag = V.press.dragging
	V.press = nil
	if not wasDrag and V.hover then
		BOBBA.events.emit("roomClick", V.hover)
	end
end

function PANEL:OnCursorMoved()
	local x, y = input.GetCursorPos()
	local p = V.press
	if p then
		if not p.dragging and (math.abs(x - p.x) > 3 or math.abs(y - p.y) > 3) then p.dragging = true end
		if p.dragging then
			V.panX, V.panY = p.panX + (x - p.x), p.panY + (y - p.y)
			V.dirty = true
		end
	end
	V.updateHover(x, y)
end

function PANEL:OnMouseWheeled(delta)
	local old = zoomInfo()
	local new = math.Clamp(V.zoom + (delta > 0 and 1 or -1), 1, #V.ZOOMS)
	if new == V.zoom then return end
	V.zoom = new
	-- keep the same part of the room in the middle
	local f = (zoomInfo().scale * zoomInfo().mult) / (old.scale * old.mult)
	V.panX, V.panY = V.panX * f, V.panY * f
	V.dirty = true
	V.updateHover(input.GetCursorPos())
end

function PANEL:OnCursorExited()
	V.hover = nil
end

vgui.Register("BobbaRoomView", PANEL, "EditablePanel")

function V.updateHover(sx, sy)
	if not V.room then return end
	local z = zoomInfo()
	local rx, ry = toRoom(sx, sy)
	V.hover = BOBBA.rooms.pick(V.room, BOBBA.rooms.view(V.room, z.scale), z.scale, rx, ry)
end

-- ---------------------------------------------------------------------------------------------
-- Showing and hiding

-- Show a room (from BOBBA.rooms.geometry). label: text in the top left corner (optional).
function V.show(room, label)
	V.room = room
	V.label = label
	V.panX, V.panY = 0, 0
	V.hover = nil
	V.bounds, V.cameras = {}, {}
	for _, z in ipairs(V.ZOOMS) do
		if not V.bounds[z.scale] then
			V.bounds[z.scale] = boundsOf(BOBBA.rooms.view(room, z.scale))
			V.cameras[z.scale] = BOBBA.nitro.create(z.scale)
		end
	end
	if not IsValid(V.panel) then V.panel = vgui.Create("BobbaRoomView") end
	V.panel:SetVisible(true)
	gui.EnableScreenClicker(true)
	V.dirty = true
end

function V.hide()
	V.room = nil
	if IsValid(V.panel) then V.panel:SetVisible(false) end
	gui.EnableScreenClicker(false)
end

-- While a room is shown, GMod's own 3D world isn't drawn at all (it would be hidden anyway).
hook.Add("RenderScene", "bobba.view", function()
	if not V.room then return end
	render.Clear(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, 255, true, true)
	return true
end)

local HIDE = { CHudHealth = true, CHudBattery = true, CHudAmmo = true, CHudSecondaryAmmo = true, CHudCrosshair = true, CHudWeaponSelection = true, CHudDamageIndicator = true }
hook.Add("HUDShouldDraw", "bobba.view", function(name)
	if V.room and HIDE[name] then return false end
end)

hook.Add("OnScreenSizeChanged", "bobba.view", function()
	V.dirty = true
end)

-- ---------------------------------------------------------------------------------------------
-- bobba_preview: look at any layout before rooms exist on the server.
--   bobba_preview            list the layouts
--   bobba_preview model_a    show one
--   bobba_preview next/prev  the next or previous one
--   bobba_preview off        back to the game

local function layoutIds()
	local ids = {}
	for _, l in ipairs(BOBBA.registry.list("layout")) do ids[#ids + 1] = l.id end
	return ids
end

local function preview(id)
	local room, err = BOBBA.rooms.geometry(id)
	if not room then
		print(err)
		return
	end
	local ids = layoutIds()
	local n = 0
	for i, x in ipairs(ids) do if x == id then n = i end end
	V.previewId = id
	V.show(room, string.format("%s  (%d/%d)   scroll = zoom   drag = move   bobba_preview next / prev / off", id, n, #ids))
end

concommand.Add("bobba_preview", function(_, _, args)
	local a = args[1]
	local ids = layoutIds()
	if not a then
		print(table.concat(ids, ", "))
		return
	end
	if a == "off" then V.hide() return end
	if a == "next" or a == "prev" then
		local cur = 0
		for i, x in ipairs(ids) do if x == V.previewId then cur = i end end
		local i = cur + (a == "next" and 1 or -1)
		if i < 1 then i = #ids elseif i > #ids then i = 1 end
		preview(ids[i])
		return
	end
	preview(a)
end, function(cmd, argStr)
	local out = {}
	local typed = string.Trim(argStr):lower()
	for _, id in ipairs(layoutIds()) do
		if id:find(typed, 1, true) == 1 then out[#out + 1] = cmd .. " " .. id end
	end
	return out
end)

BOBBA.events.on("roomClick", "bobba.view.print", function(hit)
	if V.previewId then
		print(string.format("tile %d, %d  height %d", hit.tileX, hit.tileY, hit.tileZ))
	end
end)
