-- The room you're in (client): shows it with the room view, sends your clicks as walking, and
-- draws everyone and every furni in it, sorted by depth the way Nitro sorts its sprites. Addons
-- draw the people and the furni (R.figureDrawer, R.furniDrawer, e.g. bobba_habbo's); without one,
-- or while their pictures are still loading, people are a simple stand-in figure and furni aren't
-- drawn.
--
--   BOBBA.room.figureDrawer = function(unit, info) ... return true end
--     info: x, y, z (where it stands), sx, sy (that point on screen), k (screen pixels per avatar
--     pixel), dir, posture ("mv" while stepping, "sit"/"lay" on furni, else "std"), now (SysTime()).
--     Return true when it drew the unit; false/nil draws the stand-in.
--   BOBBA.room.furniDrawer = function(item, info) return { { depth, x, y, w, h, mouse, hit, draw }, ... } end
--     info: sx, sy, k, now, alpha (0.5 for the furni being placed). depth: Nitro's relative depth;
--     mouse: it can be clicked; hit(mx, my): is it solid at that screen point (optional).
--   BOBBA.room.furniInfo = function(kind) return { name, sit, lay, walk } end    (optional)
--
--   bobba_room <id>        go to a room          (server: bobba_rooms lists them, bobba_room_create makes one)
--   bobba_furni <kind>     place a furni (room owners with bobba.staff.place; click to put it down,
--                          R to turn it, right click to cancel)

BOBBA.room = BOBBA.room or { units = {} }
local R = BOBBA.room
local V = BOBBA.view
local P = BOBBA.platform

R.items = R.items or {}

surface.CreateFont("BobbaName", { font = "Verdana", size = 11, weight = 700 })
surface.CreateFont("BobbaInfo", { font = "Verdana", size = 12, weight = 700 })

function R.show()
	local c = R.current
	if not c then return end
	V.mode = "room"
	V.look = { floor = c.floor or "", wall = c.wallpaper or "", landscape = c.landscape or "" }
	R.paintPreview = nil
	-- the room's settings: wall and floor thickness (Nitro: -2 a quarter, -1 half, 1 double), walls hidden
	local a = c.access or {}
	local function thick(v) return ({ [-2] = 0.25, [-1] = 0.5, [1] = 2 })[tonumber(v) or 0] or 1 end
	V.hideWalls = a.hideWall and true or false
	-- (the room's name is shown by the room tools, hud.lua)
	V.show(BOBBA.rooms.geometryFor(c.heightmap, { wallHeight = c.wallHeight, wallThickness = thick(a.wallThickness), floorThickness = thick(a.floorThickness) }))
end

local position
local function setUnit(s)
	local u = R.units[s.id] or { id = s.id }
	R.units[s.id] = u
	-- a step turned halfway (steering): from where it's drawn now, so it never jumps back or ahead
	-- (the server's idea of "now" is a little earlier or later than what's on this screen)
	local from = { x = s.x, y = s.y, z = s.z }
	if s.dur and u.from and u.to and position then
		local x, y, z = position(u)
		local lift = (u.posture == "sit" or u.posture == "lay") and (u.height or 0) or 0
		from = { x = x, y = y, z = z - lift }
	end
	u.name, u.dir, u.figure, u.gender, u.key = s.name, s.dir, s.figure, s.gender, s.key
	u.from = from
	u.to = s.to
	u.posture, u.height = s.posture, s.height
	u.started = SysTime()
	-- (a step turned halfway by steering is shorter: hotel/roomlive.lua live.redirect)
	u.dur = tonumber(s.dur)
	return u
end

local function setItem(s)
	local it = R.items[s.id]
	-- the same table while it's the same furni (the addon keeps its animation with it)
	if not it or it.kind ~= s.kind then
		it = { id = s.id }
		R.items[s.id] = it
	end
	it.kind, it.x, it.y, it.z, it.dir, it.state, it.data, it.wall = s.kind, s.x, s.y, s.z, s.dir, s.state, s.data, s.wall
	-- moved by a roller: it slides there (Nitro's ObjectRollingUpdate, over half a second)
	if s.slide then it.slideFrom, it.slideStart = s.slide, SysTime() else it.slideFrom = nil end
	return it
end

-- --- wall furni: where they hang (Nitro's LegacyWallGeometry, scale 32) ---------------------------
-- Habbo says where with ":w=x,y l=localX,localY l|r": the wall tile, a point on it (pixels at
-- scale 32) and which wall (l: the left one, facing 2; r: the right one, facing 4).
local WALL_SCALE = 32

-- LegacyWallGeometry.getHeight: the room's tile heights (the walls' tiles have their floor's)
function R.wallTileHeight(x, y)
	local row = V.room and V.room.heights and V.room.heights[y + 1]
	return row and row[x + 1] or 0
end

-- LegacyWallGeometry.getLocation: the point in the room (x, y, z) and the furni's direction
function R.wallLocation(wall)
	local wx, wy, lx, ly, side = tostring(wall or ""):match("^:w=(%-?%d+),(%-?%d+) l=(%-?%d+),(%-?%d+) ([lr])$")
	if not wx then return nil end
	wx, wy, lx, ly = tonumber(wx), tonumber(wy), tonumber(lx), tonumber(ly)
	local half = WALL_SCALE / 2
	local x, y, z = wx, wy, R.wallTileHeight(wx, wy)
	if side == "r" then
		x = x + (lx / half - 0.5)
		y = y + 0.5
		z = z - (ly - lx / 2) / half
		return x, y, z, 4
	end
	y = y + ((half - lx) / half - 0.5)
	x = x + 0.5
	z = z - (ly - (half - lx) / 2) / half
	return x, y, z, 2
end

-- LegacyWallGeometry.getOldLocationString: a point on a wall (direction 90 = the left wall, 180 =
-- the right one) as Habbo's wall location
function R.wallString(x, y, z, direction)
	local half = WALL_SCALE / 2
	local wx, wy, lx, ly, side
	if direction == 90 then
		wx, wy = math.floor(x - 0.5), math.floor(y + 0.5)
		local h = R.wallTileHeight(wx, wy)
		lx = half - ((y - wy) + 0.5) * half
		ly = (h - z) * half + (half - lx) / 2
		side = "l"
	elseif direction == 180 then
		wx, wy = math.floor(x + 0.5), math.floor(y - 0.5)
		local h = R.wallTileHeight(wx, wy)
		lx = ((x + 0.5) - wx) * half
		ly = (h - z) * half + lx / 2
		side = "r"
	else
		return nil
	end
	local function trunc(n) return n < 0 and math.ceil(n) or math.floor(n) end
	return ":w=" .. trunc(wx) .. "," .. trunc(wy) .. " l=" .. trunc(lx) .. "," .. trunc(ly) .. " " .. side
end

-- Nitro's validateWallItemLocation: where on a wall a furni goes for the mouse at wallX, wallY on
-- its plane (moved in so all of it is on the wall); x, y, z or nil when it doesn't fit
function R.wallPlacement(plane, wallX, wallY, sizeX, sizeZ, centerZ)
	local p = V.room and V.room.planes[plane + 1]
	if not p then return nil end
	local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
	local ll, rl = len(p.left), len(p.right)
	if ll == 0 or rl == 0 then return nil end
	if wallX < sizeX / 2 and wallX <= ll - sizeX / 2 then wallX = sizeX / 2
	elseif wallX >= sizeX / 2 and wallX > ll - sizeX / 2 then wallX = ll - sizeX / 2 end
	if wallY < centerZ and wallY <= rl - (sizeZ - centerZ) then wallY = centerZ
	elseif wallY >= centerZ and wallY > rl - (sizeZ - centerZ) then wallY = rl - (sizeZ - centerZ) end
	if wallX < sizeX / 2 or wallX > ll - sizeX / 2 or wallY < centerZ or wallY > rl - (sizeZ - centerZ) then return nil end
	local a, b = wallX / ll, wallY / rl
	return p.loc[1] + p.left[1] * a + p.right[1] * b, p.loc[2] + p.left[2] * a + p.right[2] * b, p.loc[3] + p.left[3] * a + p.right[3] * b
end

local SLIDE_TIME = 0.5
-- where a furni is drawn now (between where it was and where it is while sliding; a wall furni where
-- it hangs)
local function itemPosition(it)
	if it.wall then
		local x, y, z, dir = R.wallLocation(it.wall)
		if x then it.dir = dir return x, y, z end
	end
	local f = it.slideFrom
	if not f then return it.x, it.y, it.z end
	local k = (SysTime() - it.slideStart) / SLIDE_TIME
	if k >= 1 then it.slideFrom = nil return it.x, it.y, it.z end
	return f.x + (it.x - f.x) * k, f.y + (it.y - f.y) * k, f.z + (it.z - f.z) * k
end

P.receive("room.load", function(_, data)
	R.current = data
	R.units = {}
	R.items = {}
	R.selected, R.placing, R.selectedUnit = nil, nil, nil
	R.you = data.you
	for _, s in ipairs(data.units or {}) do setUnit(s) end
	for _, s in ipairs(data.items or {}) do setItem(s) end
	-- furni the server is still looking up: they come with room.items (or room.item.remove)
	R.itemsComing = {}
	for _, id in ipairs(data.itemsComing or {}) do R.itemsComing[id] = true end
	R.show()
	R.updateInfo()
	BOBBA.events.emit("roomShown", data)
end)

P.receive("room.units", function(_, list)
	for _, s in ipairs(list) do setUnit(s) end
end)

-- turning while walking (steering a new way near the end of a step): the step goes on
P.receive("room.unit.turn", function(_, data)
	local u = R.units[data.id]
	if u then u.dir = data.dir end
end)

P.receive("room.unit.remove", function(_, data)
	R.units[data.id] = nil
end)

P.receive("room.items", function(_, list)
	for _, s in ipairs(list) do
		setItem(s)
		if R.itemsComing then R.itemsComing[s.id] = nil end
	end
	R.updateInfo()
end)

P.receive("room.item.remove", function(_, data)
	R.items[data.id] = nil
	if R.itemsComing then R.itemsComing[data.id] = nil end
	if R.selected == data.id then R.selected = nil end
	R.updateInfo()
end)

P.receive("room.error", function(_, data)
	chat.AddText(Color(255, 120, 120), "[Bobba] ", color_white, tostring(data.message))
end)

-- where a unit is now: sliding from its tile to the next over one step (0.5 s), like Habbo. On a
-- seat or bed it is drawn at the seat's height (Nitro adds the sit/lay height to where it is).
local STEP = 0.5
function position(u)
	local lift = (u.posture == "sit" or u.posture == "lay") and (u.height or 0) or 0
	if not u.to then return u.from.x, u.from.y, u.from.z + lift end
	local f = math.min((SysTime() - u.started) / (u.dur or STEP), 1)
	local a, b = u.from, u.to
	return a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.z + (b.z - a.z) * f + lift
end

local function colorFor(name)
	local h = 0
	for i = 1, #name do h = (h * 31 + name:byte(i)) % 360 end
	return HSVToColor(h, 0.55, 0.85)
end

local function ellipse(cx, cy, rx, ry, n)
	local pts = {}
	for i = 0, n - 1 do
		local t = i / n * math.pi * 2
		pts[#pts + 1] = { x = cx + math.cos(t) * rx, y = cy + math.sin(t) * ry }
	end
	return V.clockwise(pts)
end

R.unitPosition = position

-- a unit is walking while it is on its way to the next tile
local function posture(u)
	if u.to and (SysTime() - u.started) < (u.dur or STEP) + 0.1 then return "mv" end
	return u.posture or "std"
end

-- the stand-in figure: shadow, legs, body, head, a nose showing which way it faces, and the name
local function drawUnit(u)
	local x, y, z = position(u)
	local sx, sy, k = V.project(x, y, z)
	if not sx then return end
	if R.figureDrawer then
		local ok, drew = pcall(R.figureDrawer, u, { x = x, y = y, z = z, sx = sx, sy = sy, k = k, dir = u.dir or 2, posture = posture(u), now = SysTime(), talk = (u.talkUntil or 0) > SysTime() })
		if ok and drew then return end
		if not ok then ErrorNoHalt("[Bobba] figure drawer: " .. tostring(drew) .. "\n") R.figureDrawer = nil end
	end
	draw.NoTexture()
	surface.SetDrawColor(0, 0, 0, 70)
	surface.DrawPoly(ellipse(sx, sy, 15 * k, 7 * k, 16))
	local c = colorFor(u.name or "?")
	surface.SetDrawColor(60, 60, 80, 255)
	surface.DrawRect(sx - 8 * k, sy - 30 * k, 7 * k, 30 * k)
	surface.DrawRect(sx + 1 * k, sy - 30 * k, 7 * k, 30 * k)
	surface.SetDrawColor(c.r, c.g, c.b, 255)
	surface.DrawRect(sx - 11 * k, sy - 62 * k, 22 * k, 34 * k)
	surface.SetDrawColor(240, 200, 160, 255)
	surface.DrawPoly(ellipse(sx, sy - 74 * k, 11 * k, 12 * k, 16))
	-- the nose: towards the next tile in the facing direction
	local d = ({ [0] = { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } })[u.dir or 2]
	local nx, ny = V.project(x + d[1], y + d[2], z)
	if nx then
		local dx, dy = nx - sx, ny - sy
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 0 then
			surface.SetDrawColor(200, 120, 90, 255)
			surface.DrawRect(sx + dx / len * 9 * k - 2 * k, sy - 74 * k + dy / len * 4 * k - 2 * k, 4 * k, 4 * k)
		end
	end
end

-- names go over everything (also over the wall when someone stands in the door)
local function drawName(u)
	local x, y, z = position(u)
	local sx, sy, k = V.project(x, y, z)
	if not sx then return end
	local lift = (u.posture == "sit") and 32 or ((u.posture == "lay") and 90 or 0)
	draw.SimpleTextOutlined(u.name or "?", "BobbaName", sx, sy - (92 - lift) * k, u.id == R.you and Color(255, 230, 120) or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 200))
end

-- Nitro's AvatarVisualization depths: an avatar a little in front of its spot, lying further, your
-- own a hair more (so you're on top of someone on the same tile)
local AVATAR_DEPTH, AVATAR_LAY_DEPTH, OWN_DEPTH = -0.01, -0.409, 0.001

local function info(kind)
	return R.furniInfo and R.furniInfo(kind) or nil
end

-- where a wall furni being placed would hang with the mouse over a wall: its wall location, or nil
local function wallSpot(kind, h)
	if not h or h.type ~= 2 or not h.direction then return nil end
	local fi = info(kind)
	-- (its size on the wall: the furni's logic dimensions, once its file is loaded)
	local x, y, z = R.wallPlacement(h.plane, h.wallX, h.wallY, fi and fi.sizeX or 1, fi and fi.sizeZ or 1, fi and fi.centerZ or 0)
	if not x then return nil end
	return R.wallString(x, y, z, h.direction)
end

-- the furni being placed or moved: where the mouse is
local function ghost()
	local pl = R.placing
	local h = V.hover
	if not pl or not h then return nil end
	-- the same table each frame (the addon keeps the furni's animation with it)
	local g = pl.ghost or { id = pl.id or "ghost", kind = pl.kind, state = 0, ghost = true }
	pl.ghost = g
	local fi = info(pl.kind)
	if fi and fi.wall then
		g.wall = wallSpot(pl.kind, h)
		if not g.wall then return nil end
		return g
	end
	if not h.floor then return nil end
	g.x, g.y, g.z, g.dir = h.tileX, h.tileY, h.tileZ, pl.dir
	return g
end

-- a furni's pictures on screen (from the addon), each with its depth
local function furniSprites(it, list, now)
	if not R.furniDrawer then return end
	local ix, iy, iz = itemPosition(it)
	local sx, sy, k, depth = V.project(ix, iy, iz)
	if not sx then return end
	local ok, sprites = pcall(R.furniDrawer, it, { sx = sx, sy = sy, k = k, now = now, alpha = it.ghost and 0.5 or 1 })
	if not ok then ErrorNoHalt("[Bobba] furni drawer: " .. tostring(sprites) .. "\n") R.furniDrawer = nil return end
	for i, s in ipairs(sprites or {}) do
		-- Nitro: the object's screen depth + the sprite's own (and a tiny bit per sprite, in order)
		list[#list + 1] = { z = (depth or 0) + (s.depth or 0) + 3.7e-11 * i, draw = s.draw, item = (not it.ghost) and it or nil, sprite = s }
	end
end

-- phase "behind": whoever is in the doorway (the view draws the wall with the door hole over them
-- again, so they're only seen through the hole; returns whether there was anyone); "front":
-- everyone else and every furni, deepest first (like Nitro's RoomSpriteCanvas)
V.drawUnits = function(phase)
	if V.mode ~= "room" then return end
	local list = {}
	for _, u in pairs(R.units) do
		local x, y, z = position(u)
		local behind = BOBBA.rooms.atDoor(V.room, x, y, z)
		if (phase == "behind") == behind then
			local _, _, _, depth = V.project(x, y, z)
			local rd = (u.posture == "lay" and not u.to) and AVATAR_LAY_DEPTH or AVATAR_DEPTH
			if u.id == R.you then rd = rd - OWN_DEPTH end
			list[#list + 1] = { z = (depth or 0) + rd, unit = u }
		end
	end
	if phase == "front" then
		local now = SysTime()
		local moving = R.placing and R.placing.id
		for id, it in pairs(R.items) do
			if id ~= moving then furniSprites(it, list, now) end
		end
		local g = ghost()
		if g then furniSprites(g, list, now) end
	end
	table.sort(list, function(a, b) return a.z > b.z end)
	local hits = {}
	local unitHits = {}
	for _, e in ipairs(list) do
		if e.unit then
			drawUnit(e.unit)
			-- where it can be clicked: about a standing avatar's size (64 x 110 Habbo pixels)
			local x, y, z = position(e.unit)
			local sx, sy, k = V.project(x, y, z)
			if sx then unitHits[#unitHits + 1] = { unit = e.unit, x = sx - 20 * k, y = sy - 100 * k, w = 40 * k, h = 104 * k } end
		else
			e.draw()
			if e.item and e.sprite.mouse then hits[#hits + 1] = { item = e.item, x = e.sprite.x, y = e.sprite.y, w = e.sprite.w, h = e.sprite.h, hit = e.sprite.hit, tag = e.sprite.tag } end
		end
	end
	if phase == "behind" then return #list > 0 end
	-- the mood light over the whole room (nitro-react's AdjustmentFilter: each colour multiplied)
	local t = V.roomTint
	if t then
		render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD)
		draw.NoTexture()
		surface.SetDrawColor(t.r, t.g, t.b, 255)
		surface.DrawRect(0, 0, ScrW(), ScrH())
		render.OverrideBlend(false)
	end
	R.hits = hits
	R.unitHits = unitHits
	for _, u in pairs(R.units) do drawName(u) end
	if R.chatState then R.chatState.draw() end
end

-- the furni under the mouse: the front-most picture that is solid there (the drawer's hit(); without
-- one, the picture's box)
-- the unit under the mouse, the front-most
function R.unitAt(mx, my)
	local hits = R.unitHits or {}
	for i = #hits, 1, -1 do
		local h = hits[i]
		if mx >= h.x and mx < h.x + h.w and my >= h.y and my < h.y + h.h then return h.unit end
	end
	return nil
end

function R.itemAt(mx, my)
	local hits = R.hits or {}
	for i = #hits, 1, -1 do
		local h = hits[i]
		-- (and the tag of the picture hit: a dice's top "activate", its side "deactivate")
		if mx >= h.x and mx < h.x + h.w and my >= h.y and my < h.y + h.h and (not h.hit or h.hit(mx, my)) then return h.item, h.tag end
	end
	return nil
end

-- clicking: placing a furni puts it down; a furni is selected (and you walk onto it when it's sat,
-- laid or walked on; twice quickly uses it); the floor is walked to
local lastClick = { id = nil, t = 0 }
BOBBA.events.on("roomClick", "bobba.room.walk", function(hit)
	if V.mode ~= "room" then return end
	if R.placing and R.placing.paint then
		-- a wallpaper, floor or landscape: onto the room (Nitro previews it while the mouse is on the room)
		P.send("inventory.place", { id = R.placing.inventoryId })
		R.placing = nil
		return
	end
	if R.placing then
		local pl = R.placing
		local fi = info(pl.kind)
		local wall = fi and fi.wall and wallSpot(pl.kind, hit) or nil
		if hit.floor and not (fi and fi.wall) or wall then
			if pl.id then
				P.send("room.item.move", { id = pl.id, x = hit.tileX, y = hit.tileY, dir = pl.dir, wall = wall })
				R.placing = nil
			elseif pl.inventoryId then
				-- from the inventory (Nitro's attemptItemPlacement: one of the group); with the setting
				-- "Place multiple objects" the next of the same kind follows the mouse straight away
				P.send("inventory.place", { id = pl.inventoryId, x = hit.tileX, y = hit.tileY, dir = pl.dir, wall = wall })
				local nextId = GetConVar("bobba_setting_placemultiple") and GetConVar("bobba_setting_placemultiple"):GetBool()
					and BOBBA.shop and BOBBA.shop.nextOfKind and BOBBA.shop.nextOfKind(pl.kind, pl.inventoryId)
				if nextId then
					pl.inventoryId = nextId
				else
					R.placing = nil
				end
			else
				P.send("room.item.place", { kind = pl.kind, x = hit.tileX, y = hit.tileY, dir = pl.dir, wall = wall })
				R.placing = nil
			end
		end
		return
	end
	local mx, my = input.GetCursorPos()
	-- an avatar: its infostand (yours has "Change looks"), no walking
	local unit = R.unitAt(mx, my)
	if unit then
		R.selected = nil
		R.selectedUnit = unit.id
		-- (its menu and infostand: roomwindows.lua)
		if BOBBA.roomWindows and BOBBA.roomWindows.selectUnit then BOBBA.roomWindows.selectUnit(unit.id) end
		R.updateInfo()
		return
	end
	if R.selectedUnit then
		R.selectedUnit = nil
		if BOBBA.roomWindows and BOBBA.roomWindows.selectUnit then BOBBA.roomWindows.selectUnit(nil) end
		R.updateInfo()
	end
	local it, tag = R.itemAt(mx, my)
	if it then
		local now = SysTime()
		if lastClick.id == it.id and now - lastClick.t < 0.4 then
			-- (some furni open a window instead: a trophy, a background toner; furniwidgets.lua)
			if not (R.widgets and R.widgets.open(it)) then P.send("room.item.use", { id = it.id, tag = tag }) end
			lastClick.id = nil
		else
			lastClick.id, lastClick.t = it.id, now
		end
		R.selected = it.id
		R.updateInfo()
		local fi = info(it.kind)
		if fi and not fi.wall and (fi.sit or fi.lay or fi.walk) then
			-- onto the furni: the tile under the mouse if that's one of its tiles, else its own
			local x, y = it.x, it.y
			if hit.floor then
				local w, l = fi.width or 1, fi.length or 1
				if it.dir == 2 or it.dir == 6 then w, l = l, w end
				if hit.tileX >= it.x and hit.tileX < it.x + w and hit.tileY >= it.y and hit.tileY < it.y + l then x, y = hit.tileX, hit.tileY end
			end
			P.send("room.walk", { x = x, y = y })
		end
		return
	end
	if R.selected then R.selected = nil R.updateInfo() end
	if hit.floor then P.send("room.walk", { x = hit.tileX, y = hit.tileY }) end
end)

BOBBA.events.on("roomRightClick", "bobba.room.place", function()
	if R.placing then R.placing = nil end
end)

-- R turns the furni being placed (or the selected one). The chat input has the keyboard in a room,
-- so it calls this when R is pressed with nothing typed; returns whether R turned something.
function R.pressR()
	if V.mode ~= "room" then return false end
	R.turnedAt = SysTime()
	if R.placing then
		-- (the ways the furni can face, Nitro's getValidRoomObjectDirection; a wall furni doesn't turn)
		local fi = info(R.placing.kind)
		if fi and fi.wall then return true end
		local dirs = R.placing.dirs or (fi and fi.directions and #fi.directions > 0 and fi.directions) or { 0, 2, 4, 6 }
		local i = 1
		for j, d in ipairs(dirs) do if d == R.placing.dir then i = j end end
		R.placing.dir = dirs[i % #dirs + 1]
		return true
	elseif R.selected and R.current and R.current.canEdit and not (R.items[R.selected] and R.items[R.selected].wall) then
		P.send("room.item.rotate", { id = R.selected })
		return true
	end
	return false
end

-- a wallpaper, floor or landscape being put on: the room shows it while the mouse is over the room
local PAINT_LOOK = { wallpaper = "wall", floor = "floor", landscape = "landscape" }
hook.Add("Think", "bobba.room.paint", function()
	local previewing = R.paintPreview
	local pl = R.placing
	local want = (V.mode == "room" and pl and pl.paint and V.hover) and pl or nil
	local key = want and (want.paint .. "|" .. tostring(want.data)) or nil
	if key == (previewing and previewing.key) then return end
	-- back to the room's own look, then the new preview
	if previewing then V.look[previewing.part] = previewing.was end
	R.paintPreview = nil
	if want and PAINT_LOOK[want.paint] then
		local part = PAINT_LOOK[want.paint]
		R.paintPreview = { key = key, part = part, was = V.look[part] }
		V.look[part] = want.data or ""
	end
	V.dirty = true
end)

-- windows cut holes in the walls (the view draws them, V.masks): where each is and its mask
local maskKey = ""
hook.Add("Think", "bobba.room.masks", function()
	if V.mode ~= "room" then return end
	local list, keys = {}, {}
	for _, it in pairs(R.items) do
		if it.wall then
			local fi = info(it.kind)
			if fi and fi.maskType then
				local x, y, z = R.wallLocation(it.wall)
				if x then
					list[#list + 1] = { x = x, y = y, z = z, type = fi.maskType, id = it.id }
				end
			end
		end
	end
	table.sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
	for i, m in ipairs(list) do keys[i] = m.type .. "@" .. m.x .. "," .. m.y .. "," .. m.z end
	local key = table.concat(keys, ";")
	if key ~= maskKey then
		maskKey = key
		V.masks = list
		V.dirty = true
	end
end)

-- (R is read here whatever has the keyboard, unless it's a text box with something typed in it:
-- the chat input with nothing typed, a window, the room. The chat input also turns it as the key
-- comes in, so the "r" isn't typed; R.turnedAt stops it turning twice.)
local rWasDown = false
hook.Add("Think", "bobba.room.keys", function()
	local down = input.IsKeyDown(KEY_R)
	if down and not rWasDown and (R.turnedAt or 0) < SysTime() - 0.2 then
		local f = vgui.GetKeyboardFocus and vgui.GetKeyboardFocus()
		local typing = IsValid(f) and f.GetCaretPos ~= nil and (f:GetValue() or "") ~= ""
		if not typing then R.pressR() end
	end
	rWasDown = down
end)

-- --- the selected furni: its name and what you can do with it (Habbo's infostand) -----------------
local function button(parent, label, fn)
	local b = vgui.Create("DButton", parent)
	b:SetText(label)
	b:SetFont("BobbaInfo")
	b:SetTextColor(color_white)
	b:SetTall(24)
	b:Dock(TOP)
	b:DockMargin(0, 4, 0, 0)
	b.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and Color(90, 110, 140) or Color(60, 75, 100))
	end
	b.DoClick = fn
	return b
end

function R.updateInfo()
	if IsValid(R.infoPanel) then R.infoPanel:Remove() end
	local unit = R.selectedUnit and R.units[R.selectedUnit]
	-- (someone selected: nitro-react's avatar menu and infostand, roomwindows.lua)
	if unit and BOBBA.roomWindows and BOBBA.roomWindows.selectUnit then return end
	if unit and V.mode == "room" then
		local p = vgui.Create("DPanel")
		R.infoPanel = p
		p:SetSize(180, 0)
		p:DockPadding(8, 8, 8, 8)
		p.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, Color(20, 24, 32, 230)) end
		local name = vgui.Create("DLabel", p)
		name:SetFont("BobbaInfo")
		name:SetText(unit.name or "?")
		name:SetTextColor(color_white)
		name:Dock(TOP)
		local n = 0
		if unit.id == R.you and BOBBA.avatarEditor and BOBBA.avatarEditor.open then
			button(p, BOBBA.lang.has("infostand.button.changelooks") and BOBBA.lang.get("infostand.button.changelooks") or "Change looks", function()
				BOBBA.avatarEditor.open()
			end)
			n = 1
		end
		p:SetTall(16 + 18 + n * 28)
		-- (above the toolbar: Nitro's infostand is 10 over it, 10 from the right)
		local us = BOBBA.ui and BOBBA.ui.scale and BOBBA.ui.scale() or 1
		p:SetPos(ScrW() - p:GetWide() - 10 * us, ScrH() - p:GetTall() - (55 + 10) * us)
		p:MakePopup()
		p:SetKeyboardInputEnabled(false)
		return
	end
	local it = R.selected and R.items[R.selected]
	if not it or V.mode ~= "room" then return end
	local fi = info(it.kind)
	local edit = R.current and R.current.canEdit
	local p = vgui.Create("DPanel")
	R.infoPanel = p
	p:SetSize(180, 0)
	p:DockPadding(8, 8, 8, 8)
	p.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, Color(20, 24, 32, 230)) end
	local name = vgui.Create("DLabel", p)
	name:SetFont("BobbaInfo")
	name:SetText(fi and fi.name ~= "" and fi.name or it.kind)
	name:SetTextColor(color_white)
	name:SetWrap(true)
	name:SetAutoStretchVertical(true)
	name:Dock(TOP)
	local n = 0
	if edit then
		button(p, "Use", function() P.send("room.item.use", { id = it.id }) end)
		if not it.wall then
			button(p, "Rotate  (R)", function() P.send("room.item.rotate", { id = it.id }) end)
			n = n + 1
		end
		button(p, "Move", function()
			R.placing = { kind = it.kind, dir = it.dir, id = it.id }
			R.selected = nil
			R.updateInfo()
		end)
		button(p, "Pick up", function() P.send("room.item.pickup", { id = it.id }) end)
		n = n + 3
	end
	p:SetTall(16 + 18 + n * 28)
	-- (above the toolbar: Nitro's infostand is 10 over it, 10 from the right)
		local us = BOBBA.ui and BOBBA.ui.scale and BOBBA.ui.scale() or 1
		p:SetPos(ScrW() - p:GetWide() - 10 * us, ScrH() - p:GetTall() - (55 + 10) * us)
	p:MakePopup()
	p:SetKeyboardInputEnabled(false)
end

concommand.Add("bobba_room", function(_, _, args)
	local id = tonumber(args[1])
	if not id then print("bobba_room <id>   (bobba_rooms lists them)") return end
	P.send("room.enter", { id = id })
end)

-- bobba_furni <kind>: place a furni (the server checks you may); click to put it down, R turns it,
-- right click cancels
concommand.Add("bobba_furni", function(_, _, args)
	local kind = args[1]
	if not kind then print("bobba_furni <kind>   e.g. bobba_furni throne") return end
	if not R.current then print("go into a room first") return end
	R.placing = { kind = kind, dir = tonumber(args[2]) or 2 }
	R.selected = nil
	R.updateInfo()
end)

-- tell the server we're ready for the room (also after a Lua reload)
local function ready() P.send("room.ready", {}) end
hook.Add("InitPostEntity", "bobba.room", ready)
if IsValid(LocalPlayer()) then ready() end
