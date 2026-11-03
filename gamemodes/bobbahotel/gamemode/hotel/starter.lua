-- Starter rooms (server): a new player picks a room of their own to begin with, like Habbo's
-- "choose your room" for new users. The hotel itself has none; a content addon registers them, so
-- any pack can offer its own (as many as it likes):
--
--   BOBBA.registry.register("starter_room", "classic_orange", {
--       name = "Orange",                     -- in the picker
--       layout = "model_a",                  -- a registered layout
--       wallpaper = "101", floor = "202",    -- the room's look (ids the pack's planes know), optional
--       landscape = "",
--       color = { r = 243, g = 132, b = 32 },  -- the picker's card, optional
--       order = 1,                           -- the picker's order, optional
--       furni = {                            -- placed in the room, owned by the player
--           { kind = "noob_table*1", x = 6, y = 5, dir = 0 },
--           { kind = "noob_window_double", wall = ":w=8,0 l=8,40 r" },
--       },
--       gift = { kind = "noob_lamp*1", box = "present_gen1", x = 9, y = 9, message = "Welcome!" },
--   })
--
-- Who is offered one: players who never chose one and have no room of their own. They get the
-- picker over the hotel view when they come in; closing it takes them to the hotel's first room
-- and it's offered again next time. The chosen room is theirs, named after them, and becomes their
-- home room.
--
-- Messages to players:   starter.offer { rooms = { { id, name, layout, wallpaper, floor, landscape,
--                          color, furni = { floor furni kind, ... } }, ... } }   starter.error { message }
-- Messages from players: starter.choose { id }   starter.skip {}

BOBBA.starter = BOBBA.starter or {}
local S = BOBBA.starter
local live = BOBBA.live

BOBBA.registry.defineType("starter_room", {
	fields = { name = "string", layout = "string", wallpaper = "string?", floor = "string?", landscape = "string?",
		color = "table?", order = "number?", furni = "table?", gift = "table?", roomName = "string?", description = "string?" },
	validate = function(def)
		for _, f in ipairs(def.furni or {}) do
			if type(f) ~= "table" or type(f.kind) ~= "string" or f.kind == "" then return false, "each furni needs a kind" end
			if f.wall == nil and (type(f.x) ~= "number" or type(f.y) ~= "number") then return false, f.kind .. " needs x and y, or wall" end
		end
		if def.gift and (type(def.gift.kind) ~= "string" or def.gift.kind == "") then return false, "the gift needs a kind" end
		for _, k in ipairs({ "wallpaper", "floor", "landscape" }) do
			if def[k] ~= nil and live.validLook(def[k]) == nil then return false, k .. " isn't a valid id" end
		end
		return true
	end,
})

S.GIFT_BOX = "present_gen1"

function S.migrate()
	-- who chose a starter room, and which room it made
	BOBBA.store.migrate("core.016_starter_rooms", {
		"CREATE TABLE bobbahotel_starter_rooms (key TEXT PRIMARY KEY, room INTEGER NOT NULL, kind TEXT NOT NULL, created INTEGER NOT NULL)",
	})
end

-- the starter rooms on offer, in order
function S.list()
	local out = {}
	for _, def in ipairs(BOBBA.registry.list("starter_room")) do
		if BOBBA.registry.get("layout", def.layout) then out[#out + 1] = def end
	end
	return out
end

-- whether a player is offered one: never chose one and owns no room
function S.eligible(key)
	key = tostring(key)
	if BOBBA.store.row("SELECT key FROM bobbahotel_starter_rooms WHERE key = ?", { key }) then return false end
	if BOBBA.store.row("SELECT id FROM bobbahotel_rooms WHERE owner = ? LIMIT 1", { key }) then return false end
	return #S.list() > 0
end

-- what the picker shows
function S.offer()
	local out = {}
	for _, def in ipairs(S.list()) do
		local kinds = {}
		-- (the floor furni, for the picker's card)
		for _, f in ipairs(def.furni or {}) do if f.wall == nil then kinds[#kinds + 1] = f.kind end end
		out[#out + 1] = { id = def.id, name = def.name, layout = def.layout, wallpaper = def.wallpaper or "", floor = def.floor or "",
			landscape = def.landscape or "", color = def.color, furni = kinds }
	end
	return out
end

local function insertItem(room, owner, kind, x, y, z, dir, wall, data)
	BOBBA.store.query("INSERT INTO bobbahotel_items (room, owner, kind, x, y, z, dir, state, data, wall) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)",
		{ room, owner, kind, math.floor(x or 0), math.floor(y or 0), tonumber(z) or 0, math.floor(dir or 0), data or "", wall or "" })
	return tonumber(BOBBA.store.row("SELECT last_insert_rowid() AS id").id)
end

-- makes the starter room for a player: the room's id, or nil and why
function S.create(key, name, id)
	key = tostring(key)
	local def = BOBBA.registry.get("starter_room", tostring(id or ""))
	if not def then return nil, "there's no such room to choose" end
	if not S.eligible(key) then return nil, "you already have a room" end
	local roomName = (def.roomName or "%s's room"):gsub("%%s", (tostring(name):gsub("%%", "%%%%")))
	local room, err = live.create(key, name, def.layout, roomName)
	if not room then return nil, err end
	BOBBA.store.transaction(function()
		BOBBA.store.query("UPDATE bobbahotel_rooms SET floor = ?, wallpaper = ?, landscape = ?, description = ? WHERE id = ?",
			{ live.validLook(def.floor) or "", live.validLook(def.wallpaper) or "", live.validLook(def.landscape) or "",
				tostring(def.description or ""):sub(1, 255), room })
		for _, f in ipairs(def.furni or {}) do
			insertItem(room, key, f.kind, f.x, f.y, f.z, f.dir, f.wall)
		end
		-- the gift: a box in the room with something in it (gifts.lua opens it)
		local g = def.gift
		if g then
			local tag = BOBBA.access.hotelName() .. "\t" .. tostring(g.message or "") .. "\t"
			local box = insertItem(room, key, g.box or S.GIFT_BOX, g.x, g.y, g.z, g.dir, g.wall, tag)
			BOBBA.store.query("INSERT OR REPLACE INTO bobbahotel_gifts (id, kind, data) VALUES (?, ?, ?)", { box, g.kind, g.data or "" })
		end
		BOBBA.store.query("INSERT OR REPLACE INTO bobbahotel_starter_rooms (key, room, kind, created) VALUES (?, ?, ?, ?)",
			{ key, room, def.id, math.floor(BOBBA.platform.time()) })
	end)
	BOBBA.access.setHome(key, room)
	BOBBA.events.emit("starterRoomCreated", key, room, def)
	return room
end

-- room.ready: true when the player was offered a room (and so waits in the hotel view)
function S.maybeOffer(player)
	local P = BOBBA.platform
	if not S.eligible(P.playerKey(player)) then return false end
	P.send("room.hotelview", {}, player)
	P.send("starter.offer", { rooms = S.offer() }, player)
	return true
end

function S.start()
	S.migrate()
	local P = BOBBA.platform
	P.receive("starter.choose", function(player, data)
		local key = P.playerKey(player)
		local room, err = S.create(key, P.playerName(player), data.id)
		if not room then P.send("starter.error", { message = tostring(err) }, player) return end
		P.send("room.home", { id = room }, player)
		live.enter(player, room)
	end)
	-- closed without choosing: to the hotel's first room (offered again next time)
	P.receive("starter.skip", function(player)
		if live.byPlayer[player] then return end
		live.enter(player, live.homeRoom())
	end)
end
