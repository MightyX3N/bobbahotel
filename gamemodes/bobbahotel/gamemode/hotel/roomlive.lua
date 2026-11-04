-- Rooms with people in them (server). Rooms are saved in SQLite; a room is loaded when someone
-- enters it. Every 0.5 seconds (Arcturus's room cycle) everyone walking takes one step.
--
--   BOBBA.live.create(ownerKey, ownerName, "model_a", "My room")   -> room id
--   BOBBA.live.enter(player, roomId)       BOBBA.live.leave(player)
--   BOBBA.live.walk(player, x, y)
--
-- Messages to players:  room.load { id, name, owner, layout, heightmap, wallHeight, floor, wallpaper, units = {...}, items = {...},
--                                   canEdit (may move furni here), canPlace (may place furni from nowhere) }
--                       room.units { unit, ... }   (each: id, name, x, y, z, dir, to = {x, y, z} while stepping,
--                                                   posture "sit"/"lay" and height (the seat's) when on furni)
--                       furni: see items.lua
--                       room.unit.remove { id }
-- Messages from players: room.enter { id }, room.walk { x, y }, room.ready {}

BOBBA.live = BOBBA.live or { rooms = {}, byPlayer = {}, nextUnit = 1 }
local live = BOBBA.live
local PF = BOBBA.pathfinder

live.STEP_TIME = 0.5

BOBBA.perms.define("bobba.room.create", { default = "user", description = "Create rooms" })

function live.migrate()
	BOBBA.store.migrate("core.002_rooms", {
		[[CREATE TABLE bobbahotel_rooms (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			owner TEXT NOT NULL,
			owner_name TEXT NOT NULL,
			name TEXT NOT NULL,
			description TEXT NOT NULL DEFAULT '',
			layout TEXT NOT NULL,
			wall_height INTEGER NOT NULL DEFAULT -1,
			created INTEGER NOT NULL
		)]],
		"CREATE INDEX bobbahotel_rooms_owner ON bobbahotel_rooms (owner)",
	})
	-- the room's look: its floor and wallpaper ('' = the default; what the ids mean is up to the
	-- addon that draws them, e.g. bobba_habbo's Habbo floors and wallpapers)
	BOBBA.store.migrate("core.004_room_look", {
		"ALTER TABLE bobbahotel_rooms ADD COLUMN floor TEXT NOT NULL DEFAULT ''",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN wallpaper TEXT NOT NULL DEFAULT ''",
	})
	-- and what's seen through its windows (Habbo's landscapes)
	BOBBA.store.migrate("core.014_room_landscape", {
		"ALTER TABLE bobbahotel_rooms ADD COLUMN landscape TEXT NOT NULL DEFAULT ''",
	})
end

-- A floor or wallpaper id: letters, digits, _ . - (at most 32), or '' for the default
function live.validLook(v)
	if v == nil then return nil end
	v = tostring(v)
	if v == "" or v == "default" then return "" end
	if #v > 32 or not v:match("^[%w_%.%-]+$") then return nil end
	return v
end

-- what = "floor", "wallpaper" or "landscape"
function live.setLook(id, what, v)
	v = live.validLook(v)
	if v == nil or (what ~= "floor" and what ~= "wallpaper" and what ~= "landscape") or not live.info(id) then return false end
	BOBBA.store.query("UPDATE bobbahotel_rooms SET " .. what .. " = ? WHERE id = ?", { v, tonumber(id) })
	live.refresh(id)
	return true
end

local function clean(name)
	name = tostring(name or ""):gsub("[%c]", ""):sub(1, 60)
	name = name:match("^%s*(.-)%s*$")
	return name
end

function live.create(ownerKey, ownerName, layoutId, name)
	if not BOBBA.registry.get("layout", layoutId) then return nil, "unknown layout " .. tostring(layoutId) end
	name = clean(name)
	if name == "" then return nil, "a room needs a name" end
	BOBBA.store.query("INSERT INTO bobbahotel_rooms (owner, owner_name, name, layout, wall_height, created) VALUES (?, ?, ?, ?, ?, ?)",
		{ tostring(ownerKey), clean(ownerName), name, layoutId, -1, math.floor(BOBBA.platform.time()) })
	local id = tonumber(BOBBA.store.row("SELECT last_insert_rowid() AS id").id)
	BOBBA.events.emit("roomCreated", id)
	return id
end

-- (GMod's SQLite gives every value as text: numbers are turned back into numbers here)
function live.info(id)
	local r = BOBBA.store.row("SELECT * FROM bobbahotel_rooms WHERE id = ?", { tonumber(id) or -1 })
	if not r then return nil end
	r.id, r.wall_height, r.created = tonumber(r.id), tonumber(r.wall_height) or -1, tonumber(r.created)
	r.floor, r.wallpaper, r.landscape = r.floor or "", r.wallpaper or "", r.landscape or ""
	return r
end

function live.list()
	local rows = BOBBA.store.query("SELECT id, name, owner_name, layout FROM bobbahotel_rooms ORDER BY id")
	for _, r in ipairs(rows) do r.id = tonumber(r.id) end
	return rows
end

-- Wall height (Habbo's floor plan editor setting, as Nitro reads it): 0 to 16 in steps of 0.125,
-- walls are then 3.6 + 2 x that high; -1 = Nitro's automatic walls (3.6 + the room's highest floor).
-- A room set to -1 follows the hotel's default. The hotel's default, 0.375, makes walls 4.35 high:
-- measured from Habbo, where the wall above the door is about 0.34 of the door's height (Nitro's
-- automatic wall leaves only 0.35 of 3.6 above its 3.25 high door).
live.DEFAULT_WALL_HEIGHT = 0.375

function live.validWallHeight(v)
	v = tonumber(v)
	if not v then return nil end
	if v == -1 then return -1 end
	if v < 0 or v > 16 then return nil end
	return math.floor(v * 8 + 0.5) / 8
end

-- the hotel's default (-1 here means Nitro's automatic walls)
function live.defaultWallHeight()
	return live.validWallHeight(BOBBA.store.setting("default_wall_height", tostring(live.DEFAULT_WALL_HEIGHT))) or live.DEFAULT_WALL_HEIGHT
end

-- what a room's walls are built with: its own setting, or the hotel's default
function live.wallHeightOf(info)
	if info.wall_height and info.wall_height ~= -1 then return info.wall_height end
	return live.defaultWallHeight()
end

function live.setDefaultWallHeight(v)
	v = live.validWallHeight(v)
	if not v then return false end
	BOBBA.store.setSetting("default_wall_height", v)
	for id in pairs(live.rooms) do live.refresh(id) end
	return true
end

function live.setWallHeight(id, v)
	v = live.validWallHeight(v)
	if not v or not live.info(id) then return false end
	BOBBA.store.query("UPDATE bobbahotel_rooms SET wall_height = ? WHERE id = ?", { v, tonumber(id) })
	live.refresh(id)
	return true
end

-- The room everyone comes to first. Made the first time the hotel starts.
function live.homeRoom()
	local id = tonumber(BOBBA.store.setting("home_room", ""))
	if id and live.info(id) then return id end
	id = live.create("server", "Bobba Hotel", "model_a", "Welcome Lounge")
	BOBBA.store.setSetting("home_room", id)
	return id
end

local function load(id)
	local r = live.rooms[id]
	if r then return r end
	local info = live.info(id)
	if not info then return nil, "no room " .. tostring(id) end
	local layout = BOBBA.registry.get("layout", info.layout)
	if not layout then return nil, "room " .. id .. " uses a layout that isn't installed: " .. info.layout end
	r = {
		id = id, info = info, layout = layout,
		grid = (function()
			local g = PF.grid(layout.heightmap, layout.door.x, layout.door.y, layout.door.dir)
			g.doorStraight = true -- out of the door straight, then turn
			-- (people walk through each other unless the room's settings say no)
			g.allowWalkthrough = tonumber(info.allow_walkthrough or 1) == 1
			return g
		end)(),
		units = {}, order = {},
	}
	live.rooms[id] = r
	BOBBA.items.load(r)
	BOBBA.events.emit("roomLoaded", r)
	return r
end

local function unload(r)
	live.rooms[r.id] = nil
	BOBBA.events.emit("roomUnloaded", r)
end

local function snapshot(u)
	return { id = u.id, name = u.name, key = u.key, x = u.x, y = u.y, z = u.z, dir = u.dir, to = u.to, posture = u.posture, height = u.height,
		figure = u.figure, gender = u.gender }
end
live.snapshot = snapshot

-- room.load for one player
local function roomMessage(r, u, units)
	return {
		id = r.id, name = r.info.name, owner = r.info.owner_name, layout = r.info.layout,
		heightmap = r.layout.heightmap, wallHeight = live.wallHeightOf(r.info), you = u.id, units = units,
		floor = r.info.floor, wallpaper = r.info.wallpaper, landscape = r.info.landscape,
		items = BOBBA.items.list(r), itemsComing = BOBBA.items.pending(r),
		canEdit = u.player ~= nil and BOBBA.items.canEdit(u.player, r) or false,
		-- (the room's settings and what this player may do in it: roomaccess.lua)
		access = BOBBA.access.forPlayer(r, u),
		canPlace = u.player ~= nil and BOBBA.perms.has(u.player, "bobba.staff.place") or false,
	}
end

-- Sends the room again to everyone in it (after its look changed)
function live.refresh(id)
	local r = live.rooms[tonumber(id)]
	if not r then return end
	r.info = live.info(r.id)
	local units = {}
	for _, uid in ipairs(r.order) do units[#units + 1] = snapshot(r.units[uid]) end
	for _, uid in ipairs(r.order) do
		local u = r.units[uid]
		if u.player then BOBBA.platform.send("room.load", roomMessage(r, u, units), u.player) end
	end
end

local function players(r)
	local out = {}
	for _, id in ipairs(r.order) do
		local u = r.units[id]
		if u.player then out[#out + 1] = u.player end
	end
	return out
end

local function broadcast(r, name, data)
	local list = players(r)
	if #list > 0 then BOBBA.platform.send(name, data, list) end
end

function live.leave(player)
	local u = live.byPlayer[player]
	if not u then return end
	live.byPlayer[player] = nil
	local r = u.room
	PF.removeUnit(r.grid, u.x, u.y)
	r.units[u.id] = nil
	for i, id in ipairs(r.order) do if id == u.id then table.remove(r.order, i) break end end
	broadcast(r, "room.unit.remove", { id = u.id })
	BOBBA.events.emit("roomLeft", r, u)
	if #r.order == 0 then unload(r) end
end

-- (at: where they come in instead of the door, e.g. out of a teleport: { x, y, z, dir })
-- (opts.password: what they typed for a room with a password; opts.override: let in at the door)
-- Not let in: false and why ("banned", "full", "password" (asked for), "wrongpassword",
-- "doorbell" (ringing now), "noanswer", "invisible", "not allowed")
function live.enter(player, id, at, opts)
	id = tonumber(id)
	if not live.info(id) then return false, "no room " .. tostring(id) end
	local r, err = load(id)
	if not r then return false, err end
	local A = BOBBA.access
	local current = live.byPlayer[player]
	if A and not (current and current.room == r) then
		if A.unqueue then A.unqueue(player) end
		local ok, why = A.check(r, player, opts)
		if not ok then
			-- the doorbell: out of where they were, waiting in the hotel view for someone to open
			if why == "doorbell" then
				live.leave(player)
				BOBBA.platform.send("room.hotelview", {}, player)
				if not A.ring(r, player) then why = "noanswer" end
			end
			if #r.order == 0 then unload(r) end
			return false, why
		end
	end
	-- leave the old room first (if it's this same room and now empty, it's loaded again below)
	live.leave(player)
	r = live.rooms[id] or load(id)
	if not r then return false, "no room" end
	local allowed = BOBBA.events.emit("roomCanEnter", r, player)
	if allowed == false then
		if #r.order == 0 then unload(r) end
		return false, "not allowed"
	end
	local g = r.grid
	local u = {
		id = live.nextUnit, player = player, room = r,
		key = BOBBA.platform.playerKey(player), name = BOBBA.platform.playerName(player),
		x = r.layout.door.x, y = r.layout.door.y, z = g.doorZ, dir = r.layout.door.dir,
		path = nil,
	}
	if at then u.x, u.y, u.z, u.dir = at.x, at.y, at.z or u.z, at.dir or u.dir end
	u.figure, u.gender = BOBBA.looks.get(u.key)
	live.nextUnit = live.nextUnit + 1
	r.units[u.id] = u
	r.order[#r.order + 1] = u.id
	live.byPlayer[player] = u
	PF.addUnit(g, u.x, u.y)
	local units = {}
	for _, uid in ipairs(r.order) do units[#units + 1] = snapshot(r.units[uid]) end
	BOBBA.platform.send("room.load", roomMessage(r, u, units), player)
	for _, other in ipairs(players(r)) do
		if other ~= player then BOBBA.platform.send("room.units", { snapshot(u) }, other) end
	end
	BOBBA.events.emit("roomEntered", r, u)
	return true
end

-- A unit's new look: everyone in the room sees it
function live.setFigure(u, figure, gender)
	u.figure, u.gender = figure, gender
	if u.room then broadcast(u.room, "room.units", { snapshot(u) }) end
end

-- Arcturus RoomUserRotation.walkDirection: 0 = up (y - 1), 2 = right (x + 1), 4 = down, 6 = left
local DIRS = { ["0,-1"] = 0, ["1,-1"] = 1, ["1,0"] = 2, ["1,1"] = 3, ["0,1"] = 4, ["-1,1"] = 5, ["-1,0"] = 6, ["-1,-1"] = 7 }
function live.direction(x1, y1, x2, y2)
	local dx = x2 > x1 and 1 or (x2 < x1 and -1 or 0)
	local dy = y2 > y1 and 1 or (y2 < y1 and -1 or 0)
	return DIRS[dx .. "," .. dy]
end

function live.walk(player, x, y)
	local u = live.byPlayer[player]
	if not u or u.teleporting or u.kicked then return false end
	x, y = math.floor(tonumber(x) or -1), math.floor(tonumber(y) or -1)
	local t = PF.tile(u.room.grid, x, y)
	if not t or t.state == PF.INVALID then return false end
	local path = PF.find(u.room.grid, u.x, u.y, x, y)
	if not path or #path == 0 then return false end
	u.goal = { x = x, y = y }
	u.path = path
	u.useOnArrive = nil
	u.steer = nil
	return true
end

-- The interact button (E / a controller's A): the furni next to you does what a double-click does,
-- and a seat or bed is sat or lain on. Works whatever the room's movement setting is. true, or false
-- and why.
function live.interact(player, id, tag)
	local u = live.byPlayer[player]
	if not u or u.teleporting or u.kicked then return false end
	local r = u.room
	local it = r.items[tonumber(id) or -1]
	if not it or not it.def then return false, "no such furni" end
	local I = BOBBA.items
	local on, near = false, false
	if it.def.wall then
		near = math.abs(it.x - u.x) <= 2 and math.abs(it.y - u.y) <= 2
	else
		for _, t in ipairs(I.footprint(it.def, it.x, it.y, it.dir)) do
			if t.x == u.x and t.y == u.y then on = true end
			if math.abs(t.x - u.x) <= 1 and math.abs(t.y - u.y) <= 1 then near = true end
		end
	end
	if not near then return false, "too far away" end
	if it.def.present then return BOBBA.gifts.open(r, player, it.id) end
	if not it.def.wall and (it.def.sit or it.def.lay or it.def.walk) then
		if on then return true end
		-- onto its tile closest to you
		local best, bestD
		for _, t in ipairs(I.footprint(it.def, it.x, it.y, it.dir)) do
			local d = (t.x - u.x) ^ 2 + (t.y - u.y) ^ 2
			if not bestD or d < bestD then best, bestD = t, d end
		end
		if live.walk(player, best.x, best.y) then return true end
		return false, "you can't get onto it"
	end
	return I.use(r, player, it.id, tag)
end

-- --- steering (WASD, the arrow keys, a stick): one tile at a time while a direction is held -----------
-- The room's movement setting (rooms.movement): 0 both, 1 clicking only, 2 steering only
live.MOVE_BOTH, live.MOVE_CLICK, live.MOVE_STEER = 0, 1, 2
function live.movement(r)
	return math.floor(tonumber(r.info.movement) or 0)
end

-- the next tile in the held direction (sliding along a wall when a diagonal is blocked): a path of one
local function steerPath(r, u)
	local dx, dy = u.steer[1], u.steer[2]
	local tries = { { dx, dy } }
	if dx ~= 0 and dy ~= 0 then tries[2] = { dx, 0 } tries[3] = { 0, dy } end
	for _, d in ipairs(tries) do
		local tx, ty = u.x + d[1], u.y + d[2]
		local path = PF.find(r.grid, u.x, u.y, tx, ty)
		if path and #path == 1 and path[1].x == tx and path[1].y == ty then
			u.goal = { x = tx, y = ty }
			return path
		end
	end
end

-- a direction to keep walking in (dx, dy each -1, 0 or 1; 0, 0 stops after the step under way)
function live.steer(player, dx, dy)
	local u = live.byPlayer[player]
	if not u or u.teleporting or u.kicked then return false end
	dx, dy = math.floor(tonumber(dx) or 0), math.floor(tonumber(dy) or 0)
	if dx < -1 or dx > 1 or dy < -1 or dy > 1 then return false end
	if dx == 0 and dy == 0 then u.steer = nil return true end
	if live.movement(u.room) == live.MOVE_CLICK then return false end
	local was = u.steer
	u.steer = { dx, dy }
	local changed = not was or was[1] ~= dx or was[2] ~= dy
	-- a new direction in the middle of a step takes effect now (live.redirect), not when the tile is
	-- reached: otherwise half a second of walking the old way feels like the input wasn't taken
	if changed and live.redirect(u) then
		u.useOnArrive = nil
		return true
	end
	-- it replaces a walk that was clicked (the step under way is already taken), and a new
	-- direction replaces the next tile of the old one; the next step goes there, so even a tap
	-- (pressed and let go before the next step) is one step
	if changed or u.goal == nil or #(u.path or {}) ~= 1 then
		u.path, u.goal = nil, nil
		u.path = steerPath(u.room, u)
	end
	u.useOnArrive = nil
	return true
end

-- Turning a step under way to the held direction. Early in the step (before REDIRECT_BEFORE of it is
-- walked) the avatar goes from where it is on screen to the tile next to the one it left in the new
-- direction (back to it, if that's the way); later it turns to face the new way at once and goes
-- there from the next tile. Not when the tile it was going to has furni (stepping on it may have done
-- something already). true when the step was changed.
-- (later than a third of the way, going to the tile next to the one left would mean walking partly
-- back the way it came: that looked like rubber banding)
live.REDIRECT_BEFORE = 0.35
function live.redirect(u)
	local r = u.room
	local now = BOBBA.platform.clock()
	if not u.stepStart or u.posture or u.teleporting then return false end
	local dur = u.stepDur or live.STEP_TIME
	local f = (now - u.stepStart) / dur
	if f >= 1 then return false end
	local dir = DIRS[u.steer[1] .. "," .. u.steer[2]]
	-- (one change a step: a stick wobbling between two ways mustn't send the avatar back and forth)
	if f >= live.REDIRECT_BEFORE or BOBBA.items.topAt(r, u.x, u.y) or u.redirectedStep == u.stepFrom then
		-- (too late to change this step: facing the new way shows it's coming)
		if dir and dir ~= u.dir then broadcast(r, "room.unit.turn", { id = u.id, dir = dir }) end
		u.path, u.goal = nil, nil
		return false
	end
	local g = r.grid
	local from, vis = u.stepFrom, u.visFrom or u.stepFrom
	-- where it is on screen now
	local fx, fy, fz = vis.x + (u.x - vis.x) * f, vis.y + (u.y - vis.y) * f, vis.z + (u.z - vis.z) * f
	-- the new tile: next to the one it left, in the held direction (sliding along walls)
	PF.removeUnit(g, u.x, u.y)
	local dx, dy = u.steer[1], u.steer[2]
	local tries = { { dx, dy } }
	if dx ~= 0 and dy ~= 0 then tries[2] = { dx, 0 } tries[3] = { 0, dy } end
	local tx, ty
	for _, d in ipairs(tries) do
		local cx, cy = from.x + d[1], from.y + d[2]
		local path = PF.find(g, from.x, from.y, cx, cy)
		if path and #path == 1 and path[1].x == cx and path[1].y == cy then tx, ty = cx, cy break end
	end
	if not tx or (tx == u.x and ty == u.y) then
		PF.addUnit(g, u.x, u.y)
		u.path, u.goal = nil, nil
		if not tx then
			-- (nowhere to go that way: finish the step, then turn)
			return false
		end
		return true
	end
	PF.addUnit(g, tx, ty)
	u.x, u.y, u.z = tx, ty, BOBBA.items.standZ(r, tx, ty)
	u.dir = live.direction(from.x, from.y, tx, ty) or u.dir
	u.to = { x = u.x, y = u.y, z = u.z }
	u.path, u.goal = nil, nil
	-- as long as the rest of the way is (a whole tile takes STEP_TIME)
	local left = math.max(math.abs(tx - fx), math.abs(ty - fy))
	local d2 = math.max(0.15, live.STEP_TIME * left)
	u.visFrom, u.stepStart, u.stepDur = { x = fx, y = fy, z = fz }, now, d2
	u.redirectedStep = u.stepFrom
	u.nextStep = now + d2
	local snap = snapshot(u)
	snap.x, snap.y, snap.z, snap.dur = fx, fy, fz, d2
	broadcast(r, "room.units", { snap })
	BOBBA.items.stepped(r, u)
	BOBBA.events.emit("unitStepped", r, u)
	return true
end

local function step(r, u, moved)
	-- steering: the next tile when the last step is done; nowhere to go, they turn that way
	if u.steer and not (u.path and #u.path > 0) and not u.teleporting then
		local path = steerPath(r, u)
		if path then
			u.path = path
		elseif not u.posture then
			local dir = DIRS[u.steer[1] .. "," .. u.steer[2]]
			if dir and dir ~= u.dir then
				u.dir = dir
				moved[#moved + 1] = snapshot(u)
			end
		end
	end
	local path = u.path
	if not path or #path == 0 then
		u.path = nil
		-- standing still: on a seat they sit, on a bed they lie down (items.lua)
		local settled = BOBBA.items.settle(r, u)
		if u.to or settled then
			u.to = nil
			moved[#moved + 1] = snapshot(u)
		end
		-- (walked there to use a furni: use it now)
		if u.useOnArrive then BOBBA.items.arrived(r, u) end
		return
	end
	local g = r.grid
	local nextTile = path[1]
	-- someone stepped in the way (or the tile changed): find a new way, like Arcturus does each step
	local blocked = nextTile.state == PF.BLOCKED or nextTile.state == PF.INVALID
		or (nextTile.units.n > 0 and math.sqrt((g.door.x - nextTile.x) ^ 2 + (g.door.y - nextTile.y) ^ 2) > 2
			and not (g.allowWalkthrough and #path > 1))
		or (nextTile.state == PF.OPEN and nextTile.stackHeight - PF.tile(g, u.x, u.y).stackHeight > PF.MAXIMUM_STEP_HEIGHT)
	if blocked then
		path = u.goal and PF.find(g, u.x, u.y, u.goal.x, u.goal.y)
		if not path or #path == 0 then
			u.path = nil
			if u.to then u.to = nil moved[#moved + 1] = snapshot(u) end
			return
		end
		u.path = path
		nextTile = path[1]
	end
	table.remove(path, 1)
	PF.removeUnit(g, u.x, u.y)
	PF.addUnit(g, nextTile.x, nextTile.y)
	u.dir = live.direction(u.x, u.y, nextTile.x, nextTile.y) or u.dir
	-- players see the step from where the unit was to the next tile
	local from = { x = u.x, y = u.y, z = u.z }
	-- Arcturus: on a seat or bed at its own height, on other furni on top of it
	u.x, u.y, u.z = nextTile.x, nextTile.y, BOBBA.items.standZ(r, nextTile.x, nextTile.y)
	u.posture, u.height = nil, nil
	u.to = { x = u.x, y = u.y, z = u.z }
	local s = snapshot(u)
	s.x, s.y, s.z = from.x, from.y, from.z
	moved[#moved + 1] = s
	-- (the step under way: where it started and when, so steering can turn it: live.steer)
	u.stepFrom, u.visFrom, u.stepStart, u.stepDur = from, from, BOBBA.platform.clock(), live.STEP_TIME
	BOBBA.items.stepped(r, u)
	BOBBA.events.emit("unitStepped", r, u)
end

live.ROLLER_EVERY = 4

-- a unit moved by something else (a roller): from where it was to x, y, z, seen as a step
function live.slide(r, u, x, y, z, moved)
	local from = { x = u.x, y = u.y, z = u.z }
	PF.removeUnit(r.grid, u.x, u.y)
	PF.addUnit(r.grid, x, y)
	u.x, u.y, u.z = x, y, z
	u.nextStep = BOBBA.platform.clock() + live.STEP_TIME
	u.to = { x = x, y = y, z = z }
	local s = snapshot(u)
	s.x, s.y, s.z = from.x, from.y, from.z
	moved[#moved + 1] = s
end

-- Each unit walks on its own clock: a step every STEP_TIME, and someone standing still starts at
-- once (Habbo runs everyone on one half-second beat, so a click or a key waited up to half a second
-- before anything moved). The room's own beat (rollers) stays every STEP_TIME.
live.TICK = 0.05
function live.tick()
	local now = BOBBA.platform.clock()
	for _, r in pairs(live.rooms) do
		local moved = {}
		for _, id in ipairs(r.order) do
			local u = r.units[id]
			if u and now >= (u.nextStep or 0) - 1e-6 then
				local x, y = u.x, u.y
				step(r, u, moved)
				-- (a step taken: the next one when this one has been walked)
				if u.x ~= x or u.y ~= y then u.nextStep = now + live.STEP_TIME end
			end
		end
		-- rollers move what's on them every 4 beats (Arcturus: the room's roller speed, 2 s)
		if now >= (r.nextBeat or 0) - 1e-6 then
			r.nextBeat = now + live.STEP_TIME
			r.rollerCycle = ((r.rollerCycle or 0) + 1) % live.ROLLER_EVERY
			if r.rollerCycle == 0 then BOBBA.items.rollers(r, moved) end
		end
		if #moved > 0 then broadcast(r, "room.units", moved) end
	end
end

-- messages from players
function live.start()
	live.migrate()
	BOBBA.items.start()
	BOBBA.chat.start()
	BOBBA.looks.start()
	BOBBA.navigator.start()
	BOBBA.wallet.start()
	BOBBA.inventory.start()
	BOBBA.catalog.start()
	BOBBA.gifts.start()
	BOBBA.access.start()
	BOBBA.starter.start()
	live.homeRoom()
	local P = BOBBA.platform
	local lastWalk = {}
	P.onLeave(function(player) live.leave(player) lastWalk[player] = nil end)
	P.receive("room.ready", function(player)
		local A = BOBBA.access
		local key = P.playerKey(player)
		P.send("hotel.info", { name = A.hotelName() }, player)
		P.send("room.favourites", { ids = A.favourites(key) }, player)
		P.send("room.home", { id = A.home(key) or 0 }, player)
		if live.byPlayer[player] then return end
		-- new here: first pick a room of your own (starter.lua)
		if BOBBA.starter.maybeOffer(player) then return end
		-- your home room (when you can go in), else the hotel's first room
		local home = A.home(key)
		if not (home and live.enter(player, home)) then live.enter(player, live.homeRoom()) end
	end)
	P.receive("room.enter", function(player, data)
		local ok, err = live.enter(player, data.id, nil, { password = data.password and tostring(data.password):sub(1, 40) or nil })
		if not ok then
			if err == "password" then
				local info = live.info(data.id)
				P.send("room.password", { id = tonumber(data.id), name = info and info.name or "" }, player)
			elseif err ~= "doorbell" then
				P.send("room.denied", { id = tonumber(data.id), reason = tostring(err) }, player)
			end
		end
	end)
	P.receive("room.walk", function(player, data)
		local now = P.clock()
		if lastWalk[player] and now - lastWalk[player] < 0.1 then return end
		lastWalk[player] = now
		-- (a room for steering only: no walking by clicking)
		local u = live.byPlayer[player]
		if u and live.movement(u.room) == live.MOVE_STEER then return end
		live.walk(player, data.x, data.y)
	end)
	local steers = {}
	P.onLeave(function(player) steers[player] = nil end)
	P.receive("room.steer", function(player, data)
		-- (at most 30 a second: a stick wobbling between directions)
		local now = P.clock()
		local s = steers[player]
		if not s or now - s.t >= 1 then s = { t = now, n = 0 } steers[player] = s end
		s.n = s.n + 1
		if s.n > 30 then return end
		live.steer(player, data.dx, data.dy)
	end)
	P.receive("room.interact", function(player, data)
		live.interact(player, data.id, type(data.tag) == "string" and data.tag or nil)
	end)
	P.every("rooms.tick", live.TICK, live.tick)
end
