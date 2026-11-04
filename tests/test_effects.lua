-- Avatar effects and the wardrobe (hotel/effects.lua)
local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	local mia, bo = { key = "765611980001", name = "Mia" }, { key = "765611980002", name = "Bo" }
	local id = BOBBA.live.create(mia.key, mia.name, "model_a", "Mia's room")
	BOBBA.live.enter(mia, id)
	BOBBA.live.enter(bo, id)
	return mia, bo, BOBBA.live.byPlayer[mia]
end
local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end

T["effects: given, worn (everyone sees it), its time runs out, the next one waits"] = function()
	local mia, bo, u = start()
	local E = BOBBA.effects
	E.give(mia.key, 4, 60)
	E.give(mia.key, 4, 60)
	local l = last(mia, "effects.list").effects
	eq(#l, 1)
	eq(l[1].type .. " " .. l[1].total .. " " .. l[1].secondsLeft, "4 2 0")
	P.fromPlayer(bo, "effects.enable", { id = 4 })
	eq(last(bo, "room.error").message, "you don't have that effect")
	P.fromPlayer(mia, "effects.enable", { id = 4 })
	eq(last(bo, "room.unit.effect").effect, 4)
	eq(last(mia, "effects.list").effects[1].secondsLeft, 60)
	P.now = P.now + 30
	P.runTimers()
	eq(u.effect, 4, "still on")
	P.now = P.now + 31
	P.runTimers()
	eq(u.effect, 0, "time's up")
	eq(last(mia, "effects.expired").type, 4)
	eq(last(mia, "effects.list").effects[1].total, 1, "one left")
	-- the last one used up: gone
	P.fromPlayer(mia, "effects.enable", { id = 4 })
	P.now = P.now + 61
	P.runTimers()
	eq(#last(mia, "effects.list").effects, 0)
end

T["effects: for ever (0); taken off; shown to who comes in, and again on coming back"] = function()
	local mia, bo, u = start()
	BOBBA.effects.give(mia.key, 2, 0)
	P.fromPlayer(mia, "effects.enable", { id = 2 })
	eq(last(mia, "effects.list").effects[1].permanent, true)
	P.now = P.now + 10 * 86400
	P.runTimers()
	eq(u.effect, 2)
	BOBBA.live.leave(bo)
	BOBBA.live.enter(bo, u.room.id)
	local me
	for _, s in ipairs(last(bo, "room.load").units) do if s.id == u.id then me = s end end
	eq(me.effect, 2)
	BOBBA.live.leave(mia)
	BOBBA.live.enter(mia, u.room.id)
	eq(BOBBA.live.byPlayer[mia].effect, 2, "on again in the room")
	P.fromPlayer(mia, "effects.enable", { id = 0 })
	eq(last(bo, "room.unit.effect").effect, 0)
end

T["the wardrobe: ten slots, saved looks come back"] = function()
	local mia = start()
	P.fromPlayer(mia, "wardrobe.save", { slot = 3, figure = "hd-180-1.ch-210-66", gender = "M" })
	P.fromPlayer(mia, "wardrobe.save", { slot = 11, figure = "hd-180-1", gender = "M" })
	eq(last(mia, "room.error").message, "no such wardrobe slot")
	P.fromPlayer(mia, "wardrobe.save", { slot = 1, figure = "not a look!", gender = "F" })
	eq(last(mia, "room.error").message, "that isn't a look")
	P.fromPlayer(mia, "wardrobe.get", {})
	local l = last(mia, "wardrobe.list")
	eq(l.slots, 10)
	eq(l.looks["3"].figure .. " " .. l.looks["3"].gender, "hd-180-1.ch-210-66 M")
	eq(l.looks["1"], nil)
end

return T
