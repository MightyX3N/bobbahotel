-- Trading (server): two players in a room swap furni from their inventories, the way Habbo has it
-- (Arcturus's RoomTrade, nitro-react's useInventoryTrade):
--   one opens a trade with someone in the room (the avatar menu's Trade); both see it at once
--   each puts furni in (and takes them out) - any change takes back both sides' "accept"
--   both accept -> both confirm (after Nitro's 3 second countdown) -> the furni change owners
-- Whether a room allows it is its trade setting (0 no one, 1 when either of them has rights,
-- 2 everyone) and the hotel's trading.enabled. Furni in a trade can't be put in a room meanwhile.
-- The swap happens in one transaction that checks again that each furni is still its owner's and
-- in their inventory; it goes in the economy's log (economy.lua).
-- A trade ends when either cancels, leaves the room or goes.
--
-- Messages from players: trade.open { unit }  trade.offer { ids }  trade.take { ids }
--                        trade.accept { on }  trade.confirm {}  trade.cancel {}
-- Messages to players:   trade.state { other = { key, name, figure, gender }, mine = { { id, kind, data } },
--                          theirs = {...}, accepted, theyAccepted, stage = "offer" | "confirm",
--                          confirmed, theyConfirmed }
--                        trade.closed { why = "cancelled" | "done" | "left" | "failed", by }
--                        trade.error { message }

BOBBA.trading = BOBBA.trading or { byPlayer = {}, locked = {} }
local T = BOBBA.trading
local live = BOBBA.live

T.MAX_KINDS = 9      -- Nitro's MAX_ITEMS_TO_TRADE: nine slots, each one kind
T.MAX_ITEMS = 100
T.OPEN_EVERY = 2     -- seconds between opening trades

local function P() return BOBBA.platform end
local function S() return BOBBA.store end

function T.enabled() return S().setting("trading.enabled", "1") ~= "0" end

-- may player trade with them here (Nitro's AvatarInfoUtilities: 1 = roomController || targetController)
function T.allowed(r, player, other)
	if not T.enabled() then return false, "trading is off in this hotel" end
	local mode = tonumber(r.info and r.info.trade) or 0
	if mode == 2 then return true end
	if mode == 1 then
		local A = BOBBA.access
		if A.hasRights(player, r.info) or A.hasRights(other, r.info) then return true end
		return false, "only people with rights can trade in this room"
	end
	return false, "trading isn't allowed in this room"
end

local function side(t, player) if t.a.player == player then return t.a, t.b end return t.b, t.a end

local function itemsOf(s)
	local out = {}
	for _, id in ipairs(s.order) do local it = s.items[id] if it then out[#out + 1] = { id = id, kind = it.kind, data = it.data } end end
	return out
end

function T.send(t)
	for _, me in ipairs({ t.a, t.b }) do
		local other = me == t.a and t.b or t.a
		local figure, gender = BOBBA.looks.get(other.key)
		P().send("trade.state", {
			other = { key = other.key, name = other.name, figure = figure, gender = gender },
			mine = itemsOf(me), theirs = itemsOf(other), accepted = me.accepted, theyAccepted = other.accepted,
			stage = t.stage, confirmed = me.confirmed, theyConfirmed = other.confirmed,
		}, me.player)
	end
end

-- (something changed: both accept again)
local function reset(t)
	t.a.accepted, t.b.accepted, t.a.confirmed, t.b.confirmed = false, false, false, false
	t.stage = "offer"
end

function T.close(t, why, by)
	if t.closed then return end
	t.closed = true
	for _, s in ipairs({ t.a, t.b }) do
		T.byPlayer[s.player] = nil
		for id in pairs(s.items) do T.locked[id] = nil end
		P().send("trade.closed", { why = why, by = by }, s.player)
	end
end

function T.open(player, unitId)
	local u = live.byPlayer[player]
	if not u or not u.room then return false, "you're not in a room" end
	local t = u.room.units[tonumber(unitId) or -1]
	if not t or not t.player or t.player == player then return false, "you can't trade with that" end
	if T.byPlayer[player] then return false, "you're already trading" end
	if T.byPlayer[t.player] then return false, t.name .. " is already trading" end
	local ok, why = T.allowed(u.room, player, t.player)
	if not ok then return false, why end
	local function newSide(p, unit) return { player = p, key = P().playerKey(p), name = unit.name, items = {}, order = {}, accepted = false, confirmed = false } end
	local trade = { a = newSide(player, u), b = newSide(t.player, t), room = u.room, stage = "offer" }
	T.byPlayer[player], T.byPlayer[t.player] = trade, trade
	T.send(trade)
	return true
end

local function kinds(s)
	local set, n = {}, 0
	for _, it in pairs(s.items) do if not set[it.kind] then set[it.kind] = true n = n + 1 end end
	return set, n
end

function T.offer(player, ids)
	local t = T.byPlayer[player]
	if not t then return false, "you're not trading" end
	local me = side(t, player)
	local set, n = kinds(me)
	local count = #me.order
	local why
	for _, id in ipairs(type(ids) == "table" and ids or {}) do
		id = tonumber(id)
		if id and not me.items[id] and not T.locked[id] then
			local row = S().row("SELECT id, kind, data FROM bobbahotel_items WHERE id = ? AND room = 0 AND owner = ?", { id, me.key })
			if row then
				if not set[row.kind] and n >= T.MAX_KINDS then why = "a trade has room for " .. T.MAX_KINDS .. " kinds of furni" break end
				if count >= T.MAX_ITEMS then why = "a trade has room for " .. T.MAX_ITEMS .. " furni" break end
				if not set[row.kind] then set[row.kind] = true n = n + 1 end
				me.items[id] = { kind = row.kind, data = (row.data and row.data ~= "") and row.data or nil }
				me.order[#me.order + 1] = id
				T.locked[id] = t
				count = count + 1
			end
		end
	end
	reset(t)
	T.send(t)
	return why == nil, why
end

function T.take(player, ids)
	local t = T.byPlayer[player]
	if not t then return false, "you're not trading" end
	local me = side(t, player)
	for _, id in ipairs(type(ids) == "table" and ids or {}) do
		id = tonumber(id)
		if id and me.items[id] then
			me.items[id] = nil
			T.locked[id] = nil
			for i, x in ipairs(me.order) do if x == id then table.remove(me.order, i) break end end
		end
	end
	reset(t)
	T.send(t)
	return true
end

function T.accept(player, on)
	local t = T.byPlayer[player]
	if not t or t.stage ~= "offer" then return false end
	local me, other = side(t, player)
	-- (nothing on either side: nothing to accept, as Nitro's button)
	if on and #me.order == 0 and #other.order == 0 then return false, "put something in the trade first" end
	me.accepted = on and true or false
	if t.a.accepted and t.b.accepted then t.stage = "confirm" end
	T.send(t)
	return true
end

-- the swap: every furni still its owner's and in their inventory, or nothing changes
function T.finish(t)
	local moved = { [t.a] = {}, [t.b] = {} }
	local ok, err = pcall(S().transaction, function()
		for _, s in ipairs({ t.a, t.b }) do
			local to = s == t.a and t.b or t.a
			for _, id in ipairs(s.order) do
				local row = S().row("SELECT kind, data FROM bobbahotel_items WHERE id = ? AND room = 0 AND owner = ?", { id, s.key })
				if not row then error("gone") end
				S().query("UPDATE bobbahotel_items SET owner = ? WHERE id = ?", { to.key, id })
				moved[s][#moved[s] + 1] = { id = id, kind = row.kind, data = (row.data and row.data ~= "") and row.data or nil }
			end
		end
	end)
	if not ok then return false, err end
	for _, s in ipairs({ t.a, t.b }) do
		local to = s == t.a and t.b or t.a
		local list = moved[s]
		if #list > 0 then
			local ids, counts = {}, {}
			for _, it in ipairs(list) do ids[#ids + 1] = it.id counts[it.kind] = (counts[it.kind] or 0) + 1 end
			P().send("inventory.removed", ids, s.player)
			P().send("inventory.added", list, to.player)
			if BOBBA.economy then
				for kind, n in pairs(counts) do
					BOBBA.economy.log(s.key, "furni", -n, "trade", kind, to.key)
					BOBBA.economy.log(to.key, "furni", n, "trade", kind, s.key)
				end
			end
		end
	end
	BOBBA.events.emit("tradeDone", t.a.key, t.b.key, moved[t.a], moved[t.b])
	return true
end

function T.confirm(player)
	local t = T.byPlayer[player]
	if not t or t.stage ~= "confirm" then return false end
	local me = side(t, player)
	me.confirmed = true
	if not (t.a.confirmed and t.b.confirmed) then T.send(t) return true end
	local ok = T.finish(t)
	T.close(t, ok and "done" or "failed")
	return ok
end

function T.cancel(player, why)
	local t = T.byPlayer[player]
	if not t then return end
	local me = side(t, player)
	T.close(t, why or "cancelled", me.name)
end

-- (furni that are in a trade can't be placed: inventory.lua asks)
function T.isLocked(id) return T.locked[tonumber(id) or -1] ~= nil end

function T.start()
	local p = P()
	local function err(player, why) if why then p.send("trade.error", { message = tostring(why) }, player) end end
	local openedAt = {}
	p.receive("trade.open", function(player, data)
		local now = p.clock()
		if openedAt[player] and now - openedAt[player] < T.OPEN_EVERY then return end
		openedAt[player] = now
		local _, why = T.open(player, data.unit)
		err(player, why)
	end)
	p.receive("trade.offer", function(player, data) local _, why = T.offer(player, data.ids) err(player, why) end)
	p.receive("trade.take", function(player, data) local _, why = T.take(player, data.ids) err(player, why) end)
	p.receive("trade.accept", function(player, data) local _, why = T.accept(player, data.on ~= false) err(player, why) end)
	p.receive("trade.confirm", function(player) T.confirm(player) end)
	p.receive("trade.cancel", function(player) T.cancel(player) end)
	p.onLeave(function(player) openedAt[player] = nil T.cancel(player, "left") end)
	BOBBA.events.on("roomLeft", "bobba.trading", function(_, u) if u.player then T.cancel(u.player, "left") end end)
	-- (a player reset loses their furni: no trade goes on with them)
	BOBBA.events.on("playerReset", "bobba.trading", function(key)
		for player, t in pairs(T.byPlayer) do if t.a.key == tostring(key) or t.b.key == tostring(key) then T.cancel(player, "left") end end
	end)
end
