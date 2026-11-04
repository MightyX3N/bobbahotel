-- Furni in rooms (server): saved in SQLite, placed, moved, turned, picked up and used, and what they
-- do to the room's tiles the way Arcturus works it out (github.com/ArcturusEmulator, GPL-3): a tile
-- under furni is blocked, or open (rugs), or a seat or a bed; its height is the top furni's top
-- (a seat's own height for someone sitting on it); people sit and lie on them.
--
-- What a kind of furni is (its size and height, whether it's walked, sat or laid on) comes from an
-- addon: BOBBA.items.resolver = function(kind, cb) cb(def) or cb(nil, why) end, with
--   def = { width, length, height, walk, sit, lay, stack (default: not on seats and beds),
--           directions = { 0, 2, 4, 6 } (Habbo's 0-7), states = 2, wall (hangs on a wall),
--           paint ("wallpaper" / "floor" / "landscape": put on the room, inventory.lua) }
-- A wall furni hangs where Habbo's wall location says (wall: ":w=x,y l=localX,localY l|r"); it takes
-- no tiles.
--
-- Messages to players:  room.items { item, ... } (added or changed: id, kind, x, y, z, dir, state,
--                         data, wall)
--                       room.item.remove { id }
-- Messages from players: room.item.place { kind, x, y, dir, wall }, room.item.move { id, x, y, dir, wall },
--                        room.item.pickup { id }, room.item.use { id }, room.item.stickie { id, color, text },
--                        room.item.stickie.delete { id }, room.item.dimmer { id, preset, effect, color,
--                        brightness, apply }

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
	-- teleports come in pairs (Arcturus items_teleports): each one's partner
	BOBBA.store.migrate("core.009_teleports", {
		"CREATE TABLE bobbahotel_teleports (a INTEGER PRIMARY KEY, b INTEGER NOT NULL)",
	})
	-- what some furni keep (Arcturus extradata): a trophy's engraving, a toner's colour, ...
	BOBBA.store.migrate("core.010_item_data", { "ALTER TABLE bobbahotel_items ADD COLUMN data TEXT NOT NULL DEFAULT ''" })
	-- where a wall furni hangs: Habbo's wall location (":w=x,y l=localX,localY l|r")
	BOBBA.store.migrate("core.013_wall_items", { "ALTER TABLE bobbahotel_items ADD COLUMN wall TEXT NOT NULL DEFAULT ''" })
end

-- Teleports' links go one way: each teleport has one it takes you to (its "partner"), which can be
-- any other teleport its owner has, in any of their rooms; several can lead to the same one. They
-- come unlinked; their owner links them (tele.link). A teleport that changes hands (a trade) loses
-- its links, both ways.
-- two teleports become each other's partner (both ways)
function items.link(a, b)
	BOBBA.store.query("INSERT OR REPLACE INTO bobbahotel_teleports (a, b) VALUES (?, ?)", { a, b })
	BOBBA.store.query("INSERT OR REPLACE INTO bobbahotel_teleports (a, b) VALUES (?, ?)", { b, a })
end

-- a teleport takes you to another (0 / nil: nowhere)
function items.linkTo(a, b)
	if not b or b == 0 then BOBBA.store.query("DELETE FROM bobbahotel_teleports WHERE a = ?", { a }) return end
	BOBBA.store.query("INSERT OR REPLACE INTO bobbahotel_teleports (a, b) VALUES (?, ?)", { a, b })
end

-- no links to or from these any more
function items.unlink(ids)
	if #ids == 0 then return end
	local marks = {}
	for i = 1, #ids do marks[i] = "?" end
	local list = table.concat(marks, ",")
	local args = {}
	for _, id in ipairs(ids) do args[#args + 1] = id end
	for _, id in ipairs(ids) do args[#args + 1] = id end
	BOBBA.store.query("DELETE FROM bobbahotel_teleports WHERE a IN (" .. list .. ") OR b IN (" .. list .. ")", args)
end

-- someone's teleports, by room (and those in their inventory): cb({ rooms = { { id, name,
-- teleports = { { id, kind, x, y } } } }, inventory = { { id, kind } } })
function items.ownedTeleports(key, cb)
	local rows = BOBBA.store.query("SELECT i.id, i.kind, i.room, i.x, i.y, r.name AS room_name FROM bobbahotel_items i LEFT JOIN bobbahotel_rooms r ON r.id = i.room WHERE i.owner = ? ORDER BY i.room, i.id", { tostring(key) })
	local kinds, left = {}, 0
	for _, row in ipairs(rows) do if kinds[row.kind] == nil then kinds[row.kind] = false left = left + 1 end end
	local function finish()
		local out, byRoom = { rooms = {}, inventory = {} }, {}
		for _, row in ipairs(rows) do
			local def = kinds[row.kind]
			if def and def.teleport then
				local room = tonumber(row.room) or 0
				if room == 0 then
					out.inventory[#out.inventory + 1] = { id = tonumber(row.id), kind = row.kind }
				else
					local g = byRoom[room]
					if not g then g = { id = room, name = row.room_name or ("Room " .. room), teleports = {} } byRoom[room] = g out.rooms[#out.rooms + 1] = g end
					g.teleports[#g.teleports + 1] = { id = tonumber(row.id), kind = row.kind, x = tonumber(row.x), y = tonumber(row.y) }
				end
			end
		end
		cb(out)
	end
	if left == 0 then finish() return end
	for kind in pairs(kinds) do
		items.resolve(kind, function(def)
			kinds[kind] = def or false
			left = left - 1
			if left == 0 then finish() end
		end)
	end
end

function items.partner(id)
	local row = BOBBA.store.row("SELECT b FROM bobbahotel_teleports WHERE a = ?", { id })
	return row and tonumber(row.b)
end

-- What a kind of furni is. cb(def) or cb(nil, why); straight away when it's known.
function items.define(kind, def)
	def.width, def.length, def.height = def.width or 1, def.length or 1, def.height or 0
	-- gates (furnidata's category; Arcturus InteractionGate): walked through when open
	if def.gate == nil then def.gate = def.category == "gate" end
	-- one-way gates (Arcturus InteractionOneWayGate): only ever passed through, one person at a time
	if def.oneWay == nil then def.oneWay = def.logic == "furniture_one_way_door" end
	-- rollers (category roller; Arcturus InteractionRoller): move what's on them along
	if def.roller == nil then def.roller = def.category == "roller" end
	-- teleports (category teleport; Arcturus InteractionTeleport): walked into, out of their partner
	if def.teleport == nil then def.teleport = def.category == "teleport" and (def.logic or ""):find("random") == nil end
	-- the stacking helper (Nitro's furniture_custom_stack_height; Arcturus InteractionStackHelper):
	-- its height is set by hand, and furni on its tiles go at that height, whatever is under them
	if def.stackHelper == nil then def.stackHelper = def.logic == "furniture_custom_stack_height" end
	-- gift boxes (category present): opened, not used (gifts.lua)
	if def.present == nil then def.present = def.category == "present" end
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
-- (wall furni hang on a wall: no tiles)
function items.footprint(def, x, y, dir)
	if def.wall then return {} end
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
	if not def or def.wall then return false end
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

-- can people walk on (or through) it now: walkable furni, an open gate, a one-way gate someone's
-- going through
local function walkable(it)
	local d = it.def
	if d.gate then return tonumber(it.state) == 1 end
	if d.oneWay or d.teleport then return it.passing ~= nil end
	return d.walk
end
items.walkable = walkable

-- (an open gate is walked through on the floor, not on top of it)
local function top(it)
	if it.def.gate or it.def.oneWay then return walkable(it) and it.z or it.z + it.def.height end
	if it.def.teleport then return it.z end
	return it.z + it.def.height
end

-- a stacking helper on a tile (not the excluded one)
local function helperAt(r, x, y, exclude)
	for _, it in ipairs(items.at(r, x, y, exclude)) do if it.def.stackHelper then return it end end
end
items.helperAt = helperAt

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
		stack = (topItem.def.sit and topItem.z) or top(topItem)
		if state ~= PF.LAY then
			local d = topItem.def
			state = PF.BLOCKED
			if walkable(topItem) then state = PF.OPEN end
			if d.sit then state = PF.SIT end
			if d.lay then state = PF.LAY end
		end
	end
	t.state, t.stackHeight = state, stack
	t.allowStack = not topItem or (topItem.def.stack and not topItem.def.gate and not topItem.def.oneWay and not topItem.def.teleport)
	-- (a stacking helper sets the height things go at there)
	local helper = helperAt(r, x, y)
	if helper then t.stackHeight, t.allowStack = helper.z, true end
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
	-- (a wired box's settings are only for who opens it; a teleport says whose it is: its Link button)
	local secret = it.def and (it.def.wired or (BOBBA.wired and BOBBA.wired.HABBO[it.kind]))
	return { id = it.id, kind = it.kind, x = it.x, y = it.y, z = it.z, dir = it.dir, state = it.state,
		data = (not secret and it.data and it.data ~= "") and it.data or nil, wall = (it.wall and it.wall ~= "") and it.wall or nil,
		owner = (it.def and it.def.teleport) and it.owner or nil }
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
			z = tonumber(row.z), dir = tonumber(row.dir) or 0, state = tonumber(row.state) or 0, data = row.data or "", wall = row.wall or "" }
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
-- the owner, staff, and those the owner gave rights
function items.canEdit(player, r)
	if not player then return true end -- the server itself
	if r.info.owner == BOBBA.platform.playerKey(player) then return true end
	if BOBBA.perms.has(player, "bobba.staff.anyroom") then return true end
	return BOBBA.access ~= nil and BOBBA.access.hasRightsKey(r.id, BOBBA.platform.playerKey(player))
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
		local helper = (not def.stackHelper) and helperAt(r, p.x, p.y, exclude)
		if under and not helper and not def.stackHelper and (not under.def.stack or under.def.gate or under.def.oneWay or under.def.teleport) then return nil, "it can't go on top of that" end
		if t.units.n > 0 and not (def.walk or def.sit or def.lay or def.stackHelper) then return nil, "someone is standing there" end
		local h = under and (under.z + (under.def.sit and 0 or under.def.height)) or base(t).stack
		-- (on a stacking helper's tiles: at its height; the helper itself goes on the floor)
		if helper then h = helper.z elseif def.stackHelper then h = base(t).stack end
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
-- Habbo's wall location: ":w=x,y l=localX,localY l|r" (the wall tile, where on it in pixels at
-- scale 32, which wall: l the left one, r the right one). x, y, localX, localY, side, or nil.
function items.parseWall(r, wall)
	local wx, wy, lx, ly, side = tostring(wall or ""):match("^:w=(%-?%d+),(%-?%d+) l=(%-?%d+),(%-?%d+) ([lr])$")
	if not wx then return nil end
	wx, wy, lx, ly = tonumber(wx), tonumber(wy), tonumber(lx), tonumber(ly)
	local w = r and r.layout and r.layout.width or 64
	local h = r and r.layout and r.layout.height or 64
	if wx < -1 or wy < -1 or wx > w or wy > h or math.abs(lx) > 256 or math.abs(ly) > 4096 then return nil end
	return wx, wy, lx, ly, side
end

-- wall: where a wall furni goes (Habbo's wall location; see items.parseWall)
function items.place(r, player, kind, x, y, dir, cb, existingId, wall)
	cb = cb or function() end
	x, y, dir = math.floor(tonumber(x) or -1), math.floor(tonumber(y) or -1), math.floor(tonumber(dir) or 0)
	if type(kind) ~= "string" or kind == "" or #kind > 100 then cb(nil, "no such furni") return end
	if not items.canEdit(player, r) then cb(nil, "only the room's owner can place furni here") return end
	items.resolve(kind, function(def, why)
		if not def then cb(nil, why or ("no furni called " .. kind)) return end
		if not BOBBA.live.rooms[r.id] then cb(nil, "the room closed") return end
		local z, err
		if def.wall then
			-- on a wall: the wall tile is its x, y; the left wall faces 2, the right wall 4
			local wx, wy, _, _, side = items.parseWall(r, wall)
			if not wx then cb(nil, "that goes on a wall") return end
			x, y, z, dir = wx, wy, 0, side == "l" and 2 or 4
		else
			if wall then cb(nil, "that goes on the floor") return end
			if dir < 0 or dir > 7 or not validDir(def, dir) then dir = def.directions[1] or 0 end
			z, err = items.fits(r, def, x, y, dir)
			if not z then cb(nil, err) return end
		end
		wall = def.wall and wall or ""
		-- at most 200 stickies a room (Habbo's room.error.max_stickies)
		if def.logic == "furniture_stickie" then
			local n = 0
			for _, o in pairs(r.items) do if o.def and o.def.logic == "furniture_stickie" then n = n + 1 end end
			if n >= items.STICKIES_MAX then cb(nil, "Only " .. items.STICKIES_MAX .. " stickies per room are allowed!") return end
		end
		-- one mood light a room (Arcturus: max_dimmers)
		if def.logic == "furniture_roomdimmer" then
			for _, o in pairs(r.items) do
				if o.def and o.def.logic == "furniture_roomdimmer" and o.id ~= existingId then cb(nil, "a room has only one mood light") return end
			end
		end
		local owner = player and BOBBA.platform.playerKey(player) or "server"
		local id, data
		if existingId then
			-- (still in the inventory? it may have been placed meanwhile)
			local row = BOBBA.store.row("SELECT owner FROM bobbahotel_items WHERE id = ? AND room = 0", { existingId })
			if not row then cb(nil, "that isn't in your inventory any more") return end
			owner = row.owner
			BOBBA.store.query("UPDATE bobbahotel_items SET room = ?, x = ?, y = ?, z = ?, dir = ?, state = 0, wall = ? WHERE id = ?", { r.id, x, y, z, dir, wall, existingId })
			id = existingId
			local row = BOBBA.store.row("SELECT data FROM bobbahotel_items WHERE id = ?", { id })
			data = row and row.data or ""
		else
			BOBBA.store.query("INSERT INTO bobbahotel_items (room, owner, kind, x, y, z, dir, state, wall) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)",
				{ r.id, owner, kind, x, y, z, dir, wall })
			id = tonumber(BOBBA.store.row("SELECT last_insert_rowid() AS id").id)
		end
		-- a stickie is put up yellow and blank (Arcturus PostItPlaceEvent); a mood light starts with
		-- Habbo's presets, off
		if def.logic == "furniture_stickie" and (data or "") == "" then data = items.STICKIE_COLORS[4] end
		if def.logic == "furniture_roomdimmer" and not items.dimmerData(data) then data = items.DIMMER_DEFAULT end
		if data and data ~= "" then BOBBA.store.query("UPDATE bobbahotel_items SET data = ? WHERE id = ?", { data, id }) end
		local state = 0
		if def.logic == "furniture_roomdimmer" then state = (items.dimmerData(data).on and 1 or 0) end
		local it = { id = id, owner = owner, kind = kind, x = x, y = y, z = z, dir = dir, state = state, def = def, data = data or "", wall = wall }
		r.items[id] = it
		local tiles = items.footprint(def, x, y, dir)
		updateTiles(r, tiles)
		broadcast(r, "room.items", { snapshot(it) })
		items.settleUnits(r, tiles)
		BOBBA.events.emit("itemPlaced", r, it)
		cb(it)
	end)
end

function items.placeExisting(r, player, id, kind, x, y, dir, cb, wall)
	items.place(r, player, kind, x, y, dir, cb, id, wall)
end

function items.move(r, player, id, x, y, dir, wall)
	local it = r.items[tonumber(id) or -1]
	if not it or not it.def then return false, "no such furni" end
	if not items.canEdit(player, r) then return false, "only the room's owner can move furni" end
	if it.def.wall then
		-- along the walls
		local wx, wy, _, _, side = items.parseWall(r, wall)
		if not wx then return false, "that goes on a wall" end
		it.x, it.y, it.dir, it.wall = wx, wy, side == "l" and 2 or 4, wall
		BOBBA.store.query("UPDATE bobbahotel_items SET x = ?, y = ?, dir = ?, wall = ? WHERE id = ?", { it.x, it.y, it.dir, wall, it.id })
		broadcast(r, "room.items", { snapshot(it) })
		BOBBA.events.emit("itemMoved", r, it, player)
		return true
	end
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
	BOBBA.events.emit("itemMoved", r, it, player)
	return true
end

-- moved by the room itself (wired): no one's rights asked; slides there like Habbo's. true, or
-- false and why
function items.moveBy(r, it, x, y, dir)
	if not it.def or it.def.wall then return false end
	local z, err = items.fits(r, it.def, x, y, dir, it)
	if not z then return false, err end
	local from = { x = it.x, y = it.y, z = it.z }
	local turned = dir ~= it.dir
	local old = items.footprint(it.def, it.x, it.y, it.dir)
	it.x, it.y, it.z, it.dir = x, y, z, dir
	BOBBA.store.query("UPDATE bobbahotel_items SET x = ?, y = ?, z = ?, dir = ? WHERE id = ?", { x, y, z, dir, it.id })
	local new = items.footprint(it.def, x, y, dir)
	updateTiles(r, old)
	updateTiles(r, new)
	local snap = snapshot(it)
	if not turned and (from.x ~= x or from.y ~= y) then snap.slide = from end
	broadcast(r, "room.items", { snap })
	for _, p in ipairs(new) do old[#old + 1] = p end
	items.settleUnits(r, old)
	BOBBA.events.emit("itemMoved", r, it, nil)
	return true
end

-- Turns a furni to its next direction
function items.rotate(r, player, id)
	local it = r.items[tonumber(id) or -1]
	if not it or not it.def then return false, "no such furni" end
	if it.def.wall then return false, "wall furni don't turn" end
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
	-- (someone with rights can't take the owner's furni: Arcturus's RoomPickupItemEvent)
	if player and it.owner == r.info.owner and it.owner ~= BOBBA.platform.playerKey(player)
		and not BOBBA.perms.has(player, "bobba.staff.anyroom") then
		return false, "that's the room owner's furni"
	end
	r.items[it.id] = nil
	if BOBBA.inventory then
		BOBBA.inventory.take(it.id, it.owner, it.kind)
	else
		BOBBA.store.query("DELETE FROM bobbahotel_items WHERE id = ?", { it.id })
	end
	items.removed(r, it)
	return true
end

-- a furni that's gone from a room (already out of r.items): everyone's told, its tiles freed
function items.removed(r, it)
	broadcast(r, "room.item.remove", { id = it.id })
	if it.def then
		local tiles = items.footprint(it.def, it.x, it.y, it.dir)
		updateTiles(r, tiles)
		items.settleUnits(r, tiles)
	end
	BOBBA.events.emit("itemRemoved", r, it)
end

-- Using a furni (double-click in Habbo): its next state, for the room's owner
-- What using a furni does, by its logic type (Nitro's; Arcturus has an interaction for each):
--   anyone: not only those who may change the room; adjacent: you have to stand next to it (you're
--   walked there first, like Habbo); roll: it spins (state "rolling") for some seconds, then lands
--   on a random state from..to
items.USES = {
	furniture_dice = { anyone = true, adjacent = true, closes = true, roll = { rolling = -1, seconds = 1.5, from = 1, to = 6 } },
	furniture_bottle = { anyone = true, roll = { rolling = -1, seconds = 2, from = 0, to = 7 } },
	furniture_habbowheel = { anyone = true, roll = { rolling = -1, seconds = 3, from = 1, to = 10 } },
	furniture_random_state = { roll = { rolling = nil, seconds = 0 } },
}

-- Habbo's directions: 0 up-right (y - 1), 2 down-right (x + 1), 4 down-left (y + 1), 6 up-left (x - 1)
local AHEAD = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 } }
local function ahead(x, y, dir)
	local v = AHEAD[(dir or 0) % 8] or AHEAD[0]
	return x + v[1], y + v[2]
end
items.ahead = ahead

local function unitAt(r, x, y)
	for _, u in pairs(r.units) do if u.x == x and u.y == y then return u end end
end

-- a gate: open or shut (not shut on someone)
local function useGate(r, it)
	if tonumber(it.state) == 1 then
		for _, t in ipairs(items.footprint(it.def, it.x, it.y, it.dir)) do
			if unitAt(r, t.x, t.y) then return false, "someone's in the way" end
		end
	end
	it.state = tonumber(it.state) == 1 and 0 or 1
	BOBBA.store.query("UPDATE bobbahotel_items SET state = ? WHERE id = ?", { it.state, it.id })
	updateTiles(r, items.footprint(it.def, it.x, it.y, it.dir))
	broadcast(r, "room.items", { snapshot(it) })
	return true
end

-- a one-way gate: from the tile in front of it (the side it faces away from) you go through it to
-- the tile behind; it opens for you and shuts after
local function oneWayTiles(it)
	local fx, fy = ahead(it.x, it.y, it.dir + 4)
	local bx, by = ahead(it.x, it.y, it.dir)
	return fx, fy, bx, by
end

local function useOneWay(r, it, player)
	local u = BOBBA.live.byPlayer[player]
	if not u or u.room ~= r or it.passing then return false end
	if u.px then BOBBA.live.freeStop(u) u.useOnArrive = it.id return true end
	local fx, fy, bx, by = oneWayTiles(it)
	if u.x ~= fx or u.y ~= fy or (u.path and #u.path > 0) then
		if not BOBBA.live.walk(player, fx, fy) then return false, "you can't get to it" end
		u.useOnArrive = it.id
		return true
	end
	local behind = PF.tile(r.grid, bx, by)
	if not behind or behind.state == PF.BLOCKED or behind.state == PF.INVALID or unitAt(r, bx, by) then return false, "the way through is blocked" end
	it.passing = u.id
	it.state = 1
	updateTiles(r, { { x = it.x, y = it.y } })
	broadcast(r, "room.items", { snapshot(it) })
	-- through it and out the other side
	u.goal = { x = bx, y = by }
	u.path = { PF.tile(r.grid, it.x, it.y), behind }
	return true
end

-- after someone's step: a one-way gate they've gone through shuts behind them
function items.stepped(r, u)
	for _, it in pairs(r.items) do
		if it.passing == u.id and not (u.x == it.x and u.y == it.y) and not (u.path and #u.path > 0 and u.path[1].x == it.x and u.path[1].y == it.y) then
			it.passing = nil
			it.state = 0
			updateTiles(r, { { x = it.x, y = it.y } })
			broadcast(r, "room.items", { snapshot(it) })
		end
	end
end

-- --- stickies (Arcturus InteractionPostIt): data "COLOUR text" -------------------------------------
items.STICKIE_COLORS = { "9CCEFF", "FF9CFF", "9CFF9C", "FFFF33" }
items.STICKIE_MAX = 500 -- Habbo's stickie window takes 500 letters
items.STICKIES_MAX = 200

-- the owner writes on it (and picks its colour); true or false, why
function items.writeStickie(r, player, id, color, text)
	local it = r.items[tonumber(id) or -1]
	if not it or not it.def or it.def.logic ~= "furniture_stickie" then return false, "that isn't a stickie" end
	if not items.canEdit(player, r) then return false, "only the room's owner can write on it" end
	color = tostring(color or ""):upper()
	local ok = false
	for _, c in ipairs(items.STICKIE_COLORS) do if c == color then ok = true end end
	if not ok then color = items.STICKIE_COLORS[4] end
	text = tostring(text or ""):gsub("[%z\1-\8\11-\31]", ""):sub(1, items.STICKIE_MAX)
	it.data = color .. " " .. text
	BOBBA.store.query("UPDATE bobbahotel_items SET data = ? WHERE id = ?", { it.data, it.id })
	broadcast(r, "room.items", { snapshot(it) })
	return true
end

-- thrown away (Habbo's bin on the stickie: gone for good)
function items.deleteStickie(r, player, id)
	local it = r.items[tonumber(id) or -1]
	if not it or not it.def or it.def.logic ~= "furniture_stickie" then return false, "that isn't a stickie" end
	if not items.canEdit(player, r) then return false, "only the room's owner can throw it away" end
	r.items[it.id] = nil
	BOBBA.store.query("DELETE FROM bobbahotel_items WHERE id = ?", { it.id })
	items.removed(r, it)
	return true
end

-- --- the mood light (Arcturus InteractionMoodLight, RoomMoodlightData) ----------------------------------
-- data: "on,preset,effect,#RRGGBB,brightness" (what Nitro's FurnitureRoomDimmerLogic reads: on is 2,
-- off 1; effect 2 = the background only) then its three presets "|effect,#RRGGBB,brightness"
items.DIMMER_DEFAULT = "1,1,1,#000000,255|1,#000000,255|1,#000000,255|1,#000000,255"
items.DIMMER_MIN_BRIGHTNESS = 76

function items.dimmerData(data)
	local cur, rest = tostring(data or ""):match("^([^|]*)(.*)$")
	local on, preset, effect, color, light = (cur or ""):match("^(%d),(%d),(%d),#(%x%x%x%x%x%x),(%d+)$")
	if not on then return nil end
	local d = { on = on == "2", preset = tonumber(preset), effect = tonumber(effect), color = color:upper(), light = tonumber(light), presets = {} }
	for e, c, l in rest:gmatch("|(%d),#(%x%x%x%x%x%x),(%d+)") do d.presets[#d.presets + 1] = { effect = tonumber(e), color = c:upper(), light = tonumber(l) } end
	while #d.presets < 3 do d.presets[#d.presets + 1] = { effect = 1, color = "000000", light = 255 } end
	return d
end

local function dimmerString(d)
	local out = { (d.on and 2 or 1) .. "," .. d.preset .. "," .. d.effect .. ",#" .. d.color .. "," .. d.light }
	for i = 1, 3 do local p = d.presets[i] out[#out + 1] = p.effect .. ",#" .. p.color .. "," .. p.light end
	return table.concat(out, "|")
end

local function setDimmer(r, it, d)
	it.data = dimmerString(d)
	it.state = d.on and 1 or 0
	BOBBA.store.query("UPDATE bobbahotel_items SET data = ?, state = ? WHERE id = ?", { it.data, it.state, it.id })
	broadcast(r, "room.items", { snapshot(it) })
end

-- a preset saved (Nitro's RoomDimmerSavePresetComposer): its effect, colour and brightness; apply:
-- the room shows it now
function items.saveDimmer(r, player, id, preset, effect, color, light, apply)
	local it = r.items[tonumber(id) or -1]
	if not it or not it.def or it.def.logic ~= "furniture_roomdimmer" then return false, "that isn't a mood light" end
	if not items.canEdit(player, r) then return false, "only the room's owner can set the mood light" end
	local d = items.dimmerData(it.data) or items.dimmerData(items.DIMMER_DEFAULT)
	preset = math.floor(tonumber(preset) or 0)
	if preset < 1 or preset > 3 then return false, "no such preset" end
	effect = (tonumber(effect) == 2) and 2 or 1
	color = string.format("%06X", math.floor(math.max(0, math.min(0xFFFFFF, tonumber(color) or 0))))
	light = math.floor(math.max(items.DIMMER_MIN_BRIGHTNESS, math.min(255, tonumber(light) or 255)))
	d.presets[preset] = { effect = effect, color = color, light = light }
	if apply then d.preset, d.effect, d.color, d.light = preset, effect, color, light end
	setDimmer(r, it, d)
	return true
end

-- switched on or off (RoomDimmerChangeStateComposer)
local function useDimmer(r, it)
	local d = items.dimmerData(it.data) or items.dimmerData(items.DIMMER_DEFAULT)
	d.on = not d.on
	-- (on: the chosen preset's look)
	local p = d.presets[d.preset] or d.presets[1]
	if d.on and p then d.effect, d.color, d.light = p.effect, p.color, p.light end
	setDimmer(r, it, d)
	return true
end

local function setState(r, it, state, passing)
	it.state = state
	-- (a state it's only passing through, like a dice rolling, isn't saved)
	if not passing then BOBBA.store.query("UPDATE bobbahotel_items SET state = ? WHERE id = ?", { state, it.id }) end
	broadcast(r, "room.items", { snapshot(it) })
end
items.setState = setState
function items.broadcastItem(r, it) broadcast(r, "room.items", { snapshot(it) }) end

-- the next state, as using it would (wired's toggle: no one's rights asked, no walking there)
function items.toggle(r, it)
	if not it.def then return false end
	local use = items.USES[it.def.logic or ""] or {}
	if use.roll then
		if it.rolling then return false end
		local roll = use.roll
		local from, to = roll.from or 0, roll.to or (it.def.states - 1)
		if roll.seconds > 0 then
			it.rolling = true
			setState(r, it, roll.rolling, true)
			BOBBA.platform.after(roll.seconds, function()
				it.rolling = nil
				if r.items[it.id] == it then setState(r, it, math.random(from, to)) end
			end)
		else
			setState(r, it, math.random(from, to))
		end
		return true
	end
	if it.def.gate then return useGate(r, it) end
	if (it.def.states or 1) < 2 or it.def.teleport or it.def.oneWay then return false end
	local state = tonumber(it.state) or 0
	if state < 0 or state >= it.def.states then state = -1 end
	setState(r, it, (state + 1) % it.def.states)
	return true
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

-- Using a furni (double-click in Habbo); wired's "furni is used" hears of it
local useFurni
function items.use(r, player, id, tag)
	local it = r.items[tonumber(id) or -1]
	if not it or not it.def then return false, "no such furni" end
	-- (a wired box: its window, for those who may change the room)
	if BOBBA.wired and BOBBA.wired.typeOf(it) then return BOBBA.wired.open(r, player, it) end
	local stateBefore = it.state
	local ok, why = useFurni(r, player, it, tag)
	if ok and (it.state ~= stateBefore or it.rolling) then BOBBA.events.emit("itemUsed", r, it, player) end
	return ok, why
end

function useFurni(r, player, it, tag)
	if it.def.oneWay then return useOneWay(r, it, player) end
	if it.def.teleport then return items.useTeleport(r, it, player) end
	local use = items.USES[it.def.logic or ""] or {}
	if not use.anyone and not items.canEdit(player, r) then return false, "only the room's owner can use this" end
	if it.def.gate then return useGate(r, it) end
	if it.def.logic == "furniture_roomdimmer" then return useDimmer(r, it) end
	if it.def.logic == "furniture_stickie" then return false end
	if use.adjacent then
		local u = BOBBA.live.byPlayer[player]
		if not u or u.room ~= r then return false end
		if not nextTo(it, u.x, u.y) or (u.path and #u.path > 0) then
			-- walked there, and used when there (items.arrived)
			local t = tileNextTo(r, it, u)
			if not t or not BOBBA.live.walk(player, t.x, t.y) then return false, "you can't get to it" end
			u.useOnArrive = it.id
			u.useTag = tag
			return true
		end
	end
	if use.roll then
		if it.rolling then return true end
		-- (a dice's side, Nitro's "deactivate" tag: closed again, DiceOff)
		if tag == "deactivate" and use.closes then setState(r, it, 0) return true end
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

-- Teleports (Arcturus InteractionTeleport + TeleportActionOne..Five): from the tile in front of one
-- you walk in (it opens), it shuts and flashes, you come out of its partner (in this room or
-- another) which opens and lets you out onto the tile in front of it. Without a partner placed
-- anywhere it opens again and you walk back out.
items.TELEPORT = { open = 1, flash = 2, closed = 0, step = 0.5 }

local function setTeleState(r, it, state)
	it.state = state
	broadcast(r, "room.items", { snapshot(it) })
end

local function passIn(r, it, u)
	it.passing = u.id
	updateTiles(r, { { x = it.x, y = it.y } })
end

local function passOut(r, it)
	it.passing = nil
	updateTiles(r, { { x = it.x, y = it.y } })
end

-- walk a unit one tile (onto or off a teleport) by hand
local function stepTo(r, u, x, y)
	local t = PF.tile(r.grid, x, y)
	if not t then return end
	u.goal = { x = x, y = y }
	u.path = { t }
end

-- going through a teleport: the player's game doesn't move them meanwhile (free movement: steering.lua)
local function setTeleporting(u, on)
	u.teleporting = on or nil
	if u.player then BOBBA.platform.send("room.busy", { on = on == true }, u.player) end
end

function items.useTeleport(r, it, player)
	local T = items.TELEPORT
	local after = BOBBA.platform.after
	local u = BOBBA.live.byPlayer[player]
	if not u or u.room ~= r or it.passing or it.busy then return false end
	-- (moving freely: stopped first, then in from the tile in front: items.arrived)
	if u.px then BOBBA.live.freeStop(u) u.useOnArrive = it.id return true end
	local fx, fy = ahead(it.x, it.y, it.dir)
	if u.x ~= fx or u.y ~= fy or (u.path and #u.path > 0) then
		if not BOBBA.live.walk(player, fx, fy) then return false, "you can't get to it" end
		u.useOnArrive = it.id
		return true
	end
	-- in: it opens, you step in, it shuts and flashes
	it.busy = true
	passIn(r, it, u)
	setTeleporting(u, true)
	setTeleState(r, it, T.open)
	stepTo(r, u, it.x, it.y)
	after(T.step * 2, function()
		setTeleState(r, it, T.flash)
		after(T.step * 2, function()
			local pid = items.partner(it.id)
			local row = pid and BOBBA.store.row("SELECT room, x, y, z, dir FROM bobbahotel_items WHERE id = ?", { pid })
			local stillHere = BOBBA.live.byPlayer[player] == u and u.room == r
			if not stillHere then it.busy = nil passOut(r, it) setTeleState(r, it, T.closed) return end
			if not row or tonumber(row.room) == 0 then
				-- nowhere to go: back out the way you came
				setTeleState(r, it, T.open)
				stepTo(r, u, fx, fy)
				after(T.step * 2, function()
					setTeleporting(u, false)
					it.busy = nil
					passOut(r, it)
					setTeleState(r, it, T.closed)
				end)
				return
			end
			setTeleState(r, it, T.closed)
			it.busy = nil
			passOut(r, it)
			local roomId = tonumber(row.room)
			local px, py, pz, pdir = tonumber(row.x), tonumber(row.y), tonumber(row.z), tonumber(row.dir) or 0
			local function arrive(r2, u2)
				local p = r2.items[pid]
				if not p then setTeleporting(u2, false) return end
				p.busy = true
				passIn(r2, p, u2)
				setTeleState(r2, p, T.flash)
				after(T.step * 2, function()
					setTeleState(r2, p, T.open)
					local ox, oy = ahead(p.x, p.y, p.dir)
					stepTo(r2, u2, ox, oy)
					after(T.step * 2, function()
						setTeleporting(u2, false)
						p.busy = nil
						passOut(r2, p)
						setTeleState(r2, p, T.closed)
					end)
				end)
			end
			if roomId == r.id then
				-- in this room: from one to the other
				local moved = {}
				BOBBA.live.slide(r, u, px, py, pz, moved)
				u.to = nil
				broadcast(r, "room.units", { BOBBA.live.snapshot(u) })
				arrive(r, u)
			else
				local ok = BOBBA.live.enter(player, roomId, { x = px, y = py, z = pz, dir = pdir })
				local u2 = BOBBA.live.byPlayer[player]
				if not ok or not u2 then return end
				setTeleporting(u2, true)
				-- (its furni may still be being looked up: wait for the partner a little)
				local tries = 0
				local function wait()
					if u2.room.items[pid] or tries > 20 then arrive(u2.room, u2) return end
					tries = tries + 1
					after(0.25, wait)
				end
				wait()
			end
		end)
	end)
	return true
end

items.MAX_STACK_HEIGHT = 40
function items.setStackHeight(r, player, id, height)
	local it = r.items[tonumber(id) or -1]
	if not it or not it.def or not it.def.stackHelper then return false, "no such furni" end
	if not items.canEdit(player, r) then return false, "only the room's owner can do that" end
	height = tonumber(height) or 0
	local tiles = items.footprint(it.def, it.x, it.y, it.dir)
	local z
	if height == -100 then
		-- above what's there (the tallest top on its tiles, the helper left out)
		z = 0
		for _, p in ipairs(tiles) do
			local topIt = items.topAt(r, p.x, p.y, it)
			local t = PF.tile(r.grid, p.x, p.y)
			local h = topIt and top(topIt) or (t and base(t).stack or 0)
			if h > z then z = h end
		end
	else
		z = math.min(items.MAX_STACK_HEIGHT, math.max(0, math.abs(height) / 100))
	end
	z = math.floor(z * 100 + 0.5) / 100
	it.z = z
	BOBBA.store.query("UPDATE bobbahotel_items SET z = ? WHERE id = ?", { z, it.id })
	updateTiles(r, tiles)
	broadcast(r, "room.items", { snapshot(it) })
	return true
end

-- Rollers (Arcturus Room.cycleRollers): everyone standing on one (not walking) and the furni on top
-- of it go one tile the way it points, when there's room there. Each thing moves once a turn.
function items.rollers(r, moved)
	local done = {}
	local list = {}
	for _, it in pairs(r.items) do if it.def and it.def.roller then list[#list + 1] = it end end
	table.sort(list, function(a, b) return a.id < b.id end)
	for _, roller in ipairs(list) do
		local fx, fy = ahead(roller.x, roller.y, roller.dir)
		local front = PF.tile(r.grid, fx, fy)
		local rollerTop = roller.z + roller.def.height
		if front and front.state ~= PF.INVALID then
			local frontRoller
			for _, o in ipairs(items.at(r, fx, fy)) do if o.def.roller then frontRoller = o end end
			-- the furni on it (not other rollers), lowest first
			local riders = {}
			for _, it in ipairs(items.at(r, roller.x, roller.y)) do
				if it ~= roller and not it.def.roller and not done[it] and it.z >= rollerTop - 0.01 then riders[#riders + 1] = it end
			end
			table.sort(riders, function(a, b) return a.z < b.z end)
			-- where they land: on top of what's there (the front roller, or the floor), keeping their stack
			local landZ
			do
				local topThere
				for _, o in ipairs(items.at(r, fx, fy)) do
					local mine = false
					for _, rd in ipairs(riders) do if rd == o then mine = true end end
					if not mine and (not topThere or top(o) > top(topThere)) then topThere = o end
				end
				landZ = topThere and top(topThere) or base(front).stack
				if topThere and not topThere.def.roller and not topThere.def.stack then landZ = nil end
			end
			local u = unitAt(r, roller.x, roller.y)
			-- (someone moving freely over it isn't carried)
			if u and u.px then u = nil end
			local someoneThere = unitAt(r, fx, fy)
			if #riders > 0 and landZ and not someoneThere and front.state ~= PF.BLOCKED and (front.allowStack or frontRoller) then
				local slid = {}
				for _, it in ipairs(riders) do
					local from = { x = it.x, y = it.y, z = it.z }
					it.x, it.y, it.z = it.x + (fx - roller.x), it.y + (fy - roller.y), landZ + (it.z - rollerTop)
					done[it] = true
					BOBBA.store.query("UPDATE bobbahotel_items SET x = ?, y = ?, z = ? WHERE id = ?", { it.x, it.y, it.z, it.id })
					local snap = snapshot(it)
					snap.slide = from
					slid[#slid + 1] = snap
				end
				updateTiles(r, { { x = roller.x, y = roller.y }, { x = fx, y = fy } })
				broadcast(r, "room.items", slid)
			end
			-- someone standing on it (not walking): onto the next tile if they can stand there
			if u and not done[u] and not u.teleporting and not (u.path and #u.path > 0) and not someoneThere
				and (front.state == PF.OPEN or front.state == PF.SIT or front.state == PF.LAY) then
				done[u] = true
				BOBBA.live.slide(r, u, fx, fy, items.standZ(r, fx, fy), moved)
			end
		end
	end
end

-- someone who was walked to a furni to use it got there (roomlive.lua, when they stop)
function items.arrived(r, u)
	local id, tag = u.useOnArrive, u.useTag
	u.useOnArrive, u.useTag = nil, nil
	local it = id and r.items[id]
	if not it or not u.player then return end
	if it.def.teleport or it.def.oneWay then
		-- (in front of it: in; not (stopped elsewhere after moving freely): there first)
		items.use(r, u.player, id)
	elseif nextTo(it, u.x, u.y) then
		items.use(r, u.player, id, tag)
	end
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
		u.cmdSit = nil
		if (u.dance or 0) > 0 and BOBBA.actions then BOBBA.actions.dance(u, 0) end
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
		u.cmdSit = nil
		-- (sitting down stops a dance: Arcturus)
		if (u.dance or 0) > 0 and BOBBA.actions then BOBBA.actions.dance(u, 0) end
		u.posture, u.height = "sit", chair.def.height
		u.z = chair.z
		u.dir = chair.dir
	elseif u.cmdSit then
		-- (sat down on the floor: stays so until walking or standing up; actions.lua)
		u.posture, u.height = "sit", BOBBA.actions.FLOOR_SIT
		u.z = items.standZ(r, u.x, u.y)
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
		items.place(r, player, data.kind, data.x, data.y, data.dir, function(it, why) if not it then fail(player, why) end end, nil, type(data.wall) == "string" and data.wall or nil)
	end)
	P.receive("room.item.move", function(player, data)
		local r = room(player)
		if not r then return end
		local ok, why = items.move(r, player, data.id, data.x, data.y, data.dir, type(data.wall) == "string" and data.wall or nil)
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
	-- a stacking helper's height (Nitro's FurnitureStackHeightComposer: height x 100; -100 = on top of
	-- what's on its tiles)
	P.receive("room.item.stackheight", function(player, data)
		local r = room(player)
		if not r then return end
		local ok, why = items.setStackHeight(r, player, data.id, data.height)
		if not ok then fail(player, why) end
	end)
	-- a room background toner's colour (Nitro's SetRoomBackgroundColorDataComposer: hue, saturation,
	-- lightness, 0 to 255 each)
	P.receive("room.item.toner", function(player, data)
		local r = room(player)
		if not r then return end
		local it = r.items[tonumber(data.id) or -1]
		if not it or not it.def or it.def.logic ~= "furniture_background_color" then return end
		if not items.canEdit(player, r) then fail(player, "only the room's owner can do that") return end
		local function v(x) return math.min(255, math.max(0, math.floor(tonumber(x) or 0))) end
		it.data = v(data.hue) .. "," .. v(data.saturation) .. "," .. v(data.lightness)
		BOBBA.store.query("UPDATE bobbahotel_items SET data = ? WHERE id = ?", { it.data, it.id })
		broadcast(r, "room.items", { snapshot(it) })
	end)
	-- stickies: written on, thrown away
	P.receive("room.item.stickie", function(player, data)
		local r = room(player)
		if not r then return end
		local ok, why = items.writeStickie(r, player, data.id, data.color, data.text)
		if not ok then fail(player, why) end
	end)
	P.receive("room.item.stickie.delete", function(player, data)
		local r = room(player)
		if not r then return end
		local ok, why = items.deleteStickie(r, player, data.id)
		if not ok then fail(player, why) end
	end)
	-- the mood light's presets: { id, preset, effect (1 all, 2 background), color (0xRRGGBB), brightness, apply }
	P.receive("room.item.dimmer", function(player, data)
		local r = room(player)
		if not r then return end
		local ok, why = items.saveDimmer(r, player, data.id, data.preset, data.effect, data.color, data.brightness, data.apply == true)
		if not ok then fail(player, why) end
	end)
	-- teleports: where each of yours goes (the Link window), and linking one
	P.receive("tele.links", function(player, data)
		local key = P.playerKey(player)
		local id = tonumber(data.id) or 0
		items.ownedTeleports(key, function(list)
			list.from = id
			list.to = items.partner(id) or 0
			P.send("tele.links", list, player)
		end)
	end)
	P.receive("tele.link", function(player, data)
		local key = P.playerKey(player)
		local id, to = tonumber(data.id) or -1, tonumber(data.to) or 0
		local row = BOBBA.store.row("SELECT kind FROM bobbahotel_items WHERE id = ? AND owner = ?", { id, key })
		local def = row and items.defs[row.kind]
		if not def or not def.teleport then fail(player, "you can only link your own teleports") return end
		if to ~= 0 then
			local trow = BOBBA.store.row("SELECT kind FROM bobbahotel_items WHERE id = ? AND owner = ?", { to, key })
			local tdef = trow and items.defs[trow.kind]
			if to == id or not tdef or not tdef.teleport then fail(player, "it can only go to another of your teleports") return end
		end
		items.linkTo(id, to)
		P.send("tele.linked", { id = id, to = to }, player)
	end)
	-- a furni clicked (wired's "user clicks furni"; at most a few a second)
	local clickedAt = {}
	P.onLeave(function(player) clickedAt[player] = nil end)
	P.receive("room.item.click", function(player, data)
		local r = room(player)
		if not r or not BOBBA.wired then return end
		local now = P.clock()
		if clickedAt[player] and now - clickedAt[player] < 0.2 then return end
		clickedAt[player] = now
		local it = r.items[tonumber(data.id) or -1]
		if it then BOBBA.wired.fire(r, "click", { unit = BOBBA.live.byPlayer[player], item = it }) end
	end)
	P.receive("room.item.use", function(player, data)
		local r = room(player)
		if not r then return end
		items.use(r, player, data.id, type(data.tag) == "string" and data.tag or nil)
	end)
end
