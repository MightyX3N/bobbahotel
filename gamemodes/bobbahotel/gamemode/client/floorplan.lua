-- The floor plan editor (client), nitro-react's FloorplanEditorView: draw tiles and their heights,
-- move the door and turn which way people come in, the walls' height and thickness, the floor's
-- thickness; Import/Export shows the plan as text. The server's side is hotel/floorplan.lua.
-- Opened from the room info (owner and staff).
--
-- On the canvas: hold the left mouse button and move to draw; the right (or middle) button drags it
-- around, the wheel scrolls it.

BOBBA.floorplanEditor = BOBBA.floorplanEditor or {}
local FE = BOBBA.floorplanEditor
local U = BOBBA.ui
local P = BOBBA.platform
local R = BOBBA.room
local T = function(key, fallback, vars) return U.text(key, fallback, vars) end

local W, H = 760, 500
local TILE = 32 -- a tile's width on the canvas (Nitro's TILE_SIZE); half as high
local PAD = 10

-- Nitro's heights and their colours (Constants.ts)
FE.HEIGHTS = "x0123456789abcdefghijklmnopq"
FE.COLORS = {
	x = "101010", ["0"] = "0065ff", ["1"] = "0091ff", ["2"] = "00bcff", ["3"] = "00e8ff", ["4"] = "00ffea", ["5"] = "00ffbf",
	["6"] = "00ff93", ["7"] = "00ff68", ["8"] = "00ff3d", ["9"] = "19ff00", a = "44ff00", b = "70ff00", c = "9bff00",
	d = "f2ff00", e = "ffe000", f = "ffb500", g = "ff8900", h = "ff5e00", i = "ff3200", j = "ff0700", k = "ff0023",
	l = "ff007a", m = "ff00a5", n = "ff00d1", o = "ff00fc", p = "d600ff", q = "aa00ff",
}
local colorCache = {}
local function heightColor(c)
	if not colorCache[c] then
		local hex = FE.COLORS[c] or "ffffff"
		colorCache[c] = Color(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
	end
	return colorCache[c]
end
FE.heightColor = heightColor

FE.SET, FE.UNSET, FE.UP, FE.DOWN, FE.DOOR = "set", "unset", "up", "down", "door"

-- thickness: the server's -2..1, the editor's choices 0..3 (Nitro's convertNumbersForSaving)
local function thickToChoice(v) return ({ [-2] = 0, [-1] = 1, [0] = 2, [1] = 3 })[tonumber(v) or 0] or 2 end
local function choiceToThick(c) return ({ [0] = -2, [1] = -1, [2] = 0, [3] = 1 })[c] or 0 end

-- --- the plan --------------------------------------------------------------------------------------------
-- FE.st = { size, tiles[y][x] (0-based, a height letter or "x"), blocked["x,y"], door = { x, y }, dir,
--           wallHeight (shown: the server's + 1, 0 = automatic), thickWall, thickFloor (choices 0..3),
--           action, height (0..26), orig (what the server sent), scrollX, scrollY }
local function setTiles(st, heightmap)
	st.tiles = {}
	local rows = {}
	for row in (heightmap .. "\r"):gmatch("([^\r]*)\r") do rows[#rows + 1] = row end
	while #rows > 0 and rows[#rows] == "" do rows[#rows] = nil end
	for y = 0, st.size - 1 do
		local row = rows[y + 1] or ""
		local line = {}
		for x = 0, st.size - 1 do
			local c = row:sub(x + 1, x + 1):lower()
			line[x] = (c == "" or c == "x" or not FE.HEIGHTS:find(c, 1, true)) and "x" or c
		end
		st.tiles[y] = line
	end
end

-- the plan as the server wants it: rows from the top-left to the last tile (Nitro's getCurrentTilemapString)
function FE.tilemapString(st)
	local w, h = 0, 0
	for y = 0, st.size - 1 do
		for x = 0, st.size - 1 do
			if st.tiles[y][x] ~= "x" then w, h = math.max(w, x + 1), math.max(h, y + 1) end
		end
	end
	local rows = {}
	for y = 0, h - 1 do
		local row = {}
		for x = 0, w - 1 do row[#row + 1] = st.tiles[y][x] end
		rows[#rows + 1] = table.concat(row)
	end
	return table.concat(rows, "\r")
end

local function worldPos(st, x, y)
	return (x - y) * TILE / 2 + (st.size - 1) * TILE / 2 + PAD, (x + y) * TILE / 4 + PAD
end
local function worldSize(st)
	return (2 * st.size) * TILE / 2 + 2 * PAD, (2 * st.size) * TILE / 4 + 2 * PAD
end
-- the tile under a point of the canvas's world (nil off the grid)
local function tileAt(st, wx, wy)
	local X = wx - PAD - (st.size - 1) * TILE / 2 - TILE / 2
	local Y = wy - PAD - TILE / 4
	local a, b = X / (TILE / 2), Y / (TILE / 4)
	local x, y = math.floor((a + b) / 2 + 0.5), math.floor((b - a) / 2 + 0.5)
	if x < 0 or y < 0 or x >= st.size or y >= st.size then return nil end
	return x, y
end

-- the canvas looks at the room's tiles (Nitro scrolls a third of the way in; the middle of the room is better)
local function centre(st, cw, ch)
	local minX, maxX, minY, maxY
	for y = 0, st.size - 1 do
		for x = 0, st.size - 1 do
			if st.tiles[y][x] ~= "x" then
				local wx, wy = worldPos(st, x, y)
				minX, maxX = math.min(minX or wx, wx), math.max(maxX or wx, wx + TILE)
				minY, maxY = math.min(minY or wy, wy), math.max(maxY or wy, wy + TILE / 2)
			end
		end
	end
	local ww, wh = worldSize(st)
	if not minX then minX, maxX, minY, maxY = 0, ww, 0, wh end
	st.scrollX = math.Clamp((minX + maxX) / 2 - cw / 2, 0, math.max(0, ww - cw))
	st.scrollY = math.Clamp((minY + maxY) / 2 - ch / 2, 0, math.max(0, wh - ch))
	st.recentred = true
end

-- what a click (or a drag over) does to a tile (Nitro's FloorplanEditor.onClick)
function FE.apply(st, x, y)
	local tile = st.tiles[y] and st.tiles[y][x]
	if not tile then return false end
	local idx = FE.HEIGHTS:find(tile, 1, true) - 1
	local to
	if st.action == FE.DOOR then
		if tile ~= "x" then st.door = { x = x, y = y } return true end
		return false
	elseif st.action == FE.UP then
		if tile == "x" then return false end
		to = idx + 1
	elseif st.action == FE.DOWN then
		if tile == "x" or idx <= 1 then return false end
		to = idx - 1
	elseif st.action == FE.SET then
		to = st.height + 1
	elseif st.action == FE.UNSET then
		to = 0
	end
	if not to or to == idx or to < 0 or to >= #FE.HEIGHTS then return false end
	if st.blocked[x .. "," .. y] then return false end
	st.tiles[y][x] = FE.HEIGHTS:sub(to + 1, to + 1)
	return true
end

-- --- drawing ----------------------------------------------------------------------------------------------
local BLACK, WHITE = Color(0, 0, 0), Color(255, 255, 255)

local function diamond(s, x, y, w, h, c, edge)
	local pts = { { x = (x + w / 2) * s, y = y * s }, { x = (x + w) * s, y = (y + h / 2) * s }, { x = (x + w / 2) * s, y = (y + h) * s }, { x = x * s, y = (y + h / 2) * s } }
	draw.NoTexture()
	if edge then
		surface.SetDrawColor(edge.r, edge.g, edge.b, edge.a or 255)
		surface.DrawPoly(pts)
		local k = 1.5
		pts = { { x = (x + w / 2) * s, y = (y + k) * s }, { x = (x + w - 2 * k) * s, y = (y + h / 2) * s }, { x = (x + w / 2) * s, y = (y + h - k) * s }, { x = (x + 2 * k) * s, y = (y + h / 2) * s } }
	end
	surface.SetDrawColor(c.r, c.g, c.b, c.a or 255)
	surface.DrawPoly(pts)
end

local BLOCKED = Color(214, 40, 40)
local EDGE = Color(34, 34, 34)
local function drawCanvas(d, st, cx, cy, cw, ch, hx, hy)
	local s = d.s
	local base, entry = U.icon("fp-tile"), U.icon("fp-entry")
	d:rect(cx, cy, cw, ch, BLACK)
	d:clip(cx, cy, cw, ch, function()
		local ox, oy = cx - st.scrollX, cy - st.scrollY
		local useIcons = base and base.material and entry and entry.material
		if useIcons then
			render.PushFilterMag(TEXFILTER.POINT)
			render.PushFilterMin(TEXFILTER.POINT)
		end
		local current
		for y = 0, st.size - 1 do
			local row = st.tiles[y]
			for x = 0, st.size - 1 do
				local wx, wy = worldPos(st, x, y)
				local sx, sy = ox + wx, oy + wy
				if sx + TILE >= cx and sx <= cx + cw and sy + TILE / 2 >= cy and sy <= cy + ch then
					local door = st.door.x == x and st.door.y == y
					local c = st.blocked[x .. "," .. y] and BLOCKED or heightColor(row[x])
					if useIcons then
						local ic = door and entry or base
						if current ~= ic then surface.SetMaterial(ic.material) current = ic end
						if door then surface.SetDrawColor(255, 255, 255, 255) else surface.SetDrawColor(c.r, c.g, c.b, 255) end
						local X, Y = math.floor((sx - 1) * s + 0.5), math.floor(sy * s + 0.5)
						surface.DrawTexturedRectUV(X, Y, math.floor((sx - 1 + ic.width) * s + 0.5) - X, math.floor((sy + ic.height) * s + 0.5) - Y, 0, 0, ic.u, ic.v)
					else
						current = nil
						diamond(s, sx, sy, TILE, TILE / 2, door and Color(30, 90, 220) or c, EDGE)
					end
				end
			end
		end
		if useIcons then
			render.PopFilterMin()
			render.PopFilterMag()
		end
		-- the tile under the mouse
		if hx then
			local wx, wy = worldPos(st, hx, hy)
			diamond(s, ox + wx, oy + wy, TILE, TILE / 2, Color(255, 255, 255, 90))
		end
	end)
end

-- a slider (nitro-slider): a grey track, a thumb in the height's colour with the number on it
local function drawSlider(d, st, x, y, w)
	local h = 20
	local frac = st.height / 26
	d:round(4, x, y + h / 2 - 3, w, 6, Color(195, 195, 195))
	local tw = 28
	local tx = x + frac * (w - tw)
	local c = heightColor(FE.HEIGHTS:sub(st.height + 2, st.height + 2))
	d:round(4, tx, y, tw, h, Color(0, 0, 0, 80))
	d:round(4, tx + 1, y + 1, tw - 2, h - 2, c)
	d:text(tostring(st.height), 12.6, tx + tw / 2, y + h / 2, BLACK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
	d:click(x, y - 2, w, h + 4, function() st.sliding = true end)
	if st.sliding then
		if input.IsMouseDown(MOUSE_LEFT) then
			local v = math.floor(((d.w.mx - x - tw / 2) / (w - tw)) * 26 + 0.5)
			st.height = math.Clamp(v, 0, 26)
		else
			st.sliding = false
		end
	end
end

local function fmtWall(v)
	if v == math.floor(v) then return tostring(math.floor(v)) end
	return (string.format("%.3f", v):gsub("0+$", ""))
end

local function drawEditor(w, d)
	local st = FE.st
	if not st then w:close() return end
	d:slimCard(T("floor.plan.editor.title", "Floor Plan Editor"))
	local x0, y = 9, 31 + 8
	local cw = W - 18
	-- row 1: the drawing tools | the entry direction | the walls' height
	local colA, colB = math.floor(cw * 5 / 12), math.floor(cw * 4 / 12)
	d:text(T("floor.plan.editor.draw.mode", "Drawing mode"), 14.4, x0, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	local tools = { { FE.SET, "fp-set" }, { FE.UNSET, "fp-unset" }, false, { FE.UP, "fp-up" }, { FE.DOWN, "fp-down" }, false, { FE.DOOR, "fp-door" } }
	local tx, ty, ts = x0, y + 24, 46
	for _, t in ipairs(tools) do
		if t then
			local active = st.action == t[1]
			d:click(tx, ty, ts, ts, function() st.action = t[1] end)
			d:gridItem(tx, ty, ts, ts, active)
			if not d:icon(t[2], tx, ty, ts, ts) then
				d:text(({ set = "+", unset = "-", up = "^", down = "v", door = "D" })[t[1]], 18, tx + ts / 2, ty + ts / 2, BLACK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
			end
			tx = tx + ts + 4
		else
			tx = tx + 12
		end
	end
	-- the entry direction: you, standing the way people will come in (click to turn; the arrows turn either way)
	local bx = x0 + colA
	d:text(T("floor.plan.editor.enter.direction", "Entrance direction"), 14.4, bx + colB / 2, y, BLACK, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, true)
	local ax, ay, aw, ah = bx + colB / 2 - 40, y + 22, 80, 50
	d:click(ax, ay, aw, ah, function() st.dir = (st.dir + 1) % 8 end)
	d:round(4, ax, ay, aw, ah, Color(0, 0, 0, 20))
	-- (the tile they stand on)
	diamond(d.s, ax + aw / 2 - 16, ay + ah - 14, 32, 16, Color(0, 101, 255, 170), EDGE)
	local me = BOBBA.hud and BOBBA.hud.lastMe
	local drew = false
	if me and R.figureDrawer then
		FE.unit = FE.unit or { id = "floorplan" }
		FE.unit.figure, FE.unit.gender = me.figure, me.gender
		local s = d.s
		d:clip(ax, ay, aw, ah, function()
			local ok, res = pcall(R.figureDrawer, FE.unit, { x = 0, y = 0, z = 0, sx = (ax + aw / 2) * s, sy = (ay + ah - 6) * s, k = s * 0.5, dir = st.dir, posture = "std", now = SysTime(), talk = false })
			drew = ok and res ~= false
		end)
	end
	if not drew then
		-- (no avatars: an arrow the way they face)
		local a = (st.dir * 45 - 135) * math.pi / 180
		local mx, my = ax + aw / 2, ay + ah / 2
		d:line(mx - math.cos(a) * 14, my - math.sin(a) * 7, mx + math.cos(a) * 14, my + math.sin(a) * 7, 3, BLACK)
	end
	d:click(ax - 22, ay + ah / 2 - 10, 20, 20, function() st.dir = (st.dir + 7) % 8 end)
	d:fa("chevron-left", ax - 20, ay + ah / 2 - 8, 16, Color(52, 58, 64))
	d:click(ax + aw + 2, ay + ah / 2 - 10, 20, 20, function() st.dir = (st.dir + 1) % 8 end)
	d:fa("chevron-right", ax + aw + 6, ay + ah / 2 - 8, 16, Color(52, 58, 64))
	-- the walls' height: 0 = as high as the room needs (the hotel's default), up to 16
	local cx = x0 + colA + colB
	local ccw = cw - colA - colB
	d:text(T("floor.editor.wall.height", "Wall height"), 14.4, cx, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	local iy = y + 30
	local function setWall(v) st.wallHeight = math.Clamp(math.floor(v * 8 + 0.5) / 8, 0, 16) end
	d:click(cx, iy, 16, 28, function() setWall(math.ceil(st.wallHeight) - 1) end)
	d:fa("chevron-left", cx, iy + 6, 16, Color(52, 58, 64))
	local e = d:input("wallHeight", cx + 20, iy, 60, 28, { value = fmtWall(st.wallHeight), max = 6, onChange = function(t)
		local v = tonumber(t)
		if v then setWall(v) end
	end })
	if IsValid(e) and not e:HasFocus() and e:GetValue() ~= fmtWall(st.wallHeight) then e:SetText(fmtWall(st.wallHeight)) end
	d:click(cx + 84, iy, 16, 28, function() setWall(math.floor(st.wallHeight) + 1) end)
	d:fa("chevron-right", cx + 86, iy + 6, 16, Color(52, 58, 64))
	if st.wallHeight == 0 then d:text(T("bobba.floorplan.wall.auto", "automatic"), 12.6, cx + 106, iy + 14, U.C.muted or Color(108, 117, 125), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	-- row 2: the tile height to draw with | the walls' and floor's thickness
	y = y + 24 + 46 + 10
	local half = math.floor(cw / 2)
	d:text(T("floor.plan.editor.tile.height", "Tile height") .. ": " .. st.height, 14.4, x0, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	drawSlider(d, st, x0, y + 24, half - 20)
	d:text(T("floor.plan.editor.room.options", "Room options"), 14.4, x0 + half, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	local selW = math.floor((cw - half - 6) / 2)
	local function opts(kind)
		return { { 0, T("navigator.roomsettings." .. kind .. "_thickness.thinnest", "Thinnest") }, { 1, T("navigator.roomsettings." .. kind .. "_thickness.thin", "Thin") },
			{ 2, T("navigator.roomsettings." .. kind .. "_thickness.normal", "Normal") }, { 3, T("navigator.roomsettings." .. kind .. "_thickness.thick", "Thick") } }
	end
	-- the canvas (drawn before the selects so their lists open over it)
	local canY = y + 24 + 30
	local canH = H - 9 - 28 - 8 - canY
	local ww, wh = worldSize(st)
	if not st.scrollX then centre(st, cw, canH) end
	-- (the wheel scrolls it up and down: the window's scrolling)
	local sc = d.w.scrolls.fpcanvas
	if not sc then sc = { offset = st.scrollY } d.w.scrolls.fpcanvas = sc end
	if st.recentred then sc.offset = st.scrollY st.recentred = false end
	sc.x, sc.y, sc.w, sc.h, sc.max = x0, canY, cw, canH, math.max(0, wh - canH)
	sc.offset = math.Clamp(sc.offset, 0, sc.max)
	st.scrollY = sc.offset
	local mx, my = d.w.mx or -1, d.w.my or -1
	local over = mx >= x0 and mx < x0 + cw and my >= canY and my < canY + canH and not d.w.openSelect
	local hx, hy
	if over then hx, hy = tileAt(st, mx - x0 + st.scrollX, my - canY + st.scrollY) end
	-- drawing: pressed on the canvas, then every tile the mouse goes over
	d:click(x0, canY, cw, canH, function()
		st.painting = true
		st.lastTile = nil
	end)
	if st.painting then
		if not input.IsMouseDown(MOUSE_LEFT) then st.painting = false
		elseif hx and (not st.lastTile or st.lastTile[1] ~= hx or st.lastTile[2] ~= hy) then
			st.lastTile = { hx, hy }
			FE.apply(st, hx, hy)
		end
	end
	-- dragging it around: the right or middle button
	local panDown = input.IsMouseDown(MOUSE_RIGHT) or input.IsMouseDown(MOUSE_MIDDLE)
	if panDown and over and not st.pan and not st.panHeld then st.pan = { mx = mx, my = my, sx = st.scrollX, sy = st.scrollY } end
	st.panHeld = panDown
	if st.pan then
		if not panDown then st.pan = nil
		else
			st.scrollX = math.Clamp(st.pan.sx - (mx - st.pan.mx), 0, math.max(0, ww - cw))
			st.scrollY = math.Clamp(st.pan.sy - (my - st.pan.my), 0, math.max(0, wh - canH))
			sc.offset = st.scrollY
		end
	end
	drawCanvas(d, st, x0, canY, cw, canH, hx, hy)
	if hx then
		local tile = st.tiles[hy][hx]
		local label = hx .. ", " .. hy .. (tile ~= "x" and ("  " .. T("floor.plan.editor.tile.height", "Tile height") .. ": " .. (FE.HEIGHTS:find(tile, 1, true) - 2)) or "")
		d:text(label, 12.6, x0 + 6, canY + 4, WHITE)
	end
	d:select("wallThick", x0 + half, y + 24, selW, 28, opts("wall"), st.thickWall, function(v) st.thickWall = v end)
	d:select("floorThick", x0 + half + selW + 6, y + 24, selW, 28, opts("floor"), st.thickFloor, function(v) st.thickFloor = v end)
	-- the buttons: reload | preview (not yet, as in Nitro), import/export, save
	local by = H - 9 - 28
	local function button(bx2, label, color, fn, disabled)
		local bw = d:textWidth(label, 12.6) + 24
		if bx2 < 0 then bx2 = -bx2 - bw end
		d:btn(bx2, by, bw, 28, color, fn, disabled)
		d:text(label, 12.6, bx2 + bw / 2, by + 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return bx2
	end
	button(x0, T("floor.plan.editor.reload", "Reload"), U.C.primary, function() FE.revert() end)
	local rx = W - 9
	rx = button(-rx, T("floor.plan.editor.save", "Save"), U.C.success, function() FE.save() end, st.saving)
	rx = button(-(rx - 4), T("floor.plan.editor.import.export", "Import/Export"), U.C.primary, function() FE.openImportExport() end)
	button(-(rx - 4), T("floor.plan.editor.preview", "Preview"), U.C.primary, function() end, true)
end

-- --- import / export: the plan as text --------------------------------------------------------------------
local function drawImportExport(w, d)
	local st = FE.st
	if not st then w:close() return end
	local IW, IH = 500, 475
	d:slimCard(T("floor.plan.editor.import.export", "Import/Export"))
	local e = d:input("map", 9, 31 + 8, IW - 18, IH - 31 - 8 - 9 - 28 - 8, { multiline = true, value = FE.ioText or "", onChange = function(t) FE.ioText = t end })
	if FE.ioReset and IsValid(e) then e:SetText(FE.ioText) FE.ioReset = false end
	local by = IH - 9 - 28
	local lt = T("floor.plan.editor.revert.to.last.received.map", "Revert to last received map")
	local lw = d:textWidth(lt, 12.6) + 24
	d:btn(9, by, lw, 28, U.C.primary, function()
		FE.ioText = st.orig.heightmap:gsub("\r", "\n")
		FE.ioReset = true
	end)
	d:text(lt, 12.6, 9 + lw / 2, by + 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local sv = T("floor.plan.editor.save", "Save")
	local sw = d:textWidth(sv, 12.6) + 24
	d:btn(IW - 9 - sw, by, sw, 28, U.C.success, function()
		-- (as Nitro: the text, with the door and walls as they were last received)
		local o = st.orig
		P.send("floorplan.save", { heightmap = (FE.ioText or ""):gsub("\r\n", "\r"):gsub("\n", "\r"), doorX = o.door.x, doorY = o.door.y, doorDir = o.door.dir,
			wallThickness = o.wallThickness, floorThickness = o.floorThickness, wallHeight = o.wallHeight })
	end)
	d:text(sv, 12.6, IW - 9 - sw / 2, by + 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function FE.openImportExport()
	if not FE.st then return end
	FE.ioText = FE.tilemapString(FE.st):gsub("\r", "\n")
	FE.ioReset = true
	U.toggle("floorplan-io", function() U.window("floorplan-io", 500, 475, drawImportExport) end)
end

-- --- opening, reverting, saving ------------------------------------------------------------------------------
local function fromData(data)
	local st = FE.st or {}
	st.orig = data
	st.size = tonumber(data.maxSize) or 64
	setTiles(st, data.heightmap or "")
	st.blocked = {}
	for _, k in ipairs(data.blocked or {}) do st.blocked[k] = true end
	st.door = { x = data.door.x, y = data.door.y }
	st.dir = tonumber(data.door.dir) or 2
	local wh = tonumber(data.wallHeight) or -1
	st.wallHeight = wh + 1
	st.thickWall, st.thickFloor = thickToChoice(data.wallThickness), thickToChoice(data.floorThickness)
	st.action = st.action or FE.SET
	st.height = st.height or 0
	st.saving = false
	return st
end

function FE.revert()
	if FE.st and FE.st.orig then
		fromData(FE.st.orig)
		FE.st.scrollX = nil
	end
end

function FE.save()
	local st = FE.st
	if not st or st.saving then return end
	-- (the walls' height as it was received when it wasn't changed: it may not be a whole number)
	local wall = st.wallHeight - 1
	if math.abs(wall - (tonumber(st.orig.wallHeight) or -1)) < 0.001 then wall = tonumber(st.orig.wallHeight) or -1 end
	if wall < 0 then wall = -1 end
	st.saving = true
	P.send("floorplan.save", { heightmap = FE.tilemapString(st), doorX = st.door.x, doorY = st.door.y, doorDir = st.dir,
		wallThickness = choiceToThick(st.thickWall), floorThickness = choiceToThick(st.thickFloor), wallHeight = wall })
end

function FE.open()
	P.send("floorplan.get", {})
end

P.receive("floorplan.data", function(_, data)
	FE.st = nil
	FE.st = fromData(data)
	if not U.isOpen("floorplan-editor") then U.window("floorplan-editor", W, H, drawEditor) end
end)

P.receive("floorplan.error", function(_, data)
	if FE.st then FE.st.saving = false end
	local texts = {}
	for _, e in ipairs(data.errors or {}) do texts[#texts + 1] = U.plain and U.plain(T(e[1], e[2])) or T(e[1], e[2]) end
	U.alert(T("floor.plan.editor.title", "Floor Plan Editor"), table.concat(texts, " "))
end)

-- saved (the room comes again) or gone to another room: the editor closes, as Nitro's does
BOBBA.events.on("roomShown", "bobba.floorplanEditor", function(data)
	-- (the same room sent again for another reason, e.g. its wallpaper: the editor stays)
	local st = FE.st
	if st and not st.saving and data and st.orig and data.id == st.orig.id then return end
	for _, id in ipairs({ "floorplan-editor", "floorplan-io" }) do
		if U.windows[id] then U.windows[id]:close() end
	end
	FE.st = nil
end)

-- (on the canvas, the wheel isn't the room's zoom)
FE.WIDTH, FE.HEIGHT = W, H
