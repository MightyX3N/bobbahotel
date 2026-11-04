-- The shops (the phone's catalogue): Furni (furni, walls and floors), Club (joining the club and the
-- club's pages) and the Clothes app's shop (client/app_clothes.lua). Which shop a catalogue page is in
-- is the page's "shop" (the server's catalog.lua; furni when it doesn't say). The same messages as the
-- catalogue window (client/shop.lua).

local DV = BOBBA.device
local U = BOBBA.ui
local P = BOBBA.platform
local R = BOBBA.room
local HUD = BOBBA.hud
local SHOP = BOBBA.shop
local CAT = SHOP.cat
local C, G = DV.C, DV.G
local alpha = DV.alpha
local hex = DV.hex
local T = function(k, f, v) return U.text(k, f, v) end

-- --- the pages in a shop ----------------------------------------------------------------------------
local function askIndex()
	if not CAT.pages and (CAT.indexAskedAt or 0) < SysTime() - 5 then
		CAT.indexAskedAt = SysTime()
		P.send("catalog.index", {})
	end
end

-- the top pages in a shop
function DV.shopTabs(shop)
	askIndex()
	local out = {}
	for _, p in ipairs(CAT.pages or {}) do
		if (p.shop or "furni") == shop then out[#out + 1] = p end
	end
	return out
end

-- the pages with offers under a page (itself when it has none under it), with their names
local function leaves(p, out)
	out = out or {}
	if not p.children or #p.children == 0 then out[#out + 1] = p return out end
	for _, c in ipairs(p.children) do leaves(c, out) end
	return out
end
DV.shopLeaves = leaves

-- the shop a page is in (its top page's)
local function shopOf(pageId)
	for _, t in ipairs(CAT.pages or {}) do
		for _, l in ipairs(leaves(t)) do if l.id == pageId then return t.shop or "furni" end end
		if t.id == pageId then return t.shop or "furni" end
	end
end

-- the page asked for, when it's come (CAT.page is the catalogue's one page at a time)
local function pageData(id)
	if CAT.page and CAT.page.id == id then return CAT.page end
	if CAT.asked ~= id and (CAT.phoneAsked ~= id or SysTime() - (CAT.phoneAskedAt or 0) > 4) then
		CAT.phoneAsked, CAT.phoneAskedAt = id, SysTime()
		CAT.asked = id
		P.send("catalog.page", { id = id })
	end
end

-- can you buy it: nil, or why not
local function cannot(offer, n)
	for _, c in ipairs({ "credits", "duckets", "diamonds" }) do
		local v = offer.price and offer.price[c]
		if v and v > 0 and v * (n or 1) > SHOP.amount(c) then
			return T("bobba.phone.shop.notenough", "Not enough %currency%", { currency = T("bobba.phone.currency." .. c, c) })
		end
	end
	local purse = HUD.purse or {}
	if (offer.clubLevel or 0) > (purse.clubLevel or 0) then return T("catalog.alert.hc.required", "Club required") end
end

local function offerName(o)
	if o.kind and not o.data and SHOP.furniName then return SHOP.furniName(o.kind) end
	return o.name or o.kind or "?"
end

-- buying: asked first, then the server's answer comes as a notification
function DV.buy(offer, pageId, n, appId)
	n = n or 1
	local why = cannot(offer, n)
	if why then
		DV.ask({ title = offerName(offer), text = why, ok = T("bobba.phone.app.wallet", "Wallet"), fn = function() DV.openApp("wallet") end })
		return
	end
	DV.ask({
		title = T("bobba.phone.shop.buytitle", "Buy %name%?", { name = offerName(offer) }),
		text = T("bobba.phone.shop.buytext", "It costs %price%. It goes into your Bag.", { price = DV.priceText(offer.price, n) }),
		ok = T("catalog.purchase_confirmation.buy", "Buy"),
		fn = function()
			DV.buying = { offer = offer, app = appId, at = SysTime() }
			P.send("catalog.buy", { page = offer.page or pageId, offer = offer.id, amount = n, extra = offer.trophy and (DV.trophyText or "") or nil })
		end,
	})
end

BOBBA.events.on("catalogBought", "bobba.device.shop", function(data)
	local b = DV.buying
	if not b or data.gift then return end
	DV.buying = nil
	DV.notify({ app = b.app or "furni", title = T("bobba.phone.shop.bought", "Bought"),
		text = (b.offer.club and T("bobba.phone.shop.clubbought", "Welcome to the club!")) or T("bobba.phone.shop.boughttext", "%name% is in your Bag.", { name = offerName(b.offer) }) })
end)
BOBBA.events.on("catalogError", "bobba.device.shop", function(data)
	if not DV.buying then return end
	DV.buying = nil
	DV.notify({ app = "furni", title = T("generic.failed", "Failed"), text = tostring(data.message or "") })
	return true
end)

-- the gift: the catalogue's gift window (who to, the box, a message)
local function giveAsGift(offer, pageId)
	local GIFT = SHOP.gift
	GIFT.offer, GIFT.page, GIFT.error, GIFT.sending = offer, offer.page or pageId, nil, false
	U.window("catalog-gift", 325, 404, SHOP.drawGift)
end

-- --- an offer: its picture, name, price, Buy ---------------------------------------------------------
local function offerDetail(d, offer, pageId, x, y, w, h, opts)
	opts = opts or {}
	local dark = opts.dark
	local fg = dark and hex("F7EBD0") or C.navy
	local sub = dark and hex("CDBB92") or C.ink2
	local ph = math.min(opts.pictureH or 220, h * 0.42)
	d:round(22, x, y, w, ph, dark and hex("2A2215") or C.line)
	if offer.kind then
		d:clip(x, y, w, ph, function() d:furni(offer.kind, x, y, w, ph, offer.data, true, opts.dir or 2) end)
		if opts.turn then DV.turnButton(d, x + w - 54, y + ph - 54, opts.turn) end
	end
	local ty = y + ph + 14
	for i, l in ipairs(d:wrap(offerName(offer), 20, w)) do
		if i <= 2 then d:text(l, 20, x, ty, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800) ty = ty + 26 end
	end
	if offer.pair then d:text(T("bobba.phone.shop.pair", "Comes as a pair"), 13, x, ty + 2, sub) ty = ty + 20 end
	-- the price and the buttons at the bottom
	local by = y + h - 48 - (opts.noGift and 0 or 56)
	d:text(DV.priceText(offer.price, 1), 22, x, by - 40, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	local why = cannot(offer, 1)
	if why then d:text(why, 12, x, by - 14, C.red, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700) end
	d:button(x, by, w, 48, T("catalog.purchase_confirmation.buy", "Buy"), dark and "gold" or "primary", function() DV.buy(offer, pageId, 1, opts.app) end)
	if not opts.noGift then
		local can = offer.kind and not offer.club and not offer.pair
		d.bgUnder = dark and hex("221C12") or C.white
		d:button(x, by + 56, w, 44, T("catalog.purchase_confirmation.gift", "Buy as a gift"), dark and "outlineLight" or "outline", function() giveAsGift(offer, pageId) end, not can)
		d.bgUnder = nil
	end
end

local function offerCard(d, o, x, y, w, h, on, dark)
	local hov = d.surf.mx and d.surf.mx >= x and d.surf.mx < x + w and d.surf.my >= y and d.surf.my < y + h
	d:round(20, x, y, w, h, on and (dark and hex("E8C26A") or C.navy) or (dark and hex("221C12") or C.white))
	d:round(16, x + 4, y + 4, w - 8, w - 8, dark and hex("2A2215") or C.paper)
	if o.kind then d:clip(x + 6, y + 6, w - 12, w - 12, function() d:furni(o.kind, x + 4, y + 4, w - 8, w - 8, o.data) end) end
	local fg = on and (dark and hex("14110B") or C.paper) or (dark and hex("F7EBD0") or C.navy)
	d:textFit(offerName(o), 12, w - 12, x + 8, y + w + 2, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
	d:textFit(DV.priceText(o.price, 1), 11, w - 12, x + 8, y + w + 19, alpha(fg, 0.7), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 600)
	if o.pair then
		d:pill(x + w - 34, y + 8, 26, 18, C.navy)
		d:text("×2", 10, x + w - 21, y + 17, C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
	end
	if hov and not on then d:round(20, x, y, w, h, alpha(C.navy, 0.05)) end
end

-- --- a shop: its pages, the offers on the open one, the chosen one -----------------------------------
-- opts: { app, title, dark (the club's look), banner = function(d, x, y, w) -> h }
function DV.shopView(shop, opts)
	return function(ctx)
		local d, W, H = ctx.d, ctx.w, ctx.h
		local st = ctx.state
		local dark = opts.dark
		local bg = dark and hex("14110B") or C.paper
		local fg = dark and hex("F7EBD0") or C.navy
		local sub = dark and hex("CDBB92") or C.ink2
		d:rect(0, 0, W, H, bg)
		local tablet = ctx.kind == "tablet"
		local tabs = DV.shopTabs(shop)
		if not st.tab or not (function() for _, t in ipairs(tabs) do if t.id == st.tab then return true end end end)() then
			st.tab = tabs[1] and tabs[1].id or nil
			st.page = nil
		end
		local tab
		for _, t in ipairs(tabs) do if t.id == st.tab then tab = t end end
		local pages = tab and leaves(tab) or {}
		if not st.page or not (function() for _, p in ipairs(pages) do if p.id == st.page then return true end end end)() then
			st.page = pages[1] and pages[1].id or nil
			st.offer = nil
		end
		local page = st.page and pageData(st.page)
		-- the search's results instead of the page
		local searching = st.query and st.query ~= "" and CAT.phoneSearch and CAT.phoneSearch.query == st.query
		local offers = {}
		if searching then
			for _, o in ipairs(CAT.phoneSearch.offers or {}) do if shopOf(o.page) == shop then offers[#offers + 1] = o end end
		elseif page and page.layout ~= "vip_buy" then
			for _, o in ipairs(page.offers or {}) do offers[#offers + 1] = o end
		end
		local chosen
		for _, o in ipairs(offers) do if o.id == st.offer then chosen = o end end
		local purse = HUD.purse or {}
		local function search(t)
			st.query = t or ""
			if st.query ~= "" then CAT.phoneQuery = st.query P.send("catalog.search", { query = st.query }) end
			st.offer = nil
		end
		if tablet then
			-- the rail: the shop's name, its pages
			local railW = 210
			d:text(opts.title, 22, 24, ctx.top + 22, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
			local ry = ctx.top + 52
			local railOff = d:scroll("rail", 0, ry, railW + 24, H - ry, st.railH or H)
			d:clip(0, ry, railW + 24, H - ry, function()
				local yy = ry - railOff
				for _, t in ipairs(tabs) do
					local on = t.id == st.tab
					local hov = d:click(16, yy, railW, 40, function() st.tab = t.id st.page = nil st.query = nil end)
					if on then d:round(14, 16, yy, railW, 40, dark and hex("E8C26A") or C.navy) elseif hov then d:round(14, 16, yy, railW, 40, alpha(fg, 0.08)) end
					d:textFit(t.name or "", 15, railW - 24, 30, yy + 20, on and (dark and hex("14110B") or C.paper) or fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, on and 800 or 600)
					yy = yy + 44
					if on and #pages > 1 then
						for _, p in ipairs(pages) do
							local pon = p.id == st.page and not searching
							local ph2 = d:click(28, yy, railW - 12, 32, function() st.page = p.id st.offer = nil st.query = nil end)
							if pon or ph2 then d:round(12, 28, yy, railW - 12, 32, alpha(fg, pon and 0.14 or 0.06)) end
							d:textFit(p.name or "", 13, railW - 36, 40, yy + 16, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, pon and 700 or 500)
							yy = yy + 34
						end
						yy = yy + 6
					end
				end
				st.railH = yy + railOff - ry + 20
			end)
			-- the middle: search, wallet, banner, the offers
			local mx, mw = railW + 40, W - railW - 40 - 300 - 24
			local my = ctx.top + 8
			d:input("shopsearch", mx, my, mw - 150, 44, { placeholder = T("bobba.phone.shop.search", "Search the shop"), max = 100, bg = dark and hex("221C12") or C.line, fg = fg, onEnter = search })
			d:pill(mx + mw - 140, my, 140, 44, dark and hex("E8C26A") or C.navy)
			d:text(DV.money(purse.credits) .. " " .. T("bobba.phone.currency.credits", "credits"), 14, mx + mw - 70, my + 22, dark and hex("14110B") or C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
			my = my + 44 + 16
			if opts.banner then my = my + opts.banner(d, mx, my, mw, st) + 16 end
			d:text(searching and T("bobba.phone.shop.results", "Results for \"%q%\"", { q = st.query }) or (page and page.name or ""), 16, mx, my + 10, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
			my = my + 30
			local cols = 4
			local gap = 14
			local cw = (mw - (cols - 1) * gap) / cols
			local chh = cw + 40
			local rows = math.ceil(#offers / cols)
			local off = d:scroll("offers", mx, my, mw, H - my, rows * (chh + gap) + 20)
			d:clip(mx - 4, my, mw + 8, H - my, function()
				if #offers == 0 and not (page and page.layout == "vip_buy") then
					d:text((page or searching) and T("bobba.phone.shop.empty", "Nothing here.") or T("bobba.phone.loading", "Loading…"), 14, mx + mw / 2, my + 40, sub, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
				end
				for i, o in ipairs(offers) do
					local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
					local ox2, oy2 = mx + col * (cw + gap), my + row * (chh + gap) - off
					if oy2 + chh > my and oy2 < H then
						d:click(ox2, oy2, cw, chh, function() st.offer = o.id st.dir = 2 end)
						offerCard(d, o, ox2, oy2, cw, chh, o.id == st.offer, dark)
					end
				end
			end)
			-- the right: the chosen one
			local rx, rw = W - 300 - 24, 300
			d:round(26, rx, ctx.top + 8, rw, H - ctx.top - 32, dark and hex("221C12") or C.white)
			if chosen then
				d.bgUnder = dark and hex("221C12") or C.white
				offerDetail(d, chosen, page and page.id or chosen.page, rx + 18, ctx.top + 26, rw - 36, H - ctx.top - 68,
					{ dark = dark, app = opts.app, dir = st.dir or 2, turn = function() st.dir = ((st.dir or 2) + 2) % 8 end })
				d.bgUnder = nil
			else
				for i, l in ipairs(d:wrap(T("bobba.phone.shop.pick", "Pick something to see it here."), 14, rw - 60)) do
					d:text(l, 14, rx + rw / 2, ctx.top + 200 + (i - 1) * 20, sub, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
				end
			end
			return
		end
		-- the phone: the pages as chips, the offers in a grid; one opens on its own screen
		local top = ctx.top + ctx:header(opts.title, { big = true, dark = dark })
		local x, w = 16, W - 32
		d:input("shopsearch", x, top + 2, w, 42, { placeholder = T("bobba.phone.shop.search", "Search the shop"), max = 100, bg = dark and hex("221C12") or C.line, fg = fg, onEnter = search })
		local y = top + 2 + 42 + 10
		if #tabs > 1 then
			local list = {}
			for _, t in ipairs(tabs) do list[#list + 1] = { id = t.id, label = t.name } end
			d:chips("shoptabs", x, y, w, list, st.tab, function(id) st.tab = id st.page = nil st.query = nil end,
				dark and { on = hex("E8C26A"), onFg = hex("14110B"), off = hex("221C12"), fg = hex("F7EBD0") } or nil)
			y = y + 32 + 8
		end
		if #pages > 1 then
			local list = {}
			for _, p in ipairs(pages) do list[#list + 1] = { id = p.id, label = p.name } end
			d:chips("shoppages", x, y, w, list, (not searching) and st.page or nil, function(id) st.page = id st.query = nil end,
				{ h = 28, size = 12, on = dark and hex("F7EBD0") or C.ink2, onFg = dark and hex("14110B") or C.paper, off = alpha(fg, 0.08), fg = fg })
			y = y + 28 + 10
		end
		if opts.banner then y = y + opts.banner(d, x, y, w, st) + 10 end
		local cols = 3
		local gap = 10
		local cw = (w - (cols - 1) * gap) / cols
		local chh = cw + 40
		local rows = math.ceil(#offers / cols)
		local off = d:scroll("offers", 0, y, W, H - y, rows * (chh + gap) + 30)
		d:clip(0, y, W, H - y, function()
			if #offers == 0 and not (page and page.layout == "vip_buy") then
				d:text((page or searching) and T("bobba.phone.shop.empty", "Nothing here.") or T("bobba.phone.loading", "Loading…"), 14, W / 2, y + 40, sub, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
			end
			for i, o in ipairs(offers) do
				local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
				local ox2, oy2 = x + col * (cw + gap), y + row * (chh + gap) - off
				if oy2 + chh > y and oy2 < H then
					d:click(ox2, oy2, cw, chh, function()
						ctx:push(function(c2)
							local d2 = c2.d
							d2:rect(0, 0, c2.w, c2.h, bg)
							local t2 = c2.top + c2:header(page and page.name or opts.title, { dark = dark })
							c2.state.dir = c2.state.dir or 2
							d2.bgUnder = bg
							offerDetail(d2, o, page and page.id or o.page, 20, t2 + 8, c2.w - 40, c2.h - t2 - 40,
								{ dark = dark, app = opts.app, pictureH = 300, dir = c2.state.dir, turn = function() c2.state.dir = (c2.state.dir + 2) % 8 end })
							d2.bgUnder = nil
						end, {})
					end)
					offerCard(d, o, ox2, oy2, cw, chh, false, dark)
				end
			end
		end)
	end
end

-- --- Furni ------------------------------------------------------------------------------------------
DV.app({ id = "furni", name = T("bobba.phone.app.furni", "Furni"), color = C.yellow, glyph = G.furni, order = 10,
	phone = DV.shopView("furni", { app = "furni", title = T("bobba.phone.app.furni", "Furni") }),
	tablet = DV.shopView("furni", { app = "furni", title = T("bobba.phone.app.furni", "Furni") }) })

-- --- the club: joining it (its pages' club offers), and the club's own pages --------------------------
local GOLD, DARK, DARK2 = hex("E8C26A"), hex("14110B"), hex("221C12")
local function clubBanner(d, x, y, w, st)
	local purse = HUD.purse or {}
	local member = (purse.clubLevel or 0) > 0
	local h = 150
	d:round(26, x, y, w, h, hex("2A2215"))
	d:clip(x, y, w, h, function()
		d:ring(x + w - 30, y + 20, 140, 2, alpha(GOLD, 0.6))
		d:circle(x + w - 10, y + 40, 90, alpha(GOLD, 0.16))
	end)
	d:round(11, x + 18, y + 18, 34, 34, GOLD)
	d:glyph(G.club, x + 26, y + 26, 18, DARK, 2.2)
	d:text(member and T("bobba.phone.club.member", "You're in the club") or T("bobba.phone.club.only", "Only for club members"), 22, x + 18, y + 64, hex("F7EBD0"), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	local subText = member and T("bobba.phone.club.left", "%time% left", { time = purse.clubText or "" }) or T("bobba.phone.club.perks", "Club furni, club clothes, extra dances and more.")
	d:textFit(subText, 13, w - 40, x + 18, y + 96, hex("CDBB92"))
	return h
end

-- the club's offers (a "vip_buy" page): how long, the price, Join
local function joinOffers(d, page, x, y, w, appId)
	local kind = page.clubKind or "hc"
	local purse = HUD.purse or {}
	local extending = (purse.clubLevel or 0) > 0 and (purse.clubKind or "hc") == kind
	local yy = y
	for _, o in ipairs(page.offers or {}) do
		d:round(20, x, yy, w, 64, DARK2)
		local months = math.floor((o.club or 0) / 31)
		local label = months == 1 and T("bobba.phone.club.month", "1 month") or months > 0 and T("bobba.phone.club.months", "%n% months", { n = months }) or T("bobba.phone.club.days", "%n% days", { n = o.club or 0 })
		d:text(label, 16, x + 18, yy + 22, hex("F7EBD0"), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
		d:text(DV.priceText(o.price, 1), 13, x + 18, yy + 44, hex("CDBB92"), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 600)
		d:button(x + w - 128, yy + 13, 114, 38, extending and T("bobba.phone.club.extend", "Extend") or T("bobba.phone.club.join", "Join"), "gold", function()
			DV.buy(o, page.id, 1, appId)
		end)
		yy = yy + 72
	end
	return yy - y
end

local clubShop = DV.shopView("club", { app = "club", title = T("bobba.phone.app.club", "Club"), dark = true, banner = function(d, x, y, w, st)
	local h = clubBanner(d, x, y, w, st)
	-- (a club's page: its offers to join under the banner)
	local page = st.page and CAT.page and CAT.page.id == st.page and CAT.page
	if page and page.layout == "vip_buy" then
		h = h + 12 + joinOffers(d, page, x, y + h + 12, w, "club")
	end
	return h
end })

DV.app({ id = "club", name = T("bobba.phone.app.club", "Club"), color = C.gold, glyph = G.club, order = 12, bg = hex("14110B"),
	phone = clubShop, tablet = clubShop })
