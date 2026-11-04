-- The catalogue (server): pages of furni to buy, like Habbo's (CatalogPageMessageEvent), and Habbo
-- Club. What furni there are comes from an addon; the club page is the hotel's own.
--
--   BOBBA.catalog.provider = function(cb) cb(pages) end   pages = { { name, children = { ... },
--     offers = { { kind, name, price = { credits = n } }, ... } }, ... }   (a page has children or offers)
--   (a page's shop: "furni" (the default), "clothes" or "club": which of the phone's shops shows it;
--   the pages under it are in the same one)
--
-- Every page and offer gets a number when the catalogue is built. Buying puts the furni into the
-- buyer's inventory (inventory.lua) after paying (wallet.lua); club adds days.
--
-- Messages from players: catalog.index {}, catalog.page { id }, catalog.buy { page, offer, amount },
--                        catalog.search { query }
-- Messages to players:   catalog.index { pages = { { id, name, children = {...} }, ... } }
--                        catalog.page { id, name, layout ("default_3x3" / "vip_buy"), offers = { { id, kind, name, price, club, data, count } } }
--                        catalog.bought { page, offer, amount }   catalog.error { message }
--                        catalog.search { query, pages = { id, ... }, offers = { { id, page, kind, name, price }, ... } }

BOBBA.catalog = BOBBA.catalog or {}
local CAT = BOBBA.catalog

-- club offers: days for diamonds (the hotel's settings club.price.31 / .93 for HC, vip.price.31 / .93
-- for VIP); which clubs are on sale is the wallet's club.mode
CAT.CLUB_OFFERS = {
	hc = { { days = 31, price = 250 }, { days = 93, price = 700 } },
	vip = { { days = 31, price = 400 }, { days = 93, price = 1100 } },
}
CAT.CLUB_NAMES = { hc = "Habbo Club", vip = "VIP" }
CAT.MAX_AMOUNT = 100

-- pages only staff see (a page with staff = true, and everything under it): rares and limited
-- editions, given for free
BOBBA.perms.define("bobba.staff.rares", { default = "admin", description = "See the catalogue's staff pages (rares) and take from them" })
CAT.TROPHY_MAX = 300

-- Seasons: pages marked with one (Christmas, Habboween, ...) are only in the catalogue in it, like
-- Habbo's seasonal pages. The hotel's settings: catalog.seasons (1 on, the default; 0 off: always
-- sold), season.<name> = "MM-DD..MM-DD" to change when one is (it may run over the new year).
-- Staff see and buy them all year.
CAT.SEASONS = {
	valentine = "02-01..02-29", stpatricks = "03-10..03-20", summer = "06-01..08-31", halloween = "10-01..11-07",
	christmas = "12-01..01-06", newyear = "12-26..01-15", winter = "12-01..02-28", lunarnewyear = "01-15..02-25",
	easter = "easter",
}

-- Easter Sunday of a year (the Gregorian computus)
function CAT.easter(year)
	local a, b, c = year % 19, math.floor(year / 100), year % 100
	local d, e = math.floor(b / 4), b % 4
	local f = math.floor((b + 8) / 25)
	local g = math.floor((b - f + 1) / 3)
	local h = (19 * a + b - d - g + 15) % 30
	local i, k = math.floor(c / 4), c % 4
	local l = (32 + 2 * e + 2 * i - h - k) % 7
	local m = math.floor((a + 11 * h + 22 * l) / 451)
	local month = math.floor((h + l - 7 * m + 114) / 31)
	local day = (h + l - 7 * m + 114) % 31 + 1
	return month, day
end

-- is it a season now (t: a time, default now)?
function CAT.inSeason(season, t)
	if not season then return true end
	if BOBBA.store.setting("catalog.seasons", "1") == "0" then return true end
	local span = BOBBA.store.setting("season." .. season, CAT.SEASONS[season] or "")
	t = t or BOBBA.platform.time()
	local now = os.date("*t", t)
	local today = now.month * 100 + now.day
	if span == "easter" then
		-- three weeks before Easter Sunday to two weeks after
		local m, d = CAT.easter(now.year)
		local sunday = os.time({ year = now.year, month = m, day = d, hour = 12 })
		return t >= sunday - 21 * 86400 and t <= sunday + 15 * 86400
	end
	local m1, d1, m2, d2 = span:match("^(%d+)%-(%d+)%.%.(%d+)%-(%d+)$")
	if not m1 then return true end
	local from, to = tonumber(m1) * 100 + tonumber(d1), tonumber(m2) * 100 + tonumber(d2)
	if from <= to then return today >= from and today <= to end
	return today >= from or today <= to
end

local tree, pagesById, building

local function build(cb)
	if tree then cb(tree) return end
	if building then building[#building + 1] = cb return end
	building = { cb }
	local function done(pages)
		pagesById = {}
		local nextPage, nextOffer = 1, 1
		local function number(list, staff, season)
			for _, p in ipairs(list) do
				p.staff = p.staff or staff
				p.season = p.season or season
				p.id = nextPage
				nextPage = nextPage + 1
				pagesById[p.id] = p
				for _, o in ipairs(p.offers or {}) do
					o.id = nextOffer
					nextOffer = nextOffer + 1
				end
				number(p.children or {}, p.staff, p.season)
			end
		end
		-- the club (a tab with a buy page for each club on sale, Habbo's "vip_buy"), after the addon's
		local kinds = BOBBA.wallet.clubKinds()
		local clubPages = {}
		for _, kind in ipairs(kinds) do
			local page = { name = CAT.CLUB_NAMES[kind], layout = "vip_buy", clubKind = kind, iconName = "club-" .. kind, offers = {} }
			for _, c in ipairs(CAT.CLUB_OFFERS[kind]) do
				local price = tonumber(BOBBA.store.setting(kind .. ".price." .. c.days, tostring(c.price))) or c.price
				page.offers[#page.offers + 1] = { club = c.days, tier = kind, name = c.days .. " days", price = { diamonds = price } }
			end
			clubPages[#clubPages + 1] = page
		end
		-- (the addon's club pages, its club furni, go under it too)
		for i = #pages, 1, -1 do
			if pages[i].club then table.insert(clubPages, table.remove(pages, i)) end
		end
		pages[#pages + 1] = { name = CAT.CLUB_NAMES[kinds[1]] or "Club", children = clubPages, shop = "club" }
		number(pages)
		tree = pages
		local list = building
		building = nil
		for _, w in ipairs(list) do w(tree) end
	end
	if CAT.provider then
		CAT.provider(function(pages) done(pages or {}) end)
	else
		done({})
	end
end
CAT.build = build

-- forgets the catalogue (an addon's furni changed)
function CAT.reset() tree, pagesById = nil, nil end

local function index(list, staff)
	local out = {}
	for _, p in ipairs(list) do
		if staff or (not p.staff and CAT.inSeason(p.season)) then
			-- (which of the phone's shops it's in: furni, clothes or club; a page says, else the one it's in)
			out[#out + 1] = { id = p.id, name = p.name, icon = p.icon, iconKind = p.iconKind, iconName = p.iconName, shop = p.shop,
				children = p.children and index(p.children, staff) or nil }
		end
	end
	return out
end

local function isStaff(player) return BOBBA.perms.has(player, "bobba.staff.rares") end

local function pageMessage(p)
	local offers = {}
	for _, o in ipairs(p.offers or {}) do
		offers[#offers + 1] = { id = o.id, kind = o.kind, name = o.name, price = o.price, club = o.club, tier = o.tier, pair = o.pair, trophy = o.trophy,
			data = o.data, count = o.count, clubLevel = o.clubLevel }
	end
	return { id = p.id, name = p.name, layout = p.layout or "default_3x3", clubKind = p.clubKind, offers = offers }
end

-- the furni whose name has the words in it (Nitro's catalogue search: names and class names),
-- and the pages they're on
CAT.SEARCH_MAX = 250
function CAT.search(query, staff)
	query = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local offers, pages, seen = {}, {}, {}
	if query == "" then return offers, pages end
	for id = 1, #pagesById do
		local p = pagesById[id]
		for _, o in ipairs((staff or (not p.staff and CAT.inSeason(p.season))) and p.offers or {}) do
			if o.kind and #offers < CAT.SEARCH_MAX and ((o.name or ""):lower():find(query, 1, true) or o.kind:lower():find(query, 1, true)) then
				offers[#offers + 1] = { id = o.id, page = p.id, kind = o.kind, name = o.name, price = o.price, pair = o.pair, trophy = o.trophy, data = o.data, count = o.count, clubLevel = o.clubLevel }
				if not seen[p.id] then seen[p.id] = true pages[#pages + 1] = p.id end
			end
		end
	end
	return offers, pages
end

-- a page and one of its offers, if the player may have it: page, offer or nil, why
function CAT.find(player, pageId, offerId)
	local page = pagesById and pagesById[tonumber(pageId) or -1]
	if not page or (page.staff and not isStaff(player)) then return nil, "that page isn't in the catalogue" end
	if not CAT.inSeason(page.season) and not isStaff(player) then return nil, "that's only sold in its season" end
	for _, o in ipairs(page.offers or {}) do if o.id == tonumber(offerId) then return page, o end end
	return nil, "that isn't on this page"
end

-- the engraving on a trophy someone buys
function CAT.engraving(player, text)
	local P = BOBBA.platform
	text = tostring(text or ""):gsub("[%z\1-\9\11-\31]", ""):sub(1, CAT.TROPHY_MAX)
	return P.playerName(player) .. "\t" .. os.date("%d-%m-%Y", P.time()) .. "\t" .. text
end

-- buys: n of an offer for a player. true or false, why
function CAT.buy(player, pageId, offerId, amount, extra)
	local P = BOBBA.platform
	local key = P.playerKey(player)
	local page, offer = CAT.find(player, pageId, offerId)
	if not page then return false, offer end
	amount = math.floor(tonumber(amount) or 1)
	if offer.club or offer.trophy then amount = 1 end
	-- (club furni: for members, as Habbo's)
	if offer.clubLevel and BOBBA.wallet.clubLevel(key) < offer.clubLevel then return false, "only club members can buy that" end
	if amount < 1 or amount > CAT.MAX_AMOUNT then return false, "you can buy 1 to " .. CAT.MAX_AMOUNT .. " at a time" end
	local price = {}
	for c, n in pairs(offer.price or {}) do price[c] = n * amount end
	-- (paid and given together: if giving fails, nothing's paid)
	local paid = false
	BOBBA.store.transaction(function()
		if not BOBBA.wallet.pay(key, price, "catalog", offer.kind or (offer.club and (offer.tier or "hc"))) then return end
		paid = true
		if offer.club then
			BOBBA.wallet.addClub(key, offer.club, offer.tier, "catalog")
		else
			if offer.pair then
				-- a pair (teleports): they come unlinked; their owner links them (items.lua)
				for _ = 1, amount do BOBBA.inventory.give(key, offer.kind, 2, nil, "catalog") end
			elseif offer.trophy then
				-- a trophy is engraved with who bought it, when, and their words (Arcturus: name TAB date TAB text)
				BOBBA.inventory.give(key, offer.kind, 1, CAT.engraving(player, extra), "catalog")
			else
				-- (with its data: a wallpaper's id; count: how many come in one, a pad of stickies)
				BOBBA.inventory.give(key, offer.kind, amount * (offer.count or 1), offer.data, "catalog")
			end
		end
	end)
	if not paid then return false, "you don't have enough to buy that" end
	BOBBA.events.emit("catalogBought", key, offer, amount)
	return true
end

function CAT.start()
	local P = BOBBA.platform
	-- the club's pages change with its settings
	BOBBA.events.on("settingChanged", "bobba.catalog", function(k)
		if k == "club.mode" or k:find("%.price") or k:find("^catalog%.") or k:find("club") then CAT.reset() end
	end)
	P.receive("catalog.index", function(player)
		build(function(pages) P.send("catalog.index", { pages = index(pages, isStaff(player)) }, player) end)
	end)
	P.receive("catalog.page", function(player, data)
		build(function()
			local p = pagesById[tonumber(data.id) or -1]
			if p and p.offers and (isStaff(player) or (not p.staff and CAT.inSeason(p.season))) then P.send("catalog.page", pageMessage(p), player) end
		end)
	end)
	P.receive("catalog.search", function(player, data)
		build(function()
			local offers, pages = CAT.search(data.query, isStaff(player))
			P.send("catalog.search", { query = tostring(data.query or ""), offers = offers, pages = pages }, player)
		end)
	end)
	P.receive("catalog.buy", function(player, data)
		build(function()
			local ok, why = CAT.buy(player, data.page, data.offer, data.amount, data.extra)
			if ok then P.send("catalog.bought", { page = data.page, offer = data.offer, amount = data.amount }, player)
			else P.send("catalog.error", { message = tostring(why) }, player) end
		end)
	end)
end
