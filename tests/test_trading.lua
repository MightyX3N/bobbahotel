-- Trading and the economy's log (hotel/trading.lua, hotel/economy.lua)
local T = {}
local P

local function start(tradeMode)
	P = BOBBA.platform
	BOBBA.live.start()
	BOBBA.items.define("chair", { width = 1, length = 1, height = 1, sit = true, directions = { 0, 2, 4, 6 } })
	BOBBA.items.define("lamp", { width = 1, length = 1, height = 2 })
	local mia, bo = { key = "765611980001", name = "Mia" }, { key = "765611980002", name = "Bo" }
	local id = BOBBA.live.create(mia.key, mia.name, "model_a", "Mia's room")
	BOBBA.live.enter(mia, id)
	BOBBA.live.enter(bo, id)
	local r = BOBBA.live.rooms[id]
	r.info.trade = tradeMode or 2
	return mia, bo, r
end
local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end
local function unitOf(p) return BOBBA.live.byPlayer[p] end
local function owner(id) return BOBBA.store.row("SELECT owner FROM bobbahotel_items WHERE id = ?", { id }).owner end

T["a whole trade: offer, accept, confirm; the furni change owners and it's logged"] = function()
	local mia, bo = start(2)
	local chairs = BOBBA.inventory.give(mia.key, "chair", 2, nil, "test")
	local lamp = BOBBA.inventory.give(bo.key, "lamp", 1, nil, "test")[1]
	P.fromPlayer(mia, "trade.open", { unit = unitOf(bo).id })
	local st = last(bo, "trade.state")
	eq(st.other.name, "Mia")
	eq(st.stage, "offer")
	P.fromPlayer(mia, "trade.offer", { ids = { chairs[1].id, chairs[2].id } })
	eq(#last(bo, "trade.state").theirs, 2)
	P.fromPlayer(bo, "trade.offer", { ids = { lamp.id } })
	P.fromPlayer(mia, "trade.accept", { on = true })
	eq(last(bo, "trade.state").theyAccepted, true)
	-- a change takes back the accept
	P.fromPlayer(bo, "trade.take", { ids = { lamp.id } })
	eq(last(bo, "trade.state").theyAccepted, false)
	P.fromPlayer(bo, "trade.offer", { ids = { lamp.id } })
	P.fromPlayer(mia, "trade.accept", { on = true })
	P.fromPlayer(bo, "trade.accept", { on = true })
	eq(last(mia, "trade.state").stage, "confirm")
	-- (in a trade: can't be placed)
	P.fromPlayer(mia, "inventory.place", { id = chairs[1].id, x = 3, y = 3, dir = 2 })
	eq(last(mia, "room.error").message, "that's in a trade")
	P.fromPlayer(mia, "trade.confirm")
	eq(owner(chairs[1].id), mia.key, "not until both confirm")
	P.fromPlayer(bo, "trade.confirm")
	eq(last(mia, "trade.closed").why, "done")
	eq(owner(chairs[1].id), bo.key)
	eq(owner(chairs[2].id), bo.key)
	eq(owner(lamp.id), mia.key)
	eq(#last(bo, "inventory.added"), 2)
	eq(BOBBA.trading.byPlayer[mia], nil)
	eq(BOBBA.trading.isLocked(chairs[1].id), false)
	local rows = BOBBA.economy.list(mia.key)
	local seen = {}
	for _, r in ipairs(rows) do if r.why == "trade" then seen[r.key .. r.item .. r.amount] = true end end
	assert(seen[mia.key .. "chair-2"] and seen[bo.key .. "chair2"] and seen[mia.key .. "lamp1"] and seen[bo.key .. "lamp-1"], "all four lines")
end

T["only their own furni from the inventory; nine kinds at most"] = function()
	local mia, bo = start(2)
	local placed = BOBBA.inventory.give(mia.key, "chair", 1)[1]
	BOBBA.store.query("UPDATE bobbahotel_items SET room = 5 WHERE id = ?", { placed.id })
	local bos = BOBBA.inventory.give(bo.key, "lamp", 1)[1]
	P.fromPlayer(mia, "trade.open", { unit = unitOf(bo).id })
	P.fromPlayer(mia, "trade.offer", { ids = { placed.id, bos.id } })
	eq(#last(mia, "trade.state").mine, 0)
	for i = 1, 10 do BOBBA.items.define("k" .. i, { width = 1, length = 1, height = 1 }) end
	local ids = {}
	for i = 1, 10 do ids[i] = BOBBA.inventory.give(mia.key, "k" .. i, 1)[1].id end
	P.fromPlayer(mia, "trade.offer", { ids = ids })
	eq(#last(mia, "trade.state").mine, 9)
	local e = last(mia, "trade.error")
	assert(e and e.message:find("9 kinds"), "told why")
end

T["the room's setting: none, rights, everyone; and the hotel's"] = function()
	local mia, bo, r = start(0)
	P.fromPlayer(bo, "trade.open", { unit = unitOf(mia).id })
	eq(last(bo, "trade.error").message, "trading isn't allowed in this room")
	r.info.trade = 1
	P.now = P.now + 5
	P.fromPlayer(bo, "trade.open", { unit = unitOf(mia).id })
	eq(last(mia, "trade.state").other.name, "Bo", "Mia owns the room: either having rights is enough")
	P.fromPlayer(mia, "trade.cancel")
	eq(last(bo, "trade.closed").why, "cancelled")
	r.info.trade = 2
	BOBBA.store.setSetting("trading.enabled", "0")
	P.now = P.now + 5
	P.fromPlayer(bo, "trade.open", { unit = unitOf(mia).id })
	eq(last(bo, "trade.error").message, "trading is off in this hotel")
	BOBBA.store.setSetting("trading.enabled", "1")
end

T["leaving ends it; furni that left the inventory meanwhile stop it"] = function()
	local mia, bo, r = start(2)
	local chair = BOBBA.inventory.give(mia.key, "chair", 1)[1]
	P.fromPlayer(mia, "trade.open", { unit = unitOf(bo).id })
	P.fromPlayer(mia, "trade.offer", { ids = { chair.id } })
	BOBBA.live.leave(bo)
	eq(last(mia, "trade.closed").why, "left")
	eq(BOBBA.trading.isLocked(chair.id), false)
	BOBBA.live.enter(bo, r.id)
	P.now = P.now + 5
	P.fromPlayer(mia, "trade.open", { unit = unitOf(bo).id })
	P.fromPlayer(mia, "trade.offer", { ids = { chair.id } })
	P.fromPlayer(mia, "trade.accept", { on = true })
	P.fromPlayer(bo, "trade.accept", { on = true })
	P.fromPlayer(mia, "trade.confirm")
	-- (gone some other way: a reset, staff)
	BOBBA.store.query("UPDATE bobbahotel_items SET owner = 'x' WHERE id = ?", { chair.id })
	P.fromPlayer(bo, "trade.confirm")
	eq(last(mia, "trade.closed").why, "failed")
	eq(owner(chair.id), "x")
	P.disconnect(bo)
end

T["the economy's log: buying, staff, the tutorial; managers read it"] = function()
	local mia = start(2)
	BOBBA.wallet.add(mia.key, "credits", 100, "staff", "console")
	BOBBA.wallet.pay(mia.key, { credits = 30, duckets = 0 }, "catalog", "chair")
	BOBBA.wallet.addClub(mia.key, 31, "hc", "catalog")
	local rows = BOBBA.economy.list(mia.key)
	eq(rows[1].what, "hc")
	eq(rows[1].amount, 31)
	eq(rows[2].amount, -30)
	eq(rows[2].item, "chair")
	eq(rows[3].amount, 100)
	eq(rows[3].why, "staff")
	assert(not BOBBA.wallet.pay(mia.key, { credits = -50 }), "no paying a minus")
	P.fromPlayer(mia, "manage.log", { who = "Mia" })
	eq(last(mia, "manage.log"), nil, "not a manager")
	P.granted[mia] = { ["bobba.admin.hotel"] = true }
	P.fromPlayer(mia, "manage.log", { who = "Mia" })
	local got = last(mia, "manage.log")
	eq(got.rows[1].what, "hc")
	eq(got.rows[1].name, "Mia")
	P.fromPlayer(mia, "manage.log", { who = "nobody at all" })
	eq(last(mia, "manage.log").missing, true)
	P.granted[mia] = nil
end

return T
