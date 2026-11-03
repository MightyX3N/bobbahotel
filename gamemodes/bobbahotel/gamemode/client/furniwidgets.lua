-- Windows some furni open when used (client), like nitro-react's furniture widgets:
--   a trophy (LayoutTrophyView): Habbo's gold, silver or bronze card with the engraving: who, when,
--     their words (the furni's data: name TAB date TAB text)
--   the stacking helper (FurnitureStackHeightView): its height, 0 to 40 (a slider, live), "Place
--     on top" and "Place at floor level"
--   a gift (FurnitureGiftOpeningView): the tag (who from, their face, the greeting), "Open this
--     gift" for the room's owner; opened, what was in it and where it went
--   the room background toner (FurnitureBackgroundColorView): its colour (hue, saturation,
--     lightness), On/Off and Apply. Nitro shows the browser's colour picker; here they're Habbo's
--     three sliders. While it's on, the room's background is that colour (useRoom's roomBackground).
--   a stickie (Habbo's stickie window, nitro-react's FurnitureStickieView): the note in its colour with
--     its words; the room's owner writes on it, picks one of the four colours or throws it away
--   the mood light (FurnitureDimmerView): off, Habbo's picture and "Turn on"; on, its three presets,
--     each a colour of seven, a brightness and "Background only", "Turn off" and "Apply". The room is
--     tinted the way Nitro does (RoomLogic's colour, 1.5 seconds from one to the next): the whole room
--     (nitro-react's AdjustmentFilter), or with "Background only" just its floor and walls.

local U = BOBBA.ui
local P = BOBBA.platform
local R = BOBBA.room
local V = BOBBA.view

local W = {}
R.widgets = W

-- HSL (0..255 each) to a colour, as Nitro's ColorConverter.hslToRGB
function W.hsl(h, s, l)
	h, s, l = h / 255, s / 255, l / 255
	if s <= 0 then
		local v = math.floor(l * 255 + 0.5)
		return Color(v, v, v)
	end
	local q = l < 0.5 and l * (1 + s) or (l + s - l * s)
	local p = 2 * l - q
	local function channel(t)
		if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
		if t < 1 / 6 then return p + (q - p) * 6 * t end
		if t < 1 / 2 then return q end
		if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
		return p
	end
	return Color(math.floor(channel(h + 1 / 3) * 255 + 0.5), math.floor(channel(h) * 255 + 0.5), math.floor(channel(h - 1 / 3) * 255 + 0.5))
end

local function logicOf(it)
	local info = R.furniInfo and R.furniInfo(it.kind)
	return info and info.logic
end

-- --- trophies ---------------------------------------------------------------------------------------
local function drawTrophy(w, d)
	local it = R.items[w.itemId]
	if not it then w:close() return end
	local data = tostring(it.data or "")
	local sender, date, text = data:match("^([^\t]*)\t([^\t]*)\t(.*)$")
	sender, date, text = sender or "", date or "", text or data
	local _, color = (it.kind or ""):match("^([^%*]+)%*(%d+)$")
	color = tonumber(color) or 1
	if color < 1 or color > 3 then color = 1 end
	d:icon("trophy-" .. color, 0, 0)
	-- the header (drag-handler) with the title; the close spot drawn in the picture
	d:click(340 - 5.5 - 15, 5, 15, 15, function() w:close() end)
	d:text(U.text("widget.furni.trophy.title", "Trophy"), 14.4, 170, 11, U.C.black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
	-- the words: 297 wide, 116 high, kept as written (pre-wrap)
	local x0, y0 = (340 - 297) / 2, 22 + 4
	local lines = {}
	for para in (text .. "\n"):gmatch("([^\n]*)\n") do
		local wrapped = U.wrapText(d, para, 14.4, 297)
		if #wrapped == 0 then lines[#lines + 1] = "" end
		for _, l in ipairs(wrapped) do lines[#lines + 1] = l end
	end
	d:clip(x0, y0, 297, 116, function()
		for i, l in ipairs(lines) do d:text(l, 14.4, x0, y0 + (i - 1) * 16 + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	end)
	local fy = y0 + 116 + 4 + 4 + 8
	d:text(date, 14.4, x0, fy, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
	d:text(sender, 14.4, x0 + 297, fy, U.C.black, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, true)
end

function W.trophy(it)
	local w = U.window("trophy", 340, 171, drawTrophy)
	w.itemId = it.id
	-- (no card: Habbo's picture is the window; it has no shadow under it)
	return w
end

-- --- the background toner ---------------------------------------------------------------------------
local SLIDERS = {
	{ "hue", "widget.backgroundcolor.hue", "Hue" },
	{ "saturation", "widget.backgroundcolor.saturation", "Saturation" },
	{ "lightness", "widget.backgroundcolor.lightness", "Lightness" },
}

local function slider(w, d, id, x, y, sw, value, onChange, colorAt)
	-- the track shows the colours it goes through; the thumb is a white circle with a dark ring
	local steps = 32
	for i = 0, steps - 1 do
		local c = colorAt(i / (steps - 1) * 255)
		d:rect(x + sw * i / steps, y + 5, sw / steps + 0.5, 6, c)
	end
	local tx = x + 7 + (sw - 14) * value / 255
	d:circle(tx, y + 8, 7, Color(60, 60, 60))
	d:circle(tx, y + 8, 5.5, U.C.white)
	local function set()
		local v = math.floor(math.Clamp(((w.mx or x) - x - 7) / (sw - 14), 0, 1) * 255 + 0.5)
		if v ~= value then onChange(v) end
	end
	d:click(x, y, sw, 16, function() w.dragging = id set() end)
	if w.dragging == id then
		if input.IsMouseDown(MOUSE_LEFT) then set() else w.dragging = nil end
	end
end

local function drawToner(w, d)
	local it = R.items[w.itemId]
	if not it then w:close() return end
	d:slimCard(U.text("widget.backgroundcolor.title", "Background Toner"))
	local c = w.color
	local y = 37
	for _, s in ipairs(SLIDERS) do
		d:text(U.text(s[2], s[3]), 14.4, 9, y + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		slider(w, d, s[1], 9, y + 18, d.width - 18, c[s[1]], function(v)
			c[s[1]] = v
			W.preview = { c.hue, c.saturation, c.lightness }
		end, function(v)
			local h, sa, l = c.hue, c.saturation, c.lightness
			if s[1] == "hue" then h = v elseif s[1] == "saturation" then sa = v else l = v end
			return W.hsl(h, sa, l)
		end)
		y = y + 42
	end
	-- what it'll look like
	d:round(4, 9, y, d.width - 18, 16, W.hsl(c.hue, c.saturation, c.lightness))
	y = y + 24
	local bw = d.width - 18
	d:btn(9, y, bw, 28.9, U.C.primary, function() P.send("room.item.use", { id = it.id }) end)
	d:text(U.text("widget.backgroundcolor.button.on", "On/Off"), 12.6, 9 + bw / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	y = y + 28.9 + 4
	d:btn(9, y, bw, 28.9, U.C.primary, function()
		P.send("room.item.toner", { id = it.id, hue = c.hue, saturation = c.saturation, lightness = c.lightness })
	end)
	d:text(U.text("widget.backgroundcolor.button.apply", "Apply"), 12.6, 9 + bw / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function tonerColor(it)
	local h, s, l = tostring(it.data or ""):match("^(%d+),(%d+),(%d+)$")
	return tonumber(h) or 0, tonumber(s) or 0, tonumber(l) or 0
end

function W.toner(it)
	local h, s, l = tonerColor(it)
	local w = U.window("toner", 190, 250, drawToner)
	w.itemId = it.id
	w.color = { hue = h, saturation = s, lightness = l }
	w.onClose = function() W.preview = nil end
	return w
end

-- the room's background: a toner that's on (or the one being chosen), else black
local nextCheck = 0
hook.Add("Think", "bobba.furniwidgets.background", function()
	if SysTime() < nextCheck then return end
	nextCheck = SysTime() + 0.1
	local bg
	if W.preview and U.windows.toner then
		bg = W.hsl(W.preview[1], W.preview[2], W.preview[3])
	else
		for _, it in pairs(R.items or {}) do
			if tonumber(it.state) == 1 and logicOf(it) == "furniture_background_color" then
				local h, s, l = tonerColor(it)
				if h + s + l > 0 then bg = W.hsl(h, s, l) end
			end
		end
	end
	if (bg and V.background and (bg.r ~= V.background.r or bg.g ~= V.background.g or bg.b ~= V.background.b)) or ((bg == nil) ~= (V.background == nil)) then
		V.background = bg
		V.dirty = true
	end
end)

-- --- the stacking helper ----------------------------------------------------------------------------
local function drawStackHeight(w, d)
	local it = R.items[w.itemId]
	if not it then w:close() return end
	d:slimCard(U.text("widget.custom.stack.height.title", "Stacking Helper"))
	local lines = U.wrapText(d, U.text("widget.custom.stack.height.text", "Adjust the height of stacking helper as you want, then move the other furni on top of it."), 14.4, d.width - 18)
	local y = 37
	for i, l in ipairs(lines) do d:text(l, 14.4, 9, y + (i - 1) * 16 + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	-- the slider (its value on the thumb, as Nitro's ReactSlider) and the number next to it
	local sy = 220 - 8 - 28.9 * 2 - 4 - 8 - 24
	local sw = d.width - 18 - 50 - 8
	local height = w.height
	local tx = 9 + 12 + (sw - 24) * height / 40
	d:round(3, 9, sy + 8, sw, 6, Color(182, 190, 197))
	d:round(3, 9, sy + 8, tx - 9, 6, U.C.primary)
	d:round(4, tx - 12, sy, 24, 22, U.C.primary)
	d:text(string.format("%g", height), 10.8, tx, sy + 11, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local function set()
		local v = math.Clamp(((w.mx or 9) - 9 - 12) / (sw - 24), 0, 1) * 40
		v = math.floor(v * 100 + 0.5) / 100
		if v ~= w.height then
			w.height = v
			-- (sent a moment later, as Nitro's 10 ms timeout: once the slider rests)
			w.sendAt = SysTime() + 0.05
		end
	end
	d:click(9, sy, sw, 22, function() w.dragging = true set() end)
	if w.dragging then
		if input.IsMouseDown(MOUSE_LEFT) then set() else w.dragging = nil end
	end
	if w.sendAt and SysTime() >= w.sendAt then
		w.sendAt = nil
		P.send("room.item.stackheight", { id = it.id, height = math.floor(w.height * 100 + 0.5) })
	end
	d:box(d.width - 9 - 50, sy, 50, 22, 1, 3.2, U.C.inputBorder, U.C.white)
	d:text(string.format("%g", height), 12.6, d.width - 9 - 6, sy + 11, U.C.black, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	local by = 220 - 8 - 28.9 * 2 - 4
	local bw = d.width - 18
	d:btn(9, by, bw, 28.9, U.C.primary, function() P.send("room.item.stackheight", { id = it.id, height = -100 }) end)
	d:text(U.text("furniture.above.stack", "Place on top"), 12.6, 9 + bw / 2, by + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	by = by + 28.9 + 4
	d:btn(9, by, bw, 28.9, U.C.primary, function() P.send("room.item.stackheight", { id = it.id, height = 0 }) end)
	d:text(U.text("furniture.floor.level", "Place at floor level"), 12.6, 9 + bw / 2, by + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	-- (the server's height when it changes it: on top, floor)
	if not w.dragging and not w.sendAt and w.lastZ ~= it.z then w.lastZ = it.z w.height = it.z end
end

function W.stackHeight(it)
	local w = U.window("stackheight", 275, 220, drawStackHeight)
	w.itemId = it.id
	w.height = it.z or 0
	w.lastZ = it.z
	return w
end

-- --- gifts ------------------------------------------------------------------------------------------
local function giftTag(it)
	local from, message, face = tostring(it.data or ""):match("^([^\t]*)\t([^\t]*)\t?(.*)$")
	local figure, gender = (face or ""):match("^(.-)|(%a)$")
	return from or "", message or "", figure ~= "" and figure or nil, gender
end

-- Habbo's gift tag: the card, the face on the left, the words, "- name"
local function drawTag(d, x, y, from, message, figure, gender)
	d:icon("gift-card", x, y)
	local AE = BOBBA.avatarEditor
	if figure and AE and AE.drawPreview then
		d:clip(x + 12.5, y + 50, 40, 50, function()
			AE.drawPreview(figure, gender or "M", 2, (x + 12.5 + 20) * d.s, (y + 50 - 18) * d.s, d.s)
		end)
	end
	local mx, mw = x + 65 + 12, 306 - 65 - 12 - 24
	local lines = U.wrapText(d, message, 14.4, mw)
	d:clip(mx, y + 24, mw, 149 - 48 - 20, function()
		for i, l in ipairs(lines) do d:text(l, 14.4, mx, y + 24 + (i - 1) * 17 + 8.5, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	end)
	if from ~= "" then
		d:text(U.text("catalog.gift_wrapping_new.message_from", "- %name%", { name = from }), 14.4, x + 306 - 24 - 4, y + 149 - 24 - 8, U.C.black, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
end

local function drawGift(w, d)
	local from, message, figure, gender = w.from, w.message, w.figure, w.gender
	d:slimCard(from ~= "" and U.text("widget.furni.present.window.title_from", "Gift from %name%", { name = from }) or U.text("widget.furni.present.window.title", "Special Gift"))
	local bw = d.width - 18
	if not w.opened then
		if not R.items[w.itemId] then w:close() return end
		drawTag(d, (d.width - 306) / 2, 37, from, message, figure, gender)
		if R.current and R.current.canEdit then
			local y = 37 + 149 + 8
			d:btn(9, y, bw, 28.9, U.C.success, function() P.send("room.item.open", { id = w.itemId }) end)
			d:text(U.text("widget.furni.present.open_gift", "Open this gift"), 12.6, 9 + bw / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		return
	end
	-- opened: what it was, and where it is
	local o = w.opened
	local info = R.furniInfo and R.furniInfo(o.kind)
	local name = (info and info.name) or o.kind or ""
	if R.furniIcon then
		local s = d.s
		R.furniIcon(o.kind, math.floor(9 * s), math.floor(45 * s), math.floor(80 * s), math.floor(80 * s), s, 255)
	end
	local tx, tw = 9 + 80 + 8, d.width - 9 - (9 + 80 + 8)
	local lines = U.wrapText(d, U.text("widget.furni.present.message_opened", "You open the gift and find a %product%!", { product = name }), 12.6, tw)
	for i, l in ipairs(lines) do d:text(l, 12.6, tx, 45 + (i - 1) * 15 + 7.5, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	local y = 45 + 80 + 8
	if o.inRoom then
		local hw = (bw - 4) / 2
		d:btn(9, y, hw, 28.9, U.C.primary, function() P.send("room.item.pickup", { id = o.id }) w:close() end)
		d:text(d:fit(U.text("widget.furni.present.put_in_inventory", "Put it in my inventory"), 12.6, hw - 8), 12.6, 9 + hw / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		d:btn(9 + hw + 4, y, hw, 28.9, U.C.success, function() w:close() end)
		d:text(d:fit(U.text("widget.furni.present.keep_in_room", "Keep in my room"), 12.6, hw - 8), 12.6, 9 + hw + 4 + hw / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	elseif o.id then
		d:btn(9, y, bw, 28.9, U.C.success, function()
			w:close()
			if BOBBA.shop and BOBBA.shop.place then BOBBA.shop.place({ kind = o.kind, ids = { o.id } }) end
		end)
		d:text(U.text("widget.furni.present.place_in_room", "Place in my room"), 12.6, 9 + bw / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

function W.present(it)
	local w = U.window("present", 340, 241, drawGift)
	w.itemId = it.id
	w.from, w.message, w.figure, w.gender = giftTag(it)
	return w
end

P.receive("gift.opened", function(_, data)
	local w = U.windows.present
	if w and w.itemId == data.present then w.opened = data end
end)

-- --- stickies ---------------------------------------------------------------------------------------
W.STICKIE_COLORS = { "9CCEFF", "FF9CFF", "9CFF9C", "FFFF33" }
local function hexColor(h)
	local n = tonumber(h, 16) or 0xFFFF33
	return Color(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

local function stickieData(it)
	local data = tostring(it.data or "")
	local color, text = data:match("^(%x%x%x%x%x%x) ?(.*)$")
	return (color or "FFFF33"):upper(), text or ""
end

-- Habbo's stickie layout: the note 185 x 178, the bin at 9, 4, the colours from 26, 5 every 12, the
-- close at 168, 5, the words from 5, 24 (175 x 135)
local function drawStickie(w, d)
	local it = R.items[w.itemId]
	if not it then w:close() return end
	local color, text = stickieData(it)
	local c = hexColor(color)
	d:icon("stickie", 0, 0, nil, nil, { color = c })
	d:click(168, 5, 10, 10, function() w:close() end)
	d:icon("stickie-close", 168, 5)
	local edit = R.current and R.current.canEdit
	if edit then
		d:click(9, 4, 10, 10, function()
			w.deleted = true
			P.send("room.item.stickie.delete", { id = it.id })
			w:close()
		end)
		d:icon("stickie-trash", 9, 4)
		for i, hex in ipairs(W.STICKIE_COLORS) do
			local x = 26 + (i - 1) * 12
			d:rect(x, 5, 9, 9, hexColor(hex))
			d:click(x, 5, 9, 9, function()
				P.send("room.item.stickie", { id = it.id, color = hex, text = w.typed or text })
			end)
		end
		d:input("text", 5 - 7, 24, 175, 135, { multiline = true, max = 500, value = text, bare = true })
		local e = w.inputs and w.inputs.text
		if IsValid(e) then w.typed = e:GetValue() end
	else
		-- (read only: the words wrapped, as they were written)
		local lines = {}
		for para in (text .. "\n"):gmatch("([^\n]*)\n") do
			local wrapped = U.wrapText(d, para, 12, 175)
			if #wrapped == 0 then lines[#lines + 1] = "" end
			for _, l in ipairs(wrapped) do lines[#lines + 1] = l end
		end
		d:clip(5, 24, 175, 135, function()
			for i, l in ipairs(lines) do d:text(l, 12, 5, 24 + (i - 1) * 14 + 7, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		end)
	end
end

function W.stickie(it)
	local w = U.window("stickie", 185, 178, drawStickie)
	w.itemId = it.id
	-- (what was written is saved when it's closed, like Habbo's)
	w.onClose = function(self)
		local cur = R.items[self.itemId]
		if self.deleted or not cur or not self.typed then return end
		local color, was = stickieData(cur)
		if self.typed ~= was then P.send("room.item.stickie", { id = cur.id, color = color, text = self.typed }) end
	end
	return w
end

-- --- the mood light ---------------------------------------------------------------------------------
-- (FurnitureDimmerUtilities)
W.DIMMER_COLORS = { 7665141, 21495, 15161822, 15353138, 15923281, 8581961, 0 }
W.DIMMER_HTML = { "74F5F5", "0053F7", "E759DE", "EA4532", "F2F851", "82F349", "000000" }
W.DIMMER_MIN, W.DIMMER_MAX = 76, 255

-- the mood light's data: on, preset, effect, colour, brightness and its presets
function W.dimmerData(data)
	local cur, rest = tostring(data or ""):match("^([^|]*)(.*)$")
	local on, preset, effect, color, light = (cur or ""):match("^(%d),(%d),(%d),#(%x%x%x%x%x%x),(%d+)$")
	if not on then return nil end
	local d = { on = on == "2", preset = tonumber(preset), effect = tonumber(effect), color = tonumber(color, 16), light = tonumber(light), presets = {} }
	for e, c, l in rest:gmatch("|(%d),#(%x%x%x%x%x%x),(%d+)") do d.presets[#d.presets + 1] = { effect = tonumber(e), color = tonumber(c, 16), light = tonumber(l) } end
	return d
end

local function dimmerItem()
	for _, it in pairs(R.items or {}) do
		if logicOf(it) == "furniture_roomdimmer" then return it end
	end
end

-- ColorConverter.rgbToHSL: hue, saturation, lightness 0..255 in one number
function W.rgbToHSL(c)
	local r, g, b = (math.floor(c / 65536) % 256) / 255, (math.floor(c / 256) % 256) / 255, (c % 256) / 255
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local dl = mx - mn
	local h = 0
	if dl ~= 0 then
		if mx == r then h = (g > b) and (60 * (g - b) / dl) or (60 * (g - b) / dl + 360)
		elseif mx == g then h = 60 * (b - r) / dl + 120
		else h = 60 * (r - g) / dl + 240 end
	end
	local l = 0.5 * (mx + mn)
	local s = 0
	if dl ~= 0 then s = (l <= 0.5) and (dl / l * 0.5) or (dl / (1 - l) * 0.5) end
	local function rnd(v) return math.floor(v + 0.5) end
	return rnd(h / 360 * 255) * 65536 + rnd(s * 255) * 256 + rnd(l * 255)
end

-- the colour the room is tinted: the colour's hue and saturation at the brightness (RoomLogic)
function W.dimmerTint(color, light)
	local hsl = W.rgbToHSL(color)
	local c = W.hsl(math.floor(hsl / 65536) % 256, math.floor(hsl / 256) % 256, math.floor(light + 0.5))
	return c
end

local function drawDimmer(w, d)
	local it = R.items[w.itemId]
	if not it then w:close() return end
	local data = W.dimmerData(it.data)
	if not data then w:close() return end
	local on = data.on
	-- (the window is as tall as what's in it: worked out as it's drawn, the size follows)
	local function fit(bottom)
		local want = math.ceil(bottom + 8)
		if w.height ~= want then
			w.height = want
			local s = U.scale()
			w.panel:SetSize(math.floor(w.width * s + 0.5), math.floor((want + 2) * s + 0.5))
		end
	end
	local tabs
	if on then
		tabs = {}
		for i = 1, 3 do tabs[i] = { id = i, label = U.text("widget.dimmer.tab." .. i, "Preset " .. i) } end
	end
	if on and not w.preset then w.select(data.preset) end
	d:card(U.text("widget.dimmer.title", "Room dimmer Controller"), tabs, w.preset, function(id) w.select(id) end)
	local W2 = d.width - 16
	if not on then
		local y = 33 + 8
		d:icon("dimmer-banner", 0, y, d.width)
		y = y + 79 + 8
		local lines = U.wrapText(d, U.text("widget.dimmer.info.off", "Room dimmer is currently turned off. Turn it on to adjust the lighting of your room."), 14.4, W2 - 8)
		local th = #lines * 17 + 8
		d:round(4, 8, y, W2, th, U.C.muted)
		for i, l in ipairs(lines) do d:text(l, 14.4, d.width / 2, y + 4 + (i - 1) * 17 + 8.5, U.C.black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
		y = y + th + 8
		d:btn(8, y, W2, 28.9, U.C.success, function() P.send("room.item.use", { id = it.id }) end)
		d:text(U.text("widget.dimmer.button.on", "Turn on"), 14.4, d.width / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		fit(y + 28.9)
		return
	end
	local y = 67 + 8
	d:text(U.text("widget.backgroundcolor.hue", "Hue"), 14.4, 8, y + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
	y = y + 16 + 4
	-- the seven colours (a grid of 7, 4 apart, 30 high; white 2px border, pressed in unless chosen)
	local cw = (W2 - 6 * 4) / 7
	for i, col in ipairs(W.DIMMER_COLORS) do
		local x = 8 + (i - 1) * (cw + 4)
		local hc = hexColor(W.DIMMER_HTML[i])
		d:round(4, x, y, cw, 30, U.C.white)
		d:round(3, x + 2, y + 2, cw - 4, 26, hc)
		if col ~= w.color then d:rect(x + 2, y + 2, cw - 4, 3, Color(0, 0, 0, 51)) d:rect(x + 2, y + 5, 3, 23, Color(0, 0, 0, 51)) end
		d:click(x, y, cw, 30, function() w.color = col end)
	end
	y = y + 30 + 8
	d:text(U.text("widget.backgroundcolor.lightness", "Lightness"), 14.4, 8, y + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
	y = y + 16 + 4
	-- the slider (ReactSlider: its thumb shows the brightness as 0 to 100)
	local range = W.DIMMER_MAX - W.DIMMER_MIN
	local tx = 8 + 12 + (W2 - 24) * (w.light - W.DIMMER_MIN) / range
	d:round(3, 8, y + 8, W2, 6, Color(182, 190, 197))
	d:round(3, 8, y + 8, tx - 8, 6, U.C.primary)
	d:round(4, tx - 12, y, 24, 22, U.C.primary)
	d:text(tostring(math.floor((w.light - W.DIMMER_MIN) * 100 / range)), 10.8, tx, y + 11, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local function set()
		local v = math.Clamp(((w.mx or 8) - 8 - 12) / (W2 - 24), 0, 1)
		w.light = math.floor(W.DIMMER_MIN + v * range + 0.5)
	end
	d:click(8, y, W2, 22, function() w.dragging = true set() end)
	if w.dragging then
		if input.IsMouseDown(MOUSE_LEFT) then set() else w.dragging = nil end
	end
	y = y + 22 + 8
	-- "Background only"
	d:click(8, y, W2, 16, function() w.effect = (w.effect == 2) and 1 or 2 end)
	if w.effect == 2 then
		d:round(3.6, 8, y + 0.8, 14.4, 14.4, U.C.primary)
		d:line(8 + 3.5, y + 0.8 + 7.5, 8 + 6, y + 0.8 + 10.2, 2, U.C.white)
		d:line(8 + 6, y + 0.8 + 10.2, 8 + 11, y + 0.8 + 4.3, 2, U.C.white)
	else
		d:box(8, y + 0.8, 14.4, 14.4, 1, 3.6, Color(0, 0, 0, 64), U.C.white)
	end
	d:text(U.text("widget.dimmer.type.checkbox", "Background only"), 14.4, 8 + 18.4, y + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	y = y + 16 + 8
	local bw = (W2 - 4) / 2
	d:btn(8, y, bw, 28.9, Color(168, 26, 18), function() P.send("room.item.use", { id = it.id }) end)
	d:text(U.text("widget.dimmer.button.off", "Turn off"), 14.4, 8 + bw / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	d:btn(8 + bw + 4, y, bw, 28.9, U.C.success, function()
		P.send("room.item.dimmer", { id = it.id, preset = w.preset, effect = w.effect, color = w.color, brightness = w.light, apply = true })
	end)
	d:text(U.text("widget.dimmer.button.apply", "Apply"), 14.4, 8 + bw + 4 + bw / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	fit(y + 28.9)
	-- (the room shows what's chosen while the window is open: previewDimmer)
	W.dimmerPreview = { color = w.color, light = w.light, bgOnly = w.effect == 2 }
end

function W.dimmer(it)
	local w = U.window("dimmer", 275, 240, drawDimmer)
	w.itemId = it.id
	-- a preset's settings into the window (selectPresetId)
	function w.select(id)
		local data = W.dimmerData((R.items[w.itemId] or {}).data)
		local p = data and data.presets[id]
		if not p then return end
		w.preset, w.effect, w.color, w.light = id, p.effect, p.color, math.max(W.DIMMER_MIN, p.light)
	end
	w.onClose = function() W.dimmerPreview = nil end
	return w
end

-- the room's tint now: from the mood light (or the window's preview), gliding there over 1.5 s
-- (RoomLogic.updateBackgroundColor); the whole room, or only the floor and walls
local tint = { color = 0xFFFFFF, light = 255, from = nil, to = nil, start = 0, bgOnly = false }
hook.Add("Think", "bobba.furniwidgets.dimmer", function()
	if V.mode ~= "room" then V.roomTint, V.planeTint = nil, nil return end
	local want = { color = 0xFFFFFF, light = 255, bgOnly = false }
	local it = dimmerItem()
	local data = it and W.dimmerData(it.data)
	if W.dimmerPreview and U.windows.dimmer and data and data.on then
		want = { color = W.dimmerPreview.color, light = W.dimmerPreview.light, bgOnly = W.dimmerPreview.bgOnly }
	elseif data and data.on then
		want = { color = data.color, light = data.light, bgOnly = data.effect == 2 }
	end
	local key = want.color .. "," .. want.light .. "," .. tostring(want.bgOnly)
	if key ~= tint.key then
		tint.key = key
		tint.from = { color = tint.color, light = tint.light }
		tint.to = want
		tint.start = SysTime()
		tint.bgOnly = want.bgOnly
	end
	if tint.to then
		local k = math.min(1, (SysTime() - tint.start) / 1.5)
		local f, t = tint.from, tint.to
		local function ch(c, sh) return math.floor(c / sh) % 256 end
		local r = ch(f.color, 65536) + (ch(t.color, 65536) - ch(f.color, 65536)) * k
		local g = ch(f.color, 256) + (ch(t.color, 256) - ch(f.color, 256)) * k
		local b = ch(f.color, 1) + (ch(t.color, 1) - ch(f.color, 1)) * k
		tint.color = math.floor(r) * 65536 + math.floor(g) * 256 + math.floor(b)
		tint.light = f.light + (t.light - f.light) * k
		if k >= 1 then tint.color, tint.light, tint.to = t.color, t.light, nil end
	end
	local c = W.dimmerTint(tint.color, tint.light)
	local plain = c.r >= 255 and c.g >= 255 and c.b >= 255
	-- (Background only: the floor and walls; else nitro-react's filter on the whole room)
	V.planeTint = (not plain and tint.bgOnly) and c or nil
	V.roomTint = (not plain and not tint.bgOnly) and c or nil
end)

-- what double-clicking a furni opens instead of using it; true when something opened
function W.open(it)
	local logic = logicOf(it)
	if logic == "furniture_trophy" then W.trophy(it) return true end
	if logic == "furniture_present" then W.present(it) return true end
	if logic == "furniture_custom_stack_height" then
		if R.current and R.current.canEdit then W.stackHeight(it) end
		return true
	end
	if logic == "furniture_background_color" then
		if R.current and R.current.canEdit then W.toner(it) end
		return true
	end
	if logic == "furniture_stickie" then W.stickie(it) return true end
	if logic == "furniture_roomdimmer" then
		if R.current and R.current.canEdit then W.dimmer(it) end
		return true
	end
	return false
end

BOBBA.events.on("roomShown", "bobba.furniwidgets", function()
	for _, id in ipairs({ "trophy", "toner", "stackheight", "present", "stickie", "dimmer" }) do
		if U.windows[id] then U.windows[id]:close() end
	end
	W.preview = nil
	W.dimmerPreview = nil
end)
