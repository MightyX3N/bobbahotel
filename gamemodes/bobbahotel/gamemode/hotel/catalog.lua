-- The catalogue (server): pages of furni to buy, like Habbo's (CatalogPageMessageEvent), and Habbo
-- Club. What furni there are comes from an addon; the club page is the hotel's own.
--
--   BOBBA.catalog.provider = function(cb) cb(pages) end   pages = { { name, children = { ... },
--     offers = { { kind, name, price = { credits = n } }, ... } }, ... }   (a page has children or offers)
--
-- Every page and offer gets a number when the catalogue is built. Buying puts the furni into the
-- buyer's inventory (inventory.lua) after paying (wallet.lua); club adds days.
--
-- Messages from players: catalog.index {}, catalog.page { id }, catalog.buy { page, offer, amount },
--                        catalog.search { query }
-- Messages to players:   catalog.index { pages = { { id, name, children = {...} }, ... } }
--                        catalog.page { id, name, layout ("default_3x3" / "vip_buy"), offers = { { id, kind, name, price, club } } }
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

local tree, pagesById, building

local function build(cb)
	if tree then cb(tree) return end
	if building then building[#building + 1] = cb return end
	building = { cb }
	local function done(pages)
		pagesById = {}
		local nextPage, nextOffer = 1, 1
		local function number(list, staff)
			for _, p in ipairs(list) do
				p.staff = p.staff or staff
				p.id = nextPage
				nextPage = nextPage + 1
				pagesById[p.id] = p
				for _, o in ipairs(p.offers or {}) do
					o.id = nextOffer
					nextOffer = nextOffer + 1
				end
				number(p.children or {}, p.staff)
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
		pages[#pages + 1] = { name = CAT.CLUB_NAMES[kinds[1]], children = clubPages }
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
		if staff or not p.staff then
			out[#out + 1] = { id = p.id, name = p.name, icon = p.icon, iconKind = p.iconKind, iconName = p.iconName,
				children = p.children and index(p.children, staff) or nil }
		end
	end
	return out
end

local function isStaff(player) return BOBBA.perms.has(player, "bobba.staff.rares") end

local function pageMessage(p)
	local offers = {}
	for _, o in ipairs(p.offers or {}) do
		offers[#offers + 1] = { id = o.id, kind = o.kind, name = o.name, price = o.price, club = o.club, tier = o.tier, pair = o.pair, trophy = o.trophy }
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
		for _, o in ipairs((staff or not p.staff) and p.offers or {}) do
			if o.kind and #offers < CAT.SEARCH_MAX and ((o.name or ""):lower():find(query, 1, true) or o.kind:lower():find(query, 1, true)) then
				offers[#offers + 1] = { id = o.id, page = p.id, kind = o.kind, name = o.name, price = o.price, pair = o.pair, trophy = o.trophy }
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
	local page = pagesById and pagesById[tonumber(pageId) or -1]
	if not page or (page.staff and not isStaff(player)) then return false, "that page isn't in the catalogue" end
	local offer
	for _, o in ipairs(page.offers or {}) do if o.id == tonumber(offerId) then offer = o end end
	if not offer then return false, "that isn't on this page" end
	amount = math.floor(tonumber(amount) or 1)
	if offer.club or offer.trophy then amount = 1 end
	if amount < 1 or amount > CAT.MAX_AMOUNT then return false, "you can buy 1 to " .. CAT.MAX_AMOUNT .. " at a time" end
	local price = {}
	for c, n in pairs(offer.price or {}) do price[c] = n * amount end
	if not BOBBA.wallet.pay(key, price) then return false, "you don't have enough to buy that" end
	if offer.club then
		BOBBA.wallet.addClub(key, offer.club, offer.tier)
	else
		if offer.pair then
			-- a pair that are each other's partner (teleports)
			for _ = 1, amount do
				local two = BOBBA.inventory.give(key, offer.kind, 2)
				BOBBA.items.link(two[1].id, two[2].id)
			end
		elseif offer.trophy then
			-- a trophy is engraved with who bought it, when, and their words (Arcturus: name TAB date TAB text)
			BOBBA.inventory.give(key, offer.kind, 1, CAT.engraving(player, extra))
		else
			BOBBA.inventory.give(key, offer.kind, amount)
		end
	end
	BOBBA.events.emit("catalogBought", key, offer, amount)
	return true
end

function CAT.start()
	local P = BOBBA.platform
	-- the club's pages change with its settings
	BOBBA.events.on("settingChanged", "bobba.catalog", function(k)
		if k == "club.mode" or k:find("%.price") then CAT.reset() end
	end)
	P.receive("catalog.index", function(player)
		build(function(pages) P.send("catalog.index", { pages = index(pages, isStaff(player)) }, player) end)
	end)
	P.receive("catalog.page", function(player, data)
		build(function()
			local p = pagesById[tonumber(data.id) or -1]
			if p and p.offers and (not p.staff or isStaff(player)) then P.send("catalog.page", pageMessage(p), player) end
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
