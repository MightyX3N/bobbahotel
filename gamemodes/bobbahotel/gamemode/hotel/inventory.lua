-- Everyone's inventory (server): furni that isn't in a room, the way Arcturus keeps it, as rows of
-- bobbahotel_items with room 0 and the player as owner. Bought furni comes here; picking furni up
-- brings it back to its owner's; placing takes it out into the room.
--
-- Messages to players:  inventory.items { { id, kind }, ... }  (all of it)
--                       inventory.added { { id, kind, new }, ... }  inventory.removed { id, ... }
-- Messages from players: inventory.get {}, inventory.place { id, x, y, dir }

BOBBA.inventory = BOBBA.inventory or {}
local INV = BOBBA.inventory

function INV.list(key)
	local rows = BOBBA.store.query("SELECT id, kind FROM bobbahotel_items WHERE room = 0 AND owner = ? ORDER BY id", { tostring(key) })
	local out = {}
	for _, r in ipairs(rows) do out[#out + 1] = { id = tonumber(r.id), kind = r.kind } end
	return out
end

local function playerFor(key)
	for player, k in pairs(BOBBA.wallet.online) do if k == key then return player end end
	for player, u in pairs(BOBBA.live.byPlayer) do if u.key == key then return player end end
end

-- new furni for someone: n of a kind (data: what they keep, e.g. a trophy's engraving); returns
-- the new rows
function INV.give(key, kind, n, data)
	local added = {}
	BOBBA.store.transaction(function()
		for _ = 1, math.max(1, math.floor(n or 1)) do
			BOBBA.store.query("INSERT INTO bobbahotel_items (room, owner, kind, x, y, z, dir, state, data) VALUES (0, ?, ?, 0, 0, 0, 0, 0, ?)", { tostring(key), kind, data or "" })
			-- (new: the player's inventory marks it until they look, Habbo's unseen items)
			added[#added + 1] = { id = tonumber(BOBBA.store.row("SELECT last_insert_rowid() AS id").id), kind = kind, new = true }
		end
	end)
	local player = playerFor(key)
	if player then BOBBA.platform.send("inventory.added", added, player) end
	return added
end

-- a furni back into its owner's inventory (picked up)
function INV.take(itemId, key, kind)
	BOBBA.store.query("UPDATE bobbahotel_items SET room = 0, x = 0, y = 0, z = 0, state = 0 WHERE id = ?", { itemId })
	local player = playerFor(key)
	if player then BOBBA.platform.send("inventory.added", { { id = itemId, kind = kind } }, player) end
end

function INV.start()
	local P = BOBBA.platform
	P.receive("inventory.get", function(player)
		P.send("inventory.items", INV.list(P.playerKey(player)), player)
	end)
	P.receive("inventory.place", function(player, data)
		local u = BOBBA.live.byPlayer[player]
		if not u then return end
		local key = P.playerKey(player)
		local row = BOBBA.store.row("SELECT * FROM bobbahotel_items WHERE id = ? AND room = 0 AND owner = ?", { tonumber(data.id) or -1, key })
		if not row then P.send("room.error", { message = "that isn't in your inventory" }, player) return end
		BOBBA.items.placeExisting(u.room, player, tonumber(row.id), row.kind, data.x, data.y, data.dir, function(it, why)
			if not it then P.send("room.error", { message = tostring(why) }, player) return end
			P.send("inventory.removed", { it.id }, player)
		end)
	end)
end
