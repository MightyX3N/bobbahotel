-- Starting a player over (hotel/reset.lua)
local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	BOBBA.items.define("table", { width = 1, length = 1, height = 1 })
	BOBBA.registry.register("starter_room", "test_green", { name = "Green", layout = "model_a", furni = { { kind = "table", x = 6, y = 4 } } })
	return { key = "765611980001", name = "Mia" }, { key = "765611980002", name = "Bo" }
end
local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end

T["a player starts over: rooms, furni, money, look, tutorial gone; others keep their furni; the starter room again"] = function()
	local mia, bo = start()
	P.fromPlayer(mia, "room.ready", {})
	P.fromPlayer(mia, "starter.choose", { id = "test_green" })
	local room = BOBBA.live.byPlayer[mia].room.id
	BOBBA.looks.set(mia.key, "hd-180-1.ch-210-66", "M")
	BOBBA.wallet.add(mia.key, "credits", 1000)
	BOBBA.effects.give(mia.key, 2, 0)
	BOBBA.inventory.give(mia.key, "table", 2)
	-- Bo's table in Mia's room
	local boTable = BOBBA.inventory.give(bo.key, "table", 1)[1]
	BOBBA.store.query("UPDATE bobbahotel_items SET room = ?, x = 7, y = 7 WHERE id = ?", { room, boTable.id })
	BOBBA.live.enter(bo, room)
	local startCredits = BOBBA.wallet.get(bo.key).credits
	BOBBA.reset.player(mia.key)
	eq(BOBBA.live.info(room), nil, "her room is gone")
	eq(#BOBBA.inventory.list(mia.key), 0, "her inventory is empty")
	eq(BOBBA.wallet.get(mia.key).credits, startCredits, "the start money again")
	eq(BOBBA.looks.get(mia.key), nil, "no look")
	eq(#BOBBA.effects.list(mia.key), 0)
	eq(BOBBA.tutorial.state(mia.key), nil)
	local bos = BOBBA.inventory.list(bo.key)
	eq(#bos, 1, "Bo's table is back in his inventory")
	assert(last(bo, "room.hotelview"), "Bo was in the room: out")
	assert(last(mia, "starter.offer"), "the starter room picker again")
	P.fromPlayer(mia, "starter.choose", { id = "test_green" })
	assert(BOBBA.live.byPlayer[mia], "and she can pick one")
	eq(last(mia, "tutorial.step").name, "walk", "the tutorial again")
end

T["only the look"] = function()
	local mia = start()
	BOBBA.live.enter(mia, BOBBA.live.homeRoom())
	BOBBA.looks.set(mia.key, "hd-180-1.ch-210-66", "M")
	BOBBA.reset.look(mia.key)
	eq(BOBBA.looks.get(mia.key), nil)
	eq(BOBBA.live.byPlayer[mia].figure, nil)
end

return T
