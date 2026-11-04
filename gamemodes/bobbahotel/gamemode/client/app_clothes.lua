-- The Clothes app (the phone's avatar editor and clothes shop): you, big, turning; the clothes by
-- part and their colours, your effects, the wardrobe; Save puts it on. The logic is the avatar
-- editor's (hotel/figureeditor.lua); the pictures the addon's (BOBBA.avatarEditor.drawPart / drawPreview).

local DV = BOBBA.device
local U = BOBBA.ui
local P = BOBBA.platform
local R = BOBBA.room
local AE = BOBBA.avatarEditor
local FE = BOBBA.figureEditor
local C, G = DV.C, DV.G
local alpha = DV.alpha
local hex = DV.hex
local T = function(k, f, v) return U.text(k, f, v) end

local PINK, PINK2 = hex("F26B8A"), hex("D9506F")
local TABS = {
	{ id = "generic", key = "bobba.phone.clothes.body", fallback = "Body" },
	{ id = "head", key = "bobba.phone.clothes.head", fallback = "Head" },
	{ id = "torso", key = "bobba.phone.clothes.torso", fallback = "Tops" },
	{ id = "legs", key = "bobba.phone.clothes.legs", fallback = "Bottoms" },
	{ id = "effects", key = "bobba.phone.clothes.effects", fallback = "Effects" },
	{ id = "wardrobe", key = "bobba.phone.clothes.wardrobe", fallback = "Wardrobe" },
}
local CATEGORY_NAMES = { hd = "Face", hr = "Hair", ha = "Hats", he = "Extras", ea = "Glasses", fa = "Masks", ch = "Shirts", cp = "Prints", cc = "Jackets", ca = "Chains", lg = "Trousers", sh = "Shoes", wa = "Belts" }

-- the editor (made when the clothes have come)
local function editor(st)
	if st.ed then return st.ed end
	if st.asked then return nil end
	st.asked = true
	if not AE.figureData then st.failed = T("bobba.phone.clothes.noaddon", "No addon has clothes.") return nil end
	AE.figureData(function(fd, err)
		if not fd then st.failed = tostring(err) return end
		local me = R.you and R.units[R.you]
		local figure = me and me.figure or (AE.defaultFigure and AE.defaultFigure()) or FE.DEFAULT_MALE_FIGURE
		local purse = BOBBA.hud and BOBBA.hud.purse
		st.ed = FE.new(fd, figure, me and me.gender or "M", { clubLevel = (purse and purse.clubLevel) or 0 })
		st.ed.effect = AE.enabledEffect
	end)
	P.send("effects.get", {})
	P.send("wardrobe.get", {})
	return nil
end

local function save(st)
	local ed = st.ed
	if not ed then return end
	if (ed.effect or 0) ~= AE.enabledEffect then P.send("effects.enable", { id = ed.effect or 0 }) end
	P.send("user.figure", { figure = ed.figure:getFigureString(), gender = ed.figure.gender })
	DV.notify({ app = "clothes", title = T("bobba.phone.app.clothes", "Clothes"), text = T("bobba.phone.clothes.saved", "Your new look is on.") })
end

-- you, on a floor, turning
local function drawYou(d, st, x, y, w, h, scale)
	local ed = st.ed
	d:round(30, x, y, w, h, PINK)
	d:clip(x, y, w, h, function()
		local fy = y + h * 0.78
		-- (the floor: an ellipse)
		local pts = {}
		for i = 0, 47 do
			local t = i / 48 * math.pi * 2
			pts[#pts + 1] = { x = (x + w / 2 + math.cos(t) * w * 0.36 + d.ox) * d.s, y = (fy + math.sin(t) * h * 0.06 + d.oy) * d.s }
		end
		local c = d:col(PINK2)
		surface.SetDrawColor(c.r, c.g, c.b, c.a)
		draw.NoTexture()
		surface.DrawPoly(BOBBA.view.clockwise(pts))
		if ed then
			local fx = (st.tab == "effects") and (ed.effect or 0) or 0
			d:avatar(ed.figure:getFigureString(), ed.figure.gender, ed.figure.direction, x + w / 2, fy - 115 * scale, scale, fx)
		end
	end)
end

-- a grid of square cells; returns the height
local function grid(d, n, x, y, w, cols, gap, draw, click)
	local cw = (w - (cols - 1) * gap) / cols
	for i = 1, n do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local cx, cy = x + col * (cw + gap), y + row * (cw + gap)
		d:click(cx, cy, cw, cw, function() click(i) end)
		draw(i, cx, cy, cw)
	end
	return math.ceil(n / cols) * (cw + gap) - gap
end

-- the parts of a tab: its categories (or boy / girl), the clothes, the colours
local function drawParts(ctx, st, x, y, w, h)
	local d = ctx.d
	local ed = st.ed
	local model = ed:model(st.tab)
	if not model then return end
	local chips = {}
	if model.canSetGender then
		chips = { { id = "M", label = T("bobba.phone.clothes.boy", "Boy") }, { id = "F", label = T("bobba.phone.clothes.girl", "Girl") } }
		d:chips("cat", x, y, w, chips, ed.figure.gender, function(g) ed:setGender(g) st.category = nil end, { h = 30, size = 12, off = C.white })
	else
		for _, name in ipairs(model.categories) do chips[#chips + 1] = { id = name, label = T("bobba.phone.clothes.cat." .. name, CATEGORY_NAMES[name] or name) } end
		d:chips("cat", x, y, w, chips, st.category, function(id) st.category = id end, { h = 30, size = 12, off = C.white })
	end
	y = y + 30 + 12
	if not st.category or not model.byName[st.category] then st.category = model.categories[1] end
	local category = model.byName[st.category]
	if not category then return end
	local part = category:getCurrentPart()
	local palettes = math.min(2, math.max(1, part and part.maxColorIndex or 1))
	local colorsH = palettes * 46 + 8
	local partsH = h - 42 - colorsH
	local cols = ctx.kind == "tablet" and 6 or 4
	local s = d.s
	local content = math.ceil(#category.parts / cols) * ((w - (cols - 1) * 8) / cols + 8)
	local off = d:scroll("parts", x, y, w, partsH, content)
	d:clip(x, y, w, partsH, function()
		grid(d, #category.parts, x, y - off, w, cols, 8, function(i, cx, cy, cw)
			if cy + cw < y or cy > y + partsH then return end
			local item = category.parts[i]
			d:round(16, cx, cy, cw, cw, item.isSelected and C.navy or C.white)
			if item.isClear then
				d:glyph("M6 6l12 12M18 6L6 18", cx + cw / 2 - 12, cy + cw / 2 - 12, 24, item.isSelected and C.paper or C.slate, 2.4)
			elseif AE.drawPart then
				local drawn
				d:clip(cx + 2, cy + 2, cw - 4, cw - 4, function()
					drawn = AE.drawPart(category.name, item, ed.figure, (cx + cw / 2 + d.ox) * s, (cy + cw / 2 + d.oy) * s, s * cw / 56)
				end)
				if drawn == false then d:text("…", 16, cx + cw / 2, cy + cw / 2, C.slate, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800) end
			end
			if item.isDisabled then d:round(16, cx, cy, cw, cw, Color(244, 246, 251, 170)) end
			if item.isHC then
				d:pill(cx + cw - 30, cy + cw - 22, 24, 16, C.gold)
				d:glyph(G.club, cx + cw - 25, cy + cw - 21, 14, C.navy, 2.2)
			end
		end, function(i) model:selectPart(category.name, i - 1) end)
	end)
	-- the colours: one strip each, sliding sideways
	local cy0 = y + partsH + 8
	for p = 0, palettes - 1 do
		local items = category:getPalette(p) or {}
		local py = cy0 + p * 46
		local sw = 34
		local total = #items * (sw + 8)
		local surf = d.surf
		local sc = surf.scrolls["colors" .. p] or { offset = 0 }
		surf.scrolls["colors" .. p] = sc
		sc.max = math.max(0, total - w)
		sc.offset = math.Clamp(sc.offset, 0, sc.max)
		d:dragZone(x, py, w, 40, { vertical = false, start = function() sc.from = sc.offset return true end,
			move = function(_, _, dx) sc.offset = math.Clamp(sc.from - dx, 0, sc.max) end,
			wheel = function(delta) sc.offset = math.Clamp(sc.offset - delta * 60, 0, sc.max) return true end })
		d:clip(x, py, w, 40, function()
			for i, item in ipairs(items) do
				local cx = x + (i - 1) * (sw + 8) - sc.offset + 3
				if cx + sw > x and cx < x + w then
					local rgb = item.partColor.rgb
					local col = Color(math.floor(rgb / 65536) % 256, math.floor(rgb / 256) % 256, rgb % 256)
					d:click(cx, py + 3, sw, sw, function() model:selectColor(category.name, i - 1, p) end)
					if item.isSelected then d:circle(cx + sw / 2, py + 3 + sw / 2, sw / 2 + 3, C.navy) d:circle(cx + sw / 2, py + 3 + sw / 2, sw / 2, C.white) end
					d:circle(cx + sw / 2, py + 3 + sw / 2, item.isSelected and sw / 2 - 3 or sw / 2, col)
					if item.isHC then d:circle(cx + sw - 4, py + 7, 5, C.gold) end
				end
			end
		end)
	end
end

local function drawEffects(ctx, st, x, y, w, h)
	local d = ctx.d
	local ed = st.ed
	local list = { { type = 0 } }
	for _, e in ipairs(AE.effects or {}) do list[#list + 1] = e end
	local cols = ctx.kind == "tablet" and 6 or 4
	local cw = (w - (cols - 1) * 8) / cols
	local off = d:scroll("fx", x, y, w, h, math.ceil(#list / cols) * (cw + 8) + 60)
	d:clip(x, y, w, h, function()
		local gh = grid(d, #list, x, y - off, w, cols, 8, function(i, cx, cy, cw2)
			local e = list[i]
			local on = (ed.effect or 0) == e.type
			d:round(16, cx, cy, cw2, cw2, on and C.navy or C.white)
			if e.type == 0 then d:glyph("M6 6l12 12M18 6L6 18", cx + cw2 / 2 - 12, cy + cw2 / 2 - 12, 24, on and C.paper or C.slate, 2.4)
			elseif not d:uiIcon("fx_icon_" .. e.type .. "_png", cx, cy, cw2, cw2) then
				d:text(tostring(e.type), 15, cx + cw2 / 2, cy + cw2 / 2, on and C.paper or C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
			end
			if (e.total or 1) > 1 then d:text("×" .. e.total, 11, cx + cw2 - 8, cy + cw2 - 8, on and C.paper or C.navy, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 800) end
		end, function(i) ed.effect = list[i].type ed.effectChosen = true end)
		local ty = y - off + gh + 16
		if #list == 1 then
			d:text(T("avatareditor.effects.empty", "You don't have any effects yet."), 14, x + w / 2, ty + 10, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		else
			for _, e in ipairs(AE.effects or {}) do
				if e.type == ed.effect then
					d:text(T("fx_" .. e.type, "Effect " .. e.type) .. " · " .. (AE.effectTime and AE.effectTime(e) or ""), 14, x, ty + 10, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
				end
			end
		end
	end)
end

local function drawWardrobe(ctx, st, x, y, w, h)
	local d = ctx.d
	local ed = st.ed
	local cols = ctx.kind == "tablet" and 5 or 3
	local cw = (w - (cols - 1) * 10) / cols
	local chh = cw * 1.45
	local n = AE.wardrobeSlots or 10
	local off = d:scroll("wardrobe", x, y, w, h, math.ceil(n / cols) * (chh + 10))
	d:clip(x, y, w, h, function()
		for i = 1, n do
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			local cx, cy = x + col * (cw + 10), y + row * (chh + 10) - off
			if cy + chh > y and cy < y + h then
				local look = AE.wardrobe and AE.wardrobe[i]
				d:round(18, cx, cy, cw, chh, C.white)
				if look then d:clip(cx, cy, cw, chh - 40, function() d:avatar(look.figure, look.gender, 2, cx + cw / 2, cy + chh - 40 - 125, 1) end) end
				local half = look and cw / 2 or cw
				d:click(cx, cy + chh - 36, half, 36, function()
					P.send("wardrobe.save", { slot = i, figure = ed.figure:getFigureString(), gender = ed.figure.gender })
				end)
				d:text(T("avatareditor.wardrobe.save", "Save"), 13, cx + half / 2, cy + chh - 18, C.blue, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
				if look then
					d:click(cx + half, cy + chh - 36, half, 36, function() ed:load(look.figure, look.gender, false) ed:resetCategories() end)
					d:text(T("generic_usable.button.use", "Use"), 13, cx + half + half / 2, cy + chh - 18, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
				end
			end
		end
	end)
end

local function clothesView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local st = ctx.state
	local tablet = ctx.kind == "tablet"
	d:rect(0, 0, W, H, hex("FCEEF1"))
	local ed = editor(st)
	st.tab = st.tab or "generic"
	-- the tabs (and the shop when the hotel sells clothes)
	local tabs = {}
	for _, t in ipairs(TABS) do tabs[#tabs + 1] = { id = t.id, label = T(t.key, t.fallback) } end
	if #DV.shopTabs("clothes") > 0 then tabs[#tabs + 1] = { id = "shop", label = T("bobba.phone.clothes.shop", "Shop") } end
	local function pick(id)
		if id == "shop" then ctx:push(DV.shopView("clothes", { app = "clothes", title = T("bobba.phone.clothes.shop", "Shop") }), {}) return end
		st.tab = id st.category = nil
		d.surf.scrolls.parts = nil
	end
	local pw, px, py, ph, area
	if tablet then
		px, py, pw, ph = 24, ctx.top + 8, 340, H - ctx.top - 32
		area = { x = px + pw + 24, y = ctx.top + 8, w = W - px - pw - 48 }
	else
		local top = ctx.top + ctx:header(T("bobba.phone.app.clothes", "Clothes"), { right = {
			{ label = T("avatareditor.save", "Save"), primary = true, fn = function() save(st) end },
		} })
		px, py, pw, ph = 16, top + 4, W - 32, 250
		area = { x = 16, y = py + ph + 12, w = W - 32 }
	end
	drawYou(d, st, px, py, pw, ph, tablet and 2 or 1.5)
	if ed then
		DV.turnButton(d, px + 14, py + ph - (tablet and 136 or 58), function() ed:rotate(ed.figure.direction + 1) end, true)
		DV.turnButton(d, px + pw - 58, py + ph - (tablet and 136 or 58), function() ed:rotate(ed.figure.direction - 1) end)
	end
	if tablet then
		d:round(11, px + 20, py + 18, 34, 34, C.navy)
		d:glyph(G.clothes, px + 28, py + 26, 18, C.paper, 2.2)
		d:text(T("bobba.phone.app.clothes", "Clothes"), 20, px + 64, py + 35, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
		if ed then
			d:button(px + 20, py + ph - 72, pw - 40, 52, T("bobba.phone.clothes.saveon", "Save and put on"), "primary", function() save(st) end)
			-- (undo, clear, random)
			local bw = (pw - 40 - 16) / 3
			local acts = { { T("bobba.phone.clothes.undo", "Undo"), function() ed:reset() st.category = nil end },
				{ T("bobba.phone.clothes.clear", "Clear"), function() ed:clear() st.category = nil end },
				{ T("bobba.phone.clothes.random", "Random"), function() ed:randomize() st.category = nil end } }
			for i, a in ipairs(acts) do d:button(px + 20 + (i - 1) * (bw + 8), py + ph - 128, bw, 40, a[1], "paper", a[2]) end
		end
	end
	local y = area.y
	d:chips("tabs", area.x, y, area.w, tabs, st.tab, pick, { off = C.white })
	y = y + 32 + 12
	local h = H - y - (tablet and 24 or 34)
	if not ed then
		d:text(st.failed or T("bobba.phone.loading", "Loading…"), 14, area.x + area.w / 2, y + 60, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		return
	end
	if st.tab == "effects" then drawEffects(ctx, st, area.x, y, area.w, h)
	elseif st.tab == "wardrobe" then drawWardrobe(ctx, st, area.x, y, area.w, h)
	else drawParts(ctx, st, area.x, y, area.w, h) end
end

DV.app({ id = "clothes", name = T("bobba.phone.app.clothes", "Clothes"), color = C.pink, glyph = G.clothes, order = 11, bg = hex("FCEEF1"),
	phone = clothesView, tablet = clothesView })
