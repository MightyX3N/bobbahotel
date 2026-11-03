-- Money, Habbo Club, the catalogue and the inventory
local T = {}
local P

local function start()
	P = BOBBA.platform
	local I = BOBBA.items
	I.define("chair", { width = 1, length = 1, height = 1, sit = true, directions = { 0, 2, 4, 6 } })
	I.define("lamp", { width = 1, length = 1, height = 2, states = 2 })
	-- a catalogue like the Habbo addon's: one tab, pages under it
	BOBBA.catalog.reset()
	BOBBA.catalog.provider = function(cb)
		cb({ { name = "Furni", children = {
			{ name = "Pura", offers = { { kind = "chair", name = "Pura Chair", price = { credits = 5 } } } },
			{ name = "Lights", offers = { { kind = "lamp", name = "Lava Lamp", price = { credits = 20, duckets = 10 } } } },
		} } })
	end
	BOBBA.live.start()
	local mia = { key = "765611980001", name = "Mia" }
	P.fromPlayer(mia, "room.ready")
	return mia
end

local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end

local function pages(mia)
	P.fromPlayer(mia, "catalog.index")
	local tabs = last(mia, "catalog.index").pages
	return tabs[1].children[1], tabs[1].children[2], tabs[2].children[1]
end

local function offerOf(mia, page)
	P.fromPlayer(mia, "catalog.page", { id = page.id })
	return last(mia, "catalog.page").offers[1]
end

T["a new player starts with the start amounts; it's in the purse"] = function()
	local mia = start()
	local purse = last(mia, "user.purse")
	assert(purse, "the purse came when Mia went into a room")
	eq(purse.credits, 5000)
	eq(purse.duckets, 0)
	eq(purse.diamonds, 0)
	eq(purse.clubLevel, 0)
end

T["paid for being online, as often as the setting says"] = function()
	local mia = start()
	BOBBA.store.setSetting("wallet.pay.every", "60")
	P.now = P.now + 30
	P.runTimers()
	eq(last(mia, "user.purse").credits, 5000, "not yet")
	P.now = P.now + 31
	P.runTimers()
	local purse = last(mia, "user.purse")
	eq(purse.credits, 5025)
	eq(purse.duckets, 50)
	eq(purse.diamonds, 2)
	P.disconnect(mia)
	P.now = P.now + 61
	P.runTimers()
	eq(BOBBA.wallet.get(mia.key).credits, 5025, "not when gone")
end

T["the catalogue: tabs, pages, offers; buying pays and puts furni in the inventory"] = function()
	local mia = start()
	local pura, lights, club = pages(mia)
	eq(pura.name, "Pura")
	eq(club.name, "Habbo Club")
	local chair = offerOf(mia, pura)
	eq(chair.kind, "chair")
	eq(chair.price.credits, 5)
	P.fromPlayer(mia, "catalog.buy", { page = pura.id, offer = chair.id, amount = 3 })
	assert(last(mia, "catalog.bought"), "bought")
	eq(last(mia, "user.purse").credits, 4985)
	eq(#last(mia, "inventory.added"), 3, "three chairs")
	P.fromPlayer(mia, "inventory.get")
	eq(#last(mia, "inventory.items"), 3)
	-- the lamp costs duckets too, and Mia has none
	local lamp = offerOf(mia, lights)
	P.fromPlayer(mia, "catalog.buy", { page = lights.id, offer = lamp.id, amount = 1 })
	assert(last(mia, "catalog.error").message:find("enough"), "not enough duckets")
	eq(BOBBA.wallet.get(mia.key).credits, 4985, "nothing taken")
	-- an offer from another page, or too many
	P.fromPlayer(mia, "catalog.buy", { page = lights.id, offer = chair.id, amount = 1 })
	assert(last(mia, "catalog.error").message:find("page"))
	P.fromPlayer(mia, "catalog.buy", { page = pura.id, offer = chair.id, amount = 101 })
	assert(last(mia, "catalog.error").message:find("100"))
end

T["searching the catalogue: by name, with the page"] = function()
	local mia = start()
	local pura = pages(mia)
	P.fromPlayer(mia, "catalog.search", { query = "pura ch" })
	local r = last(mia, "catalog.search")
	eq(#r.offers, 1)
	eq(r.offers[1].page, pura.id)
	eq(r.pages[1], pura.id)
	P.fromPlayer(mia, "catalog.search", { query = "lamp" })
	eq(last(mia, "catalog.search").offers[1].kind, "lamp", "by class name too")
end

T["Habbo Club: bought with diamonds, lasts its days, opens club rooms and clothes"] = function()
	local mia = start()
	local _, _, club = pages(mia)
	P.fromPlayer(mia, "catalog.page", { id = club.id })
	local page = last(mia, "catalog.page")
	eq(page.layout, "vip_buy")
	local month = page.offers[1]
	eq(month.club, 31)
	eq(month.price.diamonds, 250)
	P.fromPlayer(mia, "catalog.buy", { page = club.id, offer = month.id })
	assert(last(mia, "catalog.error"), "no diamonds")
	BOBBA.wallet.add(mia.key, "diamonds", 300)
	P.fromPlayer(mia, "navigator.create", { name = "Club room", model = "g" })
	assert(last(mia, "room.error").message:find("Club"), "not yet")
	P.fromPlayer(mia, "catalog.buy", { page = club.id, offer = month.id })
	local purse = last(mia, "user.purse")
	eq(purse.diamonds, 50)
	eq(purse.clubLevel, 1)
	eq(purse.clubDays, 31)
	P.fromPlayer(mia, "navigator.create", { name = "Club room", model = "g" })
	assert(last(mia, "navigator.created"), "a club model now")
	-- the looks check is told who it is (the Habbo addon lets members wear club clothes)
	local asked
	BOBBA.looks.validator = function(figure, gender, key) asked = key return figure end
	BOBBA.looks.set(mia.key, "hd-180-1", "M")
	eq(asked, mia.key)
	BOBBA.looks.validator = nil
	-- more days add to the end; it runs out
	BOBBA.wallet.addClub(mia.key, 31)
	eq(BOBBA.wallet.purse(mia.key).clubDays, 62)
	P.now = P.now + 63 * 86400
	eq(BOBBA.wallet.clubLevel(mia.key), 0)
end

T["the inventory: placing takes it out, picking up brings it back"] = function()
	local mia = start()
	local pura = pages(mia)
	local chair = offerOf(mia, pura)
	P.fromPlayer(mia, "catalog.buy", { page = pura.id, offer = chair.id, amount = 1 })
	local id = last(mia, "inventory.added")[1].id
	-- Mia is in the Welcome Lounge, not her room: she needs her own
	P.fromPlayer(mia, "navigator.create", { name = "Mia's room", model = "a" })
	P.fromPlayer(mia, "inventory.place", { id = id, x = 6, y = 3, dir = 2 })
	eq(last(mia, "inventory.removed")[1], id)
	local u = BOBBA.live.byPlayer[mia]
	assert(u.room.items[id], "in the room, the same furni")
	P.fromPlayer(mia, "inventory.place", { id = id, x = 7, y = 3, dir = 2 })
	assert(last(mia, "room.error").message:find("inventory"), "it isn't in the inventory any more")
	P.fromPlayer(mia, "room.item.pickup", { id = id })
	eq(last(mia, "inventory.added")[1].id, id, "back")
	P.fromPlayer(mia, "inventory.get")
	eq(#last(mia, "inventory.items"), 1)
	eq(u.room.items[id], nil)
end

T["staff: giving and taking"] = function()
	local mia = start()
	assert(BOBBA.wallet.add(mia.key, "duckets", 100))
	eq(last(mia, "user.purse").duckets, 100)
	assert(not BOBBA.wallet.add(mia.key, "duckets", -101), "can't go below 0")
	assert(not BOBBA.wallet.add(mia.key, "gold", 1), "not a currency")
	assert(BOBBA.wallet.add(mia.key, "duckets", -100))
	eq(BOBBA.wallet.get(mia.key).duckets, 0)
end

return T
