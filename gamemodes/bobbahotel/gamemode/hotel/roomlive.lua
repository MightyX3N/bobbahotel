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
		door = { x = r.layout.door.x, y = r.layout.door.y, dir = r.layout.door.dir },
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
	-- (moving freely: from where it is, first onto its tile's middle)
	if u.px then live.freeStop(u) end
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
		-- (moving freely over it: stopping there sits down)
		if on then
			if u.px then live.freeStop(u) end
			return true
		end
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

-- The room's movement setting (rooms.movement): 0 both, 1 clicking only, 2 free movement only
live.MOVE_BOTH, live.MOVE_CLICK, live.MOVE_FREE = 0, 1, 2
function live.movement(r)
	return math.floor(tonumber(r.info.movement) or 0)
end

-- --- free movement (WASD, the arrow keys, a stick) --------------------------------------------------
-- The player's own game moves their avatar at once (client/steering.lua) and sends where it is, about
-- 15 times a second: room.move { x, y, dir } (tile units, not whole tiles), and { stop = true } at the
-- end. The server checks each one (not faster than walking, only over tiles one can walk on, no step
-- up higher than Habbo's 1.1, not through the door), keeps the avatar on the tile under its middle
-- for everything else (wired, rollers, gates, the room's grid), and shows the others. A move it
-- doesn't accept puts the player back: room.unit.pos { x, y, z }. Stopped, the avatar eases onto the
-- middle of its tile (and sits there on a seat, as walking does).
live.FREE_SPEED = 1 / live.STEP_TIME -- tiles a second: a tile in half a second, Habbo's walk
live.FREE_TIMEOUT = 0.6 -- no word for this long: stopped (a player who left, a game that froze)

-- whether the way from one point to another goes only over tiles one may walk on
local function freeTileOk(r, x, y, fromTile)
	local g = r.grid
	local t = PF.tile(g, x, y)
	if not t or t.state == PF.INVALID or t.state == PF.BLOCKED then return false end
	if g.door and x == g.door.x and y == g.door.y then return false end
	if fromTile and t.stackHeight - fromTile.stackHeight > PF.MAXIMUM_STEP_HEIGHT then return false end
	return true
end
local function round(v) return math.floor(v + 0.5) end
-- (the avatar keeps this far from a wall or furni: its middle never gets nearer than that)
live.FREE_RADIUS = 0.2
function live.freeWayOk(r, x0, y0, x1, y1)
	local g = r.grid
	local d = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
	local n = math.max(1, math.ceil(d / 0.2))
	local prev = PF.tile(g, round(x0), round(y0))
	local R = live.FREE_RADIUS
	for i = 1, n do
		local f = i / n
		local x, y = x0 + (x1 - x0) * f, y0 + (y1 - y0) * f
		local tx, ty = round(x), round(y)
		-- (its edge: the tiles it would reach into)
		for _, c in ipairs({ { -R, -R }, { R, -R }, { -R, R }, { R, R } }) do
			local cx, cy = round(x + c[1]), round(y + c[2])
			if (cx ~= tx or cy ~= ty) and not (prev and cx == prev.x and cy == prev.y) and not freeTileOk(r, cx, cy, prev) then return false end
		end
		if not prev or tx ~= prev.x or ty ~= prev.y then
			if not freeTileOk(r, tx, ty, prev) then return false end
			-- (diagonally between two tiles: not past a corner, like walking)
			if prev and tx ~= prev.x and ty ~= prev.y then
				if not freeTileOk(r, tx, prev.y) and not freeTileOk(r, prev.x, ty) then return false end
			end
			prev = PF.tile(g, tx, ty)
		end
	end
	return true
end

-- where a unit is drawn now (walking a step: part way along it)
local function drawnAt(u, now)
	if u.px then return u.px, u.py end
	if u.stepStart and u.visFrom then
		local f = math.min(1, (now - u.stepStart) / (u.stepDur or live.STEP_TIME))
		if f < 1 then return u.visFrom.x + (u.x - u.visFrom.x) * f, u.visFrom.y + (u.y - u.visFrom.y) * f end
	end
	return u.x, u.y
end

local function correct(u)
	if u.player then
		local x, y = drawnAt(u, BOBBA.platform.clock())
		BOBBA.platform.send("room.unit.pos", { x = x, y = y, z = u.z }, u.player)
	end
end

-- stopped: walking on to the middle of a tile, at walking speed. Past the middle of the tile it's on,
-- that's the next one ahead (when one can stand there), so it never slides back; else this one.
local AHEAD = { [0] = { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } }
function live.freeStop(u)
	if not u.px then return end
	local r = u.room
	local now = BOBBA.platform.clock()
	local fx, fy = u.px, u.py
	u.px, u.py, u.freeAt = nil, nil, nil
	local a = AHEAD[u.dir or 2] or { 0, 0 }
	local bx, by = (u.x - fx), (u.y - fy)
	if bx * a[1] + by * a[2] < -0.05 then
		local nx, ny = u.x + a[1], u.y + a[2]
		local t = PF.tile(r.grid, nx, ny)
		local here = PF.tile(r.grid, u.x, u.y)
		local corner = a[1] == 0 or a[2] == 0 or freeTileOk(r, nx, u.y) or freeTileOk(r, u.x, ny)
		if t and t.units.n == 0 and freeTileOk(r, nx, ny, here) and corner then
			PF.removeUnit(r.grid, u.x, u.y)
			PF.addUnit(r.grid, nx, ny)
			u.x, u.y = nx, ny
			u.z = BOBBA.items.standZ(r, nx, ny)
			BOBBA.items.stepped(r, u)
			BOBBA.events.emit("unitStepped", r, u)
		end
	end
	local d = math.sqrt((u.x - fx) ^ 2 + (u.y - fy) ^ 2)
	local dur = math.max(0.05, d / live.FREE_SPEED)
	u.to = { x = u.x, y = u.y, z = u.z }
	u.visFrom, u.stepStart, u.stepDur = { x = fx, y = fy, z = u.z }, now, dur
	u.nextStep = now + dur
	local s = snapshot(u)
	s.x, s.y, s.dur = fx, fy, dur
	broadcast(r, "room.units", { s })
end

-- a position from the player's game: true, or false (and they're put back)
function live.move(player, x, y, dir, stop)
	local u = live.byPlayer[player]
	if not u or u.teleporting or u.kicked then return false end
	local r = u.room
	if live.movement(r) == live.MOVE_CLICK then correct(u) return false end
	x, y = tonumber(x), tonumber(y)
	if not x or not y or x ~= x or y ~= y then return false end
	local now = BOBBA.platform.clock()
	local px, py = drawnAt(u, now)
	-- (not faster than walking, with a little room for the network's ups and downs)
	local dt = u.freeAt and (now - u.freeAt) or 0.1
	local d = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
	-- (refused: put back; a stop still stops)
	local function refuse()
		correct(u)
		if stop then live.freeStop(u) end
		return false
	end
	if d > live.FREE_SPEED * math.min(math.max(dt, 0.05), 0.5) * 1.3 + 0.35 then return refuse() end
	if d > 0 and not live.freeWayOk(r, px, py, x, y) then return refuse() end
	-- moving: no walk to a clicked tile any more, standing up from a seat
	u.path, u.goal, u.useOnArrive = nil, nil, nil
	u.posture, u.height = nil, nil
	u.px, u.py, u.freeAt = x, y, now
	dir = math.floor(tonumber(dir) or u.dir)
	if dir >= 0 and dir <= 7 then u.dir = dir end
	-- the tile under its middle
	local tx, ty = round(x), round(y)
	if tx ~= u.x or ty ~= u.y then
		PF.removeUnit(r.grid, u.x, u.y)
		PF.addUnit(r.grid, tx, ty)
		u.x, u.y = tx, ty
		u.z = BOBBA.items.standZ(r, tx, ty)
		BOBBA.items.stepped(r, u)
		BOBBA.events.emit("unitStepped", r, u)
	end
	u.to = nil
	-- the others see it glide there
	local list = {}
	for _, id in ipairs(r.order) do
		local o = r.units[id]
		if o.player and o ~= u then list[#list + 1] = o.player end
	end
	if #list > 0 then BOBBA.platform.send("room.unit.move", { id = u.id, x = x, y = y, z = u.z, dir = u.dir }, list) end
	if stop then live.freeStop(u) end
	return true
end

local function step(r, u, moved)
	-- (moving freely: the player's game moves it; no word for a while, it has stopped)
	if u.px then
		if BOBBA.platform.clock() - (u.freeAt or 0) > live.FREE_TIMEOUT then live.freeStop(u) end
		return
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
	-- (the step under way: where it started and when, for where it's drawn: drawnAt)
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
		-- (a room for free movement only: no walking by clicking)
		local u = live.byPlayer[player]
		-- (stepping off the door is fine: steering.lua does that before moving freely)
		if u and live.movement(u.room) == live.MOVE_FREE then
			local g = u.room.grid
			if not (g.door and u.x == g.door.x and u.y == g.door.y) then return end
		end
		live.walk(player, data.x, data.y)
	end)
	local moves = {}
	P.onLeave(function(player) moves[player] = nil end)
	P.receive("room.move", function(player, data)
		-- (at most 40 a second)
		local now = P.clock()
		local m = moves[player]
		if not m or now - m.t >= 1 then m = { t = now, n = 0 } moves[player] = m end
		m.n = m.n + 1
		if m.n > 40 then return end
		live.move(player, data.x, data.y, data.dir, data.stop == true)
	end)
	P.receive("room.interact", function(player, data)
		live.interact(player, data.id, type(data.tag) == "string" and data.tag or nil)
	end)
	P.every("rooms.tick", live.TICK, live.tick)
end
