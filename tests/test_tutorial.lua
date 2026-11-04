-- The new player's tutorial (hotel/tutorial.lua)
local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	BOBBA.items.define("table", { width = 1, length = 1, height = 1, directions = { 0, 2 } })
	BOBBA.items.define("lamp", { width = 1, length = 1, height = 2 })
	BOBBA.items.define("box", { width = 1, length = 1, height = 0.5, category = "present" })
	BOBBA.registry.register("starter_room", "test_green", { name = "Green", layout = "model_a",
		furni = { { kind = "table", x = 6, y = 4 } }, gift = { kind = "lamp", box = "box", x = 9, y = 8, message = "Hi!" } })
	return { key = "765611980001", name = "Mia" }
end
local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end

T["after the starter room: walk, open the gift, move a furni, say something; a reward"] = function()
	local mia = start()
	P.fromPlayer(mia, "room.ready", {})
	P.fromPlayer(mia, "starter.choose", { id = "test_green" })
	local u = BOBBA.live.byPlayer[mia]
	eq(last(mia, "tutorial.step").name, "walk")
	-- (saying something first doesn't count: one step at a time)
	P.fromPlayer(mia, "room.chat", { text = "hello" })
	eq(last(mia, "tutorial.step").name, "walk")
	BOBBA.live.walk(mia, u.x + 2, u.y)
	P.now = P.now + 1
	P.runTimers()
	eq(last(mia, "tutorial.step").name, "gift")
	local box, tbl
	for _, it in pairs(u.room.items) do
		if it.kind == "box" then box = it end
		if it.kind == "table" then tbl = it end
	end
	P.fromPlayer(mia, "room.item.open", { id = box.id })
	eq(last(mia, "tutorial.step").name, "move")
	P.fromPlayer(mia, "room.item.rotate", { id = tbl.id })
	eq(last(mia, "tutorial.step").name, "chat")
	local before = BOBBA.wallet.get(mia.key).credits
	P.now = P.now + 5
	P.fromPlayer(mia, "room.chat", { text = "hi everyone" })
	eq(last(mia, "tutorial.done").reward, 50)
	eq(BOBBA.wallet.get(mia.key).credits, before + 50)
	eq(BOBBA.tutorial.state(mia.key).done, true)
end

T["skipping: no reward, not shown again"] = function()
	local mia = start()
	P.fromPlayer(mia, "room.ready", {})
	P.fromPlayer(mia, "starter.choose", { id = "test_green" })
	P.fromPlayer(mia, "tutorial.skip", {})
	eq(last(mia, "tutorial.done").reward, 0)
	local n = #P.inbox(mia, "tutorial.step")
	BOBBA.live.leave(mia)
	BOBBA.live.enter(mia, BOBBA.access.home(mia.key))
	eq(#P.inbox(mia, "tutorial.step"), n, "not again")
end

return T
