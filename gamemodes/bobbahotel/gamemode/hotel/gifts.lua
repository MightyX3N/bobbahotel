-- Gifts (server), like Habbo's: anything in the catalogue (not club, not teleports) can be bought for
-- someone else. It goes into their inventory wrapped in a gift box with a greeting (and the giver's
-- face, if they want). Placed in a room and opened by the room's owner, the gift becomes what was in
-- it, where the box stood (or in their inventory when it doesn't fit there).
--
-- Who's who: the players the hotel has seen (bobbahotel_users: key, name), so a gift can go to
-- someone who isn't online.
--
-- Messages from players: catalog.gift { page, offer, receiver, message, box, showFace, extra }
--                        room.item.open { id }   (open a gift)
-- Messages to players:   catalog.bought { page, offer, amount, gift = true }   catalog.error { message }
--                        gift.opened { present, id, kind, inRoom, from }

BOBBA.gifts = BOBBA.gifts or {}
local G = BOBBA.gifts

-- the boxes to choose from: Habbo's six gift boxes, then its wrapping paper in ten colours
G.BOXES = { "present_gen1", "present_gen2", "present_gen3", "present_gen4", "present_gen5", "present_gen6" }
for i = 1, 10 do G.BOXES[#G.BOXES + 1] = "present_wrap*" .. i end
G.MESSAGE_MAX = 140

function G.migrate()
	BOBBA.store.migrate("core.011_users", {
		"CREATE TABLE bobbahotel_users (key TEXT PRIMARY KEY, name TEXT NOT NULL, seen INTEGER NOT NULL DEFAULT 0)",
		"CREATE INDEX bobbahotel_users_name ON bobbahotel_users (name)",
	})
	-- what's in each gift box (its item id): a kind and its data
	BOBBA.store.migrate("core.012_gifts", {
		"CREATE TABLE bobbahotel_gifts (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, data TEXT NOT NULL DEFAULT '')",
	})
end

function G.remember(key, name)
	-- (kept as it is otherwise: since when, the motto)
	BOBBA.store.query("INSERT OR IGNORE INTO bobbahotel_users (key, name, seen) VALUES (?, ?, ?)", { tostring(key), tostring(name), BOBBA.platform.time() })
	BOBBA.store.query("UPDATE bobbahotel_users SET name = ?, seen = ? WHERE key = ?", { tostring(name), BOBBA.platform.time(), tostring(key) })
end

-- someone by name (any case): key, name
function G.findUser(name)
	name = tostring(name or ""):match("^%s*(.-)%s*$")
	if name == "" then return nil end
	local row = BOBBA.store.row("SELECT key, name FROM bobbahotel_users WHERE lower(name) = lower(?) ORDER BY seen DESC", { name })
	if row then return row.key, row.name end
end

-- buys an offer as a gift: true, or false and why
function G.send(player, data)
	local P = BOBBA.platform
	local CAT = BOBBA.catalog
	local page, offer = CAT.find(player, data.page, data.offer)
	if not page then return false, offer end
	if offer.club or offer.pair or not offer.kind then return false, "that can't be given as a gift" end
	local toKey, toName = G.findUser(data.receiver)
	if not toKey then return false, "no one called " .. tostring(data.receiver) end
	local box = G.BOXES[tonumber(data.box) or 1] or G.BOXES[1]
	local key = P.playerKey(player)
	if not BOBBA.wallet.pay(key, offer.price or {}, "gift", offer.kind, toKey) then return false, "you don't have enough to buy that" end
	-- the tag: who it's from (and their face), the greeting
	local message = tostring(data.message or ""):gsub("[%z\1-\9\11-\31]", ""):sub(1, G.MESSAGE_MAX)
	local face = ""
	if data.showFace then
		local figure, gender = BOBBA.looks.get(key)
		if figure then face = figure .. "|" .. (gender or "M") end
	end
	local tag = P.playerName(player) .. "\t" .. message .. "\t" .. face
	local present = BOBBA.inventory.give(toKey, box, 1, tag, "gift", key)[1]
	local inside = offer.trophy and CAT.engraving(player, data.extra) or offer.data or ""
	BOBBA.store.query("INSERT OR REPLACE INTO bobbahotel_gifts (id, kind, data) VALUES (?, ?, ?)", { present.id, offer.kind, inside })
	BOBBA.events.emit("giftSent", key, toKey, offer)
	return true, toName
end

-- opens a gift in a room: what was in it takes its place
function G.open(r, player, id)
	local P = BOBBA.platform
	local I = BOBBA.items
	local it = r.items[tonumber(id) or -1]
	if not it or not it.def or not it.def.present then return false, "that isn't a gift" end
	if not I.canEdit(player, r) then return false, "only the room's owner can open it" end
	local row = BOBBA.store.row("SELECT kind, data FROM bobbahotel_gifts WHERE id = ?", { it.id })
	local from = tostring(it.data or ""):match("^([^\t]*)") or ""
	local x, y, dir, owner = it.x, it.y, it.dir, it.owner
	-- the box goes away
	r.items[it.id] = nil
	BOBBA.store.query("DELETE FROM bobbahotel_items WHERE id = ?", { it.id })
	BOBBA.store.query("DELETE FROM bobbahotel_gifts WHERE id = ?", { it.id })
	I.removed(r, it)
	BOBBA.events.emit("giftOpened", r, player, it)
	if not row then P.send("gift.opened", { present = it.id, from = from }, player) return true end
	-- what was in it: into the owner's inventory, then put where the box was if it fits there
	local added = BOBBA.inventory.give(owner, row.kind, 1, row.data, "gift opened")[1]
	I.placeExisting(r, player, added.id, row.kind, x, y, dir, function(placed)
		if placed then
			P.send("inventory.removed", { added.id }, player)
		end
		P.send("gift.opened", { present = it.id, id = added.id, kind = row.kind, inRoom = placed ~= nil, from = from }, player)
	end)
	return true
end

function G.start()
	G.migrate()
	local P = BOBBA.platform
	BOBBA.events.on("roomEntered", "bobba.gifts", function(_, u)
		if u.player then G.remember(u.key, u.name) end
	end)
	P.receive("catalog.gift", function(player, data)
		BOBBA.catalog.build(function()
			local ok, why = G.send(player, data)
			if ok then P.send("catalog.bought", { page = data.page, offer = data.offer, amount = 1, gift = true, receiver = why }, player)
			else P.send("catalog.error", { message = tostring(why), gift = true }, player) end
		end)
	end)
	P.receive("room.item.open", function(player, data)
		local u = BOBBA.live.byPlayer[player]
		if not u then return end
		local ok, why = G.open(u.room, player, data.id)
		if not ok then P.send("room.error", { message = tostring(why) }, player) end
	end)
end
