-- Starting a player over (server), for staff and for trying out the new player's way in:
--   BOBBA.reset.look(key)      the default look again
--   BOBBA.reset.player(key)    as if they'd never been here: their rooms (other people's furni in them
--                              go back to their owners), inventory, money and club, look, wardrobe,
--                              effects, photos, favourites, home room, rights in other rooms, starter
--                              room and tutorial. Online, they're taken to the hotel view and offered
--                              a starter room again.
-- GMod: bobba_reset_player [name|steamid64] [all|look]   (server/players.lua; staff with bobba.staff.reset)

BOBBA.reset = BOBBA.reset or {}
local RS = BOBBA.reset
local live = BOBBA.live

BOBBA.perms.define("bobba.staff.reset", { default = "admin", description = "Start players over (bobba_reset_player)" })

local function P() return BOBBA.platform end
local function q(sql, args) return BOBBA.store.query(sql, args) end

local function online(key)
	for player, u in pairs(live.byPlayer) do if u.key == key then return player, u end end
	for player, k in pairs(BOBBA.wallet.online or {}) do if k == key then return player end end
	return nil
end

function RS.look(key)
	key = tostring(key)
	q("DELETE FROM bobbahotel_looks WHERE key = ?", { key })
	local _, u = online(key)
	if u then live.setFigure(u, nil, "M") end
	return true
end

-- furni ids and everything kept about them
local function dropItems(where, args)
	local sub = "SELECT id FROM bobbahotel_items WHERE " .. where
	q("DELETE FROM bobbahotel_teleports WHERE a IN (" .. sub .. ") OR b IN (" .. sub .. ")", (function()
		local t = {}
		for _, v in ipairs(args) do t[#t + 1] = v end
		for _, v in ipairs(args) do t[#t + 1] = v end
		return t
	end)())
	q("DELETE FROM bobbahotel_gifts WHERE id IN (" .. sub .. ")", args)
	q("DELETE FROM bobbahotel_items WHERE " .. where, args)
end

function RS.player(key)
	key = tostring(key)
	local player = online(key)
	-- out of any room first
	if player then live.leave(player) end
	-- their rooms: everyone out, other people's furni back to them, the rest gone
	local home = tonumber(BOBBA.store.setting("home_room", ""))
	for _, row in ipairs(q("SELECT id FROM bobbahotel_rooms WHERE owner = ?", { key })) do
		local id = tonumber(row.id)
		if id ~= home then
			local r = live.rooms[id]
			if r then
				local list = {}
				for _, uid in ipairs(r.order) do local u = r.units[uid] if u.player then list[#list + 1] = u.player end end
				for _, p in ipairs(list) do BOBBA.access.toHotelView(p) end
				live.rooms[id] = nil
				BOBBA.events.emit("roomUnloaded", r)
			end
			dropItems("room = ? AND owner = ?", { id, key })
			local owners = q("SELECT DISTINCT owner FROM bobbahotel_items WHERE room = ?", { id })
			q("UPDATE bobbahotel_items SET room = 0, x = 0, y = 0, z = 0, wall = '' WHERE room = ?", { id })
			for _, o in ipairs(owners) do
				local p = online(o.owner)
				if p then P().send("inventory.items", BOBBA.inventory.list(o.owner), p) end
			end
			for _, t in ipairs({ "bobbahotel_room_rights", "bobbahotel_room_bans", "bobbahotel_favourites", "bobbahotel_home_rooms" }) do
				q("DELETE FROM " .. t .. " WHERE room = ?", { id })
			end
			q("DELETE FROM bobbahotel_rooms WHERE id = ?", { id })
			BOBBA.events.emit("roomDeleted", id)
		end
	end
	-- their inventory
	dropItems("room = 0 AND owner = ?", { key })
	-- everything else kept about them
	for _, t in ipairs({ "bobbahotel_looks", "bobbahotel_wallets", "bobbahotel_effects", "bobbahotel_wardrobe", "bobbahotel_tutorial",
		"bobbahotel_starter_rooms", "bobbahotel_home_rooms", "bobbahotel_favourites", "bobbahotel_room_rights", "bobbahotel_room_bans" }) do
		q("DELETE FROM " .. t .. " WHERE key = ?", { key })
	end
	q("DELETE FROM bobbahotel_photos WHERE owner = ?", { key })
	if BOBBA.effects then BOBBA.effects.enabled[key] = nil end
	BOBBA.events.emit("playerReset", key)
	-- online: a fresh start (money, inventory, then the starter room picker or the first room)
	if player then
		local p = P()
		BOBBA.wallet.send(key)
		p.send("inventory.items", {}, player)
		p.send("room.home", { id = 0 }, player)
		p.send("room.favourites", { ids = {} }, player)
		if not BOBBA.starter.maybeOffer(player) then
			BOBBA.access.toHotelView(player)
			live.enter(player, live.homeRoom())
		end
	end
	return true
end
