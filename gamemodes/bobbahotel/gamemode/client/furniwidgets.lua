-- Windows some furni open when used (client), like nitro-react's furniture widgets:
--   a trophy (LayoutTrophyView): Habbo's gold, silver or bronze card with the engraving: who, when,
--     their words (the furni's data: name TAB date TAB text)
--   the room background toner (FurnitureBackgroundColorView): its colour (hue, saturation,
--     lightness), On/Off and Apply. Nitro shows the browser's colour picker; here they're Habbo's
--     three sliders. While it's on, the room's background is that colour (useRoom's roomBackground).

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

-- what double-clicking a furni opens instead of using it; true when something opened
function W.open(it)
	local logic = logicOf(it)
	if logic == "furniture_trophy" then W.trophy(it) return true end
	if logic == "furniture_background_color" then
		if R.current and R.current.canEdit then W.toner(it) end
		return true
	end
	return false
end

BOBBA.events.on("roomShown", "bobba.furniwidgets", function()
	for _, id in ipairs({ "trophy", "toner" }) do
		if U.windows[id] then U.windows[id]:close() end
	end
	W.preview = nil
end)
