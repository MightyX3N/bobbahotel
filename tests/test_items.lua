local T = {}
local P

-- a room of Mia's (model_a: door at 3,5 facing right, floor x 4-11, y 1-13), with Mia in it
local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	local I = BOBBA.items
	I.define("chair", { width = 1, length = 1, height = 1, sit = true, directions = { 0, 2, 4, 6 } })
	I.define("table", { width = 2, length = 1, height = 0.8, directions = { 0, 2 } })
	I.define("rug", { width = 2, length = 2, height = 0.01, walk = true })
	I.define("bed", { width = 2, length = 3, height = 1.2, lay = true, directions = { 0, 2 } })
	I.define("lamp", { width = 1, length = 1, height = 2, states = 2 })
	I.define("dice", { width = 1, length = 1, height = 1, states = 7, logic = "furniture_dice" })
	local mia, bo = { key = "765611980001", name = "Mia" }, { key = "765611980002", name = "Bo" }
	local id = BOBBA.live.create(mia.key, mia.name, "model_a", "Mia's room")
	BOBBA.live.enter(mia, id)
	return mia, bo, BOBBA.live.rooms[id]
end

local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end

local function tick(n)
	for _ = 1, n or 1 do
		P.now = P.now + 0.5
		P.runTimers()
	end
end

local function place(r, who, kind, x, y, dir)
	local got, why
	BOBBA.items.place(r, who, kind, x, y, dir, function(it, w) got, why = it, w end)
	return got, why
end

local function walkTo(p, x, y)
	P.now = P.now + 1
	assert(BOBBA.live.walk(p, x, y), "can walk to " .. x .. "," .. y)
	tick(30)
end

T["placing: saved, sent to everyone, the tile blocked; the owner only"] = function()
	local mia, bo, r = start()
	BOBBA.live.enter(bo, r.id)
	local t = place(r, mia, "table", 6, 3, 0)
	assert(t, "placed")
	local msg = last(bo, "room.items")
	eq(msg[1].kind .. " " .. msg[1].x .. "," .. msg[1].y .. " z " .. msg[1].z, "table 6,3 z 0", "Bo sees it")
	eq(BOBBA.pathfinder.tile(r.grid, 6, 3).state, "blocked")
	eq(BOBBA.pathfinder.tile(r.grid, 7, 3).state, "blocked", "2 wide")
	eq(BOBBA.pathfinder.tile(r.grid, 6, 4).state, "open")
	local _, why = place(r, bo, "chair", 8, 8, 0)
	assert(why, "Bo isn't the owner")
	local row = BOBBA.store.row("SELECT * FROM bobbahotel_items WHERE id = ?", { t.id })
	eq(row.kind, "table")
	-- after a restart the room comes back with its furni
	BOBBA.live.leave(mia)
	BOBBA.live.leave(bo)
	BOBBA.live.enter(mia, r.id)
	local load = last(mia, "room.load")
	eq(#load.items, 1)
	eq(load.canEdit, true, "Mia may move furni")
	eq(BOBBA.pathfinder.tile(BOBBA.live.rooms[r.id].grid, 7, 3).state, "blocked")
end

T["placing: not off the floor, not in the door, not on people, turned sideways it is 1 x 2"] = function()
	local mia, _, r = start()
	local _, why = place(r, mia, "table", 11, 3, 0)
	assert(why, "half off the room")
	_, why = place(r, mia, "chair", 3, 5, 0)
	assert(why, "the door")
	_, why = place(r, mia, "lamp", 3, 5, 0)
	assert(why, "Mia is at the door anyway")
	walkTo(mia, 8, 8)
	_, why = place(r, mia, "lamp", 8, 8, 0)
	assert(why, "Mia stands there")
	assert(place(r, mia, "rug", 8, 8, 0), "a rug can go under her")
	local t = place(r, mia, "table", 11, 3, 2)
	assert(t, "turned, it fits along the wall")
	eq(BOBBA.pathfinder.tile(r.grid, 11, 4).state, "blocked")
end

T["stacking: on a table yes, its height; on a chair no"] = function()
	local mia, _, r = start()
	place(r, mia, "table", 6, 3, 0)
	local lamp = place(r, mia, "lamp", 7, 3, 0)
	eq(lamp.z, 0.8, "on the table")
	eq(BOBBA.pathfinder.tile(r.grid, 7, 3).stackHeight, 2.8)
	place(r, mia, "chair", 6, 6, 0)
	local _, why = place(r, mia, "lamp", 6, 6, 0)
	assert(why, "not on a seat")
end

T["sitting: walk onto a chair, sit facing its way at its height; walk off and stand"] = function()
	local mia, bo, r = start()
	BOBBA.live.enter(bo, r.id)
	place(r, mia, "chair", 7, 5, 4)
	eq(BOBBA.pathfinder.tile(r.grid, 7, 5).state, "sit")
	walkTo(mia, 7, 5)
	local u = BOBBA.live.byPlayer[mia]
	eq(u.x .. "," .. u.y, "7,5")
	eq(u.posture, "sit")
	eq(u.height, 1)
	eq(u.dir, 4, "facing the way the chair faces")
	local seen = last(bo, "room.units")
	eq(seen[1].posture, "sit", "Bo sees her sit")
	walkTo(mia, 9, 9)
	eq(u.posture, nil, "standing again")
end

T["sitting: a chair is only walked onto as the goal, never through"] = function()
	local mia, _, r = start()
	-- a row of chairs across the room at x = 6, except one gap at y = 13
	for y = 1, 12 do place(r, mia, "chair", 6, y, 2) end
	walkTo(mia, 8, 5)
	local u = BOBBA.live.byPlayer[mia]
	eq(u.x .. "," .. u.y, "8,5", "got there round the chairs")
	eq(u.posture, nil)
end

T["lying: on a bed, moved to its pillow end, at the bed's height"] = function()
	local mia, _, r = start()
	place(r, mia, "bed", 7, 7, 0)
	eq(BOBBA.pathfinder.tile(r.grid, 8, 9).state, "lay")
	walkTo(mia, 8, 9)
	local u = BOBBA.live.byPlayer[mia]
	eq(u.posture, "lay")
	eq(u.x .. "," .. u.y, "8,7", "to the pillow row (the bed's y)")
	eq(u.height, 1.2)
	eq(u.z, 0)
end

T["furni under someone changes: a chair put under them makes them sit, picked up they stand"] = function()
	local mia, _, r = start()
	walkTo(mia, 8, 8)
	local chair = place(r, mia, "chair", 8, 8, 2)
	assert(chair, "a seat can go under someone")
	local u = BOBBA.live.byPlayer[mia]
	eq(u.posture, "sit")
	assert(BOBBA.items.pickup(r, mia, chair.id))
	eq(u.posture, nil)
	eq(BOBBA.store.row("SELECT room FROM bobbahotel_items WHERE id = ?", { chair.id }).room, "0", "back in the inventory (room 0)")
end

T["moving and turning: tiles follow, blocked moves say why"] = function()
	local mia, _, r = start()
	local t = place(r, mia, "table", 6, 3, 0)
	assert(BOBBA.items.rotate(r, mia, t.id))
	eq(t.dir, 2)
	eq(BOBBA.pathfinder.tile(r.grid, 7, 3).state, "open", "no longer 2 wide this way")
	eq(BOBBA.pathfinder.tile(r.grid, 6, 4).state, "blocked")
	assert(BOBBA.items.move(r, mia, t.id, 9, 9, 0))
	eq(BOBBA.pathfinder.tile(r.grid, 6, 3).state, "open")
	eq(BOBBA.pathfinder.tile(r.grid, 10, 9).state, "blocked")
	local ok, why = BOBBA.items.move(r, mia, t.id, 11, 9, 0)
	eq(ok, false)
	assert(why)
end

T["using: the owner switches its state round; messages from players"] = function()
	local mia, bo, r = start()
	BOBBA.live.enter(bo, r.id)
	local lamp = place(r, mia, "lamp", 9, 9, 0)
	P.fromPlayer(mia, "room.item.use", { id = lamp.id })
	eq(lamp.state, 1)
	eq(last(bo, "room.items")[1].state, 1)
	P.fromPlayer(mia, "room.item.use", { id = lamp.id })
	eq(lamp.state, 0, "round again")
	P.fromPlayer(bo, "room.item.use", { id = lamp.id })
	eq(lamp.state, 0, "not Bo")
	P.fromPlayer(bo, "room.item.pickup", { id = lamp.id })
	assert(r.items[lamp.id], "Bo can't pick it up")
	P.fromPlayer(mia, "room.item.place", { kind = "chair", x = 9, y = 10, dir = 2 })
	assert(last(mia, "room.error"), "placing from nowhere is for staff")
	P.granted[mia] = { ["bobba.staff.place"] = true }
	P.fromPlayer(mia, "room.item.place", { kind = "chair", x = 9, y = 10, dir = 2 })
	eq(#BOBBA.items.list(r), 2)
end

T["a server start: furni still being looked up come as soon as they're known, none go missing"] = function()
	local mia, bo, r = start()
	place(r, mia, "table", 6, 3, 0)
	place(r, mia, "chair", 9, 9, 0)
	local I = BOBBA.items
	-- like a fresh server: nothing known yet, the addon answers later
	BOBBA.live.leave(mia)
	I.defs = {}
	local answers = {}
	local old = I.resolver
	I.resolver = function(kind, cb) answers[#answers + 1] = { kind, cb } end
	BOBBA.live.enter(mia, r.id)
	local load = last(mia, "room.load")
	eq(#load.items, 0, "nothing known yet")
	eq(#load.itemsComing, 2, "but two are coming")
	local before = #P.inbox(mia, "room.items")
	for _, a in ipairs(answers) do
		if a[1] == "table" then a[2]({ width = 2, length = 1, height = 0.8, directions = { 0, 2 } }) else a[2](nil, "unknown") end
	end
	local box = P.inbox(mia, "room.items")
	eq(#box, before + 1, "the table is sent when it's known")
	eq(box[#box][1].kind, "table")
	eq(last(mia, "room.item.remove") ~= nil, true, "the unknown one is taken off the list coming")
	I.resolver = old
end

T["a dice: anyone rolls it, walked next to it first; it lands on 1 to 6, again and again"] = function()
	local mia, bo, r = start()
	BOBBA.live.enter(bo, r.id)
	local dice = place(r, mia, "dice", 8, 8, 0)
	assert(dice, "placed")
	-- Bo (not the owner) is at the door, far away: he walks there and it rolls when he's next to it
	local rolls = 0
	local old = P.after
	local later = {}
	P.after = function(_, fn) later[#later + 1] = fn end
	assert(BOBBA.items.use(r, bo, dice.id))
	eq(dice.state, 0, "not yet: walking")
	tick(30)
	local u = BOBBA.live.byPlayer[bo]
	assert(math.abs(u.x - 8) <= 1 and math.abs(u.y - 8) <= 1, "next to it")
	eq(dice.state, -1, "rolling")
	eq(last(mia, "room.items")[1].state, -1, "everyone sees it roll")
	for _ = 1, 20 do
		for _, fn in ipairs(later) do fn() end
		later = {}
		assert(dice.state >= 1 and dice.state <= 6, "landed on " .. dice.state)
		rolls = rolls + 1
		assert(BOBBA.items.use(r, bo, dice.id))
		eq(dice.state, -1, "rolls again")
	end
	P.after = old
	eq(rolls, 20)
end

T["switching: round and round through its states"] = function()
	local mia, _, r = start()
	local lamp = place(r, mia, "lamp", 6, 3, 0)
	for i = 1, 5 do assert(BOBBA.items.use(r, mia, lamp.id)) eq(lamp.state, i % 2) end
	lamp.state = 9
	assert(BOBBA.items.use(r, mia, lamp.id))
	eq(lamp.state, 0, "a state it can't have starts again")
end

return T
