-- Steering (WASD, the arrow keys, a stick), the interact button, and the room's movement setting
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

T["holding a direction walks tile after tile; letting go stops on the next tile"] = function()
	local mia, _, _, u = start()
	P.fromPlayer(mia, "room.steer", { dx = 1, dy = 0 })
	tick(3)
	eq(at(u), "9,6", "three steps to the right")
	eq(u.dir, 2)
	P.fromPlayer(mia, "room.steer", { dx = 0, dy = 0 })
	tick(3)
	eq(at(u), "9,6", "stopped")
	-- a diagonal
	P.fromPlayer(mia, "room.steer", { dx = -1, dy = 1 })
	tick(2)
	eq(at(u), "7,8")
	eq(u.dir, 5)
end

T["into a wall: they turn that way; a blocked diagonal slides along"] = function()
	local mia, _, r, u = start()
	-- the top wall: y 1 is the last row
	P.fromPlayer(mia, "room.steer", { dx = 0, dy = -1 })
	tick(8)
	eq(at(u), "6,1", "walked up to the wall")
	P.fromPlayer(mia, "room.steer", { dx = 1, dy = -1 })
	tick(2)
	eq(at(u), "8,1", "the diagonal into the wall slides along it")
	P.fromPlayer(mia, "room.steer", { dx = 0, dy = 0 })
	tick(1)
	place(r, mia, "block", 9, 1)
	P.fromPlayer(mia, "room.steer", { dx = 1, dy = 0 })
	tick(2)
	eq(at(u) .. " " .. u.dir, "8,1 2", "a furni in the way: standing, facing it")
	P.fromPlayer(mia, "room.steer", { dx = 0, dy = 1 })
	tick(1)
	eq(at(u), "8,2", "another way is fine")
	P.fromPlayer(mia, "room.steer", { dx = 0, dy = 0 })
	tick(1)
	P.fromPlayer(mia, "room.steer", { dx = -1, dy = 0 })
	P.fromPlayer(mia, "room.steer", { dx = 0, dy = 0 })
	tick(1)
	eq(at(u), "7,2", "a tap is one step")
end

T["steering onto a seat sits down; going on stands up; a click takes over from steering"] = function()
	local mia, _, r, u = start()
	place(r, mia, "chair", 8, 6, 4)
	P.fromPlayer(mia, "room.steer", { dx = 1, dy = 0 })
	tick(2)
	P.fromPlayer(mia, "room.steer", { dx = 0, dy = 0 })
	tick(1)
	eq(at(u) .. " " .. tostring(u.posture), "8,6 sit", "sitting")
	P.fromPlayer(mia, "room.steer", { dx = 1, dy = 0 })
	tick(1)
	eq(at(u) .. " " .. tostring(u.posture), "9,6 nil", "up and on")
	P.now = P.now + 1
	P.fromPlayer(mia, "room.walk", { x = 9, y = 10 })
	tick(5)
	eq(at(u), "9,10", "the click walked, steering ended")
	-- steering cuts a clicked walk short after the step under way
	P.now = P.now + 1
	P.fromPlayer(mia, "room.walk", { x = 9, y = 2 })
	tick(1)
	P.fromPlayer(mia, "room.steer", { dx = 1, dy = 0 })
	tick(1)
	eq(at(u), "11,10", "the step just begun turned right at once, then right again")
end

T["the room's movement: clicking only, steering only; saved and sent with the room"] = function()
	local mia, bo, r, u = start()
	P.fromPlayer(mia, "room.settings.save", settings(r, 1))
	eq(tonumber(BOBBA.live.info(r.id).movement), 1)
	eq(BOBBA.access.publicInfo(r.info, r).movement, 1, "in the room's info")
	P.fromPlayer(mia, "room.steer", { dx = 1, dy = 0 })
	tick(2)
	eq(at(u), "6,6", "no steering")
	P.now = P.now + 1
	P.fromPlayer(mia, "room.walk", { x = 8, y = 6 })
	tick(3)
	eq(at(u), "8,6", "clicking works")
	P.fromPlayer(mia, "room.settings.save", settings(r, 2))
	P.now = P.now + 1
	P.fromPlayer(mia, "room.walk", { x = 4, y = 6 })
	tick(3)
	eq(at(u), "8,6", "no clicking")
	P.fromPlayer(mia, "room.steer", { dx = 0, dy = 1 })
	tick(1)
	eq(at(u), "8,7", "steering works")
	P.fromPlayer(mia, "room.steer", { dx = 0, dy = 0 })
	tick(1)
	-- the interact button still sits you down in a steering-only room
	place(r, mia, "chair", 9, 8, 4)
	P.fromPlayer(mia, "room.interact", { id = next(r.items) and (function() for id, it in pairs(r.items) do if it.kind == "chair" then return id end end end)() })
	tick(2)
	eq(at(u) .. " " .. tostring(u.posture), "9,8 sit", "onto the seat")
	-- someone else can't change it
	P.fromPlayer(bo, "room.settings.save", settings(r, 0))
	eq(tonumber(BOBBA.live.info(r.id).movement), 2)
	-- a save without it keeps it
	local s = settings(r, nil)
	P.fromPlayer(mia, "room.settings.save", s)
	eq(tonumber(BOBBA.live.info(r.id).movement), 2)
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

T["standing still, a step starts at once; then one every half second"] = function()
	local mia, _, _, u = start()
	P.now = P.now + 5
	local function fast() P.now = P.now + 0.05 P.runTimers() end
	P.fromPlayer(mia, "room.steer", { dx = 1, dy = 0 })
	fast()
	eq(at(u), "7,6", "the first step straight away, not on the next half-second beat")
	for _ = 1, 8 do fast() end
	eq(at(u), "7,6", "the step is still being walked")
	fast() fast()
	eq(at(u), "8,6", "the next one after half a second")
	P.fromPlayer(mia, "room.steer", { dx = 0, dy = 0 })
	for _ = 1, 20 do fast() end
	eq(at(u), "8,6")
	-- a click from standing still starts at once too
	P.now = P.now + 1
	P.fromPlayer(mia, "room.walk", { x = 8, y = 9 })
	fast()
	eq(at(u), "8,7")
end

T["a new direction early in a step turns it at once; late in a step it's the next one, facing that way now"] = function()
	local mia, _, _, u = start()
	P.now = P.now + 5
	local function fast() P.now = P.now + 0.05 P.runTimers() end
	P.fromPlayer(mia, "room.steer", { dx = 1, dy = 0 })
	fast()
	eq(at(u), "7,6", "walking right")
	fast() fast() -- (0.1 of 0.5 walked)
	P.sent = {}
	P.fromPlayer(mia, "room.steer", { dx = 0, dy = 1 })
	eq(at(u), "6,7", "from the tile it left, down instead")
	local m = P.inbox(mia, "room.units")
	local s = m[#m][1]
	eq(string.format("%.1f,%.1f %.2f", s.x, s.y, s.dur), "6.2,6.0 0.50", "from where it is on screen, the rest of the way (a whole tile down)")
	for _ = 1, 7 do fast() end
	eq(at(u), "6,7", "still on its way")
	fast() fast() fast()
	eq(at(u), "6,8", "then on down")
	-- late in a step: turned to face the new way, the step finishes
	for _ = 1, 5 do fast() end
	P.sent = {}
	P.fromPlayer(mia, "room.steer", { dx = -1, dy = 0 })
	eq(at(u), "6,8", "the step goes on")
	local t = P.inbox(mia, "room.unit.turn")
	eq(t[#t].dir, 6, "facing left already")
	for _ = 1, 5 do fast() end
	eq(at(u), "5,8", "then left")
end

return T
