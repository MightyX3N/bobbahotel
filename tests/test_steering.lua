-- Free movement (WASD, the arrow keys, a stick), the interact button, and the room's movement setting
-- (hotel/roomlive.lua)
local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	local I = BOBBA.items
	I.define("chair", { width = 1, length = 1, height = 1, sit = true, directions = { 0, 2, 4, 6 } })
	I.define("lamp", { width = 1, length = 1, height = 2, states = 2 })
	I.define("block", { width = 1, length = 1, height = 1 })
	I.define("box", { width = 1, length = 1, height = 0.5, category = "present" })
	local mia, bo = { key = "765611980001", name = "Mia" }, { key = "765611980002", name = "Bo" }
	local id = BOBBA.live.create(mia.key, mia.name, "model_a", "Mia's room")
	BOBBA.live.enter(mia, id)
	local r = BOBBA.live.rooms[id]
	-- (away from the door: at 6,6)
	local u = BOBBA.live.byPlayer[mia]
	BOBBA.pathfinder.removeUnit(r.grid, u.x, u.y)
	u.x, u.y, u.z, u.dir = 6, 6, 0, 2
	BOBBA.pathfinder.addUnit(r.grid, 6, 6)
	return mia, bo, r, u
end

local function tick(n)
	for _ = 1, n or 1 do
		P.now = P.now + 0.5
		P.runTimers()
	end
end
local function place(r, mia, kind, x, y, dir)
	local got
	BOBBA.items.place(r, mia, kind, x, y, dir or 0, function(it) got = it end)
	return got
end
local function at(u) return u.x .. "," .. u.y end
local function settings(r, movement)
	local a = BOBBA.access.publicInfo(BOBBA.live.info(r.id), r)
	return { id = r.id, name = a.name, description = "", state = 0, password = "", maxUsers = 25, category = 0, tags = {}, trade = 0,
		allowPets = false, allowPetsEat = false, allowWalkthrough = true, hideWall = false, wallThickness = 0, floorThickness = 0,
		chatMode = 0, chatWeight = 1, chatSpeed = 1, chatDistance = 50, chatProtection = 2, whoMute = 0, whoKick = 0, whoBan = 0,
		movement = movement }
end

local function fast(n) for _ = 1, n or 1 do P.now = P.now + 0.05 P.runTimers() end end
-- a move from the player's game, then a moment
local function move(p, x, y, dir, stop)
	P.now = P.now + 0.1
	P.fromPlayer(p, "room.move", { x = x, y = y, dir = dir, stop = stop })
end

T["moving freely: in between tiles, on the tile under its middle, the others see it glide"] = function()
	local mia, bo, r, u = start()
	BOBBA.live.enter(bo, r.id)
	P.now = P.now + 5
	move(mia, 6.2, 6, 2)
	move(mia, 6.4, 6, 2)
	eq(string.format("%.1f,%.1f %s", u.px, u.py, at(u)), "6.4,6.0 6,6", "between tiles, on 6,6")
	move(mia, 6.6, 6.05, 2)
	eq(at(u), "7,6", "past the middle: on 7,6")
	local seen = P.inbox(bo, "room.unit.move")
	eq(string.format("%.2f,%.2f %d", seen[#seen].x, seen[#seen].y, seen[#seen].dir), "6.60,6.05 2", "Bo sees where she is")
	eq(#P.inbox(mia, "room.unit.move"), 0, "Mia's own game moves her itself")
	-- the grid knows: someone clicking a way avoids her tile like anyone's
	eq(BOBBA.pathfinder.tile(r.grid, 7, 6).units.n, 1)
	eq(BOBBA.pathfinder.tile(r.grid, 6, 6).units.n, 0)
end

T["too fast, through a wall or furni, out of the door: put back"] = function()
	local mia, _, r, u = start()
	P.now = P.now + 5
	move(mia, 9, 6, 2)
	eq(at(u), "6,6", "three tiles in a tenth of a second: no")
	local back = P.inbox(mia, "room.unit.pos")
	eq(back[#back].x .. "," .. back[#back].y, "6,6", "put back")
	place(r, mia, "block", 7, 6)
	move(mia, 6.25, 6, 2)
	move(mia, 6.45, 6, 2)
	eq(string.format("%.2f", u.px), "6.25", "not up against the furni")
	-- the wall: y 1 is the last row
	for i = 1, 26 do move(mia, 6.3, 6 - i * 0.18, 0) end
	eq(string.format("%.2f", u.py) .. " " .. at(u), "1.32 6,1", "up to the last row")
	move(mia, 6.3, 1.0, 0)
	move(mia, 6.3, 0.75, 0)
	eq(string.format("%.2f", u.py), "0.75", "up to the wall (its edge is at 0.5)")
	move(mia, 6.3, 0.6, 0)
	eq(string.format("%.2f", u.py), "0.75", "not into it (it keeps a fifth of a tile away)")
	-- the door (3,5): not out of it
	u.px, u.py = 4.3, 5
	BOBBA.pathfinder.removeUnit(r.grid, u.x, u.y) u.x, u.y = 4, 5 BOBBA.pathfinder.addUnit(r.grid, 4, 5)
	move(mia, 4.0, 5, 6) move(mia, 3.7, 5, 6) move(mia, 3.4, 5, 6)
	eq(at(u), "4,5", "not onto the door")
end

T["stopping: onto the middle of its tile; on a seat it sits; no word for a while is a stop"] = function()
	local mia, bo, r, u = start()
	BOBBA.live.enter(bo, r.id)
	P.now = P.now + 5
	move(mia, 6.2, 6.1, 2)
	move(mia, 6.35, 6.15, 2, true)
	eq(u.px, nil, "not free any more")
	local m = P.inbox(bo, "room.units")
	local s = m[#m][1]
	eq(string.format("%.2f,%.2f > %d,%d %.2f", s.x, s.y, s.to.x, s.to.y, s.dur), "6.35,6.15 > 7,6 0.33", "past the middle: walking on to the next tile's middle, at walking speed")
	eq(at(u), "7,6")
	-- not yet past the middle: onto this one
	fast(10)
	move(mia, 7.3, 6.0, 2) move(mia, 7.15, 6.0, 6, true)
	m = P.inbox(bo, "room.units")
	s = m[#m][1]
	eq(string.format("%d,%d", s.to.x, s.to.y), "7,6", "not past the middle (going left): this tile")
	fast(10)
	-- past the middle with something in the way ahead: back onto this one
	place(r, mia, "block", 9, 6)
	move(mia, 7.3, 6, 2) move(mia, 7.55, 6, 2) move(mia, 7.8, 6, 2) move(mia, 8.1, 6, 2) move(mia, 8.3, 6, 2, true)
	m = P.inbox(bo, "room.units")
	s = m[#m][1]
	eq(string.format("%d,%d", s.to.x, s.to.y), "8,6", "furni ahead: this tile")
	fast(10)
	BOBBA.live.rooms[r.id].items[(function() for id, it in pairs(r.items) do if it.kind == "block" and it.x == 9 then return id end end end)()] = nil
	-- a seat
	BOBBA.items.updateTile(r, 9, 6)
	P.now = P.now + 1
	P.fromPlayer(mia, "room.walk", { x = 6, y = 6 })
	fast(40)
	place(r, mia, "chair", 7, 6, 6)
	fast(10)
	move(mia, 6.3, 6, 2) move(mia, 6.5, 6, 2) move(mia, 6.7, 6, 2, true)
	fast(10)
	eq(at(u) .. " " .. tostring(u.posture), "7,6 sit", "stopped on the seat: sitting")
	-- moving again stands up
	move(mia, 7.2, 6, 2)
	eq(tostring(u.posture), "nil")
	-- no word
	fast(20)
	eq(u.px, nil, "stopped by itself")
	eq(at(u), "8,6", "(past the seat's middle: on to the next tile)")
end

T["not into a teleport, a one-way gate or a shut gate (only by using them); an open gate is fine"] = function()
	local mia, _, r, u = start()
	BOBBA.items.define("tele", { width = 1, length = 1, height = 2, states = 3, category = "teleport", directions = { 0, 2, 4, 6 } })
	BOBBA.items.define("gate", { width = 1, length = 1, height = 1.5, states = 2, category = "gate", directions = { 0, 2 } })
	P.now = P.now + 5
	place(r, mia, "tele", 7, 6, 6)
	for i = 1, 6 do move(mia, 6 + i * 0.1, 6, 2) end
	eq(string.format("%.1f", u.px), "6.2", "up to the teleport, not into it")
	move(mia, 6.2, 6, 2, true)
	fast(10)
	local gate = place(r, mia, "gate", 6, 7, 0)
	for i = 1, 6 do move(mia, 6, 6 + i * 0.1, 4) end
	eq(string.format("%.1f", u.py), "6.2", "a shut gate")
	BOBBA.items.use(r, mia, gate.id)
	for i = 1, 6 do move(mia, 6, 6.2 + i * 0.1, 4) end
	eq(at(u), "6,7", "an open gate")
end

T["a teleport while moving freely: stopped, in from the front; the player's game is told it's busy"] = function()
	local mia, _, r, u = start()
	BOBBA.items.define("tele", { width = 1, length = 1, height = 2, states = 3, category = "teleport", directions = { 0, 2, 4, 6 } })
	P.now = P.now + 5
	local tele = place(r, mia, "tele", 7, 6, 6)
	move(mia, 6.1, 6, 2)
	assert(BOBBA.live.interact(mia, tele.id))
	eq(u.px, nil, "stopped")
	fast(20)
	local busy = P.inbox(mia, "room.busy")
	eq(#busy, 2, "told when it starts and ends")
	eq(tostring(busy[1].on) .. " " .. tostring(busy[2].on), "true false")
	eq(u.teleporting, nil, "out again (it has no partner)")
	eq(at(u), "6,6", "back out in front of it")
end

T["the room's movement: clicking only refuses free movement, free movement only refuses clicks"] = function()
	local mia, bo, r, u = start()
	P.now = P.now + 5
	P.fromPlayer(mia, "room.settings.save", settings(r, 1))
	eq(tonumber(BOBBA.live.info(r.id).movement), 1)
	eq(BOBBA.access.publicInfo(r.info, r).movement, 1, "in the room's info")
	move(mia, 6.3, 6, 2)
	eq(u.px, nil, "no free movement")
	P.now = P.now + 1
	P.fromPlayer(mia, "room.walk", { x = 8, y = 6 })
	fast(30)
	eq(at(u), "8,6", "clicking works")
	P.fromPlayer(mia, "room.settings.save", settings(r, 2))
	P.now = P.now + 1
	P.fromPlayer(mia, "room.walk", { x = 4, y = 6 })
	fast(30)
	eq(at(u), "8,6", "no clicking")
	move(mia, 8, 6.3, 4)
	eq(string.format("%.1f", u.py), "6.3", "free movement works")
	move(mia, 8, 6.4, 4, true)
	fast(10)
	-- the interact button still sits you down
	local chair = place(r, mia, "chair", 9, 7, 4)
	P.fromPlayer(mia, "room.interact", { id = chair.id })
	fast(30)
	eq(at(u) .. " " .. tostring(u.posture), "9,7 sit", "onto the seat")
	P.fromPlayer(bo, "room.settings.save", settings(r, 0))
	eq(tonumber(BOBBA.live.info(r.id).movement), 2, "only the owner changes it")
	P.fromPlayer(mia, "room.settings.save", settings(r, nil))
	eq(tonumber(BOBBA.live.info(r.id).movement), 2, "a save without it keeps it")
end

T["a click while moving freely: from where it is, walking as usual"] = function()
	local mia, _, _, u = start()
	P.now = P.now + 5
	move(mia, 6.3, 6.2, 3)
	P.now = P.now + 1
	P.fromPlayer(mia, "room.walk", { x = 6, y = 9 })
	eq(u.px, nil, "free movement ended")
	fast(40)
	eq(at(u), "6,9", "walked there")
end

T["standing still, a click starts walking at once"] = function()
	local mia, _, _, u = start()
	P.now = P.now + 5
	P.fromPlayer(mia, "room.walk", { x = 6, y = 9 })
	fast()
	eq(at(u), "6,7", "the first step straight away")
	fast(8)
	eq(at(u), "6,7", "the step is still being walked")
	fast(2)
	eq(at(u), "6,8")
end

T["interact: only next to it; switches a lamp, opens a gift, sits"] = function()
	local mia, _, r, u = start()
	local lamp = place(r, mia, "lamp", 10, 10)
	local ok, why = BOBBA.live.interact(mia, lamp.id)
	eq(tostring(ok) .. " " .. tostring(why), "false too far away")
	lamp = place(r, mia, "lamp", 7, 7)
	assert(BOBBA.live.interact(mia, lamp.id))
	eq(r.items[lamp.id].state, 1, "switched on")
	local chair = place(r, mia, "chair", 5, 5, 2)
	assert(BOBBA.live.interact(mia, chair.id))
	tick(2)
	eq(at(u) .. " " .. tostring(u.posture), "5,5 sit")
	local box = place(r, mia, "box", 4, 4)
	BOBBA.store.query("INSERT INTO bobbahotel_gifts (id, kind, data) VALUES (?, ?, ?)", { box.id, "lamp", "" })
	assert(BOBBA.live.interact(mia, box.id))
	local opened = P.inbox(mia, "gift.opened")
	eq(opened[#opened].kind, "lamp", "the gift opened")
end

return T
