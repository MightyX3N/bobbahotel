-- The inventory's furni and the catalogue (client), as nitro-react has them:
--   InventoryFurnitureView: a search, the furni grouped by kind in a grid (how many on each), the
--     chosen one's preview, its name and "Place in room" (attemptItemPlacement: the furni follows the
--     mouse in the room until it's put down)
--   CatalogView: the top pages as tabs, the pages of the open tab on the left (CatalogNavigationView,
--     with its search), the page on the right: CatalogLayoutDefaultView (the offers in a grid, the
--     chosen one's preview, name, amount, price and Buy, which asks to confirm) or
--     CatalogLayoutVipBuyView (Habbo Club)
-- Sizes measured from nitro-react's CSS in a browser (chatdev/catref). The pictures (furni icons and
-- previews) come from an addon: BOBBA.room.furniIcon / furniPreview.

local U = BOBBA.ui
local HUD = BOBBA.hud
local P = BOBBA.platform
local R = BOBBA.room

BOBBA.shop = BOBBA.shop or {}
local SHOP = BOBBA.shop

-- the purse's amount of a currency the way Nitro asks for it (-1 credits, 0 duckets, 5 diamonds)
local POINTS = { credits = -1, duckets = 0, diamonds = 5 }
local function amount(currency)
	local p = HUD.purse
	if currency == "credits" then return p.credits or 0 end
	return (p.points or {})[POINTS[currency]] or 0
end

local function furniName(kind)
	local info = R.furniInfo and R.furniInfo(kind)
	return (info and info.name and info.name ~= "") and info.name or kind
end

-- an inventory group's name (a wallpaper's with its number)
local function groupName(g)
	local n = furniName(g.kind)
	if g.data then n = n .. " " .. g.data end
	return n
end

-- FaCaretLeft / FaCaretRight in a box of size (CSS px)
local function caret(d, x, y, size, left, c)
	local s = d.s
	local u = size / 16
	local cx, cy = x + size * 0.3, y + size / 2
	draw.NoTexture()
	surface.SetDrawColor(c.r, c.g, c.b, c.a or 255)
	if left then
		surface.DrawPoly({ { x = (cx + 4 * u) * s, y = (cy - 6 * u) * s }, { x = (cx + 4 * u) * s, y = (cy + 6 * u) * s }, { x = (cx - 2 * u) * s, y = cy * s } })
	else
		surface.DrawPoly({ { x = (cx - 2 * u) * s, y = (cy - 6 * u) * s }, { x = (cx + 4 * u) * s, y = cy * s }, { x = (cx - 2 * u) * s, y = (cy + 6 * u) * s } })
	end
end

-- LayoutRoomPreviewerView: #dfdfdf, rounded, a dark line over and left of it, white under and right,
-- shaded inside at the top-left; the furni in the middle
-- (a wallpaper, floor or landscape: its pattern, data its id)
local function paintOfKind(kind)
	local info = R.furniInfo and R.furniInfo(kind)
	return info and info.paint or nil
end

local function previewBox(d, x, y, w, h, kind, data)
	d:rect(x - 2, y - 2, w + 2, 2, Color(0, 0, 0, 102))
	d:rect(x - 2, y, 2, h, Color(0, 0, 0, 102))
	d:round(4, x, y, w, h, Color(223, 223, 223))
	d:rect(x + 2, y, w - 4, 3, Color(0, 0, 0, 51))
	d:rect(x, y + 3, 3, h - 5, Color(0, 0, 0, 51))
	d:rect(x + 2, y + h - 2, w - 2, 2, U.C.white)
	d:rect(x + w - 2, y + 2, 2, h - 2, U.C.white)
	local paint = kind and data and paintOfKind(kind)
	if paint and R.paintSwatch then
		local s = d.s
		d:clip(x + 2, y + 2, w - 4, h - 4, function()
			R.paintSwatch(paint, data, math.floor((x + 2) * s + 0.5), math.floor((y + 2) * s + 0.5), math.floor((w - 4) * s + 0.5), math.floor((h - 4) * s + 0.5), 2 * s)
		end)
	elseif kind and R.furniPreview then
		local s = d.s
		d:clip(x + 2, y + 2, w - 4, h - 4, function()
			R.furniPreview(kind, math.floor(x * s + 0.5), math.floor(y * s + 0.5), math.floor(w * s + 0.5), math.floor(h * s + 0.5), s, 2)
		end)
	end
end

-- a furni's icon in the middle of a grid item
local function furniIcon(d, kind, x, y, w, h, alpha, data)
	local s = d.s
	local paint = data and paintOfKind(kind)
	if paint and R.paintSwatch then
		-- (a pattern: a square of it)
		local q = math.min(w, h) - 8
		R.paintSwatch(paint, data, math.floor((x + (w - q) / 2) * s + 0.5), math.floor((y + (h - q) / 2) * s + 0.5), math.floor(q * s + 0.5), math.floor(q * s + 0.5), s)
		return
	end
	if not R.furniIcon then return end
	R.furniIcon(kind, math.floor(x * s + 0.5), math.floor(y * s + 0.5), math.floor(w * s + 0.5), math.floor(h * s + 0.5), s, alpha)
end

-- LayoutItemCountView: the number in red at the top right (badge bg-danger, black border)
local function countBadge(d, n, right, top)
	if U.countBadge then return U.countBadge(d, n, right, top) end
	local t = tostring(n)
	local w = d:textWidth(t, 9.5, true) + 8 + 2
	d:round(4, right - w, top, w, 15.5, U.C.black)
	d:round(3, right - w + 1, top + 1, w - 2, 13.5, U.C.danger)
	d:text(t, 9.5, right - w / 2, top + 15.5 / 2, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
end

-- AutoGrid (columnMinWidth 40, gap 8): how many columns fit, and how wide each is
local function columns(w)
	local n = math.max(1, math.floor((w + 8) / 48))
	return n, (w - 8 * (n - 1)) / n
end

-- the search button (btn-primary with FaSearch)
local function searchButton(d, x, y, w, h, fn)
	d:btn(x, y, w, h, U.C.primary, fn)
	d:fa("search", x + (w - 12.6) / 2, y + (h - 12.6) / 2, 12.6, U.C.white)
end

-- text that wraps: its lines
local function lines(d, text, size, maxW, bold)
	return U.wrapText(d, text, size, maxW, bold)
end

-- --- the inventory's furni --------------------------------------------------------------------------
SHOP.inv = SHOP.inv or { items = {}, loaded = false, unseen = {}, sent = {} }
local INV = SHOP.inv
INV.unseen, INV.sent = INV.unseen or {}, INV.sent or {}

-- how many furni came in that haven't been looked at (useInventoryUnseenTracker: the toolbar's count)
function SHOP.unseenCount()
	local n = 0
	for _ in pairs(INV.unseen) do n = n + 1 end
	return n
end

-- the next furni of a kind to place, after one that's just been put down ("Place multiple objects")
function SHOP.nextOfKind(kind, after)
	INV.sent[after] = true
	for i = #INV.items, 1, -1 do
		local it = INV.items[i]
		if it.kind == kind and not INV.sent[it.id] then return it.id end
	end
end

-- the furni grouped the way Nitro's GroupItem does: one per kind, newest first
-- (a wallpaper, floor or landscape is grouped with the same one only, like Nitro groups by its data)
local function paintOf(kind)
	local info = R.furniInfo and R.furniInfo(kind)
	return info and info.paint or nil
end

local function groups()
	local byKind, list = {}, {}
	for i = #INV.items, 1, -1 do
		local it = INV.items[i]
		local key = it.kind
		if it.data and paintOf(it.kind) then key = it.kind .. "|" .. it.data end
		local g = byKind[key]
		if not g then
			g = { kind = it.kind, key = key, ids = {}, data = paintOf(it.kind) and it.data or nil }
			byKind[key] = g
			list[#list + 1] = g
		end
		g.ids[#g.ids + 1] = it.id
	end
	return list
end

P.receive("inventory.items", function(_, list)
	INV.items = list or {}
	INV.loaded = true
	INV.sent = {}
end)
P.receive("inventory.added", function(_, list)
	for _, it in ipairs(list or {}) do
		local seen = false
		for _, o in ipairs(INV.items) do if o.id == it.id then seen = true end end
		if not seen then INV.items[#INV.items + 1] = it end
		-- (new to the inventory: marked until it's looked at)
		if it.new then INV.unseen[it.id] = true end
		INV.sent[it.id] = nil
	end
end)
P.receive("inventory.removed", function(_, ids)
	local gone = {}
	for _, id in ipairs(ids or {}) do gone[id] = true end
	for i = #INV.items, 1, -1 do if gone[INV.items[i].id] then table.remove(INV.items, i) end end
	for id in pairs(gone) do INV.unseen[id], INV.sent[id] = nil, nil end
end)

-- attemptItemPlacement: the furni follows the mouse in the room (the inventory goes away meanwhile)
function SHOP.place(g)
	if not g or not R.current then return end
	R.placing = { kind = g.kind, dir = 2, inventoryId = g.ids[1], paint = paintOf(g.kind), data = g.data }
	R.selected = nil
	if R.updateInfo then R.updateInfo() end
	local w = U.windows.inventory
	if w then w:close() end
end

-- the Furni tab (InventoryFurnitureView); false when there's nothing (the empty view is drawn instead)
function SHOP.drawInventoryFurni(w, d)
	local all = groups()
	if #all == 0 then return false end
	local search = d:input("furni-search", 9, 75, 259.6, 28.9, { placeholder = U.text("generic.search", "Search"), max = 100 })
	searchButton(d, 272.6, 75, 30.6, 28.9, function() end)
	local filter = (search:GetValue() or ""):lower()
	local list = {}
	for _, g in ipairs(all) do
		if filter == "" or groupName(g):lower():find(filter, 1, true) then list[#list + 1] = g end
	end
	-- the chosen one (the first when none is)
	local chosen
	for _, g in ipairs(all) do if g.key == INV.selected then chosen = g end end
	if not chosen then chosen = all[1] INV.selected = chosen.key end
	-- (looking at a group: its new ones are seen now, resetItems)
	for _, id in ipairs(chosen.ids) do INV.unseen[id] = nil end
	-- the grid
	local gx, gy, gw, gh = 9, 111.9, 294.2, 311 - 111.9
	local n, cw = columns(gw)
	local rows = math.ceil(#list / n)
	local off = d:scroll("furni", gx, gy, gw, gh, rows * 48 - 8)
	d:clip(gx, gy, gw, gh, function()
		for i, g in ipairs(list) do
			local col, row = (i - 1) % n, math.floor((i - 1) / n)
			local x, y = gx + col * (cw + 8), gy + row * 48 - off
			if y + 40 > gy and y < gy + gh then
				local active = g == chosen
				d:click(x, y, cw, 40, function()
					local now = SysTime()
					if INV.lastClick and INV.lastClick.kind == g.key and now - INV.lastClick.t < 0.4 then SHOP.place(g) return end
					INV.lastClick = { kind = g.key, t = now }
					INV.selected = g.key
				end)
				-- (new ones: layout-grid-item.unseen, green at 40%)
				local unseen = false
				for _, id in ipairs(g.ids) do if INV.unseen[id] then unseen = true end end
				d:gridItem(x, y, cw, 40, active, (unseen and not active) and Color(134, 185, 138) or nil)
				d:clip(x + 2, y + 2, cw - 4, 36, function() furniIcon(d, g.kind, x, y, cw, 40, nil, g.data) end)
				if #g.ids > 1 then countBadge(d, #g.ids, x + cw - 4, y + 4) end
			end
		end
	end)
	-- the chosen one: preview, name, place
	local rx, rw = 311.2, 207.8
	previewBox(d, rx, 75, rw, 140, chosen.kind, chosen.data)
	d:text(d:fit(groupName(chosen), 14.4, rw), 14.4, rx, 223 + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if R.current then
		d:btn(rx, 282.1, rw, 28.9, U.C.success, function() SHOP.place(chosen) end)
		d:text(U.text("inventory.furni.placetoroom", "Place in room"), 12.6, rx + rw / 2, 282.1 + 28.9 / 2, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	return true
end

-- the first time the inventory opens, ask for what's in it
function SHOP.inventoryOpened()
	INV.sent = {}
	if not INV.loaded then P.send("inventory.get", {}) end
end

-- --- the catalogue ----------------------------------------------------------------------------------
SHOP.cat = SHOP.cat or { pages = nil, open = {}, quantity = 1, state = "none" }
SHOP.gift = SHOP.gift or { box = 1, showFace = true }
local CAT = SHOP.cat

local function findPage(list, id, parent)
	for _, p in ipairs(list or {}) do
		p.parent = parent
		if p.id == id then return p end
		local f = findPage(p.children, id, p)
		if f then return f end
	end
end

-- opens a page (activateNode): a tab opens its first page; the pages it's under open too
function SHOP.openPage(id)
	local p = findPage(CAT.pages, id)
	if not p then return end
	-- (a page with pages under it has nothing of its own here: its first page opens)
	while p.children and p.children[1] do p = p.children[1] end
	CAT.active = p.id
	local n = p
	while n do
		CAT.open[n.id] = true
		if not n.parent then CAT.tab = n.id end
		n = n.parent
	end
	CAT.search = nil
	if not p.children then
		CAT.offer, CAT.quantity, CAT.state = nil, 1, "none"
		if not (CAT.page and CAT.page.id == p.id) and CAT.asked ~= p.id then
			CAT.asked = p.id
			P.send("catalog.page", { id = p.id })
		end
	end
end

P.receive("catalog.index", function(_, data)
	CAT.pages = data.pages or {}
	findPage(CAT.pages, -1)
	local want = CAT.wantTab
	CAT.wantTab = nil
	if want == "club" and CAT.pages[1] then SHOP.openPage(CAT.pages[#CAT.pages].id) return end
	if want then
		for _, t in ipairs(CAT.pages) do if t.name == want then SHOP.openPage(t.id) return end end
	end
	if CAT.pages[1] and not CAT.active then SHOP.openPage(CAT.pages[1].id) end
end)
P.receive("catalog.page", function(_, data)
	CAT.page = data
	if CAT.asked == data.id then CAT.asked = nil end
	-- (the grid goes back to the top for a new page)
	local w = U.windows.catalog
	if w and w.scrolls.offers then w.scrolls.offers.offset = 0 end
	if data.layout == "vip_buy" then CAT.offer = nil end
end)
P.receive("catalog.search", function(_, data)
	local w = U.windows.catalog
	local box = w and w.inputs and w.inputs.search
	if not IsValid(box) or (box:GetValue() or "") ~= data.query then return end
	CAT.search = data
	CAT.offer, CAT.quantity, CAT.state = nil, 1, "none"
end)
P.receive("catalog.error", function(_, data)
	if data.gift then
		-- (in the gift window: under the receiver; "User not found")
		SHOP.gift.sending = false
		SHOP.gift.error = tostring(data.message):find("^no one") and U.text("catalog.gift_wrapping.receiver_not_found.title", "User not found") or tostring(data.message)
		return
	end
	CAT.state = "failed"
	CAT.stateUntil = SysTime() + 3
	chat.AddText(Color(255, 120, 120), "[Bobba] ", color_white, tostring(data.message))
end)

-- the catalogue's search: as you type (a moment after), names of furni
local function searchChanged(text)
	CAT.searchAt = SysTime() + 0.3
	CAT.searchText = text
	if text == "" then CAT.search = nil end
end
hook.Add("Think", "bobba.shop.search", function()
	if CAT.searchAt and SysTime() >= CAT.searchAt then
		CAT.searchAt = nil
		if (CAT.searchText or "") ~= "" then P.send("catalog.search", { query = CAT.searchText }) end
	end
	if CAT.stateUntil and SysTime() >= CAT.stateUntil then
		CAT.stateUntil = nil
		CAT.state = "none"
	end
end)

-- the pages on the left (CatalogNavigationItemView: 23 high, 4 apart, the open ones' pages under
-- them 7 in with a line on their left)
local function drawNavItems(d, list, x, y, w, bottom, top)
	for _, p in ipairs(list) do
		local active = p.id == CAT.active
		if y + 23 > top and y < bottom then
			d:click(x, math.max(y, top), w, math.min(y + 23, bottom) - math.max(y, top), function()
				-- (an open one closes again; a closed one opens with its first page showing)
				if p.children and CAT.open[p.id] then CAT.open[p.id] = false return end
				SHOP.openPage(p.id)
			end)
			d:round(4, x, y, w, 23, active and U.C.gridActive or U.C.gridItem)
			-- (CatalogIconView, 20 x 20: a club's coin, or a furni of the page)
			if p.iconName and p.iconName:find("^club%-") then U.clubIcon(d, p.iconName:sub(6), x + 3, y + 1.5, 20, 20)
			elseif p.iconName then d:icon(p.iconName, x + 3, y + 1.5, 20, 20)
			elseif p.iconKind and R.furniIcon then
				local s = d.s
				R.furniIcon(p.iconKind, math.floor((x + 3) * s + 0.5), math.floor((y + 1.5) * s + 0.5), math.floor(20 * s + 0.5), math.floor(20 * s + 0.5), s, 255, true)
			end
			local tw = w - 27 - 3 - (p.children and 16.6 or 0)
			d:text(d:fit(p.name, 12.6, tw), 12.6, x + 27, y + 23 / 2, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			if p.children then
				local cx, cy = x + w - 3 - 12.6, y + (23 - 12.6) / 2
				local s = d.s
				draw.NoTexture()
				surface.SetDrawColor(0, 0, 0, 255)
				local mx, my = cx + 6.3, cy + 6.3
				if CAT.open[p.id] then
					surface.DrawPoly({ { x = (mx - 3.9) * s, y = (my + 2) * s }, { x = mx * s, y = (my - 2) * s }, { x = (mx + 3.9) * s, y = (my + 2) * s } })
				else
					surface.DrawPoly({ { x = (mx - 3.9) * s, y = (my - 2) * s }, { x = (mx + 3.9) * s, y = (my - 2) * s }, { x = mx * s, y = (my + 2) * s } })
				end
			end
		end
		y = y + 23
		if p.children and CAT.open[p.id] then
			local childTop = y
			y = drawNavItems(d, p.children, x + 7, y, w - 7, bottom, top) - 4
			d:rect(x, childTop, 2, y - childTop, U.C.muted)
		end
		y = y + 4
	end
	return y
end

local function navHeight(list)
	local h = 0
	for _, p in ipairs(list) do
		h = h + 23 + 4
		if p.children and CAT.open[p.id] then h = h + navHeight(p.children) end
	end
	return h
end

local function priceRows(offer, quantity)
	local rows = {}
	for _, c in ipairs({ "credits", "duckets", "diamonds" }) do
		local n = offer.price and offer.price[c]
		if n and n > 0 then rows[#rows + 1] = { c, n * quantity } end
	end
	return rows
end

-- a price: the number then its coin, right-aligned at x (Flex gap 1)
local function priceRow(d, currency, n, right, y, bold)
	d:icon("currency-" .. currency, right - 15, y + 0.5, 15, 15)
	d:text(tostring(n), 14.4, right - 15 - 4, y + 8, U.C.black, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, bold)
end

-- CatalogPurchaseWidgetView's button: Buy, then Confirm (3 seconds), not enough, failed
local function buyButton(d, x, y, w, h, offer, quantity, buyColor, page, buyKey)
	local label, color, fn, textColor, disabled = nil, buyColor or U.C.primary, nil, U.C.white, false
	local clubLevel = HUD.purse.clubLevel or 0
	for _, r in ipairs(priceRows(offer, quantity)) do
		if not label and r[2] > amount(r[1]) then
			label = r[1] == "credits" and U.text("catalog.alert.notenough.title", "Not enough credits")
				or U.text("catalog.alert.notenough.activitypoints.title." .. POINTS[r[1]], "Not enough " .. r[1])
			color, disabled = U.C.danger, true
		end
	end
	if (offer.clubLevel or 0) > clubLevel then
		label, color, disabled = U.text("catalog.alert.hc.required", "Habbo Club required"), U.C.danger, true
	end
	if not label then
		if CAT.state == "confirm" then
			label, color, textColor = U.text("catalog.marketplace.confirm_title", "Confirm"), Color(255, 193, 7), U.C.black
			fn = function()
				CAT.state = "purchase"
				CAT.stateUntil = nil
				-- (a trophy's engraving goes with it: CatalogLayoutTrophiesView's extraData)
				P.send("catalog.buy", { page = offer.page or page.id, offer = offer.id, amount = quantity, extra = offer.trophy and CAT.trophyText or nil })
			end
		elseif CAT.state == "purchase" then
			label, disabled = "...", true
		elseif CAT.state == "failed" then
			label, color = U.text("generic.failed", "Failed"), U.C.danger
		else
			label = U.text(buyKey or "catalog.purchase_confirmation.buy", "Buy")
			fn = function() CAT.state = "confirm" CAT.stateUntil = SysTime() + 3 end
		end
	end
	d:btn(x, y, w, h, color, fn or function() end, disabled)
	d:text(d:fit(label, 12.6, w - 16), 12.6, x + w / 2, y + h / 2, Color(textColor.r, textColor.g, textColor.b, disabled and 166 or 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- --- gifts (CatalogGiftView) -------------------------------------------------------------------------
-- the boxes (the server's gifts.lua has the same list): Habbo's six gift boxes, then ten wrappings
SHOP.GIFT_BOXES = { "present_gen1", "present_gen2", "present_gen3", "present_gen4", "present_gen5", "present_gen6" }
for i = 1, 10 do SHOP.GIFT_BOXES[#SHOP.GIFT_BOXES + 1] = "present_wrap*" .. i end
local GIFT = SHOP.gift

-- the Gift button: one of it (Nitro: not with an amount over 1), not club or teleports
function SHOP.giftButton(d, x, y, w, offer, page, quantity)
	local can = offer.kind and not offer.club and not offer.pair and quantity <= 1
	d:btn(x, y, w, 28.9, U.C.primary, function()
		GIFT.offer, GIFT.page, GIFT.error, GIFT.sending = offer, offer.page or page.id, nil, false
		U.window("catalog-gift", 325, 404, SHOP.drawGift)
	end, not can)
	d:text(U.text("catalog.purchase_confirmation.gift", "Give as a gift"), 12.6, x + w / 2, y + 28.9 / 2, Color(255, 255, 255, can and 255 or 166), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

P.receive("catalog.bought", function(_, data)
	CAT.state = "none"
	if data.gift then
		GIFT.sending = false
		if U.windows["catalog-gift"] then U.windows["catalog-gift"]:close() end
		chat.AddText(Color(120, 200, 120), "[Bobba] ", color_white, "Your gift is on its way to " .. tostring(data.receiver or "them") .. ".")
	end
end)

function SHOP.drawGift(w, d)
	local offer = GIFT.offer
	if not offer then w:close() return end
	d:slimCard(U.text("catalog.gift_wrapping.title", "Customize your gift"))
	local x, cw = 9, d.width - 18
	-- the receiver (by name; "User not found" under it when they aren't)
	d:text(U.text("catalog.gift_wrapping.receiver", "Receiver (always add a Habbo name)"), 14.4, x, 37 + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local receiver = d:input("receiver", x, 57, cw, 28.9, { max = 50, onChange = function() GIFT.error = nil end })
	if GIFT.error then d:box(x, 57, cw, 28.9, 1, 3.2, U.C.danger, Color(0, 0, 0, 0)) end
	-- the gift tag: Habbo's card, your face on the left, the greeting, your name under it
	local gy = 94
	local gx = (d.width - 306) / 2
	d:icon("gift-card", gx, gy)
	local me = R.units and R.units[R.you]
	local AE = BOBBA.avatarEditor
	if GIFT.showFace and me and AE and AE.drawPreview then
		d:clip(gx + 12.5, gy + 50, 40, 50, function()
			AE.drawPreview(me.figure or "", me.gender or "M", 2, (gx + 12.5 + 20) * d.s, (gy + 50 - 18) * d.s, d.s)
		end)
	end
	local mx, my, mw = gx + 65 + 12, gy + 24, 306 - 65 - 12 - 24
	local msg = d:input("message", mx, my, mw, 149 - 24 - 24 - 20, { multiline = true, max = 140, bare = true,
		placeholder = U.text("catalog.gift_wrapping_new.message_hint", U.text("catalog.gift_wrapping.greetings", "Type your greetings here")) })
	d:text(U.text("catalog.gift_wrapping_new.message_from", "- %name%", { name = (me and me.name) or "" }), 14.4, gx + 306 - 24 - 4, gy + 149 - 24 - 8, U.C.black, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	-- show my face
	local cy = gy + 149 + 8
	d:click(x, cy, cw, 16, function() GIFT.showFace = not GIFT.showFace end)
	if GIFT.showFace then
		d:round(3.6, x, cy + 0.8, 14.4, 14.4, U.C.primary)
		d:line(x + 3.5, cy + 0.8 + 7.5, x + 6, cy + 0.8 + 10.2, 2, U.C.white)
		d:line(x + 6, cy + 0.8 + 10.2, x + 11, cy + 0.8 + 4.3, 2, U.C.white)
	else
		d:box(x, cy + 0.8, 14.4, 14.4, 1, 3.6, Color(0, 0, 0, 64), U.C.white)
	end
	d:text(d:fit(U.text("catalog.gift_wrapping.show_face.title", "Show my name and face on the gift tag"), 14.4, cw - 22), 14.4, x + 18.4, cy + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	-- the box: its picture, back and forward, its name and the price of wrapping
	local by = cy + 28
	local kind = SHOP.GIFT_BOXES[GIFT.box] or SHOP.GIFT_BOXES[1]
	d:clip(x, by, 80, 80, function() furniIcon(d, kind, x, by, 80, 80) end)
	local bx = x + 80 + 8
	d:btn(bx, by, 30, 28.9, U.C.primary, function() GIFT.box = (GIFT.box - 2) % #SHOP.GIFT_BOXES + 1 end)
	d:fa("chevron-left", bx + (30 - 12.6) / 2, by + (28.9 - 12.6) / 2, 12.6, U.C.white)
	d:btn(bx + 30, by, 30, 28.9, U.C.primary, function() GIFT.box = GIFT.box % #SHOP.GIFT_BOXES + 1 end)
	d:fa("chevron-right", bx + 30 + (30 - 12.6) / 2, by + (28.9 - 12.6) / 2, 12.6, U.C.white)
	local tx = bx + 60 + 8
	d:text(d:fit(U.text("catalog.gift_wrapping.pick_box", "Pick a box") .. " " .. GIFT.box .. "/" .. #SHOP.GIFT_BOXES, 14.4, d.width - 9 - tx, true), 14.4, tx, by + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
	d:text(U.text("catalog.gift_wrapping_new.freeprice", "Price: Free"), 14.4, tx, by + 8 + 20, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	-- what's wrong, cancel, give
	local fy = d.height - 8 - 28.9
	if GIFT.error then
		d:text(d:fit(GIFT.error, 12.6, cw), 12.6, x, fy - 10, U.C.danger, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local hover = d:click(x, fy, 80, 28.9, function() w:close() end)
	d:text(U.text("cancel", "Cancel"), 12.6, x + 8, fy + 14.45, hover and U.C.primary or U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local gw = d:textWidth(U.text("catalog.gift_wrapping.give_gift", "Give this gift"), 12.6) + 16
	d:btn(d.width - 9 - gw, fy, gw, 28.9, U.C.success, function()
		if GIFT.sending then return end
		local name = receiver:GetValue() or ""
		if name:match("^%s*$") then GIFT.error = U.text("catalog.gift_wrapping.receiver_not_found.title", "User not found") return end
		GIFT.sending = true
		P.send("catalog.gift", { page = GIFT.page, offer = offer.id, receiver = name, message = msg:GetValue() or "",
			box = GIFT.box, showFace = GIFT.showFace, extra = offer.trophy and CAT.trophyText or nil })
	end, GIFT.sending)
	d:text(U.text("catalog.gift_wrapping.give_gift", "Give this gift"), 12.6, d.width - 9 - gw / 2, fy + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- CatalogLayoutDefaultView: the offers (5 to a row), the chosen one on the right
local function drawDefault(d, page, offers)
	local trophies = page.layout == "trophies"
	local gx, gy, gw, gh = 164, 75, 263.3, 391 - 75
	local n, cw = columns(gw)
	local rows = math.ceil(#offers / n)
	-- CatalogLayoutTrophiesView: the grid, and under it the words to engrave (a text box that takes
	-- the rest of the height)
	if trophies then
		gh = math.min(rows * 48 - 8, 316 - 8 - 80)
		local ty = gy + gh + 8
		local box = d:input("trophy", gx, ty, gw, 391 - ty, { multiline = true, max = 300, onChange = function(t) CAT.trophyText = t end })
		CAT.trophyText = box:GetValue() or ""
	end
	local off = d:scroll("offers", gx, gy, gw, gh, rows * 48 - 8)
	d:clip(gx, gy, gw, gh, function()
		for i, o in ipairs(offers) do
			local col, row = (i - 1) % n, math.floor((i - 1) / n)
			local x, y = gx + col * (cw + 8), gy + row * 48 - off
			if y + 40 > gy and y < gy + gh then
				local active = CAT.offer == o.id and CAT.offerPage == (o.page or page.id)
				d:click(x, y, cw, 40, function()
					if not active then CAT.quantity, CAT.state = 1, "none" end
					CAT.offer, CAT.offerPage = o.id, o.page or page.id
				end)
				d:gridItem(x, y, cw, 40, active)
				if o.kind then d:clip(x + 2, y + 2, cw - 4, 36, function() furniIcon(d, o.kind, x, y, cw, 40, nil, o.data) end) end
				-- (teleports come two to an offer: PRICING_MODEL_MULTI's count)
				if o.pair then countBadge(d, 2, x + cw - 4, y + 4) end
			end
		end
	end)
	local offer
	for _, o in ipairs(offers) do if o.id == CAT.offer and (o.page or page.id) == CAT.offerPage then offer = o end end
	if not offer then return end
	local rx, rw = 435.3, 185.8
	previewBox(d, rx, 75, rw, 140, offer.kind, offer.data)
	d:text(d:fit((offer.kind and not offer.data) and furniName(offer.kind) or offer.name, 14.4, rw), 14.4, rx, 223 + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if trophies then
		-- (no amount: one trophy, its price at the right above Buy)
		local prices = priceRows(offer, 1)
		for i, r in ipairs(prices) do priceRow(d, r[1], r[2], rx + rw, 309.2 - (#prices - i) * 20, true) end
		buyButton(d, rx, 329.2, rw, 28.9, offer, 1, U.C.primary, page)
		SHOP.giftButton(d, rx, 362.1, rw, offer, page, 1)
		return
	end
	-- the amount (CatalogSpinnerWidgetView: 1 to 100)
	d:text(U.text("catalog.bundlewidget.spinner.select.amount", "Amount:"), 14.4, rx, 288.2 + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local function setQuantity(q) CAT.quantity = math.Clamp(q, 1, 100) if CAT.state ~= "purchase" then CAT.state = "none" end end
	d:click(rx, 308, 14.4, 17, function() setQuantity(CAT.quantity - 1) end)
	caret(d, rx, 309.5, 14.4, true, U.C.black)
	d:box(453.6, 308.2, 28, 17, 1, 3.2, U.C.inputBorder, U.C.white)
	d:text(tostring(CAT.quantity), 12.6, 453.6 + 28 - 5, 308.2 + 8.5, U.C.black, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	d:click(485.6, 308, 14.4, 17, function() setQuantity(CAT.quantity + 1) end)
	caret(d, 485.6, 309.5, 14.4, false, U.C.black)
	-- the price, right, at the bottom of that row
	local prices = priceRows(offer, CAT.quantity)
	for i, r in ipairs(prices) do priceRow(d, r[1], r[2], rx + rw, 309.2 - (#prices - i) * 20, true) end
	buyButton(d, rx, 329.2, rw, 28.9, offer, CAT.quantity, U.C.primary, page)
	SHOP.giftButton(d, rx, 362.1, rw, offer, page, CAT.quantity)
end

-- ClubOfferData: 31 days a month
local function clubText(days)
	local months, extra = math.floor(days / 31), days % 31
	local t = ""
	if months > 0 then t = U.text("catalog.vip.item.header.months", "%num_months% months", { num_months = months }) end
	if extra > 0 then t = (t ~= "" and (t .. " ") or "") .. U.text("catalog.vip.item.header.days", "%num_days% days", { num_days = extra }) end
	return t
end


-- CatalogLayoutVipBuyView: the club offers on the left, what you'd get on the right
-- a club's texts: Habbo's are about HC; for VIP they say VIP
local function clubWords(t, kind)
	if kind ~= "vip" then return t end
	return (t:gsub("Habbo Club", "VIP"):gsub("%f[%w]HC%f[%W]", "VIP"))
end

local function drawVip(d, page)
	local kind = page.clubKind or "hc"
	local lx, lw = 164, 263.3
	local chosen
	for i, o in ipairs(page.offers or {}) do
		local y = 75 + (i - 1) * 58
		local active = CAT.offer == o.id
		if active then chosen = o end
		d:click(lx, y, lw, 50, function() if not active then CAT.state = "none" end CAT.offer, CAT.offerPage = o.id, page.id end)
		d:gridItem(lx, y, lw, 50, active)
		d:icon(kind == "vip" and "vip-banner" or "hc-banner", lx + 6, y + 5, 68, 40)
		d:text(clubText(o.club), 14.4, lx + lw - 6, y + 9 + 8, U.C.black, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		for _, r in ipairs(priceRows(o, 1)) do priceRow(d, r[1], r[2], lx + lw - 6, y + 25, false) end
	end
	local hc = lines(d, clubWords(U.plain(U.text("catalog.vip.buy.hccenter", "Habbo Club gives you more clothes, room models and more.")), kind), 14.4, lw)
	for i, l in ipairs(hc) do d:text(l, 14.4, lx + lw / 2, 391 - (#hc - i) * 16 - 8, U.C.black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
	-- the right: how much club is left; the chosen offer's end date, price and Buy
	local rx, rw = 435.3, 185.8
	local purse = HUD.purse
	-- (extending: this club is the one you have)
	local extending = (purse.clubLevel or 0) > 0 and (purse.clubKind or "hc") == kind
	-- (a member sees how long is left; anyone else what club gives, as Habbo's page says)
	local info = extending and U.text("catalog.vip.extend.info", "You have %days% days of Habbo Club left.", { days = purse.clubDays or 0 })
		or U.text("catalog.vip.buy.info", "Get exclusive clothes and hair styles and so much more!")
	local details = lines(d, clubWords(U.plain(info), kind), 14.4, rw)
	-- the chosen offer at the bottom (Flex align end): what it is and until when on the left, wrapping,
	-- the price on the right; then Buy
	local head, untilLines, prices = {}, {}, {}
	if chosen then
		local months = math.floor(chosen.club / 31)
		local unit = months > 0 and "months" or "days"
		local headText = U.text("catalog.vip.buy.confirm." .. (extending and "extension." or "subscription.") .. unit,
			(extending and "%NUM_" .. unit:upper() .. "%-" .. unit:sub(1, -2) .. " HC extension" or "%NUM_" .. unit:upper() .. "%-" .. unit:sub(1, -2) .. " HC subscription"))
		headText = headText:gsub("%%NUM_" .. unit:upper() .. "%%", tostring(months > 0 and months or chosen.club))
		local ends = os.date("*t", os.time() + ((purse.clubMinutes or 0) * 60) + chosen.club * 86400)
		local untilText = U.text("catalog.vip.buy.confirm.end_date", "Valid until: %month%/%day%/%year%")
		untilText = untilText:gsub("%%month%%", tostring(ends.month)):gsub("%%day%%", tostring(ends.day)):gsub("%%year%%", tostring(ends.year))
		prices = priceRows(chosen, 1)
		local pw = 0
		for _, r in ipairs(prices) do pw = math.max(pw, d:textWidth(tostring(r[2]), 14.4) + 4 + 15) end
		local tw = rw - pw - 8
		head = lines(d, clubWords(U.plain(headText), kind), 14.4, tw, true)
		untilLines = lines(d, U.plain(untilText), 14.4, tw)
	end
	local textRows = #head + #untilLines
	local blockTop = chosen and (362.1 - 8 - math.max(textRows * 16, #prices * 20 - 4)) or 391
	local ty = 75 + (blockTop - 8 - 75 - #details * 16) / 2
	for i, l in ipairs(details) do d:text(l, 14.4, rx + rw / 2, ty + (i - 1) * 16 + 8, U.C.black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
	if not chosen then return end
	local y = 362.1 - 8 - textRows * 16
	for _, l in ipairs(head) do d:text(l, 14.4, rx, y + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true) y = y + 16 end
	for _, l in ipairs(untilLines) do d:text(l, 14.4, rx, y + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) y = y + 16 end
	for i, r in ipairs(prices) do priceRow(d, r[1], r[2], rx + rw, 362.1 - 8 - 16 - (#prices - i) * 20, false) end
	buyButton(d, rx, 362.1, rw, 28.9, chosen, 1, U.C.success, page, "buy")
end

local function drawCatalog(w, d)
	local tabs
	if CAT.pages then
		tabs = {}
		for _, t in ipairs(CAT.pages) do tabs[#tabs + 1] = { id = t.id, label = t.name } end
	end
	d:card(U.text("catalog.title", "Catalogue"), tabs, CAT.tab, function(id)
		local box = w.inputs and w.inputs.search
		if IsValid(box) then box:SetValue("") end
		SHOP.openPage(id)
	end)
	-- the search and the pages
	d:input("search", 9, 75, 113, 28.9, { placeholder = U.text("generic.search", "Search..."), max = 100, onChange = searchChanged })
	searchButton(d, 126, 75, 30, 28.9, function()
		local box = w.inputs and w.inputs.search
		if IsValid(box) then searchChanged(box:GetValue() or "") CAT.searchAt = SysTime() end
	end)
	d:box(9, 111.9, 147, 279.1, 2, 4, U.C.muted, U.C.gridItem)
	local nx, ny, nw, nh = 15, 117.9, 135, 279.1 - 12
	local navList
	if CAT.search then
		navList = {}
		for _, id in ipairs(CAT.search.pages or {}) do
			local p = findPage(CAT.pages, id)
			if p then navList[#navList + 1] = { id = p.id, name = p.name, icon = p.icon, iconKind = p.iconKind, iconName = p.iconName } end
		end
	else
		local tab = CAT.tab and findPage(CAT.pages, CAT.tab)
		navList = tab and tab.children or {}
	end
	local off = d:scroll("nav", nx, ny, nw, nh, navHeight(navList) - 4)
	d:clip(nx, ny, nw, nh, function() drawNavItems(d, navList, nx, ny - off, nw, ny + nh, ny) end)
	-- the page
	if CAT.search then
		drawDefault(d, { id = -1 }, CAT.search.offers or {})
	elseif CAT.page and CAT.page.id == CAT.active then
		if CAT.page.layout == "vip_buy" then drawVip(d, CAT.page) else drawDefault(d, CAT.page, CAT.page.offers or {}) end
	end
end

-- the club's tab (the last one)
local function clubTab()
	return CAT.pages and CAT.pages[#CAT.pages]
end

-- a new club mode: the catalogue's club pages are different now
BOBBA.events.on("purseChanged", "bobba.shop.club", function(p)
	if CAT.mode and CAT.mode ~= p.clubMode then
		CAT.pages, CAT.page, CAT.active, CAT.tab, CAT.asked = nil, nil, nil, nil, nil
		if U.windows.catalog then P.send("catalog.index", {}) end
	end
	CAT.mode = p.clubMode
end)

-- opens the catalogue (at a tab, by its name, or "club": the club's tab)
-- the catalogue changed (a season began or ended, an admin changed it): asked for again
local function catalogChanged()
	CAT.pages, CAT.page, CAT.active, CAT.tab, CAT.asked, CAT.search = nil, nil, nil, nil, nil, nil
	if U.windows.catalog then P.send("catalog.index", {}) end
end
P.receive("catalog.changed", catalogChanged)

function SHOP.openCatalog(tabName)
	if not U.windows.catalog then
		-- (each time it opens: what's in it may have changed with the date, a season)
		if CAT.pages and CAT.openedDay ~= os.date("%Y-%m-%d") then
			CAT.pages, CAT.page, CAT.active, CAT.tab, CAT.asked, CAT.search = nil, nil, nil, nil, nil, nil
		end
		CAT.openedDay = os.date("%Y-%m-%d")
		U.window("catalog", 630, 400, drawCatalog)
	end
	if not CAT.pages then
		CAT.wantTab = tabName
		P.send("catalog.index", {})
	elseif tabName == "club" then
		local t = clubTab()
		if t then SHOP.openPage(t.id) end
	elseif tabName then
		for _, t in ipairs(CAT.pages) do if t.name == tabName then SHOP.openPage(t.id) end end
	end
end

HUD.actions.catalog = function()
	if U.windows.catalog then U.windows.catalog:close() return end
	SHOP.openCatalog()
end
HUD.actions.club = function() SHOP.openCatalog("club") end
concommand.Add("bobba_catalog", function() SHOP.openCatalog() end)
