-- Dancing, expressions, signs, sitting on the floor, falling asleep (hotel/actions.lua)
local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	BOBBA.items.define("chair", { width = 1, length = 1, height = 1, sit = true, directions = { 0, 2, 4, 6 } })
	local mia, bo = { key = "765611980001", name = "Mia" }, { key = "765611980002", name = "Bo" }
	local id = BOBBA.live.create(mia.key, mia.name, "model_a", "Mia's room")
	BOBBA.live.enter(mia, id)
	BOBBA.live.enter(bo, id)
	return mia, bo, BOBBA.live.byPlayer[mia], BOBBA.live.rooms[id]
end
local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end

T["dancing: everyone sees it; club dances for members; it shows to who comes in later"] = function()
	local mia, bo, u = start()
	P.fromPlayer(mia, "room.dance", { style = 1 })
	eq(last(bo, "room.unit.dance").dance, 1)
	eq(u.dance, 1)
	P.fromPlayer(mia, "room.dance", { style = 3 })
	eq(last(mia, "room.error").message, "that dance is for Habbo Club members")
	eq(u.dance, 1)
	BOBBA.wallet.addClub(mia.key, 31)
	P.fromPlayer(mia, "room.dance", { style = 3 })
	eq(last(bo, "room.unit.dance").dance, 3)
	-- (in the room's units for someone coming in)
	BOBBA.live.leave(bo)
	BOBBA.live.enter(bo, u.room.id)
	local me
	for _, s in ipairs(last(bo, "room.load").units) do if s.id == u.id then me = s end end
	eq(me.dance, 3)
	P.fromPlayer(mia, "room.dance", { style = 0 })
	eq(last(bo, "room.unit.dance").dance, 0)
end

T["expressions and signs: shown to the room; blowing kisses and laughing for VIP"] = function()
	local mia, bo, u = start()
	P.fromPlayer(mia, "room.expression", { id = 1 })
	eq(last(bo, "room.unit.expression").expression, 1)
	P.fromPlayer(mia, "room.expression", { id = 2 })
	eq(last(mia, "room.error").message, "that's for VIP members")
	BOBBA.wallet.addClub(mia.key, 31)
	P.fromPlayer(mia, "room.expression", { id = 3 })
	eq(last(bo, "room.unit.expression").expression, 3)
	P.fromPlayer(mia, "room.sign", { id = 14 })
	eq(last(bo, "room.unit.sign").sign, 14)
	P.fromPlayer(mia, "room.sign", { id = 18 })
	eq(last(bo, "room.unit.sign").sign, 14, "no sign 18")
	eq(u.id, last(bo, "room.unit.sign").id)
end

T["sitting on the floor: straight, stays sat while standing still, walking stands you up; stops dancing"] = function()
	local mia, bo, u, r = start()
	P.fromPlayer(mia, "room.dance", { style = 1 })
	u.dir = 3
	P.fromPlayer(mia, "room.posture", { sit = true })
	local s = last(bo, "room.units")[1]
	eq(s.posture .. " " .. s.height .. " " .. s.dir .. " " .. tostring(s.floorSit), "sit 0.5 2 true")
	eq(u.dance, 0, "stopped dancing")
	P.runTimers() P.runTimers()
	eq(u.posture, "sit", "still sitting")
	P.fromPlayer(mia, "room.posture", { sit = false })
	eq(last(bo, "room.units")[1].posture, nil)
	P.fromPlayer(mia, "room.posture", { sit = true })
	BOBBA.live.walk(mia, u.x + 1, u.y)
	P.now = P.now + 1
	P.runTimers()
	eq(u.posture, nil, "walking stood up")
	eq(u.cmdSit, nil)
end

T["idle: asleep after two minutes of nothing (not while dancing), awake on doing something"] = function()
	local mia, bo, u = start()
	P.now = P.now + 121
	P.runTimers()
	eq(u.idle, true)
	eq(last(bo, "room.unit.idle").idle, true)
	P.fromPlayer(mia, "room.sign", { id = 1 })
	eq(u.idle, false)
	eq(last(bo, "room.unit.idle").idle, false)
	P.fromPlayer(mia, "room.dance", { style = 1 })
	P.now = P.now + 500
	P.runTimers()
	eq(u.idle, false, "dancing isn't idle")
	-- the menu's Idle
	P.fromPlayer(mia, "room.expression", { id = 5 })
	eq(u.idle, true)
	eq(u.dance, 0, "asleep: no dancing")
end

return T
