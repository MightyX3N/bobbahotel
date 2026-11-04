-- The avatar editor (client): nitro-react's AvatarEditorView, AvatarEditorModelView,
-- AvatarEditorFigureSetView, AvatarEditorPaletteSetView and AvatarEditorFigurePreviewView, laid out
-- the way its SCSS lays them out (620 x 374; sizes measured from nitro-react's own CSS in a browser),
-- on the logic in hotel/figureeditor.lua. Saving sends the look to the server (hotel/looks.lua).
--
-- The clothes, their pictures and the icons come from an addon (bobba_habbo: Habbo's figuredata,
-- clothes and editor icons):
--   AE.figureData(function(fd) end)                 the figure data (shape: hotel/figureeditor.lua)
--   AE.drawPart(category, item, figure, cx, cy, s)  a clothing piece's picture, its middle at cx, cy
--     (screen pixels, s times its size); return false while it's still loading
--   AE.drawPreview(figure, gender, direction, cx, top, s)   the whole avatar: its middle at cx, its top
--   AE.drawIcon(name, selected, cx, cy, s)          an icon ("male", "hr", "clear", "arrow-left", ...)
--
--   bobba_avatar_editor     opens it (also: click your avatar, then "Change looks")

BOBBA.avatarEditor = BOBBA.avatarEditor or {}
local AE = BOBBA.avatarEditor
local U = BOBBA.ui
local R = BOBBA.room
local P = BOBBA.platform
local FE = BOBBA.figureEditor
local L = function(key, fallback)
	if BOBBA.lang.has(key) then return BOBBA.lang.get(key) end
	return fallback
end

AE.WIDTH, AE.HEIGHT = 620, 374

-- the categories' tabs (AvatarEditorFigureCategory) and their texts (Habbo's when the addon has them)
local TABS = {
	{ id = "generic", key = "avatareditor.category.generic", fallback = "Body" },
	{ id = "head", key = "avatareditor.category.head", fallback = "Head" },
	{ id = "torso", key = "avatareditor.category.torso", fallback = "Torso" },
	{ id = "legs", key = "avatareditor.category.legs", fallback = "Legs" },
	-- Habbo's own editor has the effects you own as a tab (as the Habbo AIR client and gk-nitro do)
	{ id = "effects", key = "avatareditor.category.effects", fallback = "Effects" },
	-- nitro-react's wardrobe: ten saved looks
	{ id = "wardrobe", key = "avatareditor.category.wardrobe", fallback = "Wardrobe" },
}

-- what the server says (hotel/effects.lua): the effects you own, the one you wear, the wardrobe
AE.effects = AE.effects or {}
AE.enabledEffect = AE.enabledEffect or 0
AE.wardrobe = AE.wardrobe or {}
AE.wardrobeSlots = AE.wardrobeSlots or 10
P.receive("effects.list", function(_, data)
	AE.effects = data.effects or {}
	AE.effectsAt = SysTime()
	AE.enabledEffect = tonumber(data.enabled) or 0
	if AE.editor and not AE.editor.effectChosen then AE.editor.effect = AE.enabledEffect end
end)
P.receive("wardrobe.list", function(_, data)
	AE.wardrobe = {}
	for slot, l in pairs(data.looks or {}) do AE.wardrobe[tonumber(slot)] = l end
	AE.wardrobeSlots = tonumber(data.slots) or 10
end)

-- --- the layout, in CSS pixels (from nitro-react's CSS: see the comment at the top) ----------------
local CONTENT = { x = 9, y = 75, h = 290 }
local LEFT = { x = 9, w = 450 }
local CATS = { x = 9, w = 68, itemH = 40, gap = 8 }
local PARTS = { x = 85, w = 183, cols = 3, rowH = 50, gap = 8 }
local COLORS = { x = 276, w = 183, cols = 5, rowH = 40, gap = 4 }
local RIGHT = { x = 467, w = 145 }
local PREVIEW = { x = 467, y = 75, w = 145, h = 221 }
local BUTTONS = { x = 467, y = 304, w = 145, h = 28 }
local SAVE = { x = 467, y = 336, w = 145, h = 29 }

-- a grid of n items, columns that fill the width (repeat(auto-fill, minmax(min, 1fr)))
local function cell(g, i)
	local w = (g.w - (g.cols - 1) * g.gap) / g.cols
	local col, row = (i - 1) % g.cols, math.floor((i - 1) / g.cols)
	return g.x + col * (w + g.gap), row * (g.rowH + g.gap), w, g.rowH
end

local function rows(g, n) return math.ceil(n / g.cols) * (g.rowH + g.gap) - g.gap end

-- --- drawing ----------------------------------------------------------------------------------------
local function icon(d, name, selected, x, y, w, h, fallback)
	local s = d.s
	local ox, oy = d.w.panel:LocalToScreen(0, 0)
	local cx, cy = (x + w / 2) * s, (y + h / 2) * s
	if AE.drawIcon and AE.drawIcon(name, selected, cx, cy, s) then return end
	d:text(fallback or name, 12, x + w / 2, y + h / 2, selected and U.C.primary or U.C.paleSky, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
end

local CATEGORY_NAMES = { hd = "Face", hr = "Hair", ha = "Hats", he = "Extras", ea = "Glasses", fa = "Masks", ch = "Shirts", cp = "Prints", cc = "Jackets", ca = "Chains", lg = "Trousers", sh = "Shoes", wa = "Belts" }

-- a club piece or colour: the club's coin in its bottom right corner (LayoutCurrencyIcon type hc,
-- end-1 bottom-1), so it's clear why it can't be chosen without the club
local function clubMark(d, item, x, y, w, h)
	if not item.isHC then return end
	local level = (item.partColor and item.partColor.clubLevel) or (item.partSet and item.partSet.clubLevel) or 1
	local kind = U.clubKindFor and U.clubKindFor(level) or "hc"
	if U.clubIcon then U.clubIcon(d, kind, x + w - 4 - 16, y + h - 4 - 16, 16, 16) end
end

local function drawModel(w, d, ed)
	local model = ed:model(w.tab)
	if not model then return end
	-- the left column: gender, or this tab's categories
	local y = CONTENT.y
	if model.canSetGender then
		for _, g in ipairs({ "M", "F" }) do
			local name = g == "M" and "male" or "female"
			d:click(CATS.x, y, CATS.w, CATS.itemH, function() ed:setGender(g) w.category = nil end)
			icon(d, name, ed.figure.gender == g, CATS.x, y, CATS.w, CATS.itemH, g == "M" and "Boy" or "Girl")
			y = y + CATS.itemH + CATS.gap
		end
	else
		for _, name in ipairs(model.categories) do
			d:click(CATS.x, y, CATS.w, CATS.itemH, function() w.category = name end)
			icon(d, name, w.category == name, CATS.x, y, CATS.w, CATS.itemH, CATEGORY_NAMES[name])
			y = y + CATS.itemH + CATS.gap
		end
	end
	if not w.category or not model.byName[w.category] then w.category = model.categories[1] end
	local category = model.byName[w.category]
	if not category then return end
	-- the clothes (AvatarEditorFigureSetView: AutoGrid, 3 columns, 50 high)
	local n = #category.parts
	local offset = d:scroll("parts", PARTS.x, CONTENT.y, PARTS.w, CONTENT.h, rows(PARTS, n))
	d:clip(PARTS.x, CONTENT.y, PARTS.w, CONTENT.h, function()
		local s = d.s
		for i, item in ipairs(category.parts) do
			local x, ry, cw, ch = cell(PARTS, i)
			local y2 = CONTENT.y + ry - offset
			if y2 + ch >= CONTENT.y and y2 <= CONTENT.y + CONTENT.h then
				d:click(x, math.max(y2, CONTENT.y), cw, math.min(y2 + ch, CONTENT.y + CONTENT.h) - math.max(y2, CONTENT.y), function()
					model:selectPart(category.name, i - 1)
				end)
				d:gridItem(x, y2, cw, ch, item.isSelected)
				if item.isClear then
					icon(d, "clear", false, x, y2, cw, ch, "X")
				elseif AE.drawPart then
					-- (the picture stays inside its box, like a CSS background: big hats and wings are cut)
					local drawn
					d:clip(x, y2, cw, ch, function()
						drawn = AE.drawPart(category.name, item, ed.figure, (x + cw / 2) * s, (y2 + ch / 2) * s, s)
					end)
					if drawn == false then icon(d, "loading", false, x, y2, cw, ch, "...") end
				else
					d:text(category.name .. "-" .. item.id, 9, x + cw / 2, y2 + ch / 2, U.C.paleSky, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				-- HC clothes the player can't wear are dimmed (AvatarEditorGridPartItem: alpha 0.2)
				if item.isDisabled then d:round(4, x + 2, y2 + 2, cw - 4, ch - 4, Color(205, 211, 217, 204)) end
				clubMark(d, item, x, y2, cw, ch)
			end
		end
	end)
	-- the colours: one palette, or two when the piece has two colours (AvatarEditorPaletteSetView)
	local part = category:getCurrentPart()
	local palettes = math.max(1, part and part.maxColorIndex or 1)
	if palettes > 2 then palettes = 2 end
	local ph = palettes == 2 and (CONTENT.h - 8) / 2 or CONTENT.h
	for p = 0, palettes - 1 do
		local items = category:getPalette(p) or {}
		local top = CONTENT.y + p * (ph + 8)
		local poff = d:scroll("palette" .. p, COLORS.x, top, COLORS.w, ph, rows(COLORS, #items))
		d:clip(COLORS.x, top, COLORS.w, ph, function()
			for i, item in ipairs(items) do
				local x, ry, cw, ch = cell(COLORS, i)
				local y2 = top + ry - poff
				if y2 + ch >= top and y2 <= top + ph then
					d:click(x, math.max(y2, top), cw, math.min(y2 + ch, top + ph) - math.max(y2, top), function()
						model:selectColor(category.name, i - 1, p)
					end)
					local c = item.partColor.rgb
					d:gridItem(x, y2, cw, ch, item.isSelected, Color(math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256), true)
					clubMark(d, item, x, y2, cw, ch)
				end
			end
		end)
	end
end

-- the effects tab: "none" and every effect you own (Habbo's fx icons), 6 a row
local FX = { x = 9, w = 450, cols = 6, rowH = 60, gap = 8 }
local function drawEffects(w, d, ed)
	local list = { { type = 0 } }
	for _, e in ipairs(AE.effects) do list[#list + 1] = e end
	local offset = d:scroll("effects", FX.x, CONTENT.y, FX.w, CONTENT.h, rows(FX, #list))
	d:clip(FX.x, CONTENT.y, FX.w, CONTENT.h, function()
		for i, e in ipairs(list) do
			local x, ry, cw, ch = cell(FX, i)
			local y2 = CONTENT.y + ry - offset
			if y2 + ch >= CONTENT.y and y2 <= CONTENT.y + CONTENT.h then
				d:click(x, math.max(y2, CONTENT.y), cw, math.min(y2 + ch, CONTENT.y + CONTENT.h) - math.max(y2, CONTENT.y), function() ed.effect = e.type ed.effectChosen = true end)
				d:gridItem(x, y2, cw, ch, (ed.effect or 0) == e.type)
				if e.type == 0 then icon(d, "clear", false, x, y2, cw, ch, "X")
				elseif not d:icon("fx_icon_" .. e.type .. "_png", x, y2, cw, ch) then
					d:text(tostring(e.type), 14.4, x + cw / 2, y2 + ch / 2, U.C.paleSky, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
				end
				-- (more than one: how many, in the corner)
				if (e.total or 1) > 1 then d:text("x" .. e.total, 11, x + cw - 5, y2 + ch - 4, U.C.black, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, true) end
			end
		end
	end)
	if #AE.effects == 0 then
		local msg = L("avatareditor.effects.empty", "You don't have any effects yet.")
		d:text(msg, 12.6, FX.x + FX.w / 2, CONTENT.y + 60 + 30, U.C.black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

-- how long the chosen effect has left (gk-nitro's getEffectTimeDisplay)
local function effectTime(e)
	if e.permanent then return L("avatareditor.effects.active.permanent", "Permanent") end
	local left = e.secondsLeft or 0
	if left > 0 then left = math.max(0, left - math.floor(SysTime() - (AE.effectsAt or SysTime()))) end
	if left <= 0 then left = e.duration or 0 end
	local days = math.floor(left / 86400)
	if days > 0 then return string.format("%d %s", days, L("avatareditor.effects.days", "days")) end
	return string.format("%02d:%02d:%02d", math.floor(left / 3600), math.floor(left % 3600 / 60), left % 60)
end

-- the wardrobe (AvatarEditorWardrobeView: 5 a row, each the look facing you, "Save" and "Use")
local WR = { x = 9, w = 450, cols = 5, rowH = 141, gap = 8 }
local function drawWardrobe(w, d, ed)
	local s = d.s
	for i = 1, AE.wardrobeSlots do
		local x, ry, cw, ch = cell(WR, i)
		local y = CONTENT.y + ry
		d:round(4, x, y, cw, ch, U.C.paleSky)
		local look = AE.wardrobe[i]
		d:clip(x, y, cw, ch, function()
			-- (the floor and the shadow, as the preview has them)
			local ex, ey = x + cw / 2, y + ch * 0.75 + ch * 0.25
			local pts = {}
			for k = 0, 47 do
				local t = k / 48 * math.pi * 2
				pts[#pts + 1] = { x = (ex + math.cos(t) * cw) * s, y = (ey + math.sin(t) * ch * 0.25) * s }
			end
			draw.NoTexture()
			surface.SetDrawColor(255, 255, 255, 50)
			surface.DrawPoly(BOBBA.view.clockwise(pts))
			if look then
				local sx, sy = x + cw / 2, y + ch - 25 - 12
				pts = {}
				for k = 0, 31 do
					local t = k / 32 * math.pi * 2
					pts[#pts + 1] = { x = (sx + math.cos(t) * 20) * s, y = (sy + math.sin(t) * 10) * s }
				end
				surface.SetDrawColor(0, 0, 0, 51)
				surface.DrawPoly(BOBBA.view.clockwise(pts))
				if AE.drawPreview then AE.drawPreview(look.figure, look.gender, 2, (x + cw / 2) * s, (y + ch - 10 - 130) * s, s) end
			end
		end)
		-- the buttons (link buttons at the bottom)
		local by = y + ch - 22
		local half = look and cw / 2 or cw
		local hover = d:click(x, by, half, 22, function()
			P.send("wardrobe.save", { slot = i, figure = ed.figure:getFigureString(), gender = ed.figure.gender })
		end)
		d:text(L("avatareditor.wardrobe.save", "Save"), 12.6, x + half / 2, by + 11, hover and U.C.black or U.C.primary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		if look then
			local h2 = d:click(x + half, by, half, 22, function() ed:load(look.figure, look.gender, false) ed:resetCategories() end)
			d:text(L("generic_usable.button.use", "Use"), 12.6, x + half + half / 2, by + 11, h2 and U.C.black or U.C.primary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
end

-- AvatarEditorFigurePreviewView
local function drawPreview(w, d, ed)
	local c = PREVIEW
	d:rect(c.x, c.y, c.w, c.h, U.C.paleSky)
	d:clip(c.x, c.y, c.w, c.h, function()
		-- ::after: the floor, an ellipse from 75% down, twice as big, glowing white at its edge
		local fy0 = c.h * 0.75
		local ex, ey, ew, eh = c.x + c.w / 2, c.y + fy0 + (c.h - fy0) / 2, c.w * 2, (c.h - fy0) * 2
		local s = d.s
		local function ellipse(rx, ry, col)
			local pts = {}
			for i = 0, 63 do
				local t = i / 64 * math.pi * 2
				pts[#pts + 1] = { x = (ex + math.cos(t) * rx) * s, y = (ey + math.sin(t) * ry) * s }
			end
			draw.NoTexture()
			surface.SetDrawColor(col.r, col.g, col.b, col.a or 255)
			surface.DrawPoly(BOBBA.view.clockwise(pts))
		end
		for g = 10, 1, -1 do ellipse(ew / 2 + g, eh / 2 + g, Color(255, 255, 255, math.floor(153 * (1 - g / 10) * 0.35))) end
		ellipse(ew / 2, eh / 2, U.C.paleSky)
		-- .avatar-shadow: 70 x 30, 15 from the bottom, black at 20%
		local sx, sy = c.x + c.w / 2, c.y + c.h - 15 - 15
		local pts = {}
		for i = 0, 63 do
			local t = i / 64 * math.pi * 2
			pts[#pts + 1] = { x = (sx + math.cos(t) * 35) * s, y = (sy + math.sin(t) * 15) * s }
		end
		draw.NoTexture()
		surface.SetDrawColor(0, 0, 0, 51)
		surface.DrawPoly(BOBBA.view.clockwise(pts))
		-- the avatar (LayoutAvatarImageView, scale 2): the cropped picture's top 40 above the box
		if AE.drawPreview then
			local fx = (w.tab == "effects") and (ed.effect or 0) or 0
			AE.drawPreview(ed.figure:getFigureString(), ed.figure.gender, ed.figure.direction, (c.x + c.w / 2) * s, (c.y - 40) * s, 2 * s, fx)
		end
	end)
	-- the chosen effect: its name and the time it has left (gk-nitro)
	if w.tab == "effects" and (ed.effect or 0) > 0 then
		for _, e in ipairs(AE.effects) do
			if e.type == ed.effect then
				-- (one line at the top, so the avatar stays in view)
				local line = L("fx_" .. e.type, "Effect " .. e.type) .. " · " .. effectTime(e)
				d:round(4, c.x + 4, c.y + 4, c.w - 8, 18, Color(255, 255, 255, 190))
				d:text(d:fit(line, 11, c.w - 14), 11, c.x + c.w / 2, c.y + 13, U.C.black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
	end
	-- the arrows turn it (arrow-left: direction + 1, arrow-right: direction - 1)
	d:click(c.x + 10, c.y + 188, 28, 21, function() ed:rotate(ed.figure.direction + 1) end)
	icon(d, "arrow-left", false, c.x + 10, c.y + 188, 28, 21, "<")
	d:click(c.x + 106, c.y + 188, 28, 21, function() ed:rotate(ed.figure.direction - 1) end)
	icon(d, "arrow-right", false, c.x + 106, c.y + 188, 28, 21, ">")
end

-- the little white pictures on the buttons (FaUndo, FaTrash, FaDice), drawn
local function glyph(d, kind, cx, cy)
	local s = d.s
	local x, y = cx * s, cy * s
	local u = s
	surface.SetDrawColor(255, 255, 255, 255)
	draw.NoTexture()
	if kind == "undo" then
		for a = 0, 40 do
			local t = math.rad(-30 + a * 6)
			surface.DrawRect(x + math.cos(t) * 5 * u - u / 2, y + math.sin(t) * 5 * u - u / 2, 1.6 * u, 1.6 * u)
		end
		surface.DrawPoly({ { x = x - 7 * u, y = y - 1 * u }, { x = x - 6 * u, y = y - 6 * u }, { x = x - 2 * u, y = y - 3 * u } })
	elseif kind == "trash" then
		surface.DrawRect(x - 5 * u, y - 5 * u, 10 * u, 1.5 * u)
		surface.DrawRect(x - 1.5 * u, y - 6.5 * u, 3 * u, 1.5 * u)
		surface.DrawRect(x - 4 * u, y - 3 * u, 8 * u, 9 * u)
		surface.SetDrawColor(24, 93, 121, 255)
		surface.DrawRect(x - 2 * u, y - 1.5 * u, 1 * u, 6 * u)
		surface.DrawRect(x + 1 * u, y - 1.5 * u, 1 * u, 6 * u)
	elseif kind == "dice" then
		draw.RoundedBox(math.floor(2 * u), x - 6 * u, y - 6 * u, 12 * u, 12 * u, Color(255, 255, 255))
		surface.SetDrawColor(24, 93, 121, 255)
		for _, p in ipairs({ { -3, -3 }, { 3, 3 }, { 0, 0 }, { 3, -3 }, { -3, 3 } }) do
			surface.DrawRect(x + (p[1] - 1) * u, y + (p[2] - 1) * u, 2 * u, 2 * u)
		end
	end
end

local function drawButtons(w, d, ed)
	local b = BUTTONS
	local bw = (b.w + 2) / 3
	local actions = {
		{ glyph = "undo", fn = function() ed:reset() w.category = nil end },
		{ glyph = "trash", fn = function() ed:clear() w.category = nil end },
		{ glyph = "dice", fn = function() ed:randomize() w.category = nil end },
	}
	for i, a in ipairs(actions) do
		local x = b.x + (i - 1) * (bw - 1)
		d:button(x, b.y, bw, b.h, U.C.secondary, a.fn, { i == 1, i == 3, i == 1, i == 3 })
		glyph(d, a.glyph, x + bw / 2, b.y + b.h / 2)
	end
	d:button(SAVE.x, SAVE.y, SAVE.w, SAVE.h, U.C.success, function()
		if (ed.effect or 0) ~= AE.enabledEffect then P.send("effects.enable", { id = ed.effect or 0 }) end
		P.send("user.figure", { figure = ed.figure:getFigureString(), gender = ed.figure.gender })
		w:close()
	end)
	d:text(L("avatareditor.save", "Save"), 12.6, SAVE.x + SAVE.w / 2, SAVE.y + SAVE.h / 2, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- --- opening it ---------------------------------------------------------------------------------------
function AE.open()
	if not AE.figureData then
		chat.AddText(Color(255, 120, 120), "[Bobba] ", color_white, "No addon has clothes for the avatar editor.")
		return
	end
	AE.figureData(function(fd, err)
		if not fd then
			chat.AddText(Color(255, 120, 120), "[Bobba] ", color_white, "The clothes couldn't be loaded: " .. tostring(err))
			return
		end
		-- the look you have now (your unit in the room), else the default
		local me = R.you and R.units[R.you]
		local figure = me and me.figure or (AE.defaultFigure and AE.defaultFigure()) or FE.DEFAULT_MALE_FIGURE
		local gender = me and me.gender or "M"
		local purse = BOBBA.hud and BOBBA.hud.purse
		local ed = FE.new(fd, figure, gender, { clubLevel = (purse and purse.clubLevel) or 0 })
		AE.editor = ed
		ed.effect = AE.enabledEffect
		P.send("effects.get", {})
		P.send("wardrobe.get", {})
		U.window("avatar-editor", AE.WIDTH, AE.HEIGHT, function(w, d)
			w.tab = w.tab or "generic"
			local tabs = {}
			for _, t in ipairs(TABS) do tabs[#tabs + 1] = { id = t.id, label = L(t.key, t.fallback) } end
			d:card(L("avatareditor.title", "Avatar Editor"), tabs, w.tab, function(id)
				if id ~= w.tab then w.tab = id w.category = nil w.scrolls = {} end
			end)
			if w.tab == "effects" then drawEffects(w, d, ed)
			elseif w.tab == "wardrobe" then drawWardrobe(w, d, ed)
			else drawModel(w, d, ed) end
			drawPreview(w, d, ed)
			drawButtons(w, d, ed)
		end)
	end)
end

concommand.Add("bobba_avatar_editor", function() AE.open() end)
