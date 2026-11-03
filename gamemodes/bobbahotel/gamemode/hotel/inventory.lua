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
	local rows = BOBBA.store.query("SELECT id, kind, data FROM bobbahotel_items WHERE room = 0 AND owner = ? ORDER BY id", { tostring(key) })
	local out = {}
	-- (data: what the furni keeps; the inventory shows a wallpaper's id, a trophy's engraving ...)
	for _, r in ipairs(rows) do out[#out + 1] = { id = tonumber(r.id), kind = r.kind, data = (r.data and r.data ~= "") and r.data or nil } end
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
			added[#added + 1] = { id = tonumber(BOBBA.store.row("SELECT last_insert_rowid() AS id").id), kind = kind, new = true,
				data = (data and data ~= "") and data or nil }
		end
	end)
	local player = playerFor(key)
	if player then BOBBA.platform.send("inventory.added", added, player) end
	return added
end

-- a furni back into its owner's inventory (picked up)
function INV.take(itemId, key, kind)
	BOBBA.store.query("UPDATE bobbahotel_items SET room = 0, x = 0, y = 0, z = 0, state = 0, wall = '' WHERE id = ?", { itemId })
	local player = playerFor(key)
	local row = BOBBA.store.row("SELECT data FROM bobbahotel_items WHERE id = ?", { itemId })
	local data = row and row.data ~= "" and row.data or nil
	if player then BOBBA.platform.send("inventory.added", { { id = itemId, kind = kind, data = data } }, player) end
end

-- puts a wallpaper, floor or landscape (row: its inventory row) on a room: true, or false and why
local LOOK_COLUMN = { wallpaper = "wallpaper", floor = "floor", landscape = "landscape" }
function INV.paint(r, player, row, paint)
	if not BOBBA.items.canEdit(player, r) then return false, "only the room's owner can change how it looks" end
	local column = LOOK_COLUMN[paint]
	if not column or not BOBBA.live.validLook(row.data) or row.data == "" then return false, "that has no pattern" end
	BOBBA.store.query("DELETE FROM bobbahotel_items WHERE id = ?", { tonumber(row.id) })
	BOBBA.platform.send("inventory.removed", { tonumber(row.id) }, player)
	BOBBA.live.setLook(r.id, column, row.data)
	BOBBA.events.emit("roomPainted", r.id, column, row.data)
	return true
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
		BOBBA.items.resolve(row.kind, function(def, why)
			if not def then P.send("room.error", { message = tostring(why) }, player) return end
			-- a wallpaper, floor or landscape goes onto the room and is used up (Arcturus RoomPlaceItemEvent)
			if def.paint then
				local ok, why2 = INV.paint(u.room, player, row, def.paint)
				if not ok then P.send("room.error", { message = tostring(why2) }, player) end
				return
			end
			BOBBA.items.placeExisting(u.room, player, tonumber(row.id), row.kind, data.x, data.y, data.dir, function(it, why3)
				if not it then P.send("room.error", { message = tostring(why3) }, player) return end
				P.send("inventory.removed", { it.id }, player)
			end, type(data.wall) == "string" and data.wall or nil)
		end)
	end)
end
