-- The room on screen (client). The planes come from BOBBA.rooms (Nitro's own geometry, camera and
-- sorting); this file only draws them and handles the mouse:
--   Ctrl + scroll = zoom, like Habbo: smooth, any size from half to 4x Habbo's, towards the mouse,
--   drag = move the room,
--   click = a tile (walking comes with the server rooms).
-- The planes' screen positions and colours are worked out once and only again when something
-- changes (moving, zooming, another room); each frame just draws them (a room has 60-350 planes).
-- (Not drawn through a render target: GMod brightens those on HDR maps, and colours must be exact.)

BOBBA.view = BOBBA.view or {}
local V = BOBBA.view

-- Player setting (saved on their own PC): 1 = zoom with Ctrl + scroll like Habbo, 0 = plain scroll
V.cvZoomCtrl = V.cvZoomCtrl or CreateClientConVar("bobba_zoom_with_ctrl", "1", true, false, "1 = Ctrl + scroll zooms (like Habbo), 0 = scrolling alone zooms")

-- Zoom: the room is worked out at Nitro's scale 64 (Habbo's zoomed-in size) and drawn V.zoomNow
-- times as big. Each scroll notch sets a new target and the zoom glides there.
V.SCALE = 64
V.MIN_ZOOM, V.MAX_ZOOM = 0.5, 4
V.ZOOM_STEP = 1.2 -- per scroll notch
V.ZOOM_SPEED = 14 -- how fast it glides (higher = quicker)
V.zoomNow = V.zoomNow or 2 -- rooms open zoomed in
V.zoomTarget = V.zoomTarget or V.zoomNow
V.panX, V.panY = V.panX or 0, V.panY or 0

local BACKGROUND = Color(0, 0, 0)
local CURSOR = Color(255, 255, 255)

surface.CreateFont("BobbaViewLabel", { font = "Tahoma", size = 13, weight = 700 })

-- ---------------------------------------------------------------------------------------------
-- Where things are

local function zoomInfo()
	return { scale = V.SCALE, mult = V.zoomNow }
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

V.clockwise = clockwise

local STYLE_FOR = { [1] = "floor", [2] = "wall", [3] = "landscape" }

function V.styleFor(kind)
	local id = (V.styles and V.styles[kind]) or ("default_" .. kind)
	return BOBBA.registry.get("plane_style", id) or BOBBA.registry.get("plane_style", "default_" .. kind)
end

-- the planes as screen polygons with their colours, deepest first (like Nitro's RoomSpriteCanvas)
local function buildPolys()
	local z = zoomInfo()
	local view = BOBBA.rooms.view(V.room, z.scale)
	local camera = V.cameras[z.scale]
	local holes = BOBBA.rooms.holes(V.room)
	local ox, oy = origin()
	local m = z.mult
	local polys, back = {}, {}
	local doorFloor = BOBBA.rooms.doorFloor(V.room)
	local function screen(index, u, v)
		local s = camera.screen(BOBBA.rooms.planePoint(V.room, index, u, v))
		return { x = ox + math.Round(s[1]) * m, y = oy + math.Round(s[2]) * m }
	end
	for _, p in ipairs(view) do
		local style = V.styleFor(STYLE_FOR[p.type])
		local r, g, b = BOBBA.rooms.planeColor(style, p.color)
		if holes[p.index] then
			-- a plane with the door cut out: drawn as the pieces around the hole
			for _, q in ipairs(BOBBA.rooms.planePieces(V.room, p.index)) do
				polys[#polys + 1] = { r = r, g = g, b = b, pts = clockwise({
					screen(p.index, q[1], q[3]), screen(p.index, q[2], q[3]), screen(p.index, q[2], q[4]), screen(p.index, q[1], q[4]),
				}) }
			end
		else
			-- the door tile's floor goes behind the walls (seen through the door hole)
			local list = (p.index == doorFloor) and back or polys
			list[#list + 1] = {
				r = r, g = g, b = b,
				pts = clockwise({
					{ x = ox + p.a[1] * m, y = oy + p.a[2] * m },
					{ x = ox + p.b[1] * m, y = oy + p.b[2] * m },
					{ x = ox + p.c[1] * m, y = oy + p.c[2] * m },
					{ x = ox + p.d[1] * m, y = oy + p.d[2] * m },
				}),
			}
			-- the floor's tile lines, right on top of it (they are part of its look)
			if style.grid and p.type == 1 then
				local gr, gg, gb = math.floor(r * style.grid), math.floor(g * style.grid), math.floor(b * style.grid)
				for _, l in ipairs(BOBBA.rooms.gridLines(V.room, p.index)) do
					local function at(x, y)
						local s = camera.screen(x, y, l[5])
						return { x = ox + s[1] * m, y = oy + s[2] * m }
					end
					list[#list + 1] = { r = gr, g = gg, b = gb, pts = clockwise({ at(l[1], l[3]), at(l[2], l[3]), at(l[2], l[4]), at(l[1], l[4]) }) }
				end
			end
		end
	end
	V.polys = polys
	V.backPolys = back
	V.builds = (V.builds or 0) + 1
end

local function drawPolys(list)
	draw.NoTexture()
	for _, p in ipairs(list) do
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
	V.stepZoom(RealFrameTime())
	if V.dirty or not V.polys then
		buildPolys()
		V.dirty = false
	end
	surface.SetDrawColor(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, 255)
	surface.DrawRect(0, 0, w, h)
	drawPolys(V.backPolys) -- the door tile's floor
	if V.drawUnits then V.drawUnits("behind") end -- in the door: behind the walls (Nitro)
	drawPolys(V.polys)
	drawCursor()
	if V.drawUnits then V.drawUnits("front") end
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
			V.anchor = nil
			V.panX, V.panY = p.panX + (x - p.x), p.panY + (y - p.y)
			V.dirty = true
		end
	end
	V.updateHover(x, y)
end

function PANEL:OnMouseWheeled(delta)
	-- Habbo zooms with Ctrl + scroll (plain scrolling is left for windows); players can switch that off
	local ctrl = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
	if V.cvZoomCtrl:GetBool() and not ctrl then return end
	local target = math.Clamp(V.zoomTarget * (delta > 0 and V.ZOOM_STEP or 1 / V.ZOOM_STEP), V.MIN_ZOOM, V.MAX_ZOOM)
	if target == V.zoomTarget then return end
	V.zoomTarget = target
	-- the spot under the mouse stays under the mouse while zooming
	local mx, my = input.GetCursorPos()
	local rx, ry = toRoom(mx, my)
	V.anchor = { sx = mx, sy = my, rx = rx, ry = ry }
end

-- Moves the zoom towards its target (called every frame; dt = seconds since the last frame)
function V.stepZoom(dt)
	if V.zoomNow == V.zoomTarget then return end
	local f = 1 - math.exp(-dt * V.ZOOM_SPEED)
	V.zoomNow = V.zoomNow + (V.zoomTarget - V.zoomNow) * f
	if math.abs(V.zoomNow - V.zoomTarget) < 0.002 then V.zoomNow = V.zoomTarget end
	local a = V.anchor
	if a and V.bounds then
		local b = V.bounds[V.SCALE]
		local cx, cy = (b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2
		V.panX = a.sx - ScrW() / 2 + (cx - a.rx) * V.zoomNow
		V.panY = a.sy - ScrH() / 2 + (cy - a.ry) * V.zoomNow
	end
	if V.zoomNow == V.zoomTarget then V.anchor = nil end
	V.dirty = true
	V.updateHover(input.GetCursorPos())
end

function PANEL:OnCursorExited()
	V.hover = nil
end

vgui.Register("BobbaRoomView", PANEL, "EditablePanel")

-- A point in the room (tile x, y, height z) on screen: pixel x, y, and how big things are drawn
-- (1 = Habbo's zoomed-in size, 64 px per tile).
function V.project(x, y, z)
	local zi = zoomInfo()
	local s = V.cameras[zi.scale].screen(x, y, z)
	if not s then return nil end
	local ox, oy = origin()
	return ox + s[1] * zi.mult, oy + s[2] * zi.mult, zi.mult, s[3]
end

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
	if V.room ~= room then V.panX, V.panY = 0, 0 end
	V.room = room
	V.label = label
	V.hover = nil
	V.bounds = { [V.SCALE] = boundsOf(BOBBA.rooms.view(room, V.SCALE)) }
	V.cameras = { [V.SCALE] = BOBBA.nitro.create(V.SCALE) }
	V.anchor = nil
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
	V.mode = "preview"
	V.show(room, string.format("%s  (%d/%d)   Ctrl+scroll = zoom   drag = move   bobba_preview next / prev / off", id, n, #ids))
end

concommand.Add("bobba_preview", function(_, _, args)
	local a = args[1]
	local ids = layoutIds()
	if not a then
		print(table.concat(ids, ", "))
		return
	end
	if a == "off" then
		V.previewId = nil
		if BOBBA.room and BOBBA.room.current then BOBBA.room.show() else V.hide() end
		return
	end
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
	if V.mode == "preview" then
		print(string.format("tile %d, %d  height %d", hit.tileX, hit.tileY, hit.tileZ))
	end
end)
