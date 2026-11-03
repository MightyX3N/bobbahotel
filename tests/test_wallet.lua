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
			{ name = "Teleports", offers = { { kind = "tele", name = "Door", price = { credits = 6 }, pair = true } } },
			{ name = "Habboween", season = "halloween", children = {
				{ name = "2015", offers = { { kind = "pumpkin", name = "Pumpkin", price = { credits = 3 } } } },
			} },
			{ name = "Trophies", layout = "trophies", offers = { { kind = "prizetrophy*1", name = "Classic trophy", price = { credits = 10 }, trophy = true } } },
		} }, { name = "Rares", staff = true, children = {
			{ name = "Thrones", offers = { { kind = "throne", name = "Throne", price = {} } } },
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
	eq(purse.clubLevel, 2, "the only club: everything in it")
	eq(purse.clubKind, "hc")
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

T["club modes: VIP instead of HC, or both (HC level 1, VIP level 2)"] = function()
	local mia = start()
	-- VIP only: the club tab is VIP, and it gives everything
	BOBBA.store.setSetting("club.mode", "vip")
	local _, _, club = pages(mia)
	eq(club.name, "VIP")
	P.fromPlayer(mia, "catalog.page", { id = club.id })
	local vip = last(mia, "catalog.page").offers[1]
	eq(vip.tier, "vip")
	eq(vip.price.diamonds, 400)
	BOBBA.wallet.add(mia.key, "diamonds", 2000)
	P.fromPlayer(mia, "catalog.buy", { page = club.id, offer = vip.id })
	local purse = last(mia, "user.purse")
	eq(purse.clubLevel, 2)
	eq(purse.clubKind, "vip")
	eq(purse.clubMode, "vip")
	-- both: VIP is 2, HC is 1; the tab has a page for each
	BOBBA.store.setSetting("club.mode", "both")
	eq(last(mia, "user.purse").clubMode, "both", "everyone online is told")
	P.fromPlayer(mia, "catalog.index")
	local tab = last(mia, "catalog.index").pages[2]
	eq(tab.name, "Habbo Club")
	eq(#tab.children, 2)
	eq(tab.children[2].name, "VIP")
	eq(BOBBA.wallet.clubLevel(mia.key), 2, "her VIP still runs")
	BOBBA.wallet.addClub(mia.key, -40, "vip")
	eq(BOBBA.wallet.clubLevel(mia.key), 0, "VIP over")
	BOBBA.wallet.addClub(mia.key, 31, "hc")
	eq(BOBBA.wallet.clubLevel(mia.key), 1, "HC only")
	P.fromPlayer(mia, "navigator.create", { name = "VIP room", model = "t" })
	assert(last(mia, "room.error").message:find("Club"), "model t is VIP's")
	P.fromPlayer(mia, "navigator.create", { name = "HC room", model = "g" })
	assert(last(mia, "navigator.created"), "model g is HC's")
	-- back to HC only: HC gets VIP's things too
	BOBBA.store.setSetting("club.mode", "hc")
	eq(BOBBA.wallet.clubLevel(mia.key), 2)
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

T["teleports are bought as a pair that go together"] = function()
	local mia = start()
	P.fromPlayer(mia, "catalog.index")
	local page = last(mia, "catalog.index").pages[1].children[3]
	P.fromPlayer(mia, "catalog.page", { id = page.id })
	local offer = last(mia, "catalog.page").offers[1]
	assert(offer.pair, "shown as two")
	P.fromPlayer(mia, "catalog.buy", { page = page.id, offer = offer.id, amount = 2 })
	P.fromPlayer(mia, "inventory.get")
	local list = last(mia, "inventory.items")
	eq(#list, 4)
	eq(BOBBA.items.partner(list[1].id), list[2].id)
	eq(BOBBA.items.partner(list[2].id), list[1].id)
	eq(BOBBA.items.partner(list[3].id), list[4].id)
	eq(BOBBA.wallet.get(mia.key).credits, 5000 - 12, "6 a pair")
end

T["a trophy is engraved with who bought it, when, and what they wrote"] = function()
	local mia = start()
	P.fromPlayer(mia, "catalog.index")
	local page = last(mia, "catalog.index").pages[1].children[4]
	P.fromPlayer(mia, "catalog.page", { id = page.id })
	local msg = last(mia, "catalog.page")
	eq(msg.layout, "trophies")
	local offer = msg.offers[1]
	assert(offer.trophy)
	P.fromPlayer(mia, "catalog.buy", { page = page.id, offer = offer.id, amount = 5, extra = "Best room\nof 2026\1" })
	local list = BOBBA.inventory.list(mia.key)
	eq(#list, 1, "one trophy, whatever the amount")
	local row = BOBBA.store.row("SELECT data FROM bobbahotel_items WHERE id = ?", { list[1].id })
	eq(row.data, "Mia\t" .. os.date("%d-%m-%Y", P.time()) .. "\tBest room\nof 2026")
end

T["the staff's rares tab: only staff see it, search it and take from it (free)"] = function()
	local mia = start()
	P.fromPlayer(mia, "catalog.index")
	local tabs = last(mia, "catalog.index").pages
	for _, t in ipairs(tabs) do assert(t.name ~= "Rares", "Mia isn't staff") end
	local rares = BOBBA.catalog.build(function() end)
	P.fromPlayer(mia, "catalog.search", { query = "throne" })
	eq(#last(mia, "catalog.search").offers, 0)
	-- the Rares tab's page is number 9 here (tabs and pages are numbered in order); asking for it anyway
	P.fromPlayer(mia, "catalog.buy", { page = 9, offer = 7, amount = 1 })
	assert(last(mia, "catalog.error"), "not hers to take")
	P.granted[mia] = { ["bobba.staff.rares"] = true }
	P.fromPlayer(mia, "catalog.index")
	tabs = last(mia, "catalog.index").pages
	local rareTab
	for _, t in ipairs(tabs) do if t.name == "Rares" then rareTab = t end end
	assert(rareTab, "staff see it")
	local page = rareTab.children[1]
	P.fromPlayer(mia, "catalog.page", { id = page.id })
	local offer = last(mia, "catalog.page").offers[1]
	P.fromPlayer(mia, "catalog.buy", { page = page.id, offer = offer.id, amount = 2 })
	eq(#BOBBA.inventory.list(mia.key), 2)
	eq(BOBBA.wallet.get(mia.key).credits, 5000, "free")
	local _ = rares
end

T["gifts: bought for someone (by name, online or not), wrapped with a greeting; opened in a room it's what was in it"] = function()
	local mia = start()
	local bo = { key = "765611980002", name = "Bo" }
	P.fromPlayer(bo, "room.ready")
	P.disconnect(bo)
	BOBBA.items.define("present_gen3", { width = 1, length = 1, height = 0.5, category = "present" })
	local pura = pages(mia)
	local chair = offerOf(mia, pura)
	P.fromPlayer(mia, "catalog.gift", { page = pura.id, offer = chair.id, receiver = "nobody", message = "hi" })
	assert(last(mia, "catalog.error").message:find("nobody"), "no such player")
	P.fromPlayer(mia, "catalog.gift", { page = pura.id, offer = chair.id, receiver = " bo ", message = "For your room\1!", box = 3, showFace = true })
	local bought = last(mia, "catalog.bought")
	assert(bought.gift)
	eq(bought.receiver, "Bo")
	eq(BOBBA.wallet.get(mia.key).credits, 4995, "Mia paid")
	eq(#BOBBA.inventory.list(mia.key), 0)
	local got = BOBBA.inventory.list(bo.key)
	eq(#got, 1)
	eq(got[1].kind, "present_gen3", "the box she picked")
	local row = BOBBA.store.row("SELECT data FROM bobbahotel_items WHERE id = ?", { got[1].id })
	eq(row.data:match("^([^\t]*)\t([^\t]*)"), "Mia", "from Mia")
	eq(select(2, row.data:match("^([^\t]*)\t([^\t]*)")), "For your room!")
	-- Bo opens it in his room: the chair is where the box was
	P.fromPlayer(bo, "room.ready")
	P.fromPlayer(bo, "navigator.create", { name = "Bo's room", model = "a" })
	P.fromPlayer(bo, "inventory.place", { id = got[1].id, x = 6, y = 3, dir = 2 })
	local r = BOBBA.live.byPlayer[bo].room
	assert(r.items[got[1].id], "the box is in the room")
	P.fromPlayer(mia, "room.enter", { id = r.id })
	P.fromPlayer(mia, "room.item.open", { id = got[1].id })
	assert(last(mia, "room.error"), "not Mia's room")
	P.fromPlayer(bo, "room.item.open", { id = got[1].id })
	local opened = last(bo, "gift.opened")
	eq(opened.kind, "chair")
	eq(opened.inRoom, true)
	eq(opened.from, "Mia")
	eq(r.items[got[1].id], nil, "the box is gone")
	local c = r.items[opened.id]
	eq(c.kind .. " " .. c.x .. "," .. c.y, "chair 6,3")
	eq(#BOBBA.inventory.list(bo.key), 0)
	-- club and teleports aren't gifts
	local _, _, clubPage = pages(mia)
	P.fromPlayer(mia, "catalog.page", { id = clubPage.id })
	local month = last(mia, "catalog.page").offers[1]
	P.fromPlayer(mia, "catalog.gift", { page = clubPage.id, offer = month.id, receiver = "Bo" })
	assert(last(mia, "catalog.error").message:find("gift"))
end

T["seasonal pages: only in their season (the admin can switch it off or move a season)"] = function()
	local mia = start()
	local CAT = BOBBA.catalog
	local function day(m, d) return os.time({ year = 2026, month = m, day = d, hour = 12 }) end
	P.now = day(7, 1)
	local function names()
		P.fromPlayer(mia, "catalog.index")
		local out = {}
		for _, p in ipairs(last(mia, "catalog.index").pages[1].children) do out[#out + 1] = p.name end
		return table.concat(out, ",")
	end
	assert(not names():find("Habboween"), "July: no Habboween")
	P.fromPlayer(mia, "catalog.search", { query = "pumpkin" })
	eq(#last(mia, "catalog.search").offers, 0)
	P.now = day(10, 20)
	assert(names():find("Habboween"), "October: Habboween")
	-- buying it is only in season too
	P.fromPlayer(mia, "catalog.index")
	local hw
	for _, p in ipairs(last(mia, "catalog.index").pages[1].children) do if p.name == "Habboween" then hw = p.children[1] end end
	P.fromPlayer(mia, "catalog.page", { id = hw.id })
	local pumpkin = last(mia, "catalog.page").offers[1]
	P.now = day(12, 20)
	P.fromPlayer(mia, "catalog.buy", { page = hw.id, offer = pumpkin.id, amount = 1 })
	assert(last(mia, "catalog.error").message:find("season"))
	-- switched off: always
	BOBBA.store.setSetting("catalog.seasons", "0")
	assert(names():find("Habboween"))
	BOBBA.store.setSetting("catalog.seasons", "1")
	-- moved: Habboween in December this hotel
	BOBBA.store.setSetting("season.halloween", "12-15..12-31")
	assert(names():find("Habboween"))
	-- seasons over the new year, and Easter (5 April 2026)
	assert(CAT.inSeason("christmas", day(1, 3)) and CAT.inSeason("christmas", day(12, 2)) and not CAT.inSeason("christmas", day(1, 10)))
	assert(CAT.inSeason("easter", day(3, 20)) and CAT.inSeason("easter", day(4, 18)) and not CAT.inSeason("easter", day(3, 10)))
	local m, d = CAT.easter(2026)
	eq(m * 100 + d, 405)
	local m2, d2 = CAT.easter(2027)
	eq(m2 * 100 + d2, 328)
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
