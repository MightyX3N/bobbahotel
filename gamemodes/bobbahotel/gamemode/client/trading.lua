-- Trading (client; hotel/trading.lua is the server's side). Opened from the avatar menu's Trade.
--   the classic look: nitro-react's InventoryTradeView in the inventory window (its primary-slim
--     card while trading): your furni on the left (a search, offer one or all of a kind), what you're
--     offering and what they're offering on the right, nine slots each with a lock (accepted or not),
--     Cancel, and Accept / Modify -> the 3 second countdown -> Confirm -> waiting for them
--   the phone: the Bag app's trade view: what you offer (add from your bag), what they offer,
--     the same steps
-- Messages: see hotel/trading.lua.

BOBBA.trade = BOBBA.trade or {}
local TR = BOBBA.trade
local P = BOBBA.platform
local U = BOBBA.ui
local SHOP = BOBBA.shop
local T = function(k, f, v) return U.text(k, f, v) end

TR.COUNTDOWN = 3

-- what step I'm at: "offer", "countdown" (both accepted, 3 2 1), "confirm", "waiting" (I confirmed)
function TR.step()
	local st = TR.state
	if not st then return nil end
	if st.stage == "offer" then return "offer" end
	if st.confirmed then return "waiting" end
	if SysTime() - (TR.confirmAt or 0) < TR.COUNTDOWN then return "countdown" end
	return "confirm"
end
function TR.countdown() return math.max(1, math.ceil(TR.COUNTDOWN - (SysTime() - (TR.confirmAt or 0)))) end

-- the furni grouped by kind (a wallpaper with its pattern), like the inventory's
function TR.group(list)
	local by, out = {}, {}
	for _, it in ipairs(list or {}) do
		local paint = SHOP.paintOf and SHOP.paintOf(it.kind)
		local key = (paint and it.data) and (it.kind .. "|" .. it.data) or it.kind
		local g = by[key]
		if not g then
			g = { kind = it.kind, key = key, ids = {}, data = paint and it.data or nil }
			by[key] = g
			out[#out + 1] = g
		end
		g.ids[#g.ids + 1] = it.id
	end
	return out
end

-- my inventory's groups, without what's already offered (Nitro's getUnlockedCount)
function TR.mine()
	local offered = {}
	for _, it in ipairs(TR.state and TR.state.mine or {}) do offered[it.id] = true end
	local out = {}
	for _, g in ipairs(SHOP.groups()) do
		local ids = {}
		for _, id in ipairs(g.ids) do if not offered[id] then ids[#ids + 1] = id end end
		out[#out + 1] = { kind = g.kind, key = g.key, data = g.data, ids = ids, total = #g.ids }
	end
	return out
end

function TR.offer(g, n)
	if not g or #g.ids == 0 then return end
	local ids = {}
	for i = 1, math.min(n or 1, #g.ids) do ids[i] = g.ids[i] end
	P.send("trade.offer", { ids = ids })
end
function TR.take(g) if g and #g.ids > 0 then P.send("trade.take", { ids = { g.ids[#g.ids] } }) end end
function TR.cancel() if TR.state then P.send("trade.cancel", {}) end end
-- the big button: accept / modify, then confirm
function TR.progress()
	local st = TR.state
	if not st then return end
	local step = TR.step()
	if step == "offer" then
		-- (Nitro: a word when they offer nothing)
		if #(st.theirs or {}) == 0 and not st.accepted then TR.say(T("inventory.trading.warning.other_not_offering", "The other user has not offered anything.")) end
		P.send("trade.accept", { on = not st.accepted })
	elseif step == "confirm" then
		P.send("trade.confirm", {})
		st.confirmed = true
	end
end

function TR.start(other) P.send("trade.open", { unit = other }) end

-- --- telling the player ---------------------------------------------------------------------------
local function phone() return BOBBA.device and BOBBA.device.active and BOBBA.device.active() end
function TR.say(text, title)
	title = title or T("inventory.trading.title", "Trading")
	if phone() then BOBBA.device.notify({ app = "bag", title = title, text = text })
	else U.alert(title, text) end
end

P.receive("trade.state", function(_, data)
	local was = TR.state
	if data.stage == "confirm" and (not was or was.stage ~= "confirm") then TR.confirmAt = SysTime() end
	TR.state = data
	if not was then
		if SHOP.inventoryOpened then SHOP.inventoryOpened() end
		TR.selected, TR.mineSel, TR.theirSel = nil, nil, nil
		if phone() then TR.openPhone() elseif TR.openClassic then TR.openClassic() end
	end
end)
P.receive("trade.closed", function(_, data)
	local st = TR.state
	TR.state = nil
	local name = st and st.other and st.other.name or ""
	if data.why == "done" then
		TR.say(T("inventory.trading.info.closed", "The trade is done."), T("inventory.trading.completed", "Trade completed"))
	elseif data.why == "failed" then
		TR.say(T("inventory.trading.info.failed", "The trade didn't go through: something in it isn't there any more."))
	elseif data.by and data.by ~= "" and data.by == name then
		-- (they cancelled, or went)
		TR.say(data.why == "left" and T("inventory.trading.info.left", "%name% left, so the trade is off.", { name = name })
			or T("inventory.trading.info.cancelled", "%name% cancelled the trade.", { name = name }))
	end
	if TR.closeClassic then TR.closeClassic() end
	if TR.closePhone then TR.closePhone() end
end)
P.receive("trade.error", function(_, data)
	TR.say((tostring(data.message or ""):gsub("^%l", string.upper)))
end)

-- --- the classic look (InventoryTradeView, 528 x 320) ------------------------------------------------
-- FaLock (green) / FaUnlock (red), 12 high
local function lock(d, x, y, locked)
	local c = locked and U.C.success or U.C.danger
	d:round(1.5, x, y + 5, 10, 7, c)
	local ax = locked and x + 2 or x + 5
	d:rect(ax, y + 1, 1.6, 5, c)
	d:rect(ax + 4.4, y + 1, 1.6, locked and 5 or 2, c)
	d:rect(ax, y, 6, 1.6, c)
	d:rect(x + 4.2, y + 7.5, 1.6, 2.5, U.C.white)
end
-- a small button with a chevron (the trade-button)
local function chevronButton(d, x, y, color, right, fn)
	d:btn(x, y, 14, 12, color, fn)
	d:fa(right and "chevron-right" or "chevron-left", x + 3, y + 1.5, 9, U.C.white)
end
-- the name under a grid (badge bg-muted)
local function badge(d, x, y, w, text)
	d:round(4, x, y, w, 18, U.C.muted)
	d:text(d:fit(text, 11.5, w - 8, true), 11.5, x + w / 2, y + 9, U.C.black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
end
local function selectName(g) return g and SHOP.groupName(g) or T("catalog_selectproduct", "Select a product") end

-- nine slots, three a row
local function slots(d, x, y, w, groups, selKey, onClick, onDouble, removable)
	local cw = (w - 16) / 3
	for i = 1, 9 do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local sx, sy = x + col * (cw + 8), y + row * 46
		local g = groups[i]
		local active = g and g.key == selKey
		d:gridItem(sx, sy, cw, 40, active)
		if g then
			d:click(sx, sy, cw, 40, function()
				local now = SysTime()
				if onDouble and TR.lastSlot == g.key and now - (TR.lastSlotAt or 0) < 0.4 then onDouble(g) return end
				TR.lastSlot, TR.lastSlotAt = g.key, now
				onClick(g)
			end)
			d:clip(sx + 2, sy + 2, cw - 4, 36, function() SHOP.furniIcon(d, g.kind, sx, sy, cw, 40, nil, g.data) end)
			if #g.ids > 1 then SHOP.countBadge(d, #g.ids, sx + cw - 4, sy + 4) end
			if active and removable then chevronButton(d, sx + 4, sy + 40 - 16, U.C.danger, false, function() TR.take(g) end) end
		end
	end
	return 3 * 46 - 6
end

function TR.drawClassic(w, d)
	local st = TR.state
	if not st then return end
	d:slimCard(T("inventory.title", "Inventory"))
	local step = TR.step()
	local canChange = step == "offer" and not st.accepted
	-- left (4 of 12): your furni
	local lx, lw = 9, 160
	local search = d:input("trade-search", lx, 39, lw - 32, 28.9, { placeholder = T("generic.search", "Search"), max = 100 })
	SHOP.searchButton(d, lx + lw - 28.6, 39, 28.6, 28.9, function() end)
	local filter = (search:GetValue() or ""):lower()
	local list = {}
	for _, g in ipairs(TR.mine()) do
		if filter == "" or SHOP.groupName(g):lower():find(filter, 1, true) then list[#list + 1] = g end
	end
	local chosen
	for _, g in ipairs(list) do if g.key == TR.selected then chosen = g end end
	local gy, gh = 39 + 28.9 + 8, 311 - 52 - (39 + 28.9 + 8)
	local cw = (lw - 16) / 3
	local rows = math.ceil(#list / 3)
	local off = d:scroll("trade-mine", lx, gy, lw, gh, rows * 48 - 8)
	d:clip(lx, gy, lw, gh, function()
		for i, g in ipairs(list) do
			local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
			local x, y = lx + col * (cw + 8), gy + row * 48 - off
			if y + 40 > gy and y < gy + gh then
				local count = #g.ids
				local active = g == chosen
				d:click(x, y, cw, 40, function()
					if count == 0 then return end
					local now = SysTime()
					if canChange and TR.lastMine == g.key and now - (TR.lastMineAt or 0) < 0.4 then TR.offer(g, 1) return end
					TR.lastMine, TR.lastMineAt = g.key, now
					TR.selected = g.key
				end)
				d:gridItem(x, y, cw, 40, active)
				d:clip(x + 2, y + 2, cw - 4, 36, function() SHOP.furniIcon(d, g.kind, x, y, cw, 40, count == 0 and 0.5 or nil, g.data) end)
				if count > 1 then SHOP.countBadge(d, count, x + cw - 4, y + 4) end
				if active and count > 0 and canChange then chevronButton(d, x + cw - 18, y + 40 - 16, U.C.success, true, function() TR.offer(g, 1) end) end
			end
		end
	end)
	-- (one, or all of the kind)
	local by = 311 - 52 + 6
	local bw = (lw - 4) / 2
	local can = chosen and #chosen.ids > 0 and canChange
	d:btn(lx, by, bw, 24, U.C.secondary, function() if can then TR.offer(chosen, 1) end end, not can)
	d:text(T("inventory.trading.offerone", "Offer 1"), 11.5, lx + bw / 2, by + 12, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	d:btn(lx + bw + 4, by, bw, 24, U.C.secondary, function() if can then TR.offer(chosen, #chosen.ids) end end, not can)
	d:text(T("inventory.trading.offerall", "Offer all"), 11.5, lx + bw + 4 + bw / 2, by + 12, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	badge(d, lx, 311 - 18, lw, selectName(chosen))
	-- right (8 of 12): yours and theirs
	local rx, rw = lx + lw + 8, 528 - 9 - (lx + lw + 8)
	local half = (rw - 8) / 2
	local mine, theirs = TR.group(st.mine), TR.group(st.theirs)
	local function sel(groups, key) for _, g in ipairs(groups) do if g.key == key then return g end end end
	-- you
	d:text(d:fit(T("inventory.trading.you", "You") .. " " .. T("inventory.trading.areoffering", "are offering") .. ":", 12.6, half - 18), 12.6, rx, 47, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	lock(d, rx + half - 11, 41, st.accepted)
	slots(d, rx, 58, half, mine, TR.mineSel, function(g) TR.mineSel = g.key end, canChange and TR.take or nil, canChange)
	badge(d, rx, 58 + 138 + 6, half, selectName(sel(mine, TR.mineSel)))
	-- them
	local ox = rx + half + 8
	d:text(d:fit((st.other and st.other.name or "") .. " " .. T("inventory.trading.isoffering", "is offering") .. ":", 12.6, half - 18), 12.6, ox, 47, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	lock(d, ox + half - 11, 41, st.theyAccepted)
	slots(d, ox, 58, half, theirs, TR.theirSel, function(g) TR.theirSel = g.key end)
	badge(d, ox, 58 + 138 + 6, half, selectName(sel(theirs, TR.theirSel)))
	-- Cancel, and the step's button
	local yb = 311 - 28.9
	d:btn(rx, yb, 80, 28.9, U.C.danger, function() TR.cancel() end)
	d:text(T("generic.cancel", "Cancel"), 12.6, rx + 40, yb + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local label, disabled
	local empty = #(st.mine or {}) == 0 and #(st.theirs or {}) == 0
	if step == "offer" then label, disabled = st.accepted and T("inventory.trading.modify", "Modify trade") or T("inventory.trading.accept", "Accept trade"), empty
	elseif step == "countdown" then label, disabled = T("inventory.trading.countdown", "Trading in %counter%...", { counter = TR.countdown() }), true
	elseif step == "confirm" then label = T("inventory.trading.button.restore", "Confirm trade")
	else label, disabled = T("inventory.trading.info.waiting", "Waiting for the other user..."), true end
	local lw2 = math.max(110, d:textWidth(label, 12.6) + 26)
	d:btn(rx + rw - lw2, yb, lw2, 28.9, U.C.secondary, function() TR.progress() end, disabled)
	d:text(label, 12.6, rx + rw - lw2 / 2, yb + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- the inventory's window shows the trade while there is one (Nitro: isTrading)
function TR.openClassic()
	local w = U.windows.inventory
	if not w then
		if BOBBA.hud and BOBBA.hud.actions and BOBBA.hud.actions.inventory then BOBBA.hud.actions.inventory() end
	end
end
function TR.closeClassic() end

-- --- the phone: the Bag app's trade view --------------------------------------------------------------
local DV = BOBBA.device
if not DV then return end
local C = DV.C

local function grid(ctx, d, x, y, w, groups, cols, onTap, empty)
	if #groups == 0 then
		d:round(18, x, y, w, 70, C.line)
		d:text(empty, 13, x + w / 2, y + 35, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		return 70
	end
	local gap = 10
	local cw = (w - (cols - 1) * gap) / cols
	for i, g in ipairs(groups) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local gx, gy = x + col * (cw + gap), y + row * (cw + gap)
		local hov = onTap and d:click(gx, gy, cw, cw, function() onTap(g) end)
		d:round(16, gx, gy, cw, cw, hov and C.mist or C.white)
		d:clip(gx + 4, gy + 4, cw - 8, cw - 8, function() d:furni(g.kind, gx, gy, cw, cw, g.data) end)
		if #g.ids > 1 then
			local t = "×" .. #g.ids
			local tw = d:textWidth(t, 11, 800) + 14
			d:pill(gx + cw - tw - 5, gy + 5, tw, 20, C.navy)
			d:text(t, 11, gx + cw - tw / 2 - 5, gy + 15, C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
		end
	end
	local rows = math.ceil(#groups / cols)
	return rows * (cw + gap) - gap
end

-- your bag: tap one to put it in
local function pickView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	d:rect(0, 0, W, H, C.paper)
	if not TR.state then ctx:pop() return end
	local top = ctx.top + ctx:header(T("bobba.phone.trade.add", "Add to the trade"))
	local x, w = 20, W - 40
	if ctx.kind == "tablet" then x, w = 40, W - 80 end
	local list = {}
	for _, g in ipairs(TR.mine()) do if #g.ids > 0 then list[#list + 1] = g end end
	local cols = ctx.kind == "tablet" and 7 or 3
	local off = d:scroll("trade-pick", 0, top + 10, W, H - top - 10, math.ceil(#list / cols) * ((w - (cols - 1) * 10) / cols + 10) + 40)
	d:clip(0, top + 10, W, H - top - 10, function()
		grid(ctx, d, x, top + 10 - off, w, list, cols, function(g) TR.offer(g, 1) end, T("bobba.phone.trade.nothing", "Nothing left in your bag to trade."))
	end)
end

local function tradeView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local st = TR.state
	d:rect(0, 0, W, H, C.paper)
	if not st then
		local top = ctx.top + ctx:header(T("inventory.trading.title", "Trading"))
		d:text(T("bobba.phone.trade.over", "The trade is over."), 14, W / 2, top + 60, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		return
	end
	local top = ctx.top + ctx:header(T("bobba.phone.trade.with", "Trade with %name%", { name = st.other and st.other.name or "" }), { back = function() TR.cancel() ctx:pop() end })
	local x, w = 20, W - 40
	if ctx.kind == "tablet" then x, w = math.max(20, (W - 640) / 2), math.min(640, W - 40) end
	local cols = ctx.kind == "tablet" and 6 or 4
	local step = TR.step()
	local canChange = step == "offer" and not st.accepted
	local bottomH = 140
	local off = d:scroll("trade", 0, top, W, H - top - bottomH, TR.phoneH or 0)
	d:clip(0, top, W, H - top - bottomH, function()
		local y = top + 10 - off
		-- yours
		d:text(T("bobba.phone.trade.you", "You offer"), 13, x + 4, y + 8, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
		local s1 = st.accepted and T("bobba.phone.trade.ready", "Ready") or ""
		d:text(s1, 13, x + w - 4, y + 8, C.green, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 800)
		y = y + 22
		y = y + grid(ctx, d, x, y, w, TR.group(st.mine), cols, canChange and function(g) TR.take(g) end or nil,
			T("bobba.phone.trade.offernothing", "Nothing yet")) + 10
		if canChange then
			d:button(x, y, w, 44, T("bobba.phone.trade.add", "Add to the trade"), "light", function() ctx:push(pickView, {}) end)
			y = y + 54
			d:text(T("bobba.phone.trade.taphint", "Tap one of yours to take it back out."), 12, x + 4, y, C.slate)
			y = y + 26
		end
		-- theirs
		y = y + 8
		d:text(T("bobba.phone.trade.they", "%name% offers", { name = st.other and st.other.name or "" }), 13, x + 4, y + 8, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
		d:text(st.theyAccepted and T("bobba.phone.trade.ready", "Ready") or "", 13, x + w - 4, y + 8, C.green, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 800)
		y = y + 22
		y = y + grid(ctx, d, x, y, w, TR.group(st.theirs), cols, nil, T("bobba.phone.trade.offernothing", "Nothing yet")) + 20
		TR.phoneH = y + off - top
	end)
	-- the steps
	local by = H - bottomH + 12
	local say
	if step == "offer" then
		say = st.accepted and (st.theyAccepted and "" or T("bobba.phone.trade.waitaccept", "Waiting for them to accept"))
			or (st.theyAccepted and T("bobba.phone.trade.theyaccepted", "They've accepted. Accept too?") or T("bobba.phone.trade.offerhint", "Both accept, then both confirm."))
	elseif step == "countdown" then say = T("bobba.phone.trade.check", "Check what's in it one more time")
	elseif step == "confirm" then say = T("bobba.phone.trade.confirmhint", "Confirm and the furni change hands")
	else say = T("inventory.trading.info.waiting", "Waiting for the other user...") end
	d:textFit(say, 13, w, x + w / 2, by + 8, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
	local half = (w - 10) / 2
	d:button(x, by + 26, half, 52, T("generic.cancel", "Cancel"), "light", function() TR.cancel() end)
	local label, style, disabled = nil, "primary", false
	local empty = #(st.mine or {}) == 0 and #(st.theirs or {}) == 0
	if step == "offer" then label, disabled = st.accepted and T("bobba.phone.trade.change", "Change") or T("bobba.phone.trade.accept", "Accept"), empty
	elseif step == "countdown" then label, disabled = tostring(TR.countdown()), true
	elseif step == "confirm" then label, style = T("bobba.phone.trade.confirm", "Confirm"), "green"
	else label, disabled = T("bobba.phone.trade.waiting", "Waiting..."), true end
	d:button(x + half + 10, by + 26, half, 52, label, style, function() TR.progress() end, disabled)
end

function TR.openPhone() DV.openApp("bag", tradeView, {}) end
function TR.closePhone()
	-- (the trade's screen showing: back to the bag)
	if DV.stack and DV.stack.app and DV.stack.app.id == "bag" and DV.stack.screens then
		for _, s in ipairs(DV.stack.screens) do
			if s.view == tradeView or s.view == pickView then DV.openApp("bag") return end
		end
	end
end
