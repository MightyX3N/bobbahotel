-- Rooms with people in them (server). Rooms are saved in SQLite; a room is loaded when someone
-- enters it. Every 0.5 seconds (Arcturus's room cycle) everyone walking takes one step.
--
--   BOBBA.live.create(ownerKey, ownerName, "model_a", "My room")   -> room id
--   BOBBA.live.enter(player, roomId)       BOBBA.live.leave(player)
--   BOBBA.live.walk(player, x, y)
--
-- Messages to players:  room.load { id, name, owner, layout, heightmap, wallHeight, units = {...} }
--                       room.units { unit, ... }   (each: id, name, x, y, z, dir, to = {x, y, z} while stepping)
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
	BOBBA.store.query("INSERT INTO bobbahotel_rooms (owner, owner_name, name, layout, created) VALUES (?, ?, ?, ?, ?)",
		{ tostring(ownerKey), clean(ownerName), name, layoutId, math.floor(BOBBA.platform.time()) })
	local id = tonumber(BOBBA.store.row("SELECT last_insert_rowid() AS id").id)
	BOBBA.events.emit("roomCreated", id)
	return id
end

-- (GMod's SQLite gives every value as text: numbers are turned back into numbers here)
function live.info(id)
	local r = BOBBA.store.row("SELECT * FROM bobbahotel_rooms WHERE id = ?", { tonumber(id) or -1 })
	if not r then return nil end
	r.id, r.wall_height, r.created = tonumber(r.id), tonumber(r.wall_height) or -1, tonumber(r.created)
	return r
end

function live.list()
	local rows = BOBBA.store.query("SELECT id, name, owner_name, layout FROM bobbahotel_rooms ORDER BY id")
	for _, r in ipairs(rows) do r.id = tonumber(r.id) end
	return rows
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
		grid = PF.grid(layout.heightmap, layout.door.x, layout.door.y, layout.door.dir),
		units = {}, order = {},
	}
	live.rooms[id] = r
	BOBBA.events.emit("roomLoaded", r)
	return r
end

local function unload(r)
	live.rooms[r.id] = nil
	BOBBA.events.emit("roomUnloaded", r)
end

local function snapshot(u)
	return { id = u.id, name = u.name, key = u.key, x = u.x, y = u.y, z = u.z, dir = u.dir, to = u.to }
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

function live.enter(player, id)
	id = tonumber(id)
	if not live.info(id) then return false, "no room " .. tostring(id) end
	-- leave the old room first (if it's this same room and now empty, it's loaded again below)
	live.leave(player)
	local r, err = load(id)
	if not r then return false, err end
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
	live.nextUnit = live.nextUnit + 1
	r.units[u.id] = u
	r.order[#r.order + 1] = u.id
	live.byPlayer[player] = u
	PF.addUnit(g, u.x, u.y)
	local units = {}
	for _, uid in ipairs(r.order) do units[#units + 1] = snapshot(r.units[uid]) end
	BOBBA.platform.send("room.load", {
		id = r.id, name = r.info.name, owner = r.info.owner_name, layout = r.info.layout,
		heightmap = r.layout.heightmap, wallHeight = r.info.wall_height, you = u.id, units = units,
	}, player)
	for _, other in ipairs(players(r)) do
		if other ~= player then BOBBA.platform.send("room.units", { snapshot(u) }, other) end
	end
	BOBBA.events.emit("roomEntered", r, u)
	return true
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
	if not u then return false end
	x, y = math.floor(tonumber(x) or -1), math.floor(tonumber(y) or -1)
	local t = PF.tile(u.room.grid, x, y)
	if not t or t.state == PF.INVALID then return false end
	local path = PF.find(u.room.grid, u.x, u.y, x, y)
	if not path or #path == 0 then return false end
	u.goal = { x = x, y = y }
	u.path = path
	return true
end

local function step(r, u, moved)
	local path = u.path
	if not path or #path == 0 then
		if u.to then
			u.to = nil
			moved[#moved + 1] = snapshot(u)
		end
		u.path = nil
		return
	end
	local g = r.grid
	local nextTile = path[1]
	-- someone stepped in the way (or the tile changed): find a new way, like Arcturus does each step
	local blocked = nextTile.state == PF.BLOCKED or nextTile.state == PF.INVALID
		or (nextTile.units.n > 0 and math.sqrt((g.door.x - nextTile.x) ^ 2 + (g.door.y - nextTile.y) ^ 2) > 2)
		or (nextTile.state == PF.OPEN and nextTile.stackHeight - PF.tile(g, u.x, u.y).stackHeight > PF.MAXIMUM_STEP_HEIGHT)
	if blocked then
		path = PF.find(g, u.x, u.y, u.goal.x, u.goal.y)
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
	u.x, u.y, u.z = nextTile.x, nextTile.y, nextTile.stackHeight
	u.to = { x = u.x, y = u.y, z = u.z }
	local s = snapshot(u)
	s.x, s.y, s.z = from.x, from.y, from.z
	moved[#moved + 1] = s
	BOBBA.events.emit("unitStepped", r, u)
end

function live.tick()
	for _, r in pairs(live.rooms) do
		local moved = {}
		for _, id in ipairs(r.order) do
			local u = r.units[id]
			if u then step(r, u, moved) end
		end
		if #moved > 0 then broadcast(r, "room.units", moved) end
	end
end

-- messages from players
function live.start()
	live.migrate()
	live.homeRoom()
	local P = BOBBA.platform
	local lastWalk = {}
	P.onLeave(function(player) live.leave(player) lastWalk[player] = nil end)
	P.receive("room.ready", function(player)
		if not live.byPlayer[player] then live.enter(player, live.homeRoom()) end
	end)
	P.receive("room.enter", function(player, data)
		local ok, err = live.enter(player, data.id)
		if not ok then P.send("room.error", { message = tostring(err) }, player) end
	end)
	P.receive("room.walk", function(player, data)
		local now = P.clock()
		if lastWalk[player] and now - lastWalk[player] < 0.1 then return end
		lastWalk[player] = now
		live.walk(player, data.x, data.y)
	end)
	P.every("rooms.tick", live.STEP_TIME, live.tick)
end
