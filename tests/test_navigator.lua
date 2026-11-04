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

local function codes(result)
	local out = {}
	for _, b in ipairs(result.blocks) do out[#out + 1] = b.code .. ":" .. #b.rooms end
	return table.concat(out, " ")
end

T["the views: public rooms, everyone's rooms, events, my world"] = function()
	local mia, bo = start()
	P.fromPlayer(mia, "room.ready")
	BOBBA.live.create(bo.key, bo.name, "model_b", "Bo's place")
	P.fromPlayer(mia, "navigator.search", { view = "official_view", query = "" })
	local r = last(mia, "navigator.result")
	eq(codes(r), "official-root:1", "the Welcome Lounge")
	eq(r.blocks[1].rooms[1].users, 1, "Mia is in it")
	P.fromPlayer(mia, "navigator.search", { view = "hotel_view", query = "" })
	eq(codes(last(mia, "navigator.result")), "popular:1", "Bo's room")
	P.fromPlayer(mia, "navigator.search", { view = "roomads_view", query = "" })
	eq(codes(last(mia, "navigator.result")), "top_promotions:0")
	P.fromPlayer(mia, "navigator.search", { view = "myworld_view", query = "" })
	eq(codes(last(mia, "navigator.result")), "my:0", "Mia has no rooms yet (empty lists left out, as Arcturus)")
	P.fromPlayer(bo, "navigator.search", { view = "myworld_view", query = "" })
	eq(codes(last(bo, "navigator.result")), "my:1")
end

T["searching: by name, by owner, anything"] = function()
	local mia, bo = start()
	BOBBA.live.create(bo.key, bo.name, "model_b", "Disco Party")
	BOBBA.live.create(mia.key, mia.name, "model_a", "Quiet corner")
	P.fromPlayer(mia, "navigator.search", { view = "hotel_view", query = "roomname:disco" })
	local r = last(mia, "navigator.result")
	eq(codes(r), "query:1")
	eq(r.blocks[1].rooms[1].name, "Disco Party")
	P.fromPlayer(mia, "navigator.search", { view = "hotel_view", query = "owner:mia" })
	eq(last(mia, "navigator.result").blocks[1].rooms[1].name, "Quiet corner")
	P.fromPlayer(mia, "navigator.search", { view = "hotel_view", query = "o" })
	eq(codes(last(mia, "navigator.result")), "query:3", "anything: names and owners (Disco, Quiet corner, the lounge's owner Bobba Hotel)")
end

T["making a room: checked, saved with its settings, and gone into"] = function()
	local mia = start()
	P.fromPlayer(mia, "room.ready")
	P.fromPlayer(mia, "navigator.create", { name = "ab", model = "a" })
	assert(last(mia, "room.error"), "a name needs 3 letters")
	P.fromPlayer(mia, "navigator.create", { name = "Club room", model = "g" })
	assert(last(mia, "room.error").message:find("Club"), "model g is for club members")
	P.fromPlayer(mia, "navigator.create", { name = "  My room  ", description = "Come in", model = "c", maxUsers = 30, trade = 2 })
	local made = last(mia, "navigator.created")
	assert(made, "made")
	local info = BOBBA.live.info(made.id)
	eq(info.name, "My room")
	eq(info.layout, "model_c")
	eq(info.description, "Come in")
	eq(tonumber(info.max_users), 30)
	eq(tonumber(info.trade), 2)
	eq(last(mia, "room.load").id, made.id, "Mia is taken into it")
	P.fromPlayer(mia, "navigator.create", { name = "Odd", model = "b", maxUsers = 33 })
	eq(tonumber(BOBBA.live.info(last(mia, "navigator.created").id).max_users), 10, "a size Habbo doesn't offer becomes 10")
end

return T
