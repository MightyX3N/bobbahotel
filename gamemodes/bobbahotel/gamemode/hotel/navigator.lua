-- The navigator (server): finding rooms and making new ones, the way Arcturus answers Nitro's
-- navigator. Four views, as Habbo's: official_view (the hotel's own rooms), hotel_view (everyone's
-- rooms, the fullest first), roomads_view (events: none yet) and myworld_view (your rooms, your
-- favourites). A search ("roomname:", "owner:", "tag:" or anything) gives one list, "query".
--
-- Messages from players: navigator.search { view, query }
--                        navigator.create { name, description, layout, maxUsers, trade, category }
-- Messages to players:   navigator.result { view, query, blocks = { { code, rooms = { room, ... } }, ... } }
--                          room: { id, name, owner, description, users, maxUsers, door = "open" | "doorbell" |
--                                  "password" | "invisible", tags, category, official }
--                        navigator.roominfo { id } -> navigator.roominfo { room ..., favourite, home, canEdit, hasRights }
--                        navigator.created { id }   (then the room is entered)

BOBBA.navigator = BOBBA.navigator or {}
local NAV = BOBBA.navigator
local live = BOBBA.live

NAV.VIEWS = { "official_view", "hotel_view", "roomads_view", "myworld_view" }
NAV.MAX_USERS = { 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 }
NAV.MAX_ROOMS_PER_PLAYER = 25
-- Nitro's room models for new rooms (ui-config "navigator.room.models": name, tiles, club level)
NAV.MODELS = {
	{ "a", 104, 0 }, { "b", 94, 0 }, { "c", 36, 0 }, { "d", 84, 0 }, { "e", 80, 0 }, { "f", 80, 0 }, { "i", 416, 0 },
	{ "j", 320, 0 }, { "k", 448, 0 }, { "l", 352, 0 }, { "m", 384, 0 }, { "n", 372, 0 }, { "g", 80, 1 }, { "h", 74, 1 },
	{ "o", 416, 1 }, { "p", 352, 1 }, { "q", 304, 1 }, { "r", 336, 1 }, { "u", 748, 1 }, { "v", 438, 1 }, { "t", 540, 2 },
	{ "w", 512, 2 }, { "x", 396, 2 }, { "y", 440, 2 }, { "z", 456, 2 }, { "0", 208, 2 }, { "1", 1009, 2 }, { "2", 1044, 2 },
	{ "3", 183, 2 }, { "4", 254, 2 }, { "5", 1024, 2 }, { "6", 801, 2 }, { "7", 354, 2 }, { "8", 888, 2 }, { "9", 926, 2 },
}

function NAV.migrate()
	-- what a new room is made with: how many may come in, who may trade, its category
	BOBBA.store.migrate("core.006_room_settings", {
		"ALTER TABLE bobbahotel_rooms ADD COLUMN max_users INTEGER NOT NULL DEFAULT 25",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN trade INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN category INTEGER NOT NULL DEFAULT 0",
	})
end

-- the hotel's own rooms (made by the server, like the Welcome Lounge)
local function isOfficial(row) return row.owner == "server" end

local function roomData(row)
	local loaded = live.rooms[tonumber(row.id)]
	local A = BOBBA.access
	return {
		id = tonumber(row.id), name = row.name, owner = row.owner_name, description = row.description or "",
		users = loaded and #loaded.order or 0, maxUsers = tonumber(row.max_users) or 25,
		door = A and A.STATES[tonumber(row.state) or 0] or "open", tags = A and A.tags(row) or {},
		category = tonumber(row.category) or 0, official = isOfficial(row) or nil,
	}
end
NAV.roomData = roomData

-- invisible rooms are only listed for their owner, those with rights and staff
local function visibleTo(player, row)
	if tonumber(row.state) ~= 3 then return true end
	if not player then return true end
	local A = BOBBA.access
	local info = { id = tonumber(row.id), owner = row.owner }
	return A.level(player, info) > 0
end

local function allRooms()
	return BOBBA.store.query("SELECT * FROM bobbahotel_rooms ORDER BY id")
end

-- the fullest first, then the newest
local function byUsers(list)
	table.sort(list, function(a, b)
		if a.users ~= b.users then return a.users > b.users end
		return a.id > b.id
	end)
	return list
end

-- the blocks of a view (Arcturus's navigator filters)
function NAV.view(view, playerKey, player)
	local rows = allRooms()
	local function pick(fn, all)
		local out = {}
		for _, r in ipairs(rows) do if fn(r) and (all or visibleTo(player, r)) then out[#out + 1] = roomData(r) end end
		return out
	end
	if view == "official_view" then
		return { { code = "official-root", rooms = byUsers(pick(isOfficial)) } }
	elseif view == "hotel_view" then
		-- (Habbo shows only rooms with people in "popular"; here every room is listed, the fullest first,
		-- so rooms can be found while the hotel is small); then a list per category (Arcturus's
		-- NavigatorHotelFilter: the top 10 of each, those with rooms)
		local blocks = { { code = "popular", rooms = byUsers(pick(function(r) return not isOfficial(r) end)) } }
		for _, c in ipairs(BOBBA.access.CATEGORIES) do
			local list = byUsers(pick(function(r) return not isOfficial(r) and tonumber(r.category) == c.id end))
			while #list > 10 do table.remove(list) end
			if #list > 0 then blocks[#blocks + 1] = { code = "category." .. c.code, category = c.id, rooms = list } end
		end
		return blocks
	elseif view == "roomads_view" then
		return { { code = "top_promotions", rooms = {} }, { code = "new_ads", rooms = {} } }
	elseif view == "myworld_view" then
		local A = BOBBA.access
		local fav = {}
		for _, id in ipairs(A.favourites(playerKey)) do fav[id] = true end
		local withRights = {}
		for _, r in ipairs(BOBBA.store.query("SELECT room FROM bobbahotel_room_rights WHERE key = ?", { tostring(playerKey) })) do withRights[tonumber(r.room)] = true end
		-- (Arcturus leaves out the empty lists, except your own rooms)
		local blocks = { { code = "my", rooms = pick(function(r) return r.owner == playerKey end, true) } }
		local favs = pick(function(r) return fav[tonumber(r.id)] end, true)
		if #favs > 0 then blocks[#blocks + 1] = { code = "favorites", rooms = favs } end
		local rights = pick(function(r) return withRights[tonumber(r.id)] end, true)
		if #rights > 0 then blocks[#blocks + 1] = { code = "with_rights", rooms = rights } end
		return blocks
	end
	return {}
end

-- a search: "roomname:x", "owner:x", "tag:x", "desc:x", "group:x" or just x (name, owner,
-- description or tags); a tag is any one of the room's tags, exactly (any case)
function NAV.search(query, player)
	local kind, text = query:match("^(%a+):(.*)$")
	if not kind then kind, text = "anything", query end
	text = text:lower()
	local out = {}
	for _, r in ipairs(allRooms()) do
		local name, owner, desc = (r.name or ""):lower(), (r.owner_name or ""):lower(), (r.description or ""):lower()
		local tags = (r.tags or ""):lower()
		local function hasTag(t) for x in tags:gmatch("[^;]+") do if x == t then return true end end return false end
		local hit
		if kind == "roomname" then hit = name:find(text, 1, true)
		elseif kind == "owner" then hit = owner == text
		elseif kind == "tag" then hit = hasTag(text)
		elseif kind == "desc" then hit = desc:find(text, 1, true)
		elseif kind == "group" then hit = false -- (no groups yet)
		else hit = name:find(text, 1, true) or owner:find(text, 1, true) or desc:find(text, 1, true) or tags:find(text, 1, true) end
		if hit and visibleTo(player, r) then out[#out + 1] = roomData(r) end
	end
	return { { code = "query", rooms = byUsers(out) } }
end

-- a new room for a player: name (3 to 60), description (up to 255), a model of NAV.MODELS they may use
function NAV.create(player, data)
	local P = BOBBA.platform
	if not BOBBA.perms.has(player, "bobba.room.create") then return nil, "not allowed" end
	local name = tostring(data.name or ""):gsub("[%c]", "")
	name = name:match("^%s*(.-)%s*$")
	if #name < 3 then return nil, "a room's name needs at least 3 letters" end
	local model
	for _, m in ipairs(NAV.MODELS) do if m[1] == tostring(data.model or "") then model = m end end
	if not model then return nil, "unknown room model" end
	local key = P.playerKey(player)
	local clubLevel = BOBBA.wallet and BOBBA.wallet.clubLevel(key) or 0
	if model[3] > clubLevel then return nil, "that room model is for Habbo Club members" end
	local count = BOBBA.store.row("SELECT COUNT(*) AS n FROM bobbahotel_rooms WHERE owner = ?", { key })
	if tonumber(count and count.n or 0) >= NAV.MAX_ROOMS_PER_PLAYER then return nil, "you have too many rooms" end
	local id, err = live.create(key, P.playerName(player), "model_" .. model[1], name)
	if not id then return nil, err end
	local maxUsers = tonumber(data.maxUsers) or 10
	local okMax = false
	for _, v in ipairs(NAV.MAX_USERS) do if v == maxUsers then okMax = true end end
	if not okMax then maxUsers = 10 end
	local trade = math.Clamp and math.Clamp(tonumber(data.trade) or 0, 0, 2) or math.min(2, math.max(0, tonumber(data.trade) or 0))
	local desc = tostring(data.description or ""):gsub("[%c]", " "):sub(1, 255)
	local category = 0
	for _, c in ipairs(BOBBA.access.CATEGORIES) do
		if c.id == tonumber(data.category) and (not c.staff or BOBBA.access.isStaff(player)) then category = c.id end
	end
	BOBBA.store.query("UPDATE bobbahotel_rooms SET description = ?, max_users = ?, trade = ?, category = ? WHERE id = ?",
		{ desc, maxUsers, math.floor(trade), category, id })
	return id
end

function NAV.start()
	NAV.migrate()
	local P = BOBBA.platform
	P.receive("navigator.search", function(player, data)
		local view = tostring(data.view or "official_view")
		local query = tostring(data.query or ""):sub(1, 100)
		local blocks = (query ~= "") and NAV.search(query, player) or NAV.view(view, P.playerKey(player), player)
		P.send("navigator.result", { view = view, query = query, blocks = blocks }, player)
	end)
	-- the room info popup (the "i" button): the room's data, and whether it's your favourite / home
	P.receive("navigator.roominfo", function(player, data)
		local info = live.info(data.id)
		if not info then return end
		local A = BOBBA.access
		local d = roomData(info)
		local key = P.playerKey(player)
		d.favourite = false
		for _, id in ipairs(A.favourites(key)) do if id == info.id then d.favourite = true end end
		d.home = A.home(key) == info.id
		d.canEdit = A.ownerLevel(player, info)
		d.hasRights = A.hasRights(player, info)
		P.send("navigator.roominfo", d, player)
	end)
	P.receive("navigator.create", function(player, data)
		local id, err = NAV.create(player, data)
		if not id then P.send("room.error", { message = tostring(err) }, player) return end
		P.send("navigator.created", { id = id }, player)
		live.enter(player, id)
	end)
end
