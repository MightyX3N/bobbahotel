-- The start screen: pick a hotel to check in to (your own on this computer, and hotels you've
-- added), what the chosen one is like, settings; on the first start finding Garry's Mod. Neutral (not
-- any pack's look): a sunset on the left, the hotel's skyline on the right. Each hotel's own page
-- (its "website") comes after checking in: the gamemode draws it (client/website.lua).
-- Drawn in 1280 x 800 "page pixels", scaled to the window; the halves stretch with it.

local FS = require("bobba.fs")
local ST = require("bobba.steam")
local SQ = require("bobba.sqlite")
local lg = love.graphics

local L = {}
local settings, actions
local page = "servers" -- servers, setup
local sheet -- nil, "settings", "add"
local data = {} -- what your hotel's database says (L.refresh)
local regions = {}
local hoverId
local s = 1
local fields = {}
local focus
local message -- { text, where, good }
local candidate
local VERSION = "Bobba (desktop)"

local function rgb(h) return { tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16) } end
local C = {
	ink = rgb("2A1206"), ink2 = rgb("4A1A06"), ink3 = rgb("6B3A1E"), card = rgb("FFF9F0"), sel = rgb("FFE2C2"), cream = rgb("FFF6E8"),
	rust = rgb("7A2E0E"), dash = rgb("E3B98F"), green = rgb("1E7A46"), grey = rgb("8A5A3C"), red = rgb("C0392B"),
	top = rgb("FF6B4A"), bottom = rgb("FFC24B"), sky1 = rgb("3B1A3F"), sky2 = rgb("A8432A"), sky3 = rgb("E8873A"),
	sun = rgb("FFC24B"), b1 = rgb("2A1630"), b2 = rgb("331A38"), win = rgb("FFD27A"), mint = rgb("6EE7A8"), field = rgb("F3D9BF"),
	orange = rgb("FF9F5A"), sky = rgb("9DB4FF"), leaf = rgb("B7E4C7"), lilac = rgb("B98CFF"), pink = rgb("F26B8A"),
}
local function col(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end

-- --- fonts ----------------------------------------------------------------------------------------
local fontFiles = { r = "fonts/PlusJakartaSans-Medium.ttf", b = "fonts/PlusJakartaSans-Bold.ttf", x = "fonts/PlusJakartaSans-ExtraBold.ttf", logo = "fonts/LilitaOne-Regular.ttf" }
local fonts = {}
local function font(px, kind)
	kind = kind or "r"
	local size = math.max(6, math.floor(px * s + 0.5))
	local key = kind .. size
	if not fonts[key] then
		local ok, f = pcall(lg.newFont, fontFiles[kind], size)
		fonts[key] = require("bobba.fallback").apply(ok and f or lg.newFont(size), size)
	end
	return fonts[key]
end
local function spaced(t, kind) t = tostring(t) if kind == "b" or kind == "x" then t = t:gsub(" ", " \226\128\138") end return t end
local function text(t, x, y, px, kind, c, align, w, a)
	local f = font(px, kind)
	col(c or C.ink, a)
	t = spaced(t, kind)
	local tw = f:getWidth(t) / s
	if align == "center" then x = x + (w - tw) / 2 elseif align == "right" then x = x + w - tw end
	lg.print(t, f, math.floor(x * s + 0.5) / s, math.floor(y * s + 0.5) / s, 0, 1 / s, 1 / s)
	return tw
end
local function textWidth(t, px, kind) return font(px, kind):getWidth(spaced(t, kind)) / s end
local function para(t, x, y, w, px, kind, c, lineH, maxLines)
	local f = font(px, kind)
	local _, lines = f:getWrap(spaced(t, kind), w * s)
	lineH = lineH or px * 1.5
	for i, l in ipairs(lines) do
		if maxLines and i > maxLines then break end
		text(l, x, y + (i - 1) * lineH, px, kind, c)
	end
	return math.min(#lines, maxLines or #lines) * lineH
end
local function fit(t, px, kind, w)
	t = tostring(t)
	if textWidth(t, px, kind) <= w then return t end
	while #t > 0 and textWidth(t .. "…", px, kind) > w do t = t:gsub("[%z\1-\127\194-\244][\128-\191]*$", "") end
	return t .. "…"
end

-- --- shapes ---------------------------------------------------------------------------------------
local cornerImg
local function corner()
	if cornerImg then return cornerImg end
	local N = 64
	local d = love.image.newImageData(N, N)
	for y = 0, N - 1 do
		for x = 0, N - 1 do
			local dx, dy = N - (x + 0.5), N - (y + 0.5)
			d:setPixel(x, y, 1, 1, 1, math.min(1, math.max(0, N - math.sqrt(dx * dx + dy * dy) + 0.5)))
		end
	end
	cornerImg = lg.newImage(d)
	cornerImg:setFilter("linear", "linear")
	return cornerImg
end
local function box(x, y, w, h, r, c, a)
	col(c, a)
	r = math.min(r or 0, w / 2, h / 2)
	if r <= 0 then lg.rectangle("fill", x, y, w, h) return end
	lg.rectangle("fill", x + r, y, w - 2 * r, h)
	lg.rectangle("fill", x, y + r, r, h - 2 * r)
	lg.rectangle("fill", x + w - r, y + r, r, h - 2 * r)
	local img = corner()
	local k = r / img:getWidth()
	lg.draw(img, x, y, 0, k, k)
	lg.draw(img, x + w, y, 0, -k, k)
	lg.draw(img, x, y + h, 0, k, -k)
	lg.draw(img, x + w, y + h, 0, -k, -k)
end
local function ring(x, y, w, h, r, c, b)
	box(x, y, w, h, r, c)
end
-- a vertical gradient: stops { { t, colour }, ... }
local function gradient(x, y, w, h, stops)
	local verts = {}
	for _, st in ipairs(stops) do
		local c = st[2]
		local yy = y + h * st[1]
		verts[#verts + 1] = { x, yy, 0, 0, c[1] / 255, c[2] / 255, c[3] / 255, 1 }
		verts[#verts + 1] = { x + w, yy, 0, 0, c[1] / 255, c[2] / 255, c[3] / 255, 1 }
	end
	local mesh = lg.newMesh(verts, "strip", "static")
	lg.setColor(1, 1, 1)
	lg.draw(mesh)
end
local function circle(x, y, r, c, a) col(c, a) lg.circle("fill", x, y, r, 64) end
local function dashedBox(x, y, w, h, r, c)
	col(c)
	lg.setLineWidth(2)
	local dash, gap = 8, 6
	local function dline(x1, y1, x2, y2)
		local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
		local n = math.floor(len / (dash + gap))
		for i = 0, n do
			local t0, t1 = i * (dash + gap) / len, math.min(1, (i * (dash + gap) + dash) / len)
			lg.line(x1 + (x2 - x1) * t0, y1 + (y2 - y1) * t0, x1 + (x2 - x1) * t1, y1 + (y2 - y1) * t1)
		end
	end
	dline(x + r, y, x + w - r, y) dline(x + r, y + h, x + w - r, y + h)
	dline(x, y + r, x, y + h - r) dline(x + w, y + r, x + w, y + h - r)
	lg.arc("line", "open", x + r, y + r, r, math.pi, 1.5 * math.pi)
	lg.arc("line", "open", x + w - r, y + r, r, 1.5 * math.pi, 2 * math.pi)
	lg.arc("line", "open", x + r, y + h - r, r, 0.5 * math.pi, math.pi)
	lg.arc("line", "open", x + w - r, y + h - r, r, 0, 0.5 * math.pi)
	lg.setLineWidth(1)
end

local function region(id, x, y, w, h, fn)
	regions[#regions + 1] = { id = id, x = x, y = y, w = w, h = h, fn = fn }
	return hoverId == id
end

-- --- text boxes -------------------------------------------------------------------------------------
local function field(id, value)
	if not fields[id] then fields[id] = { text = value or "" } end
	return fields[id]
end
local function input(id, x, y, w, h, placeholder, onEnter, value)
	local f = field(id, value)
	local focused = focus == id
	box(x, y, w, h, h / 2, focused and C.rust or C.dash)
	box(x + 2, y + 2, w - 4, h - 4, h / 2 - 2, C.cream)
	local px = 15
	local fnt = font(px)
	local sx0 = math.floor((x + 16) * s + L.ox)
	lg.setScissor(sx0, math.floor(y * s + L.oy), math.floor((w - 32) * s), math.floor(h * s))
	local tw = fnt:getWidth(f.text) / s
	local shift = math.max(0, tw - (w - 36))
	if f.text == "" and not focused then text(placeholder or "", x + 18, y + (h - px * 1.3) / 2, px, "r", C.ink3, nil, nil, 0.7)
	else text(f.text, x + 18 - shift, y + (h - px * 1.3) / 2, px, "r", C.ink) end
	if focused and love.timer.getTime() % 1 < 0.5 then
		col(C.ink)
		lg.rectangle("fill", x + 18 + tw - shift + 1, y + 11, math.max(1, math.floor(s)) / s, h - 22)
	end
	lg.setScissor()
	region("input:" .. id, x, y, w, h, function() focus = id end)
	f.onEnter = onEnter
	return f
end

-- buttons: "dark" (the big one), "light", "outline"
local function button(id, label, x, y, w, h, kind, fn, px, disabled)
	local hover = (not disabled) and region(id, x, y, w, h, fn)
	px = px or 16
	if kind == "outline" then
		box(x, y, w, h, h / 2, C.ink, disabled and 0.4 or 1)
		box(x + 2, y + 2, w - 4, h - 4, h / 2 - 2, hover and C.sel or C.card)
		text(label, x, y + (h - px * 1.3) / 2, px, "b", C.ink, "center", w)
	elseif kind == "light" then
		box(x, y, w, h, h / 2, hover and C.sel or C.field)
		text(label, x, y + (h - px * 1.3) / 2, px, "b", C.ink, "center", w)
	else
		box(x, y, w, h, h / 2, hover and C.ink2 or C.ink, disabled and 0.45 or 1)
		text(label, x, y + (h - px * 1.3) / 2, px, "x", C.cream, "center", w)
	end
	return hover
end

-- --- your hotel, and the hotels you've added ----------------------------------------------------------
local function hotelName() return data.hotelName or "Bobba Hotel" end
local function packName()
	if settings.garrysmod and FS.isDir(settings.garrysmod .. "/addons/bobba_habbo") then return "Habbo pack" end
	return "Default pack"
end

function L.refresh()
	data = {}
	local opts = actions.options()
	data.folder = opts.save
	local path = opts.save .. "/" .. opts.database
	if not FS.exists(path) then return end
	local db = SQ.open(path)
	if not db then return end
	local key = SQ.quote(settings.playerKey or "")
	local function row(q) local ok, r = pcall(db.query, db, q) return ok and r and r[1] or nil end
	data.user = row("SELECT * FROM bobbahotel_users WHERE key = " .. key)
	local name = row("SELECT v FROM bobbahotel_settings WHERE k = 'hotel_name'")
	data.hotelName = name and name.v ~= "" and name.v or nil
	local desc = row("SELECT v FROM bobbahotel_settings WHERE k = 'hotel.description'")
	data.description = desc and desc.v ~= "" and desc.v or nil
	local rooms = row("SELECT COUNT(*) AS n FROM bobbahotel_rooms")
	data.rooms = rooms and tonumber(rooms.n) or 0
	local people = row("SELECT COUNT(*) AS n FROM bobbahotel_users")
	data.people = people and tonumber(people.n) or 0
	db:close()
end

-- the list: your hotel first, then the ones added ({ name, address })
local LETTER_COLORS = { C.orange, C.sky, C.leaf, C.lilac, C.pink }
local function servers()
	local list = { { name = hotelName(), info = "On this computer · " .. packName(), status = "Ready", statusColor = C.green, local_ = true } }
	for _, sv in ipairs(settings.servers or {}) do
		list[#list + 1] = { name = sv.name ~= "" and sv.name or sv.address, info = sv.address, status = "Soon", statusColor = C.grey, address = sv.address, saved = sv }
	end
	return list
end
local function chosen()
	local list = servers()
	local i = math.max(1, math.min(#list, settings.chosen or 1))
	return list[i], i
end

-- --- the left: the sunset, the logo, the list, check in ------------------------------------------------
local function logo(cx, y, px)
	local t = "bobba"
	local w = textWidth(t, px, "logo")
	text(t, cx - w / 2 + 8, y + 8, px, "logo", C.rust, nil, nil, 0.45)
	text(t, cx - w / 2 + 4, y + 4, px, "logo", C.rust)
	text(t, cx - w / 2, y, px, "logo", C.cream)
end

local function serverList(cx, y)
	local list = servers()
	local _, ci = chosen()
	local w = 460
	local x = cx - w / 2
	local rowH = 70
	local h = 10 + #list * (rowH + 6) + 56 + 10
	box(x + 4, y + 14, w, h, 26, C.rust, 0.18)
	box(x, y, w, h, 26, C.card)
	local yy = y + 10
	for i, sv in ipairs(list) do
		local on = i == ci
		local hover = region("server" .. i, x + 10, yy, w - 20, rowH, function() settings.chosen = i actions.save() message = nil end)
		if on or hover then box(x + 10, yy, w - 20, rowH, 18, C.sel, on and 1 or 0.55) end
		box(x + 24, yy + 12, 46, 46, 15, LETTER_COLORS[(i - 1) % #LETTER_COLORS + 1])
		text(sv.name:sub(1, 1):upper(), x + 24, yy + 21, 19, "x", C.ink, "center", 46)
		text(fit(sv.name, 16, "b", w - 200), x + 84, yy + 14, 16, "b", C.ink)
		text(fit(sv.info, 13, "r", w - 200), x + 84, yy + 37, 13, "r", C.ink3)
		local stw = textWidth(sv.status, 13, "b")
		circle(x + w - 34 - stw - 10, yy + rowH / 2, 4.5, sv.statusColor)
		text(sv.status, x + w - 34 - stw, yy + rowH / 2 - 9, 13, "b", sv.statusColor)
		-- (an added one can be taken off)
		if sv.saved and hover then
			local rx = x + w - 34 - stw - 44
			if region("remove" .. i, rx, yy + 20, 30, 30, function()
				for j, o in ipairs(settings.servers) do if o == sv.saved then table.remove(settings.servers, j) break end end
				settings.chosen = 1
				actions.save()
			end) then box(rx, yy + 20, 30, 30, 15, C.field) end
			text("×", rx, yy + 23, 18, "b", C.ink2, "center", 30)
		end
		yy = yy + rowH + 6
	end
	local hover = region("add", x + 10, yy, w - 20, 50, function() sheet = "add" focus = "addname" message = nil end)
	if hover then box(x + 10, yy, w - 20, 50, 18, C.sel, 0.5) end
	dashedBox(x + 10, yy, w - 20, 50, 18, C.dash)
	text("+  Add a server", x + 10, yy + 15, 15, "b", C.rust, "center", w - 20)
	return h
end

local function leftPanel(x0, W, H)
	gradient(x0, 0, W, H, { { 0, C.top }, { 1, C.bottom } })
	local cx = x0 + W / 2
	-- settings and full screen
	local hv = region("menu", x0 + 16, 14, 40, 40, function() sheet = sheet == "settings" and nil or "settings" message = nil end)
	box(x0 + 16, 14, 40, 40, 12, C.ink, hv and 0.28 or 0.18)
	col(C.ink)
	for i = 0, 2 do lg.rectangle("fill", x0 + 26, 25 + i * 7, 20, 2.4) end
	local hf = region("full", x0 + 64, 14, 40, 40, function()
		local Win = require("bobba.window")
		Win.toggle()
		settings.fullscreen = Win.full()
		actions.save()
	end)
	box(x0 + 64, 14, 40, 40, 12, C.ink, hf and 0.28 or 0.18)
	col(C.ink)
	lg.setLineWidth(2.2)
	lg.line(x0 + 78, 26, x0 + 92, 26, x0 + 92, 40) lg.line(x0 + 76, 28, x0 + 76, 42, x0 + 90, 42)
	lg.setLineWidth(1)
	if page == "setup" then
		logo(cx, 100, 76)
		L.setupCard(cx, 230)
		text(VERSION, x0 + 16, H - 28, 12, "b", C.ink2)
		return
	end
	local top = math.max(60, (H - 640) / 2)
	logo(cx, top + 10, 76)
	text("Pick a hotel to check in", cx - 230, top + 104, 15, "b", C.ink2, "center", 460)
	local lh = serverList(cx, top + 140)
	local sv = chosen()
	local by = top + 140 + lh + 22
	button("checkin", "Check in to " .. fit(sv.name, 18, "x", 300), cx - 230, by, 460, 58, "dark", function() L.enter() end, 18)
	if message and message.where == "checkin" then
		para(message.text, cx - 230, by + 70, 460, 13, "b", message.good and C.green or C.ink2, 18)
	else
		text("Your own hotel runs right here, like GMod's singleplayer.", cx - 230, by + 72, 13, "b", C.ink2, "center", 460)
	end
	text(VERSION, x0 + 16, H - 28, 12, "b", C.ink2)
	if sheet then L.sheetCard(cx, top + 120) end
end

-- --- the right: the chosen hotel ------------------------------------------------------------------------------
local function rightPanel(x0, W, H)
	gradient(x0, 0, W, H, { { 0, C.sky1 }, { 0.7, C.sky2 }, { 1, C.sky3 } })
	-- the skyline (from the bottom; the sun behind it)
	local bx = x0 + W / 2 - 320
	local base = H
	circle(bx + 470, base - 190, 120, C.sun, 0.9)
	local bld = { { 90, 280, 90, C.b1 }, { 190, 340, 120, C.b2 }, { 330, 240, 80, C.b1 }, { 420, 180, 150, C.b2 } }
	for _, b in ipairs(bld) do box(bx + b[1], base - b[2], b[3], b[2] + 10, 6, b[4]) end
	col(C.win)
	for _, wnd in ipairs({ { 110, 250 }, { 146, 250 }, { 110, 210 }, { 212, 310 }, { 246, 310 }, { 280, 270 }, { 212, 230 }, { 246, 190 }, { 350, 210 }, { 380, 170 }, { 444, 150 }, { 480, 150 }, { 516, 110 } }) do
		lg.rectangle("fill", bx + wnd[1], base - wnd[2], 15, 19, 2, 2)
	end
	local sv = chosen()
	local x = x0 + 56
	local y = math.max(70, (H - 640) / 2 + 30)
	local pill = sv.local_ and "On this computer" or "Somewhere else"
	local pw = textWidth(pill, 13, "b") + 40
	box(x, y, pw, 30, 14, C.cream, 0.16)
	circle(x + 16, y + 15, 4.5, sv.local_ and C.mint or C.dash)
	text(pill, x + 28, y + 7, 13, "b", C.cream)
	y = y + 50
	local nameH = para(sv.name, x, y, W - 112, 56, "logo", C.cream, 60, 2)
	y = y + nameH + 12
	local desc
	if sv.local_ then
		desc = data.description or ("Your own hotel. " .. (data.rooms or 0) .. " rooms so far, and everyone who's checked in keeps their rooms, furni and friends here.")
	else
		desc = "Hotels on other computers open when the hotel server comes: then you'll check in here the same way."
	end
	y = y + para(desc, x, y, math.min(470, W - 112), 17, "r", rgb("F6DCCB"), 26, 5) + 22
	local tags = sv.local_ and { packName(), "English", "as " .. (settings.playerName or "you") } or { sv.address or "", "Coming later" }
	local tx = x
	for _, t in ipairs(tags) do
		local tw = textWidth(t, 13, "b") + 24
		if tx + tw > x0 + W - 40 then tx = x y = y + 40 end
		box(tx, y, tw, 32, 12, C.cream, 0.16)
		text(t, tx + 12, y + 7, 13, "b", C.cream)
		tx = tx + tw + 8
	end
	-- your own hotel: its Manage screen (its addons, their settings, its look) once it's started
	if sv.local_ then
		y = y + 58
		button("manage", "Manage hotel", x, y, 200, 46, "light", function() L.enter(nil, true) end, 15)
	end
end

-- --- the sheets: settings, adding a server --------------------------------------------------------------
function L.sheetCard(cx, y)
	local w = 460
	local x = cx - w / 2
	if sheet == "add" then
		local h = 300
		region("sheet", x, y, w, h, function() focus = nil end)
		box(x + 4, y + 14, w, h, 26, C.rust, 0.2)
		box(x, y, w, h, 26, C.card)
		text("Add a server", x + 26, y + 24, 20, "x", C.ink)
		text("Its name (for you)", x + 26, y + 66, 13, "b", C.ink3)
		local nf = input("addname", x + 26, y + 86, w - 52, 46, "e.g. Sunset Hotel")
		text("Its address", x + 26, y + 144, 13, "b", C.ink3)
		local af = input("addaddress", x + 26, y + 164, w - 52, 46, "address:port", function() L.addServer() end)
		button("addok", "Add", x + w - 26 - 130, y + 232, 130, 46, "dark", function() L.addServer() end, 16)
		button("addcancel", "Cancel", x + 26, y + 232, 130, 46, "outline", function() sheet = nil message = nil focus = nil end, 15)
		if message and message.where == "add" then text(message.text, x + 26, y + h + 14, 13, "b", C.ink2) end
		return
	end
	-- settings
	local h = 446
	region("sheet", x, y, w, h, function() focus = nil end)
	box(x + 4, y + 14, w, h, 26, C.rust, 0.2)
	box(x, y, w, h, 26, C.card)
	text("Settings", x + 26, y + 24, 20, "x", C.ink)
	local yy = y + 66
	text("Your name", x + 26, yy, 13, "b", C.ink3)
	input("name", x + 26, yy + 20, w - 52 - 100, 46, "Your name", function(t) L.saveName(t) end, settings.playerName or "")
	button("savename", "Save", x + w - 26 - 90, yy + 20, 90, 46, "dark", function() L.saveName(field("name").text) end, 15)
	if message and message.where == "name" then text(message.text, x + 26, yy + 72, 12, "b", message.good and C.green or C.red) end
	yy = yy + 100
	text("Garry's Mod folder", x + 26, yy, 13, "b", C.ink3)
	text(fit(settings.garrysmod or "(not set)", 13, "r", w - 52 - 110), x + 26, yy + 22, 13, "r", C.ink)
	button("folder", "Change", x + w - 26 - 100, yy + 12, 100, 40, "light", function() page = "setup" sheet = nil message = nil end, 14)
	yy = yy + 66
	text("Window", x + 26, yy, 13, "b", C.ink3)
	local Win = require("bobba.window")
	button("fullscreen", Win.full() and "Leave full screen" or "Full screen (F11)", x + 26, yy + 20, w - 52, 44, "light", function()
		Win.toggle()
		settings.fullscreen = Win.full()
		actions.save()
	end, 14)
	yy = yy + 82
	button("openfolder", "Open this hotel's files", x + 26, yy, w - 52, 44, "light", function()
		if data.folder then FS.mkdirs(data.folder) love.system.openURL("file:///" .. data.folder) end
	end, 14)
	button("closesheet", "Done", x + w / 2 - 70, y + h - 64, 140, 44, "dark", function() sheet = nil message = nil focus = nil end, 15)
end

function L.addServer()
	local name = (field("addname").text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local address = (field("addaddress").text or ""):gsub("%s", "")
	if address == "" then message = { text = "It needs an address (like play.example.com:27015).", where = "add" } return end
	settings.servers = settings.servers or {}
	settings.servers[#settings.servers + 1] = { name = name, address = address }
	settings.chosen = #settings.servers + 1
	actions.save()
	fields.addname, fields.addaddress = nil, nil
	sheet, focus = nil, nil
	message = { text = "Added. Hotels on other computers open when the hotel server comes.", where = "checkin" }
end

-- --- first start: finding Garry's Mod ----------------------------------------------------------------------
function L.useFolder(p)
	p = FS.clean(p or "")
	local gm = ST.isGarrysmod(p)
	if gm then
		settings.garrysmod = gm
		actions.save()
		message = nil
		page = "servers"
		L.refresh()
		return true
	end
	if ST.hasGarrysmod(p) then
		message = { text = "That's Garry's Mod, but Bobba Hotel isn't in it (garrysmod/gamemodes/bobbahotel).", where = "folder" }
	else
		message = { text = "That isn't a garrysmod folder (it has gamemodes/ and addons/ in it).", where = "folder" }
	end
	return false
end

function L.setupCard(cx, y)
	local w = 520
	local x = cx - w / 2
	local h = candidate and 400 or 320
	box(x + 4, y + 14, w, h, 26, C.rust, 0.2)
	box(x, y, w, h, 26, C.card)
	text("Where's Garry's Mod?", x + 28, y + 26, 22, "x", C.ink)
	local yy = y + 64 + para("Bobba plays from your Garry's Mod: its gamemode, addons and the files it already downloaded. Show it the garrysmod folder once and it remembers.", x + 28, y + 64, w - 56, 14, "r", C.ink3, 21)
	yy = yy + 14
	if candidate then
		box(x + 20, yy, w - 40, 70, 18, C.sel)
		text("Found on this computer", x + 36, yy + 12, 12, "b", C.ink3)
		text(fit(candidate.path, 13, "b", w - 200), x + 36, yy + 32, 13, "b", C.ink)
		if candidate.ok then button("use-found", "Use it", x + w - 20 - 110, yy + 15, 96, 40, "dark", function() L.useFolder(candidate.path) end, 14)
		else text("Bobba isn't in it yet", x + w - 180, yy + 26, 12, "b", C.red) end
		yy = yy + 86
	end
	text("Or type where it is", x + 28, yy, 13, "b", C.ink3)
	local f = input("folder", x + 28, yy + 20, w - 56 - 90, 46, "E:\\SteamLibrary\\steamapps\\common\\GarrysMod\\garrysmod", function(t) L.useFolder(t) end)
	button("use-typed", "Use", x + w - 28 - 80, yy + 20, 80, 46, "dark", function() L.useFolder(f.text) end, 15)
	if message and message.where == "folder" then para(message.text, x + 28, yy + 74, w - 56, 12, "b", C.red, 17)
	else text("You can also drag the garrysmod folder onto this window.", x + 28, yy + 76, 12, "b", C.ink3) end
	if settings.garrysmod then
		button("back", "Back", x + 28, y + h - 58, 100, 40, "outline", function() page = "servers" message = nil end, 14)
	end
end

-- --- Love's events -------------------------------------------------------------------------------------------
function L.start(st, acts)
	settings, actions = st, acts
	if not (settings.garrysmod and ST.isGarrysmod(settings.garrysmod)) then
		page = "setup"
		local p, ok = ST.findGarrysmod()
		if p then candidate = { path = p, ok = ok } end
	end
	L.refresh()
end

-- checking in: your own hotel plays here; others need the hotel server (later)
function L.enter(roomId, manage)
	if not (settings.garrysmod and ST.isGarrysmod(settings.garrysmod)) then page = "setup" return end
	local sv = chosen()
	if not sv.local_ then
		message = { text = "Hotels on other computers open when the hotel server comes. Your own hotel works now.", where = "checkin" }
		return
	end
	actions.play(roomId, manage and { manage = true } or nil)
end

function L.saveName(t)
	t = tostring(t or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if t == "" or #t > 32 then message = { text = "1 to 32 letters", where = "name" } return end
	settings.playerName = t
	actions.save()
	message = { text = "Saved", good = true, where = "name" }
	focus = nil
end

function L.update(dt) end

L.ox, L.oy = 0, 0
function L.draw()
	local W, H = lg.getDimensions()
	s = math.min(W / 1280, H / 800)
	if s > 1 then s = math.floor(s * 4) / 4 end
	L.ox, L.oy = 0, 0
	regions = {}
	lg.clear(0, 0, 0)
	lg.push()
	lg.scale(s, s)
	local PW, PH = W / s, H / s
	local half = math.floor(PW / 2)
	rightPanel(half, PW - half, PH)
	leftPanel(0, half, PH)
	lg.pop()
	local mx, my = love.mouse.getPosition()
	mx, my = mx / s, my / s
	hoverId = nil
	for i = #regions, 1, -1 do
		local r = regions[i]
		if mx >= r.x and my >= r.y and mx < r.x + r.w and my < r.y + r.h then hoverId = r.id break end
	end
	love.mouse.setCursor(hoverId and love.mouse.getSystemCursor(hoverId:sub(1, 6) == "input:" and "ibeam" or (hoverId == "sheet" and "arrow" or "hand")) or nil)
end

function L.mousepressed(x, y, b)
	if b ~= 1 then return end
	local mx, my = x / s, y / s
	for i = #regions, 1, -1 do
		local r = regions[i]
		if mx >= r.x and my >= r.y and mx < r.x + r.w and my < r.y + r.h then
			if r.id:sub(1, 6) ~= "input:" then focus = nil end
			r.fn()
			return
		end
	end
	focus = nil
	-- (a click outside a sheet closes it)
	if sheet then sheet = nil message = nil end
end

function L.textinput(t)
	if not focus then return end
	local f = field(focus)
	f.text = f.text .. t
end

function L.keypressed(key)
	if key == "f11" then
		local Win = require("bobba.window")
		Win.toggle()
		settings.fullscreen = Win.full()
		actions.save()
		return
	end
	if not focus then
		if key == "escape" and sheet then sheet = nil return end
		if (key == "return" or key == "kpenter") and page ~= "setup" and not sheet then L.enter() end
		return
	end
	local f = field(focus)
	if key == "backspace" then
		f.text = f.text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
	elseif key == "return" or key == "kpenter" then
		if f.onEnter then f.onEnter(f.text) end
	elseif key == "tab" and sheet == "add" then
		focus = focus == "addname" and "addaddress" or "addname"
	elseif key == "escape" then
		focus = nil
	elseif key == "v" and love.keyboard.isDown("lctrl", "rctrl") then
		f.text = f.text .. (love.system.getClipboardText() or ""):gsub("[\r\n]", "")
	end
end

function L.directorydropped(path) L.useFolder(path) end
function L.filedropped(f)
	local p = f:getFilename()
	if p then L.useFolder(FS.parent(p)) end
end

function L.leave() love.mouse.setCursor() end

return L
