-- The starter room picker (client): a new player chooses the room they begin with (the server's
-- side, and how a pack adds rooms to it, is hotel/starter.lua). Each room is a card with its
-- wallpaper over its floor and its furni standing on it; the chosen one is made and you go in.

BOBBA.starterPicker = BOBBA.starterPicker or {}
local SP = BOBBA.starterPicker
local U = BOBBA.ui
local P = BOBBA.platform
local R = BOBBA.room
local T = function(key, fallback, vars) return U.text(key, fallback, vars) end

local BLACK, WHITE = Color(0, 0, 0), Color(255, 255, 255)
local COLS, CARD_W, CARD_H, GAP = 3, 168, 150, 8

-- a room's card: the wall, the floor under it, its furni on the floor, its name
local function card(d, room, x, y, active)
	d:gridItem(x, y, CARD_W, CARD_H, active)
	local s = d.s
	local px, py, pw = x + 6, y + 6, CARD_W - 12
	local wallH, floorH = 70, 40
	local function swatch(paint, id, sy, sh, fallback)
		d:rect(px, sy, pw, sh, fallback)
		if id ~= "" and R.paintSwatch then
			d:clip(px, sy, pw, sh, function()
				R.paintSwatch(paint, id, math.floor(px * s + 0.5), math.floor(sy * s + 0.5), math.floor(pw * s + 0.5), math.floor(sh * s + 0.5), 2 * s)
			end)
		end
	end
	swatch("wallpaper", room.wallpaper or "", py, wallH, Color(181, 185, 197))
	swatch("floor", room.floor or "", py + wallH, floorH, Color(152, 152, 98))
	-- (the floor's edge against the wall)
	d:rect(px, py + wallH, pw, 1, Color(0, 0, 0, 40))
	-- the furni: the first (biggest) in the middle, the rest beside it
	if R.furniPreview then
		local floorFurni = room.furni or {}
		d:clip(px, py, pw, wallH + floorH, function()
			local spots = { { 0, 0 }, { -44, 8 }, { 44, 8 }, { -62, 18 }, { 62, 18 } }
			for i = math.min(#floorFurni, #spots), 1, -1 do
				local sp = spots[i]
				local cx, cy = px + pw / 2 + sp[1], py + wallH + floorH / 2 - 6 + sp[2]
				R.furniPreview(floorFurni[i], math.floor((cx - 40) * s + 0.5), math.floor((cy - 40) * s + 0.5), math.floor(80 * s + 0.5), math.floor(80 * s + 0.5), s * 0.5, 2)
			end
		end)
	end
	-- the name, on a band of the room's colour
	local c = room.color
	local band = c and Color(c.r or 0, c.g or 0, c.b or 0) or Color(30, 114, 149)
	local ny = py + wallH + floorH + 4
	d:round(3, px, ny, pw, CARD_H - (ny - y) - 6, band)
	d:text(room.name or "", 14.4, x + CARD_W / 2, ny + (CARD_H - (ny - y) - 6) / 2, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
end

function SP.open(rooms)
	SP.rooms = rooms or {}
	SP.chosen = SP.rooms[1] and SP.rooms[1].id or nil
	SP.done = false
	local n = #SP.rooms
	local cols = math.min(COLS, math.max(1, n))
	local W = 9 * 2 + cols * CARD_W + (cols - 1) * GAP
	W = math.max(W, 360)
	local w = U.window("starter-rooms", W, 400, function(w, d)
		d:card(T("nux.roomchooser.title", "Pick your room"))
		local x0, y = 9, 34 + 10
		for _, l in ipairs(d:wrap(T("nux.roomchooser.info", "Welcome! Choose a room of your own to start with. It's yours to decorate, and there's a gift waiting for you inside."), 14.4, W - 18)) do
			d:text(l, 14.4, x0, y, BLACK)
			y = y + 21.6
		end
		y = y + 8
		local gridW = cols * CARD_W + (cols - 1) * GAP
		local gx = math.floor((W - gridW) / 2)
		for i, room in ipairs(SP.rooms) do
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			local cx, cy = gx + col * (CARD_W + GAP), y + row * (CARD_H + GAP)
			d:click(cx, cy, CARD_W, CARD_H, function() SP.chosen = room.id end)
			card(d, room, cx, cy, SP.chosen == room.id)
		end
		y = y + math.ceil(n / cols) * (CARD_H + GAP) + 4
		if SP.error then
			for _, l in ipairs(d:wrap(SP.error, 14.4, W - 18)) do
				d:text(l, 14.4, x0, y, U.C.danger)
				y = y + 21.6
			end
			y = y + 4
		end
		local busy = SP.done
		d:btn(x0, y, W - 18, 28, U.C.success, function()
			if not SP.chosen or SP.done then return end
			SP.done = true
			SP.error = nil
			P.send("starter.choose", { id = SP.chosen })
		end, busy or not SP.chosen)
		d:text(T("nux.roomchooser.choose", "Choose this room"), 12.6, W / 2, y + 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		w:setHeight(y + 28 + 9)
	end)
	-- closed without choosing: to the hotel's first room (it's offered again next time)
	w.onClose = function()
		if not SP.done then P.send("starter.skip", {}) end
	end
end

-- (opened once the loading screen has gone)
P.receive("starter.offer", function(_, data)
	SP.error = nil
	SP.pending = data.rooms or {}
end)

P.receive("starter.error", function(_, data)
	SP.done = false
	SP.error = tostring(data.message or "")
end)

-- in a room (the chosen one): the picker goes
hook.Add("Think", "bobba.starterPicker", function()
	if SP.pending and not (BOBBA.loading and BOBBA.loading.active) then
		local rooms = SP.pending
		SP.pending = nil
		SP.open(rooms)
	end
	local w = U.windows["starter-rooms"]
	if w and SP.done and R.current and R.current.id then
		w:close()
	end
end)
