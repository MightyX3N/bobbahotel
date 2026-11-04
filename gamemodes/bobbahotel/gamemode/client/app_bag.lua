-- The Bag app (the phone's inventory): your furni, grouped by kind, a search; one opened shows its
-- picture and "Place in room" (the furni follows the mouse in the room). client/shop.lua has the data.

local DV = BOBBA.device
local U = BOBBA.ui
local R = BOBBA.room
local V = BOBBA.view
local SHOP = BOBBA.shop
local C, G = DV.C, DV.G
local alpha = DV.alpha
local T = function(k, f, v) return U.text(k, f, v) end

local function place(g)
	DV.home()
	DV.show(false)
	SHOP.place(g)
end

-- one kind of furni: the picture, how many, place it
local function furniView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local key = ctx.state.key
	local g
	for _, x in ipairs(SHOP.groups()) do if x.key == key then g = x end end
	d:rect(0, 0, W, H, C.paper)
	local top = ctx.top + ctx:header(g and SHOP.groupName(g) or T("bobba.phone.app.bag", "Bag"))
	if not g then
		d:text(T("bobba.phone.bag.gone", "You don't have this any more."), 14, W / 2, top + 60, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		return
	end
	for _, id in ipairs(g.ids) do SHOP.inv.unseen[id] = nil end
	local x, w = 20, W - 40
	if ctx.kind == "tablet" then x, w = math.max(20, (W - 560) / 2), math.min(560, W - 40) end
	local ph = math.min(300, H * 0.38)
	d:round(28, x, top + 10, w, ph, C.line)
	ctx.state.dir = ctx.state.dir or 2
	d:clip(x, top + 10, w, ph, function() d:furni(g.kind, x, top + 10, w, ph, g.data, true, ctx.state.dir) end)
	-- (turn it)
	DV.turnButton(d, x + w - 56, top + 10 + ph - 56, function() ctx.state.dir = (ctx.state.dir + 2) % 8 end)
	local y = top + 10 + ph + 20
	d:text(SHOP.groupName(g), 22, x, y, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	y = y + 34
	d:text(T("bobba.phone.bag.have", "You have %count%", { count = #g.ids }), 14, x, y, C.ink2)
	y = y + 40
	if V.mode == "room" and R.current then
		d:button(x, y, w, 52, T("inventory.furni.placetoroom", "Place in room"), "primary", function() place(g) end)
	else
		d:round(20, x, y, w, 52, C.line)
		d:text(T("bobba.phone.bag.goroom", "Go to a room to place it"), 14, x + w / 2, y + 26, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
	end
end

local function bagView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local st = ctx.state
	if not st.started then st.started = true SHOP.inventoryOpened() end
	d:rect(0, 0, W, H, C.paper)
	local tablet = ctx.kind == "tablet"
	local top = ctx.top + ctx:header(T("bobba.phone.app.bag", "Bag"), { big = true })
	local x, w = 20, W - 40
	if tablet then x, w = 40, W - 80 end
	local e = d:input("bagsearch", x, top + 4, w, 44, { placeholder = T("bobba.phone.bag.search", "Search your furni"), max = 100 })
	local filter = (e:GetValue() or ""):lower()
	local y = top + 4 + 44 + 14
	local list = {}
	for _, g in ipairs(SHOP.groups()) do
		if filter == "" or SHOP.groupName(g):lower():find(filter, 1, true) then list[#list + 1] = g end
	end
	if not SHOP.inv.loaded then
		d:text(T("bobba.phone.loading", "Loading…"), 14, W / 2, y + 40, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		return
	end
	if #list == 0 then
		local msg = filter ~= "" and T("bobba.phone.bag.nomatch", "Nothing by that name.") or T("bobba.phone.bag.empty", "Your bag is empty. Furni you buy or get come here.")
		for i, l in ipairs(d:wrap(msg, 14, w - 40)) do d:text(l, 14, W / 2, y + 40 + (i - 1) * 20, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600) end
		return
	end
	local cols = tablet and 7 or 3
	local gap = 12
	local cw = (w - (cols - 1) * gap) / cols
	local ch = cw + 26
	local rows = math.ceil(#list / cols)
	local off = d:scroll("bag", 0, y, W, H - y, rows * (ch + gap) + 30)
	d:clip(0, y, W, H - y, function()
		for i, g in ipairs(list) do
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			local gx, gy = x + col * (cw + gap), y + row * (ch + gap) - off
			if gy + ch > y and gy < H then
				local unseen = false
				for _, id in ipairs(g.ids) do if SHOP.inv.unseen[id] then unseen = true end end
				local hov = d:click(gx, gy, cw, ch, function() ctx:push(furniView, { key = g.key }) end)
				d:round(18, gx, gy, cw, cw, hov and C.mist or C.white)
				d:clip(gx + 4, gy + 4, cw - 8, cw - 8, function() d:furni(g.kind, gx, gy, cw, cw, g.data) end)
				if #g.ids > 1 then
					local t = "×" .. #g.ids
					local tw = d:textWidth(t, 11, 800) + 14
					d:pill(gx + cw - tw - 6, gy + 6, tw, 20, C.navy)
					d:text(t, 11, gx + cw - tw / 2 - 6, gy + 16, C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
				end
				if unseen then d:circle(gx + 12, gy + 12, 5, C.green) end
				d:text(d:fit(SHOP.groupName(g), 12, cw, 600), 12, gx + cw / 2, gy + cw + 6, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 600)
			end
		end
	end)
end

DV.app({ id = "bag", name = T("bobba.phone.app.bag", "Bag"), color = C.orange, glyph = G.bag, order = 13,
	badge = function() return SHOP.unseenCount and SHOP.unseenCount() or 0 end,
	phone = bagView, tablet = bagView })
