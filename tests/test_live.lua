local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	return { key = "765611980001", name = "Mia" }, { key = "765611980002", name = "Bo" }
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

T["the first start makes a home room; a ready player is put in it at the door"] = function()
	local mia = start()
	local home = BOBBA.live.homeRoom()
	eq(BOBBA.live.homeRoom(), home, "the same home room every time")
	eq(BOBBA.live.info(home).layout, "model_a")
	P.fromPlayer(mia, "room.ready")
	local load = last(mia, "room.load")
	assert(load, "room.load sent")
	eq(load.id, home)
	eq(load.layout, "model_a")
	eq(#load.units, 1, "just Mia")
	local me = load.units[1]
	eq(me.name, "Mia")
	eq(me.x .. "," .. me.y .. " dir " .. me.dir, "3,5 dir 2", "at model_a's door, facing in")
	eq(load.you, me.id, "told which one is you")
	P.fromPlayer(mia, "room.ready")
	eq(#P.inbox(mia, "room.load"), 1, "ready twice doesn't enter twice")
end

T["walking: one tile per step, the path Arcturus would take, then standing still"] = function()
	local mia = start()
	P.fromPlayer(mia, "room.ready")
	P.now = P.now + 1
	P.fromPlayer(mia, "room.walk", { x = 6, y = 5 })
	local seen = {}
	for i = 1, 6 do
		tick()
		local m = last(mia, "room.units")
		if m then seen[#seen + 1] = m[1] end
		P.sent = {}
	end
	-- 3,5 -> 4,5 -> 5,5 -> 6,5, then a message that she stopped
	eq(#seen, 4, "three steps and a stop")
	eq(seen[1].x .. "," .. seen[1].y .. ">" .. seen[1].to.x .. "," .. seen[1].to.y, "3,5>4,5")
	eq(seen[3].to.x .. "," .. seen[3].to.y, "6,5")
	eq(seen[1].dir, 2, "facing right (x + 1)")
	eq(seen[4].to, nil, "stopped")
	eq(seen[4].x .. "," .. seen[4].y, "6,5")
end

T["near the door players may walk through each other (Arcturus)"] = function()
	local mia, bo = start()
	P.fromPlayer(mia, "room.ready")
	BOBBA.live.walk(mia, 5, 5)
	tick(3)
	P.fromPlayer(bo, "room.ready")
	BOBBA.live.walk(bo, 6, 5)
	local path = {}
	for _ = 1, 4 do tick() local u = BOBBA.live.byPlayer[bo] path[#path + 1] = u.x .. "," .. u.y end
	eq(path[2], "5,5", "straight through")
end

T["walking: diagonal, and not through walls or off the room"] = function()
	local mia = start()
	P.fromPlayer(mia, "room.ready")
	eq(BOBBA.live.walk(mia, 0, 0), false, "outside the room")
	eq(BOBBA.live.walk(mia, 3, 5), false, "already there")
	eq(BOBBA.live.walk(mia, "a", nil), false, "nonsense")
	eq(BOBBA.live.walk(mia, 5, 7), true)
	tick()
	local u = BOBBA.live.byPlayer[mia]
	eq(u.x .. "," .. u.y .. " dir " .. u.dir, "4,5 dir 2", "out of the door straight first")
	tick()
	eq(u.x .. "," .. u.y .. " dir " .. u.dir, "5,6 dir 3", "then a diagonal step")
	-- and back in: through the tile in front of the door too
	BOBBA.live.walk(mia, 3, 5)
	tick()
	eq(u.x .. "," .. u.y, "4,5", "into the door only from the tile in front of it")
	tick()
	eq(u.x .. "," .. u.y, "3,5", "on the door")
end

T["two players: both see each other, and walk around each other"] = function()
	local mia, bo = start()
	P.fromPlayer(mia, "room.ready")
	BOBBA.live.walk(mia, 7, 5)
	tick(5)
	P.fromPlayer(bo, "room.ready")
	eq(#last(bo, "room.load").units, 2, "Bo sees Mia when he comes in")
	local added = last(mia, "room.units")
	eq(added[1].name, "Bo", "Mia sees Bo come in")
	-- Bo walks to the other side of Mia; she's in the way on the straight line. (Within 2 tiles of
	-- the door players may walk through each other, as in Arcturus, so she stands further in.)
	BOBBA.live.walk(bo, 10, 5)
	local cells = {}
	for _ = 1, 9 do
		tick()
		local u = BOBBA.live.byPlayer[bo]
		cells[#cells + 1] = u.x .. "," .. u.y
	end
	for _, c in ipairs(cells) do assert(c ~= "7,5", "walked through Mia: " .. table.concat(cells, " ")) end
	local u = BOBBA.live.byPlayer[bo]
	eq(u.x .. "," .. u.y, "10,5", "got there anyway")
end

T["leaving: the others are told, an empty room is unloaded; entering another room"] = function()
	local mia, bo = start()
	P.fromPlayer(mia, "room.ready")
	P.fromPlayer(bo, "room.ready")
	local home = BOBBA.live.homeRoom()
	local boId = BOBBA.live.byPlayer[bo].id
	P.disconnect(bo)
	eq(last(mia, "room.unit.remove").id, boId, "Mia told Bo left")
	local other = BOBBA.live.create(mia.key, mia.name, "model_h", "Mia's room")
	P.fromPlayer(mia, "room.enter", { id = other })
	eq(last(mia, "room.load").id, other)
	eq(BOBBA.live.rooms[home], nil, "the empty home room is unloaded")
	P.fromPlayer(mia, "room.enter", { id = other })
	eq(BOBBA.live.rooms[other] ~= nil, true, "entering the same room again keeps it loaded")
	eq(#BOBBA.live.rooms[other].order, 1, "and Mia is in it once")
	P.fromPlayer(mia, "room.enter", { id = 99999 })
	eq(last(mia, "room.error").message, "no room 99999")
	eq(BOBBA.live.byPlayer[mia].room.id, other, "still in her room")
end

T["rooms: names are cleaned, layouts checked"] = function()
	start()
	local id = BOBBA.live.create("1", "Mia", "model_a", "  Hi\n there\0  ")
	eq(BOBBA.live.info(id).name, "Hi there")
	eq(BOBBA.live.create("1", "Mia", "nope", "x"), nil, "unknown layout")
	eq(BOBBA.live.create("1", "Mia", "model_a", "   "), nil, "empty name")
	eq(BOBBA.live.create("1", "Mia", "model_a", string.rep("a", 100)) ~= nil, true)
	eq(#BOBBA.live.info(BOBBA.live.homeRoom()).name > 0, true)
end

T["walk clicks: at most 10 a second"] = function()
	local mia = start()
	P.fromPlayer(mia, "room.ready")
	P.fromPlayer(mia, "room.walk", { x = 6, y = 5 })
	P.fromPlayer(mia, "room.walk", { x = 7, y = 9 })
	eq(BOBBA.live.byPlayer[mia].goal.x, 6, "second click too fast")
	P.now = P.now + 0.2
	P.fromPlayer(mia, "room.walk", { x = 7, y = 9 })
	eq(BOBBA.live.byPlayer[mia].goal.x, 7, "later click counts")
end

T["wall height: per room, a default for new rooms, everyone in the room gets the new look"] = function()
	local mia, bo = start()
	P.fromPlayer(mia, "room.ready")
	P.fromPlayer(bo, "room.ready")
	local home = BOBBA.live.homeRoom()
	eq(BOBBA.live.info(home).wall_height, -1, "follows the hotel default")
	eq(last(mia, "room.load").wallHeight, 0.375, "the hotel default: walls lined up with Habbo's")
	eq(BOBBA.live.setWallHeight(home, "0.55"), true)
	eq(BOBBA.live.info(home).wall_height, 0.5, "steps of 0.125")
	eq(last(mia, "room.load").wallHeight, 0.5, "Mia got the new look")
	eq(last(bo, "room.load").wallHeight, 0.5, "Bo too")
	eq(#last(bo, "room.load").units, 2, "with everyone still there")
	eq(BOBBA.live.setWallHeight(home, 17), false, "too high")
	eq(BOBBA.live.setWallHeight(home, "abc"), false)
	eq(BOBBA.live.setWallHeight(home, -0.5), false)
	eq(BOBBA.live.setWallHeight(home, -1), true, "back to following the default")
	eq(BOBBA.live.setDefaultWallHeight(1), true)
	eq(last(mia, "room.load").wallHeight, 1, "a new hotel default reaches rooms that follow it")
	local id = BOBBA.live.create("1", "Mia", "model_b", "Tall")
	eq(BOBBA.live.wallHeightOf(BOBBA.live.info(id)), 1, "new rooms follow the default")
	-- and the client builds taller walls from it
	local room = BOBBA.rooms.geometryFor(BOBBA.registry.get("layout", "model_b").heightmap, { wallHeight = 1 })
	eq(room.wallHeight, 4.6)
	BOBBA.rooms.clearCache()
	local habbo = BOBBA.rooms.geometryFor(BOBBA.registry.get("layout", "model_a").heightmap, { wallHeight = BOBBA.live.DEFAULT_WALL_HEIGHT })
	local wall
	for _, p in ipairs(habbo.planes) do if p.type == BOBBA.rooms.PLANE_WALL and p.right[3] > 1 then wall = p break end end
	eq(wall.right[3], 4.35, "walls 4.35 high with the hotel default")
end

return T
