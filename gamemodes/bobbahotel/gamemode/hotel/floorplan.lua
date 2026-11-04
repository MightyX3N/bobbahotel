-- The floor plan editor (server): a room's owner draws its tiles and their heights, where the door
-- is and which way people come in, and sets the walls' height and the walls' and floor's thickness.
-- Saved, the room gets a shape of its own (the layout it was made from stays in its info) and
-- everyone in it comes in again, as Arcturus's FloorPlanEditorSaveEvent does.
--
-- Messages from players: floorplan.get {}   -> floorplan.data { heightmap, door = { x, y, dir }, wallHeight,
--                                                 wallThickness, floorThickness, blocked = { "x,y", ... }, maxSize }
--                        floorplan.save { heightmap, doorX, doorY, doorDir, wallThickness, floorThickness, wallHeight }
-- Messages to players:   floorplan.error { errors = { { key, text }, ... } }   (Habbo's text keys, and English)
--
-- Who may: the room's owner (or staff acting as owner), with bobba.room.floorplan; in Habbo it's
-- for Habbo Club members (the hotel's setting floorplan.club, "1" by default: club level 1).

BOBBA.floorplan = BOBBA.floorplan or {}
local FP = BOBBA.floorplan
local live = BOBBA.live

FP.MAX_SIZE = 64          -- tiles a side (Arcturus's MAXIMUM_FLOORPLAN_WIDTH_LENGTH)
FP.MAX_HEIGHT = 26        -- Nitro's highest tile ("q")

BOBBA.perms.define("bobba.room.floorplan", { default = "user", description = "Use the floor plan editor in your own rooms" })

function FP.migrate()
	-- a room's own shape ('' = the layout's) and its door
	BOBBA.store.migrate("core.018_room_floorplan", {
		"ALTER TABLE bobbahotel_rooms ADD COLUMN heightmap TEXT NOT NULL DEFAULT ''",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN door_x INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN door_y INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN door_dir INTEGER NOT NULL DEFAULT 2",
	})
end

local function P() return BOBBA.platform end

-- the club level the editor needs (0 = everyone)
function FP.clubNeeded()
	return tonumber(BOBBA.store.setting("floorplan.club", "1")) or 1
end

-- may this player edit room r's floor plan? true, or false and why (a text key and English)
function FP.allowed(player, r)
	local A = BOBBA.access
	if not (A and A.ownerLevel(player, r.info)) then return false, { "floor.plan.editor.no.rights", "Only the room's owner can change its floor plan." } end
	if A.isStaff(player) then return true end
	if not BOBBA.perms.has(player, "bobba.room.floorplan") then return false, { "floorplan.permission", "You may not use the floor plan editor." } end
	local need = FP.clubNeeded()
	local have = BOBBA.wallet and BOBBA.wallet.clubLevel(P().playerKey(player)) or 0
	if need > 0 and have < need then return false, { "floor.plan.editor.club.only", "The floor plan editor is for Habbo Club members." } end
	return true
end

-- the tiles floor furni stand on (they can't be removed or raised: "x,y" = true)
function FP.blocked(r)
	local out = {}
	for _, it in pairs(r.items or {}) do
		if (it.wall or "") == "" and it.x then
			-- (one still being looked up: at least the tile it's on)
			local tiles = it.def and BOBBA.items.footprint(it.def, it.x, it.y, it.dir or 0) or { { x = it.x, y = it.y } }
			for _, t in ipairs(tiles) do out[t.x .. "," .. t.y] = true end
		end
	end
	return out
end

-- the biggest a side may be: 64, or more when the room already is (some of Habbo's public rooms)
local function maxSize(r)
	local l = r.layout
	local w, h = 0, 0
	for _, row in ipairs(BOBBA.util.split(l.heightmap, "\r")) do w = math.max(w, #row) h = h + 1 end
	return math.min(BOBBA.rooms.MAX_SIZE, math.max(FP.MAX_SIZE, w, h))
end

function FP.data(r)
	local blocked = {}
	for k in pairs(FP.blocked(r)) do blocked[#blocked + 1] = k end
	table.sort(blocked)
	local d = r.layout.door
	return {
		id = r.id, heightmap = r.layout.heightmap, door = { x = d.x, y = d.y, dir = d.dir or 2 },
		wallHeight = tonumber(r.info.wall_height) or -1,
		wallThickness = tonumber(r.info.wall_thickness) or 0, floorThickness = tonumber(r.info.floor_thickness) or 0,
		blocked = blocked, maxSize = maxSize(r), maxHeight = FP.MAX_HEIGHT,
	}
end

local E = {
	chars = { "notification.floorplan_editor.error.title", "The floor plan has characters that can't be tiles." },
	rows = { "notification.floorplan_editor.error.message.rows", "Every row of the floor plan must be as long as the first." },
	empty = { "notification.floorplan_editor.error.message.effective_height_is_0", "The room needs at least one tile." },
	area = { "notification.floorplan_editor.error.message.too_large_area", "The room is too big." },
	tall = { "notification.floorplan_editor.error.message.too_large_height", "The room has too many rows." },
	wide = { "notification.floorplan_editor.error.message.too_large_width", "The room is too wide." },
	high = { "notification.floorplan_editor.error.message.too_high", "A tile is too high." },
	doorOut = { "notification.floorplan_editor.error.message.entry_tile_outside_map", "The door is outside the room." },
	doorTile = { "notification.floorplan_editor.error.message.entry_not_on_tile", "The door must be on a tile." },
	doorDir = { "notification.floorplan_editor.error.message.invalid_entry_tile_direction", "The door's direction isn't one of the eight." },
	wall = { "notification.floorplan_editor.error.message.invalid_wall_thickness", "That wall thickness isn't one of the choices." },
	floor = { "notification.floorplan_editor.error.message.invalid_floor_thickness", "That floor thickness isn't one of the choices." },
	wallHeight = { "notification.floorplan_editor.error.message.invalid_walls_fixed_height", "The walls' height must be from 0 to 16." },
	furni = { "notification.floorplan_editor.error.message.change_blocked_by_room_item", "Furni stands where the floor would change. Move it first." },
}
FP.ERRORS = E

-- Checks a floor plan; returns the plan to save, or nil and the errors ({ key, english } each).
-- (Arcturus's checks, and furni: a tile under furni can't go or change height)
function FP.check(r, data)
	local errors = {}
	local function add(e) errors[#errors + 1] = e end
	local map = tostring(data.heightmap or ""):gsub("\r\n", "\r"):gsub("\n", "\r")
	-- (rows left empty at the end are dropped; X is x; letters are heights in lower case)
	map = map:gsub("\r+$", ""):gsub("X", "x"):lower()
	local size = maxSize(r)
	if #map > size * (size + 1) then return nil, { E.area } end
	if map:find("[^x0-9a-z\r]") then add(E.chars) end
	local rows = BOBBA.util.split(map, "\r")
	local width = #(rows[1] or "")
	for _, row in ipairs(rows) do
		if #row ~= width then add(E.rows) break end
	end
	if not map:find("[0-9a-wyz]") then add(E.empty) end
	if #rows > size then add(E.tall)
	else for _, row in ipairs(rows) do if #row > size or #row == 0 then add(E.wide) break end end end
	for c in map:gmatch("[0-9a-wyz]") do
		if tonumber(c, 36) > FP.MAX_HEIGHT then add(E.high) break end
	end
	if #errors > 0 then return nil, errors end
	local dx, dy, dir = math.floor(tonumber(data.doorX) or -1), math.floor(tonumber(data.doorY) or -1), math.floor(tonumber(data.doorDir) or -1)
	if dx < 0 or dx >= width or dy < 0 or dy >= #rows then add(E.doorOut)
	elseif rows[dy + 1]:sub(dx + 1, dx + 1) == "x" then add(E.doorTile) end
	if dir < 0 or dir > 7 then add(E.doorDir) end
	local wt, ft = math.floor(tonumber(data.wallThickness) or 9), math.floor(tonumber(data.floorThickness) or 9)
	if wt < -2 or wt > 1 then add(E.wall) end
	if ft < -2 or ft > 1 then add(E.floor) end
	local wh = live.validWallHeight(data.wallHeight == nil and -1 or data.wallHeight)
	if not wh then add(E.wallHeight) end
	-- furni: their tiles stay, at the same height
	local old = r.layout.heightmap
	local oldRows = BOBBA.util.split(old, "\r")
	for k in pairs(FP.blocked(r)) do
		local x, y = k:match("^(%-?%d+),(%-?%d+)$")
		x, y = tonumber(x), tonumber(y)
		local was = (oldRows[y + 1] or ""):sub(x + 1, x + 1)
		local now = (rows[y + 1] or ""):sub(x + 1, x + 1)
		if now == "" or now == "x" or (was ~= "" and was:lower() ~= now) then add(E.furni) break end
	end
	if #errors > 0 then return nil, errors end
	return { heightmap = table.concat(rows, "\r"), doorX = dx, doorY = dy, doorDir = dir, wallThickness = wt, floorThickness = ft, wallHeight = wh }
end

-- Saves room r's floor plan; everyone in it comes in again (at the door). true, or false and errors.
function FP.save(player, r, data)
	local ok, why = FP.allowed(player, r)
	if not ok then return false, { why } end
	local plan, errors = FP.check(r, data)
	if not plan then return false, errors end
	BOBBA.store.query("UPDATE bobbahotel_rooms SET heightmap = ?, door_x = ?, door_y = ?, door_dir = ?, wall_thickness = ?, floor_thickness = ?, wall_height = ? WHERE id = ?",
		{ plan.heightmap, plan.doorX, plan.doorY, plan.doorDir, plan.wallThickness, plan.floorThickness, plan.wallHeight, r.id })
	FP.reload(r.id)
	BOBBA.events.emit("roomFloorPlanChanged", r.id)
	return true
end

-- Everyone out of the room (so it's loaded again with its new shape) and back in at the door
function FP.reload(id)
	local r = live.rooms[id]
	if not r then return end
	local players = {}
	for _, uid in ipairs(r.order) do
		local u = r.units[uid]
		if u.player then players[#players + 1] = u.player end
	end
	for _, p in ipairs(players) do live.leave(p) end
	-- (nobody left: it's unloaded; if something kept it, it's dropped anyway)
	if live.rooms[id] == r then live.rooms[id] = nil BOBBA.events.emit("roomUnloaded", r) end
	for _, p in ipairs(players) do
		local ok = live.enter(p, id, nil, { override = true })
		if not ok then P().send("room.hotelview", {}, p) end
	end
end

function FP.start()
	FP.migrate()
	local p = P()
	local function inRoom(player)
		local u = live.byPlayer[player]
		return u and u.room
	end
	p.receive("floorplan.get", function(player)
		local r = inRoom(player)
		if not r then return end
		local ok, why = FP.allowed(player, r)
		if not ok then p.send("floorplan.error", { errors = { why } }, player) return end
		p.send("floorplan.data", FP.data(r), player)
	end)
	local last = {}
	p.onLeave(function(player) last[player] = nil end)
	p.receive("floorplan.save", function(player, data)
		-- (one save a second at most: each one moves everyone)
		local now = p.clock()
		if last[player] and now - last[player] < 1 then return end
		last[player] = now
		local r = inRoom(player)
		if not r then return end
		local ok, errors = FP.save(player, r, data)
		if not ok then p.send("floorplan.error", { errors = errors }, player) end
	end)
end
