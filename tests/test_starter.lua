-- Starter rooms: offered to new players, made with the pack's furni, a gift inside (hotel/starter.lua)
local T = {}
local P

local function start(register)
	P = BOBBA.platform
	BOBBA.live.start()
	BOBBA.items.define("table", { width = 2, length = 2, height = 1, directions = { 0, 2 } })
	BOBBA.items.define("stool", { width = 1, length = 1, height = 1, sit = true, directions = { 0, 2, 4, 6 } })
	BOBBA.items.define("window", { width = 1, length = 1, height = 0, wall = true })
	BOBBA.items.define("lamp", { width = 1, length = 1, height = 2 })
	BOBBA.items.define("box", { width = 1, length = 1, height = 0.5, category = "present" })
	if register ~= false then
		BOBBA.registry.register("starter_room", "test_green", { name = "Green", layout = "model_a", order = 2, wallpaper = "105", floor = "201",
			furni = { { kind = "table", x = 6, y = 4 }, { kind = "stool", x = 5, y = 4, dir = 2 }, { kind = "window", wall = ":w=7,0 l=6,47 r" } },
			gift = { kind = "lamp", box = "box", x = 9, y = 8, message = "Hi!" } })
		BOBBA.registry.register("starter_room", "test_red", { name = "Red", layout = "model_a", order = 1 })
	end
	return { key = "765611980001", name = "Mia" }, { key = "765611980002", name = "Bo" }
end

local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end

T["no starter rooms registered: new players go straight to the hotel's first room"] = function()
	local mia = start(false)
	P.fromPlayer(mia, "room.ready", {})
	eq(last(mia, "starter.offer"), nil)
	eq(BOBBA.live.byPlayer[mia].room.id, BOBBA.live.homeRoom())
end

T["a new player is offered the rooms in order, in the hotel view"] = function()
	local mia = start()
	P.fromPlayer(mia, "room.ready", {})
	local offer = last(mia, "starter.offer")
	eq(#offer.rooms, 2)
	eq(offer.rooms[1].id .. " " .. offer.rooms[2].id, "test_red test_green", "by order")
	eq(table.concat(offer.rooms[2].furni, ","), "table,stool", "the floor furni, for the card")
	eq(BOBBA.live.byPlayer[mia], nil, "not in a room")
	assert(last(mia, "room.hotelview"), "in the hotel view")
end

T["choosing: the room is made, decorated, theirs and their home; a gift with the lamp inside"] = function()
	local mia = start()
	P.fromPlayer(mia, "room.ready", {})
	P.fromPlayer(mia, "starter.choose", { id = "test_green" })
	local u = BOBBA.live.byPlayer[mia]
	assert(u, "in the room")
	local info = u.room.info
	eq(info.owner .. "|" .. info.name .. "|" .. info.wallpaper .. "|" .. info.floor, mia.key .. "|Mia's room|105|201")
	eq(BOBBA.access.home(mia.key), info.id, "it's their home room")
	eq(last(mia, "room.home").id, info.id)
	local kinds, box = {}, nil
	for _, it in pairs(u.room.items) do
		kinds[#kinds + 1] = it.kind
		eq(it.owner, mia.key, it.kind .. " is hers")
		if it.kind == "box" then box = it end
	end
	table.sort(kinds)
	eq(table.concat(kinds, ","), "box,stool,table,window")
	eq(u.room.items[box.id].x .. "," .. u.room.items[box.id].y, "9,8")
	-- opening the gift: the lamp, where the box stood
	P.fromPlayer(mia, "room.item.open", { id = box.id })
	local opened = last(mia, "gift.opened")
	eq(opened.kind .. " " .. tostring(opened.inRoom) .. " " .. opened.from, "lamp true " .. BOBBA.access.hotelName())
	-- never offered again
	BOBBA.live.leave(mia)
	P.fromPlayer(mia, "room.ready", {})
	eq(#P.inbox(mia, "starter.offer"), 1, "offered once")
	eq(BOBBA.live.byPlayer[mia].room.id, info.id, "home, to her own room")
	P.fromPlayer(mia, "starter.choose", { id = "test_red" })
	eq(last(mia, "starter.error").message, "you already have a room")
end

T["skipping: to the hotel's first room, offered again next time; not to those who have rooms"] = function()
	local mia, bo = start()
	P.fromPlayer(mia, "room.ready", {})
	P.fromPlayer(mia, "starter.skip", {})
	eq(BOBBA.live.byPlayer[mia].room.id, BOBBA.live.homeRoom())
	BOBBA.live.leave(mia)
	P.fromPlayer(mia, "room.ready", {})
	eq(#P.inbox(mia, "starter.offer"), 2, "offered again")
	-- someone with a room of their own already
	BOBBA.live.create(bo.key, bo.name, "model_a", "Bo's den")
	P.fromPlayer(bo, "room.ready", {})
	eq(last(bo, "starter.offer"), nil)
	P.fromPlayer(mia, "starter.choose", { id = "nope" })
	eq(last(mia, "starter.error").message, "there's no such room to choose")
end

T["a starter room that's wrong is left out"] = function()
	start(false)
	local ok = BOBBA.registry.register("starter_room", "bad1", { name = "Bad", layout = "model_a", furni = { { kind = "x" } } })
	eq(ok, false, "furni with no place")
	ok = BOBBA.registry.register("starter_room", "bad2", { name = "Bad", layout = "model_a", wallpaper = "no way!" })
	eq(ok, false, "a bad wallpaper id")
	BOBBA.registry.register("starter_room", "nolayout", { name = "Gone", layout = "model_nope" })
	eq(#BOBBA.starter.list(), 0, "a layout that isn't installed")
end

return T
