-- Furni in rooms (server): saved in SQLite, placed, moved, turned, picked up and used, and what they
-- do to the room's tiles the way Arcturus works it out (github.com/ArcturusEmulator, GPL-3): a tile
-- under furni is blocked, or open (rugs), or a seat or a bed; its height is the top furni's top
-- (a seat's own height for someone sitting on it); people sit and lie on them.
--
-- What a kind of furni is (its size and height, whether it's walked, sat or laid on) comes from an
-- addon: BOBBA.items.resolver = function(kind, cb) cb(def) or cb(nil, why) end, with
--   def = { width, length, height, walk, sit, lay, stack (default: not on seats and beds),
--           directions = { 0, 2, 4, 6 } (Habbo's 0-7), states = 2 }
--
-- Messages to players:  room.items { item, ... } (added or changed: id, kind, x, y, z, dir, state)
--                       room.item.remove { id }
-- Messages from players: room.item.place { kind, x, y, dir }, room.item.move { id, x, y, dir },
--                        room.item.pickup { id }, room.item.use { id }

BOBBA.items = BOBBA.items or { defs = {}, waiting = {} }
local items = BOBBA.items
local PF = BOBBA.pathfinder

items.MAX_HEIGHT = 40

function items.migrate()
	BOBBA.store.migrate("core.003_items", {
		[[CREATE TABLE bobbahotel_items (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			room INTEGER NOT NULL,
			owner TEXT NOT NULL,
			kind TEXT NOT NULL,
			x INTEGER NOT NULL,
			y INTEGER NOT NULL,
			z REAL NOT NULL,
			dir INTEGER NOT NULL DEFAULT 0,
			state INTEGER NOT NULL DEFAULT 0
		)]],
		"CREATE INDEX bobbahotel_items_room ON bobbahotel_items (room)",
	})
end

-- What a kind of furni is. cb(def) or cb(nil, why); straight away when it's known.
function items.define(kind, def)
	def.width, def.length, def.height = def.width or 1, def.length or 1, def.height or 0
	def.directions = def.directions or { 0, 2, 4, 6 }
	def.states = math.max(1, def.states or 1)
	if def.stack == nil then def.stack = not def.sit and not def.lay end
	items.defs[kind] = def
	return def
end

function items.resolve(kind, cb)
	local def = items.defs[kind]
	if def then cb(def) return end
	if not items.resolver then cb(nil, "no addon says what furni are (e.g. bobba_habbo)") return end
	if items.waiting[kind] then table.insert(items.waiting[kind], cb) return end
	items.waiting[kind] = { cb }
	items.resolver(kind, function(d, why)
		local list = items.waiting[kind]
		items.waiting[kind] = nil
		if d then d = items.define(kind, d) end
		for _, w in ipairs(list) do w(d, why) end
	end)
end

-- The tiles a furni covers (Arcturus RoomLayout.getTilesAt): turned sideways it swaps width and length
function items.footprint(def, x, y, dir)
	local w, l = def.width, def.length
	if dir == 2 or dir == 6 then w, l = l, w end
	local out = {}
	for i = 0, w - 1 do
		for j = 0, l - 1 do out[#out + 1] = { x = x + i, y = y + j } end
	end
	return out
end

local function covers(item, x, y)
	local def = item.def
	if not def then return false end
	local w, l = def.width, def.length
	if item.dir == 2 or item.dir == 6 then w, l = l, w end
	return x >= item.x and x < item.x + w and y >= item.y and y < item.y + l
end

function items.at(r, x, y, exclude)
	local out = {}
	for _, it in pairs(r.items) do
		if it ~= exclude and covers(it, x, y) then out[#out + 1] = it end
	end
	return out
end

local function top(it) return it.z + it.def.height end

-- Room.getTopItemAt: the furni whose top is highest
function items.topAt(r, x, y, exclude)
	local best
	for _, it in ipairs(items.at(r, x, y, exclude)) do
		if not best or top(it) >= top(best) then best = it end
	end
	return best
end

-- Room.getTallestChair
function items.chairAt(r, x, y)
	local best
	for _, it in ipairs(items.at(r, x, y)) do
		if it.def.sit and (not best or top(it) >= top(best)) then best = it end
	end
	return best
end

-- the tile as the heightmap made it, before any furni
local function base(t)
	if not t.base then t.base = { state = t.state, stack = t.stackHeight } end
	return t.base
end

-- Room.getStackHeight / calculateTileState for one tile
function items.updateTile(r, x, y)
	local t = PF.tile(r.grid, x, y)
	if not t then return end
	local b = base(t)
	if b.state == PF.INVALID then return end
	local list = items.at(r, x, y)
	local state, stack, topItem = b.state, b.stack, nil
	for _, it in ipairs(list) do
		if it.def.lay then state = PF.LAY end
	end
	topItem = items.topAt(r, x, y)
	if topItem then
		stack = topItem.z + (topItem.def.sit and 0 or topItem.def.height)
		if state ~= PF.LAY then
			local d = topItem.def
			state = PF.BLOCKED
			if d.walk then state = PF.OPEN end
			if d.sit then state = PF.SIT end
			if d.lay then state = PF.LAY end
		end
	end
	t.state, t.stackHeight = state, stack
	t.allowStack = not topItem or topItem.def.stack
end

local function updateTiles(r, list)
	for _, p in ipairs(list) do items.updateTile(r, p.x, p.y) end
end

-- Where someone standing on a tile is (Arcturus: on a seat or bed at its own height, on other
-- furni on top of it, else the floor)
function items.standZ(r, x, y)
	local it = items.topAt(r, x, y)
	if it then
		if it.def.sit or it.def.lay then return it.z end
		return top(it)
	end
	local t = PF.tile(r.grid, x, y)
	return t and base(t).stack or 0
end

local function snapshot(it)
	return { id = it.id, kind = it.kind, x = it.x, y = it.y, z = it.z, dir = it.dir, state = it.state }
end
items.snapshot = snapshot

-- the players in a room (defined below)
local broadcast

-- --- loading a room's furni ------------------------------------------------------------------------
-- What a furni is may take the addon a moment to look up (after a server start it reads Habbo's
-- furnidata first). Players who come in meanwhile are told which furni are still coming
-- (items.pending), and get each one as soon as it's known, so no furni is ever missing from a room.
function items.load(r)
	r.items = {}
	local rows = BOBBA.store.query("SELECT * FROM bobbahotel_items WHERE room = ? ORDER BY id", { r.id })
	for _, row in ipairs(rows) do
		local it = { id = tonumber(row.id), owner = row.owner, kind = row.kind, x = tonumber(row.x), y = tonumber(row.y),
			z = tonumber(row.z), dir = tonumber(row.dir) or 0, state = tonumber(row.state) or 0 }
		r.items[it.id] = it
		-- what it is may need a moment (the addon may have to look it up); its tiles change then
		items.resolve(it.kind, function(def)
			if r.items[it.id] ~= it then return end
			if not def then
				BOBBA.warn("room %d: furni %d is '%s', which isn't known; left out", r.id, it.id, it.kind)
				r.items[it.id] = nil
				broadcast(r, "room.item.remove", { id = it.id })
				return
			end
			it.def = def
			updateTiles(r, items.footprint(def, it.x, it.y, it.dir))
			broadcast(r, "room.items", { snapshot(it) })
		end)
	end
end

-- the ids of the furni still being looked up (sent with room.load)
function items.pending(r)
	local out = {}
	for id, it in pairs(r.items) do if not it.def then out[#out + 1] = id end end
	table.sort(out)
	return out
end

-- the list sent with room.load
function items.list(r)
	local out = {}
	for _, it in pairs(r.items) do if it.def then out[#out + 1] = snapshot(it) end end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

-- --- who may do what -------------------------------------------------------------------------------
function items.canEdit(player, r)
	if not player then return true end -- the server itself
	if r.info.owner == BOBBA.platform.playerKey(player) then return true end
	return BOBBA.perms.has(player, "bobba.staff.anyroom")
end

-- --- placing ---------------------------------------------------------------------------------------
local function validDir(def, dir)
	for _, d in ipairs(def.directions) do if d == dir then return true end end
	return false
end

-- Room.furnitureFitsAt (the parts that apply here). Returns the height it goes at, or nil and why.
function items.fits(r, def, x, y, dir, exclude)
	if not validDir(def, dir) then return nil, "it can't face that way" end
	local g = r.grid
	local z = 0
	local tiles = items.footprint(def, x, y, dir)
	for _, p in ipairs(tiles) do
		local t = PF.tile(g, p.x, p.y)
		if not t or base(t).state == PF.INVALID then return nil, "not on the floor" end
		if g.door and p.x == g.door.x and p.y == g.door.y then return nil, "not in the door" end
		local under = items.topAt(r, p.x, p.y, exclude)
		if under and not under.def.stack then return nil, "it can't go on top of that" end
		if t.units.n > 0 and not (def.walk or def.sit or def.lay) then return nil, "someone is standing there" end
		local h = under and (under.z + (under.def.sit and 0 or under.def.height)) or base(t).stack
		if h > z then z = h end
	end
	if z + def.height > items.MAX_HEIGHT then return nil, "too high" end
	return z
end

function broadcast(r, name, data)
	local list = {}
	for _, uid in ipairs(r.order) do
		local u = r.units[uid]
		if u.player then list[#list + 1] = u.player end
	end
	if #list > 0 then BOBBA.platform.send(name, data, list) end
end

-- Puts a furni into a room. cb(item) or cb(nil, why) (the furni may first need looking up).
-- existingId: a saved furni (from someone's inventory) put down instead of a new one.
function items.place(r, player, kind, x, y, dir, cb, existingId)
	cb = cb or function() end
	x, y, dir = math.floor(tonumber(x) or -1), math.floor(tonumber(y) or -1), math.floor(tonumber(dir) or 0)
	if type(kind) ~= "string" or kind == "" or #kind > 100 then cb(nil, "no such furni") return end
	if not items.canEdit(player, r) then cb(nil, "only the room's owner can place furni here") return end
	items.resolve(kind, function(def, why)
		if not def then cb(nil, why or ("no furni called " .. kind)) return end
		if not BOBBA.live.rooms[r.id] then cb(nil, "the room closed") return end
		if dir < 0 or dir > 7 or not validDir(def, dir) then dir = def.directions[1] or 0 end
		local z, err = items.fits(r, def, x, y, dir)
		if not z then cb(nil, err) return end
		local owner = player and BOBBA.platform.playerKey(player) or "server"
		local id
		if existingId then
			-- (still in the inventory? it may have been placed meanwhile)
			local row = BOBBA.store.row("SELECT owner FROM bobbahotel_items WHERE id = ? AND room = 0", { existingId })
			if not row then cb(nil, "that isn't in your inventory any more") return end
			owner = row.owner
			BOBBA.store.query("UPDATE bobbahotel_items SET room = ?, x = ?, y = ?, z = ?, dir = ?, state = 0 WHERE id = ?", { r.id, x, y, z, dir, existingId })
			id = existingId
		else
			BOBBA.store.query("INSERT INTO bobbahotel_items (room, owner, kind, x, y, z, dir, state) VALUES (?, ?, ?, ?, ?, ?, ?, 0)",
				{ r.id, owner, kind, x, y, z, dir })
			id = tonumber(BOBBA.store.row("SELECT last_insert_rowid() AS id").id)
		end
		local it = { id = id, owner = owner, kind = kind, x = x, y = y, z = z, dir = dir, state = 0, def = def }
		r.items[id] = it
		local tiles = items.footprint(def, x, y, dir)
		updateTiles(r, tiles)
		broadcast(r, "room.items", { snapshot(it) })
		items.settleUnits(r, tiles)
		BOBBA.events.emit("itemPlaced", r, it)
		cb(it)
	end)
end

function items.placeExisting(r, player, id, kind, x, y, dir, cb)
	items.place(r, player, kind, x, y, dir, cb, id)
end

function items.move(r, player, id, x, y, dir)
	local it = r.items[tonumber(id) or -1]
	if not it or not it.def then return false, "no such furni" end
	if not items.canEdit(player, r) then return false, "only the room's owner can move furni" end
	x, y, dir = math.floor(tonumber(x) or it.x), math.floor(tonumber(y) or it.y), math.floor(tonumber(dir) or it.dir)
	local z, err = items.fits(r, it.def, x, y, dir, it)
	if not z then return false, err end
	local old = items.footprint(it.def, it.x, it.y, it.dir)
	it.x, it.y, it.z, it.dir = x, y, z, dir
	BOBBA.store.query("UPDATE bobbahotel_items SET x = ?, y = ?, z = ?, dir = ? WHERE id = ?", { x, y, z, dir, it.id })
	local new = items.footprint(it.def, x, y, dir)
	updateTiles(r, old)
	updateTiles(r, new)
	-- furni stacked on top stays where it was (as in Arcturus): the tiles say what it stands on now
	broadcast(r, "room.items", { snapshot(it) })
	for _, p in ipairs(new) do old[#old + 1] = p end
	items.settleUnits(r, old)
	return true
end

-- Turns a furni to its next direction
function items.rotate(r, player, id)
	local it = r.items[tonumber(id) or -1]
	if not it or not it.def then return false, "no such furni" end
	local dirs = it.def.directions
	local nextDir = dirs[1]
	for i, d in ipairs(dirs) do
		if d == it.dir then nextDir = dirs[i % #dirs + 1] break end
	end
	return items.move(r, player, id, it.x, it.y, nextDir)
end

-- Picking furni up: back into its owner's inventory (Arcturus: RoomItemManager.pickUpItem)
function items.pickup(r, player, id)
	local it = r.items[tonumber(id) or -1]
	if not it then return false, "no such furni" end
	if not items.canEdit(player, r) then return false, "only the room's owner can pick furni up" end
	r.items[it.id] = nil
	if BOBBA.inventory then
		BOBBA.inventory.take(it.id, it.owner, it.kind)
	else
		BOBBA.store.query("DELETE FROM bobbahotel_items WHERE id = ?", { it.id })
	end
	broadcast(r, "room.item.remove", { id = it.id })
	if it.def then
		local tiles = items.footprint(it.def, it.x, it.y, it.dir)
		updateTiles(r, tiles)
		items.settleUnits(r, tiles)
	end
	BOBBA.events.emit("itemRemoved", r, it)
	return true
end

-- Using a furni (double-click in Habbo): its next state, for the room's owner
-- What using a furni does, by its logic type (Nitro's; Arcturus has an interaction for each):
--   anyone: not only those who may change the room; adjacent: you have to stand next to it (you're
--   walked there first, like Habbo); roll: it spins (state "rolling") for some seconds, then lands
--   on a random state from..to
items.USES = {
	furniture_dice = { anyone = true, adjacent = true, roll = { rolling = -1, seconds = 1.5, from = 1, to = 6 } },
	furniture_bottle = { anyone = true, roll = { rolling = -1, seconds = 2, from = 0, to = 7 } },
	furniture_habbowheel = { anyone = true, roll = { rolling = -1, seconds = 3, from = 1, to = 10 } },
	furniture_random_state = { roll = { rolling = nil, seconds = 0 } },
}

local function setState(r, it, state, passing)
	it.state = state
	-- (a state it's only passing through, like a dice rolling, isn't saved)
	if not passing then BOBBA.store.query("UPDATE bobbahotel_items SET state = ? WHERE id = ?", { state, it.id }) end
	broadcast(r, "room.items", { snapshot(it) })
end

-- is a unit next to a furni (on a tile touching it, corners too)?
local function nextTo(it, ux, uy)
	for _, t in ipairs(items.footprint(it.def, it.x, it.y, it.dir)) do
		if math.abs(t.x - ux) <= 1 and math.abs(t.y - uy) <= 1 then return true end
	end
	return false
end

-- the closest tile next to a furni someone can stand on
local function tileNextTo(r, it, u)
	local best, bestD
	local fp = items.footprint(it.def, it.x, it.y, it.dir)
	local on = {}
	for _, t in ipairs(fp) do on[t.x .. "," .. t.y] = true end
	for _, t in ipairs(fp) do
		for dx = -1, 1 do
			for dy = -1, 1 do
				local x, y = t.x + dx, t.y + dy
				local tile = PF.tile(r.grid, x, y)
				if not on[x .. "," .. y] and tile and tile.state ~= PF.BLOCKED and tile.state ~= PF.INVALID then
					local d = (x - u.x) ^ 2 + (y - u.y) ^ 2
					if not bestD or d < bestD then best, bestD = { x = x, y = y }, d end
				end
			end
		end
	end
	return best
end

-- Using a furni (double-click in Habbo)
function items.use(r, player, id)
	local it = r.items[tonumber(id) or -1]
	if not it or not it.def then return false, "no such furni" end
	local use = items.USES[it.def.logic or ""] or {}
	if not use.anyone and not items.canEdit(player, r) then return false, "only the room's owner can use this" end
	if use.adjacent then
		local u = BOBBA.live.byPlayer[player]
		if not u or u.room ~= r then return false end
		if not nextTo(it, u.x, u.y) or (u.path and #u.path > 0) then
			-- walked there, and used when there (items.arrived)
			local t = tileNextTo(r, it, u)
			if not t or not BOBBA.live.walk(player, t.x, t.y) then return false, "you can't get to it" end
			u.useOnArrive = it.id
			return true
		end
	end
	if use.roll then
		if it.rolling then return true end
		local roll = use.roll
		local states = it.def.states
		local from, to = roll.from or 0, roll.to or (states - 1)
		if roll.seconds > 0 then
			it.rolling = true
			setState(r, it, roll.rolling, true)
			BOBBA.platform.after(roll.seconds, function()
				it.rolling = nil
				if r.items[it.id] ~= it then return end
				setState(r, it, math.random(from, to))
			end)
		else
			setState(r, it, math.random(from, to))
		end
		return true
	end
	if it.def.states < 2 then return false, "nothing to switch" end
	-- (a state it can't have, e.g. left by another kind of use, starts again from 0)
	local state = tonumber(it.state) or 0
	if state < 0 or state >= it.def.states then state = -1 end
	setState(r, it, (state + 1) % it.def.states)
	return true
end

-- someone who was walked to a furni to use it got there (roomlive.lua, when they stop)
function items.arrived(r, u)
	local id = u.useOnArrive
	u.useOnArrive = nil
	local it = id and r.items[id]
	if it and u.player and nextTo(it, u.x, u.y) then items.use(r, u.player, id) end
end

-- --- people on furni (Room.cycleRoomUnit) ----------------------------------------------------------
-- Someone who isn't walking: on a seat they sit (facing the way it faces), on a bed they lie down
-- (moved to the bed's pillow end), elsewhere they stand. Returns true when something changed.
function items.settle(r, u)
	if u.path and #u.path > 0 then return false end
	local before = (u.posture or "") .. u.x .. "," .. u.y .. "," .. u.z .. "," .. u.dir .. "," .. (u.height or 0)
	local chair = items.chairAt(r, u.x, u.y)
	local t = PF.tile(r.grid, u.x, u.y)
	local topItem = items.topAt(r, u.x, u.y)
	if topItem and topItem.def.lay then
		u.posture, u.height = "lay", topItem.def.height
		u.dir = topItem.dir % 4
		local x, y = u.x, u.y
		if topItem.dir == 0 or topItem.dir == 4 then y = topItem.y else x = topItem.x end
		if x ~= u.x or y ~= u.y then
			PF.removeUnit(r.grid, u.x, u.y)
			PF.addUnit(r.grid, x, y)
			u.x, u.y = x, y
		end
		u.z = topItem.z
	elseif chair and t and t.state == PF.SIT then
		u.posture, u.height = "sit", chair.def.height
		u.z = chair.z
		u.dir = chair.dir
	else
		u.posture, u.height = nil, nil
		u.z = items.standZ(r, u.x, u.y)
	end
	local after = (u.posture or "") .. u.x .. "," .. u.y .. "," .. u.z .. "," .. u.dir .. "," .. (u.height or 0)
	return before ~= after
end

-- after furni changed: everyone standing still on those tiles
function items.settleUnits(r, tiles)
	local changed = {}
	for _, uid in ipairs(r.order) do
		local u = r.units[uid]
		if not (u.path and #u.path > 0) then
			for _, p in ipairs(tiles) do
				if u.x == p.x and u.y == p.y then
					if items.settle(r, u) then changed[#changed + 1] = BOBBA.live.snapshot(u) end
					break
				end
			end
		end
	end
	if #changed > 0 then broadcast(r, "room.units", changed) end
end

-- --- messages ----------------------------------------------------------------------------------------
function items.start()
	items.migrate()
	local P = BOBBA.platform
	local function room(player)
		local u = BOBBA.live.byPlayer[player]
		return u and u.room
	end
	local function fail(player, why)
		if why then P.send("room.error", { message = tostring(why) }, player) end
	end
	P.receive("room.item.place", function(player, data)
		local r = room(player)
		if not r then return end
		if not BOBBA.perms.has(player, "bobba.staff.place") then fail(player, "placing furni from nowhere is for staff") return end
		items.place(r, player, data.kind, data.x, data.y, data.dir, function(it, why) if not it then fail(player, why) end end)
	end)
	P.receive("room.item.move", function(player, data)
		local r = room(player)
		if not r then return end
		local ok, why = items.move(r, player, data.id, data.x, data.y, data.dir)
		if not ok then fail(player, why) end
	end)
	P.receive("room.item.rotate", function(player, data)
		local r = room(player)
		if not r then return end
		local ok, why = items.rotate(r, player, data.id)
		if not ok then fail(player, why) end
	end)
	P.receive("room.item.pickup", function(player, data)
		local r = room(player)
		if not r then return end
		local ok, why = items.pickup(r, player, data.id)
		if not ok then fail(player, why) end
	end)
	P.receive("room.item.use", function(player, data)
		local r = room(player)
		if not r then return end
		items.use(r, player, data.id)
	end)
end
