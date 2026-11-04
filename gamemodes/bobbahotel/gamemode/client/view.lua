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
-- The size things are drawn at, by the screen's height: Habbo's size up to 1080 pixels... 2x from
-- 1440, 3x from 2160 (4K). Whole sizes keep the pixel art sharp. Rooms open at it, and the chat uses
-- it, so bubbles and avatars keep Habbo's sizes next to each other on any screen.
function V.uiScale(h) return math.max(1, math.floor((h or ScrH()) / 720)) end
V.zoomNow = V.zoomNow or V.uiScale() -- rooms open at the screen's size
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

-- An addon can paint the floor and walls (e.g. bobba_habbo with Habbo's floors and wallpapers):
--   V.planePainter = function(kind, id, plane) return paint end      kind "floor" / "wall" / "landscape";
--   id from V.look ({ floor = "", wall = "", landscape = "" }); plane: the view's plane (textureWidth/Height, textureX/Y,
--   normal, texture). paint = { width, height, layers = { { color, fill = true } or
--   { color, quads = { { image = { path, texWidth, texHeight }, x, y, w, h, u0, v0, u1, v1 } } } } },
--   in the plane's own texture (width x height pixels), the way Nitro's plane rasterizers paint it;
--   nil while it isn't ready (then the plane is plain). Painted planes are shaded like Nitro's.
V.look = V.look or { floor = "", wall = "" }

local materials = {}
local function material(path)
	local m = materials[path]
	if not m then
		m = BOBBA.platform.dataMaterial(path, "noclamp")
		materials[path] = m
	end
	return m
end

-- Nitro's RoomPlane.getMatrixForDimensions: the plane's texture (width x height) onto its corners
local function planeMatrix(p, width, height)
	local cx, cy = p.c[1], p.c[2]
	local l3, l4 = p.d[1] - cx, p.d[2] - cy
	local l5, l6 = p.b[1] - cx, p.b[2] - cy
	if p.type == 2 or p.type == 3 then
		if math.abs(l5 - width) <= 1 then l5 = width end
		if math.abs(l6 - width) <= 1 then l6 = width end
		if math.abs(l3 - height) <= 1 then l3 = height end
		if math.abs(l4 - height) <= 1 then l4 = height end
	end
	local xs, ys, xk, yk = l5 / width, l6 / width, l3 / height, l4 / height
	return function(bx, by) return cx + bx * xs + by * xk, cy + bx * ys + by * yk end
end

local KIND = { [1] = "floor", [2] = "wall", [3] = "landscape" }

-- Windows: holes in the walls (Nitro's plane masks), so the landscape behind shows through.
--   V.masks = { { x, y, z, type }, ... }   where each window is and its mask type (room.lua)
--   V.maskShape = function(type, scale, normal) return { { x0, x1, y0, y1 }, ... } end   the hole's
--     rectangles in the plane's texture pixels from the mask's spot (an addon, from Habbo's room
--     content); nil while it isn't known
local function vdot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function vlen(a) return math.sqrt(vdot(a, a)) end
local function vproj(a, b) local l = vlen(b) return l > 0 and vdot(a, b) / l or -1 end

-- RoomVisualization.updatePlaneMasks / RoomPlane.updateMask: the holes the windows cut in a wall,
-- in units along its sides { u0, u1, v0, v1 }
local function maskHoles(p, scale)
	local out = {}
	if p.type ~= 2 or not V.masks or not V.maskShape then return out end
	local plane = V.room.planes[p.index + 1]
	local L, H = vlen(plane.left), vlen(plane.right)
	local W, Hp = p.textureWidth, p.textureHeight
	if L <= 0 or H <= 0 then return out end
	for _, m in ipairs(V.masks) do
		local diff = { m.x - plane.loc[1], m.y - plane.loc[2], m.z - plane.loc[3] }
		if math.abs(vproj(diff, plane.normal)) < 0.01 then
			local u, v = vproj(diff, plane.left), vproj(diff, plane.right)
			local posX, posY = W - W * u / L, Hp - Hp * v / H
			local ok, rects = pcall(V.maskShape, m.type, scale, p.normal)
			for _, r in ipairs(ok and rects or {}) do
				local u0, u1 = L * (1 - (posX + r[2]) / W), L * (1 - (posX + r[1]) / W)
				local v0, v1 = H * (1 - (posY + r[4]) / Hp), H * (1 - (posY + r[3]) / Hp)
				u0, u1, v0, v1 = math.max(0, u0), math.min(L, u1), math.max(0, v0), math.min(H, v1)
				if u1 > u0 and v1 > v0 then out[#out + 1] = { u0, u1, v0, v1 } end
			end
		end
	end
	return out
end

-- a plane as rectangles (u0, u1, v0, v1) leaving its holes out (the door's and the windows')
local function piecesWithout(L, H, holes)
	local pieces = { { 0, L, 0, H } }
	for _, h in ipairs(holes) do
		local out = {}
		for _, r in ipairs(pieces) do
			local a, b = math.max(r[1], h[1]), math.min(r[2], h[2])
			local c, e = math.max(r[3], h[3]), math.min(r[4], h[4])
			if a >= b or c >= e then
				out[#out + 1] = r
			else
				if r[1] < a then out[#out + 1] = { r[1], a, r[3], r[4] } end
				if b < r[2] then out[#out + 1] = { b, r[2], r[3], r[4] } end
				if c > r[3] then out[#out + 1] = { a, b, r[3], c } end
				if e < r[4] then out[#out + 1] = { a, b, e, r[4] } end
			end
		end
		pieces = out
	end
	return pieces
end

-- a painted plane as textured polygons (and coloured ones), cut into the plane's pieces (around
-- the door hole). shade: Nitro's plane colour (0xRRGGBB, multiplied in)
local function paintedPolys(p, paint, pieces, shade, ox, oy, m, out)
	local W, Hp = paint.width, paint.height
	local L, H = pieces.L, pieces.H
	local toScreen = planeMatrix(p, W, Hp)
	local function at(bx, by)
		local x, y = toScreen(bx, by)
		return ox + x * m, oy + y * m
	end
	-- the pieces in the texture's pixels (the texture runs from the far corner back: u = L at x = 0)
	local rects = {}
	for _, q in ipairs(pieces) do
		rects[#rects + 1] = { W * (1 - q[2] / L), W * (1 - q[1] / L), Hp * (1 - q[4] / H), Hp * (1 - q[3] / H) }
	end
	local sr, sg, sb = math.floor(shade / 65536) % 256, math.floor(shade / 256) % 256, shade % 256
	for _, layer in ipairs(paint.layers) do
		local c = layer.color or 0xFFFFFF
		local r = math.floor((math.floor(c / 65536) % 256) * sr / 255 + 0.5)
		local g = math.floor((math.floor(c / 256) % 256) * sg / 255 + 0.5)
		local b = math.floor((c % 256) * sb / 255 + 0.5)
		for _, rc in ipairs(rects) do
			if layer.fill then
				local x1, y1 = at(rc[1], rc[3])
				local x2, y2 = at(rc[2], rc[3])
				local x3, y3 = at(rc[2], rc[4])
				local x4, y4 = at(rc[1], rc[4])
				out[#out + 1] = { r = r, g = g, b = b, pts = clockwise({ { x = x1, y = y1 }, { x = x2, y = y2 }, { x = x3, y = y3 }, { x = x4, y = y4 } }) }
			else
				for _, q in ipairs(layer.quads) do
					local x0, x1 = math.max(q.x, rc[1]), math.min(q.x + q.w, rc[2])
					local y0, y1 = math.max(q.y, rc[3]), math.min(q.y + q.h, rc[4])
					if x1 > x0 and y1 > y0 then
						local img = q.image
						local fu, fv = (q.u1 - q.u0) / q.w, (q.v1 - q.v0) / q.h
						local u0 = (q.u0 + (x0 - q.x) * fu) / img.texWidth
						local u1 = (q.u0 + (x1 - q.x) * fu) / img.texWidth
						local v0 = (q.v0 + (y0 - q.y) * fv) / img.texHeight
						local v1 = (q.v0 + (y1 - q.y) * fv) / img.texHeight
						local ax, ay = at(x0, y0)
						local bx, by = at(x1, y0)
						local cx, cy = at(x1, y1)
						local dx, dy = at(x0, y1)
						out[#out + 1] = { r = r, g = g, b = b, mat = material(img.path), pts = clockwise({
							{ x = ax, y = ay, u = u0, v = v0 }, { x = bx, y = by, u = u1, v = v0 },
							{ x = cx, y = cy, u = u1, v = v1 }, { x = dx, y = dy, u = u0, v = v1 },
						}) }
					end
				end
			end
		end
	end
end

-- the planes as screen polygons with their colours, deepest first (like Nitro's RoomSpriteCanvas)
local function buildPolys()
	local z = zoomInfo()
	local view = BOBBA.rooms.view(V.room, z.scale)
	local camera = V.cameras[z.scale]
	local holes = BOBBA.rooms.holes(V.room)
	local ox, oy = origin()
	local m = z.mult
	local polys, back, doorWall = {}, {}, {}
	local doorFloor = BOBBA.rooms.doorFloor(V.room)
	local function screen(index, u, v)
		local s = camera.screen(BOBBA.rooms.planePoint(V.room, index, u, v))
		return { x = ox + math.Round(s[1]) * m, y = oy + math.Round(s[2]) * m }
	end
	-- (a landscape's picture runs on from one window wall to the next: RoomVisualization gives each
	-- landscape plane the length of the ones before it as its texture offset)
	local landscapeOffset, before = {}, 0
	for i, pl in ipairs(V.room.planes) do
		if pl.type == 3 then landscapeOffset[i - 1] = before before = before + vlen(pl.left) end
	end
	-- (the room's settings can hide the walls: only the floor is drawn then)
	local planes = view
	if V.hideWalls then
		planes = {}
		for _, p in ipairs(view) do if p.type == 1 then planes[#planes + 1] = p end end
	end
	for _, p in ipairs(planes) do
		local style = V.styleFor(STYLE_FOR[p.type])
		local r, g, b = BOBBA.rooms.planeColor(style, p.color)
		local kind = KIND[p.type]
		local paint
		if p.type == 3 then p.textureX = math.floor((landscapeOffset[p.index] or 0) * z.scale / 2) end
		if kind and V.planePainter then
			local ok, res = pcall(V.planePainter, kind, V.look[kind] or "", p)
			if ok then paint = res else ErrorNoHalt("[Bobba] plane painter: " .. tostring(res) .. "\n") V.planePainter = nil end
		end
		-- the windows' holes in it
		local windows = maskHoles(p, z.scale)
		local all = {}
		for _, h in ipairs(holes[p.index] or {}) do all[#all + 1] = h end
		for _, h in ipairs(windows) do all[#all + 1] = h end
		if paint then
			local L, H = BOBBA.rooms.planeSize(V.room, p.index)
			local pieces = piecesWithout(L, H, all)
			pieces.L, pieces.H = L, H
			local doorFloor = (p.index == BOBBA.rooms.doorFloor(V.room))
			local list = doorFloor and back or polys
			local before = #list
			paintedPolys(p, paint, pieces, p.color, ox, oy, m, list)
			if holes[p.index] then
				for i = before + 1, #list do doorWall[#doorWall + 1] = list[i] end
			end
		elseif #all > 0 then
			-- a plane with the door (or windows) cut out: drawn as the pieces around the holes
			local L, H = BOBBA.rooms.planeSize(V.room, p.index)
			for _, q in ipairs(piecesWithout(L, H, all)) do
				local piece = { r = r, g = g, b = b, pts = clockwise({
					screen(p.index, q[1], q[3]), screen(p.index, q[2], q[3]), screen(p.index, q[2], q[4]), screen(p.index, q[1], q[4]),
				}) }
				polys[#polys + 1] = piece
				if holes[p.index] then doorWall[#doorWall + 1] = piece end
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
	V.doorWallPolys = doorWall
	V.builds = (V.builds or 0) + 1
end

-- V.planeTint: a colour the floor and walls are multiplied by (the mood light's "Background only",
-- Nitro's RoomVisualization plane colours); V.roomTint: the whole room (room.lua draws it)
local function drawPolys(list)
	draw.NoTexture()
	local current = nil
	local t = V.planeTint
	render.PushFilterMag(TEXFILTER.POINT)
	render.PushFilterMin(TEXFILTER.POINT)
	for _, p in ipairs(list) do
		if p.mat ~= current then
			current = p.mat
			if current then surface.SetMaterial(current) else draw.NoTexture() end
		end
		if t then surface.SetDrawColor(math.floor(p.r * t.r / 255 + 0.5), math.floor(p.g * t.g / 255 + 0.5), math.floor(p.b * t.b / 255 + 0.5), 255)
		else surface.SetDrawColor(p.r, p.g, p.b, 255) end
		surface.DrawPoly(p.pts)
	end
	render.PopFilterMin()
	render.PopFilterMag()
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
	-- (black, or a background toner's colour: V.background)
	local bg = V.background or BACKGROUND
	surface.SetDrawColor(bg.r, bg.g, bg.b, 255)
	surface.DrawRect(0, 0, w, h)
	drawPolys(V.backPolys) -- the door tile's floor
	drawPolys(V.polys)
	-- whoever is in the doorway: on top of the floor, then the wall with the door hole once more over
	-- them, so they're only seen through the hole (Nitro draws them behind all the walls; drawing
	-- them before the floor hid their feet under the room's floor halfway through the door)
	if V.drawUnits and V.drawUnits("behind") then drawPolys(V.doorWallPolys) end
	drawCursor()
	-- (what the interact button would use: steering.lua)
	if V.drawOverlay then V.drawOverlay() end
	if V.drawUnits then V.drawUnits("front") end
	-- (over everyone: the list of things the interact button can use)
	if V.drawOverlayTop then V.drawOverlayTop() end
	if V.label then
		draw.SimpleText(V.label, "BobbaViewLabel", 12, 12, color_white)
	end
end

function PANEL:OnMousePressed(code)
	if code == MOUSE_RIGHT then BOBBA.events.emit("roomRightClick", V.hover or { floor = false }) return end
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
	-- (also off the floor: furni can stand up over the walls)
	if not wasDrag then
		BOBBA.events.emit("roomClick", V.hover or { floor = false })
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

-- The room tools' zoom button (Nitro: the room drawn at half its size, and back): around the middle
function V.toggleZoom()
	local full = V.uiScale()
	V.zoomTarget = (V.zoomTarget >= full * 0.75) and full / 2 or full
	local cx, cy = ScrW() / 2, ScrH() / 2
	local rx, ry = toRoom(cx, cy)
	V.anchor = { sx = cx, sy = cy, rx = rx, ry = ry }
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
	local bg = V.background or BACKGROUND
	render.Clear(bg.r, bg.g, bg.b, 255, true, true)
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
	if V.mode == "preview" and hit.floor then
		print(string.format("tile %d, %d  height %d", hit.tileX, hit.tileY, hit.tileZ))
	end
end)
