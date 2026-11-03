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
}

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
					local drawn = AE.drawPart(category.name, item, ed.figure, (x + cw / 2) * s, (y2 + ch / 2) * s, s)
					if drawn == false then icon(d, "loading", false, x, y2, cw, ch, "...") end
				else
					d:text(category.name .. "-" .. item.id, 9, x + cw / 2, y2 + ch / 2, U.C.paleSky, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				-- HC clothes the player can't wear are dimmed (AvatarEditorGridPartItem: alpha 0.2)
				if item.isDisabled then d:round(4, x + 2, y2 + 2, cw - 4, ch - 4, Color(205, 211, 217, 204)) end
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
				end
			end
		end)
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
			AE.drawPreview(ed.figure:getFigureString(), ed.figure.gender, ed.figure.direction, (c.x + c.w / 2) * s, (c.y - 40) * s, 2 * s)
		end
	end)
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
		local ed = FE.new(fd, figure, gender, { clubLevel = 0 })
		AE.editor = ed
		U.window("avatar-editor", AE.WIDTH, AE.HEIGHT, function(w, d)
			w.tab = w.tab or "generic"
			local tabs = {}
			for _, t in ipairs(TABS) do tabs[#tabs + 1] = { id = t.id, label = L(t.key, t.fallback) } end
			d:card(L("avatareditor.title", "Avatar Editor"), tabs, w.tab, function(id)
				if id ~= w.tab then w.tab = id w.category = nil w.scrolls = {} end
			end)
			drawModel(w, d, ed)
			drawPreview(w, d, ed)
			drawButtons(w, d, ed)
		end)
	end)
end

concommand.Add("bobba_avatar_editor", function() AE.open() end)
