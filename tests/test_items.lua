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
	I.define("gate", { width = 1, length = 1, height = 1.5, states = 2, category = "gate", directions = { 0, 2 } })
	I.define("roller", { width = 1, length = 1, height = 0.2, walk = true, category = "roller" })
	I.define("tele", { width = 1, length = 1, height = 2, states = 3, category = "teleport", directions = { 0, 2, 4, 6 } })
	I.define("toner", { width = 1, length = 1, height = 1, states = 2, logic = "furniture_background_color" })
	I.define("helper", { width = 2, length = 2, height = 0, walk = true, logic = "furniture_custom_stack_height" })
	I.define("poster", { width = 1, length = 1, height = 0, wall = true })
	I.define("post.it", { width = 1, length = 1, height = 0, wall = true, logic = "furniture_stickie" })
	I.define("roomdimmer", { width = 1, length = 1, height = 0, wall = true, states = 2, logic = "furniture_roomdimmer" })
	I.define("oneway", { width = 1, length = 1, height = 2, states = 2, logic = "furniture_one_way_door", directions = { 0, 2, 4, 6 } })
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

T["gates: shut they block the way, open they're walked through; not shut on someone"] = function()
	local mia, _, r = start()
	-- a wall of gates across the room at y = 6 would be a lot: one gate, and check the tile
	local g = place(r, mia, "gate", 7, 6, 0)
	eq(BOBBA.pathfinder.tile(r.grid, 7, 6).state, "blocked")
	assert(BOBBA.items.use(r, mia, g.id))
	eq(g.state, 1)
	eq(BOBBA.pathfinder.tile(r.grid, 7, 6).state, "open", "open: walk through")
	eq(BOBBA.items.standZ(r, 7, 6), 0, "on the floor, not on top of it")
	walkTo(mia, 7, 6)
	local ok, why = BOBBA.items.use(r, mia, g.id)
	assert(not ok and why:find("way"), "not shut on Mia")
	walkTo(mia, 7, 7)
	assert(BOBBA.items.use(r, mia, g.id))
	eq(BOBBA.pathfinder.tile(r.grid, 7, 6).state, "blocked")
	local _, why2 = place(r, mia, "chair", 7, 6, 0)
	assert(why2, "nothing on a gate")
end

T["a one-way gate: walked to its front, through it, and it shuts behind"] = function()
	local mia, bo, r = start()
	BOBBA.live.enter(bo, r.id)
	-- facing 2 (x + 1): in front is x - 1, behind is x + 1
	local g = place(r, mia, "oneway", 7, 6, 2)
	eq(BOBBA.pathfinder.tile(r.grid, 7, 6).state, "blocked")
	assert(BOBBA.items.use(r, bo, g.id), "anyone uses it")
	tick(40)
	local u = BOBBA.live.byPlayer[bo]
	eq(u.x .. "," .. u.y, "8,6", "Bo is through")
	eq(g.state, 0, "shut again")
	eq(g.passing, nil)
	eq(BOBBA.pathfinder.tile(r.grid, 7, 6).state, "blocked")
	-- from behind it doesn't go back the other way: he's walked round to the front first
	P.now = P.now + 1
	assert(BOBBA.items.use(r, bo, g.id))
	tick(60)
	eq(u.x .. "," .. u.y, "8,6", "through again")
end

T["rollers: what's on them, and who stands on them, go along; a line of rollers carries it on"] = function()
	local mia, _, r = start()
	-- two rollers pointing x + 1 at 6,3 and 7,3
	local r1 = place(r, mia, "roller", 6, 3, 2)
	local r2 = place(r, mia, "roller", 7, 3, 2)
	walkTo(mia, 6, 5)
	local roll = function() for _ = 1, BOBBA.live.ROLLER_EVERY do tick() end end
	roll()
	local lamp = place(r, mia, "lamp", 6, 3, 0)
	eq(lamp.z, 0.2, "on the roller")
	roll()
	eq(lamp.x .. "," .. lamp.y .. " z " .. lamp.z, "7,3 z 0.2", "onto the next roller")
	local msg = last(mia, "room.items")
	eq(msg[1].slide.x, 6, "seen sliding from where it was")
	roll()
	eq(lamp.x .. "," .. lamp.y .. " z " .. lamp.z, "8,3 z 0", "off the end, on the floor")
	roll()
	eq(lamp.x, 8, "not on a roller any more")
	-- Mia steps on and is carried (along both rollers while she walked there? no: she's put on the first)
	walkTo(mia, 6, 4)
	BOBBA.live.walk(mia, 6, 3)
	for _ = 1, 3 do tick() end
	r.rollerCycle = 0
	roll()
	local u = BOBBA.live.byPlayer[mia]
	eq(u.x .. "," .. u.y, "7,3")
	roll()
	eq(u.x .. "," .. u.y, "7,3", "the lamp is in front: she stays")
	local _ = r1, r2
end

-- timers that go off as the room ticks (P.after), for things that take time
local function laterTimers()
	local queue = {}
	local old = P.after
	P.after = function(sec, fn) queue[#queue + 1] = { at = P.now + sec, fn = fn } end
	local function run()
		local due = {}
		for i = #queue, 1, -1 do if queue[i].at <= P.now then due[#due + 1] = table.remove(queue, i) end end
		table.sort(due, function(a, b) return a.at < b.at end)
		for _, q in ipairs(due) do q.fn() end
	end
	return run, function() P.after = old end
end

local function tickAll(n, run)
	for _ = 1, n do
		P.now = P.now + 0.5
		P.runTimers()
		run()
	end
end

T["teleports: in one, out of its partner (this room or another); alone it lets you back out"] = function()
	local mia, bo, r = start()
	BOBBA.live.enter(bo, r.id)
	local run, restore = laterTimers()
	local a = place(r, mia, "tele", 6, 3, 4)
	local b = place(r, mia, "tele", 10, 10, 2)
	BOBBA.items.link(a.id, b.id)
	eq(BOBBA.pathfinder.tile(r.grid, 6, 3).state, "blocked", "you don't just walk in")
	-- Bo uses it from the door: walked to its front (facing 4: y + 1), in, out of b, onto b's front (x + 1)
	assert(BOBBA.items.use(r, bo, a.id))
	tickAll(60, run)
	local u = BOBBA.live.byPlayer[bo]
	eq(u.x .. "," .. u.y, "11,10", "out of the other one")
	eq(a.state .. b.state, "00", "both shut")
	eq(BOBBA.pathfinder.tile(r.grid, 10, 10).state, "blocked")
	-- to another room: b goes to Mia's other room
	local other = BOBBA.live.create(mia.key, mia.name, "model_a", "Other room")
	BOBBA.live.enter(mia, other)
	local r2 = BOBBA.live.rooms[other]
	BOBBA.items.pickup(r, mia, b.id)
	BOBBA.items.placeExisting(r2, mia, b.id, "tele", 8, 8, 2, function() end)
	assert(BOBBA.items.use(r, bo, a.id))
	tickAll(60, run)
	u = BOBBA.live.byPlayer[bo]
	eq(u.room.id, other, "Bo is in the other room")
	eq(u.x .. "," .. u.y, "9,8", "out of b")
	-- b's partner in the inventory: back out the same one
	BOBBA.items.pickup(r, mia, a.id)
	assert(BOBBA.items.use(r2, bo, b.id))
	tickAll(60, run)
	eq(u.room.id, other)
	eq(u.x .. "," .. u.y, "9,8", "back out where he went in")
	eq(b.state, 0)
	restore()
end

T["a background toner: its colour set by the owner, kept; switched on and off"] = function()
	local mia, bo, r = start()
	BOBBA.live.enter(bo, r.id)
	local t = place(r, mia, "toner", 6, 3, 0)
	P.fromPlayer(mia, "room.item.toner", { id = t.id, hue = 120, saturation = 300, lightness = -5 })
	eq(t.data, "120,255,0")
	eq(last(bo, "room.items")[1].data, "120,255,0", "everyone sees it")
	P.fromPlayer(bo, "room.item.toner", { id = t.id, hue = 1, saturation = 1, lightness = 1 })
	eq(t.data, "120,255,0", "not Bo's to change")
	assert(BOBBA.items.use(r, mia, t.id))
	eq(t.state, 1)
	eq(BOBBA.store.row("SELECT data FROM bobbahotel_items WHERE id = ?", { t.id }).data, "120,255,0")
	-- picked up and put back it keeps its colour
	BOBBA.items.pickup(r, mia, t.id)
	local got
	BOBBA.items.placeExisting(r, mia, t.id, "toner", 7, 3, 0, function(it) got = it end)
	eq(got.data, "120,255,0")
end

T["the stacking helper: furni on its tiles go at the height it's set to"] = function()
	local mia, _, r = start()
	local chair = place(r, mia, "chair", 6, 3, 0)
	local h = place(r, mia, "helper", 6, 3, 0)
	assert(h, "goes over furni")
	eq(h.z, 0, "on the floor")
	assert(BOBBA.items.setStackHeight(r, mia, h.id, 250))
	eq(h.z, 2.5)
	local lamp = place(r, mia, "lamp", 7, 4, 0)
	eq(lamp.z, 2.5, "at the helper's height, though the floor is empty there")
	local lamp2 = place(r, mia, "lamp", 6, 3, 0)
	eq(lamp2.z, 2.5, "on the chair's tile too, chairs don't take furni")
	assert(BOBBA.items.setStackHeight(r, mia, h.id, -100))
	eq(h.z, 4.5, "above what's on it (the lamps: 2.5 + 2)")
	assert(BOBBA.items.setStackHeight(r, mia, h.id, 99999))
	eq(h.z, 40, "40 at most")
	local _ = chair
end

T["switching: round and round through its states"] = function()
	local mia, _, r = start()
	local lamp = place(r, mia, "lamp", 6, 3, 0)
	for i = 1, 5 do assert(BOBBA.items.use(r, mia, lamp.id)) eq(lamp.state, i % 2) end
	lamp.state = 9
	assert(BOBBA.items.use(r, mia, lamp.id))
	eq(lamp.state, 0, "a state it can't have starts again")
end

T["wall furni: hung on a wall where Habbo says, no tiles taken; moved along it, never turned or on the floor"] = function()
	local mia, bo, r = start()
	BOBBA.live.enter(bo, r.id)
	local _, why = place(r, mia, "poster", 6, 3, 0)
	assert(why, "a wall furni needs a wall")
	local got
	BOBBA.items.place(r, mia, "poster", 0, 0, 0, function(it, w) got, why = it, w end, nil, ":w=6,0 l=10,20 r")
	assert(got, why)
	local msg = last(bo, "room.items")[1]
	eq(msg.wall .. " " .. msg.x .. "," .. msg.y .. " " .. msg.dir, ":w=6,0 l=10,20 r 6,0 4", "on the right wall, facing 4")
	eq(BOBBA.pathfinder.tile(r.grid, 6, 1).state, "open", "no tiles")
	_, why = place(r, mia, "chair", 6, 1, 0)
	assert(not why, "a chair goes under it")
	BOBBA.items.place(r, mia, "chair", 0, 0, 0, function(_, w) why = w end, nil, ":w=6,0 l=10,20 r")
	eq(why, "that goes on the floor")
	-- along the walls, to the left one
	assert(BOBBA.items.move(r, mia, got.id, 0, 0, 0, ":w=3,7 l=4,50 l"))
	eq(last(bo, "room.items")[1].dir, 2, "the left wall faces 2")
	local ok
	ok, why = BOBBA.items.move(r, mia, got.id, 6, 6, 0)
	assert(not ok, "not to the floor")
	ok = BOBBA.items.move(r, mia, got.id, 0, 0, 0, "w=bad")
	assert(not ok, "a bad wall location")
	ok = BOBBA.items.rotate(r, mia, got.id)
	assert(not ok, "not turned")
	-- after a restart it's still there
	BOBBA.live.leave(mia)
	BOBBA.live.leave(bo)
	BOBBA.live.enter(mia, r.id)
	local wall
	for _, s in ipairs(last(mia, "room.load").items) do if s.id == got.id then wall = s.wall end end
	eq(wall, ":w=3,7 l=4,50 l")
	-- picked up and placed from the inventory onto a wall again
	assert(BOBBA.items.pickup(BOBBA.live.rooms[r.id], mia, got.id))
	P.fromPlayer(mia, "inventory.place", { id = got.id, wall = ":w=8,0 l=3,30 r" })
	eq(BOBBA.live.rooms[r.id].items[got.id].wall, ":w=8,0 l=3,30 r")
end

T["stickies: put up yellow and blank; the owner writes on them, picks a colour, throws them away"] = function()
	local mia, bo, r = start()
	BOBBA.live.enter(bo, r.id)
	local got, why
	BOBBA.items.place(r, mia, "post.it", 0, 0, 0, function(it, w) got, why = it, w end, nil, ":w=6,0 l=10,30 r")
	assert(got, why)
	eq(last(bo, "room.items")[1].data, "FFFF33")
	P.fromPlayer(bo, "room.item.stickie", { id = got.id, color = "9CCEFF", text = "hi" })
	assert(last(bo, "room.error"), "Bo can't")
	P.fromPlayer(mia, "room.item.stickie", { id = got.id, color = "9cceff", text = "Back at 5\nMia\1" })
	eq(last(bo, "room.items")[1].data, "9CCEFF Back at 5\nMia")
	P.fromPlayer(mia, "room.item.stickie", { id = got.id, color = "123456", text = "x" })
	eq(last(bo, "room.items")[1].data, "FFFF33 x", "only Habbo's four colours")
	P.fromPlayer(mia, "room.item.stickie.delete", { id = got.id })
	eq(r.items[got.id], nil)
	eq(BOBBA.store.row("SELECT id FROM bobbahotel_items WHERE id = ?", { got.id }), nil, "gone for good")
end

T["the mood light: one a room; switched on with its preset, presets saved and applied by the owner"] = function()
	local mia, bo, r = start()
	BOBBA.live.enter(bo, r.id)
	local got, why
	BOBBA.items.place(r, mia, "roomdimmer", 0, 0, 0, function(it, w) got, why = it, w end, nil, ":w=6,0 l=10,30 r")
	assert(got, why)
	eq(got.data, BOBBA.items.DIMMER_DEFAULT, "off, Habbo's presets")
	BOBBA.items.place(r, mia, "roomdimmer", 0, 0, 0, function(it, w) why = w end, nil, ":w=8,0 l=10,30 r")
	eq(why, "a room has only one mood light")
	P.fromPlayer(mia, "room.item.dimmer", { id = got.id, preset = 2, effect = 2, color = 0x0053F7, brightness = 200, apply = false })
	eq(BOBBA.items.dimmerData(got.data).presets[2].color, "0053F7", "saved")
	eq(BOBBA.items.dimmerData(got.data).on, false, "still off")
	P.fromPlayer(bo, "room.item.use", { id = got.id })
	eq(BOBBA.items.dimmerData(got.data).on, false, "Bo can't switch it")
	P.fromPlayer(mia, "room.item.use", { id = got.id })
	local d = BOBBA.items.dimmerData(last(bo, "room.items")[1].data)
	eq(d.on, true)
	eq(last(bo, "room.items")[1].state, 1, "lit")
	P.fromPlayer(mia, "room.item.dimmer", { id = got.id, preset = 2, effect = 2, color = 0x0053F7, brightness = 10, apply = true })
	d = BOBBA.items.dimmerData(got.data)
	eq(d.preset .. " " .. d.effect .. " " .. d.color .. " " .. d.light, "2 2 0053F7 76", "applied (no darker than Habbo's least)")
	P.fromPlayer(mia, "room.item.use", { id = got.id })
	eq(BOBBA.items.dimmerData(got.data).on, false, "off again")
end

return T
