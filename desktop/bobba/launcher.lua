-- The start page, made like the old Habbo website: your hotel's "Me" page (what you have in the
-- hotel you played last), My hotels, Settings, and on the first start finding Garry's Mod.
-- Drawn at 1280 x 720 "website pixels", scaled to the window.

local FS = require("bobba.fs")
local ST = require("bobba.steam")
local SQ = require("bobba.sqlite")
local lg = love.graphics

local L = {}
local settings, actions
local page = "home" -- setup, home, account, hotels, settings
local data = {} -- what the hotel's database says (L.refresh)
local regions = {} -- the clickable parts drawn this frame
local hoverId
local s, ox, oy = 1, 0, 0 -- scale and where the 1280 x 720 page is
local fields = {} -- text boxes by id
local focus -- the text box typed in
local message -- a line under the folder box: { text, good }
local candidate -- the garrysmod folder found on this computer
local images = {}

local C = {
	page = { 0xE6, 0xE5, 0xDE }, header = { 0xBF, 0xE0, 0xF1 }, ink = { 0x1E, 0x1E, 0x1E }, dark = { 0x2A, 0x2A, 0x2A },
	white = { 255, 255, 255 }, grey = { 0x6C, 0x71, 0x78 }, line = { 0xC9, 0xC8, 0xC0 }, faint = { 0x8A, 0x89, 0x84 },
	orange = { 0xE8, 0x64, 0x0C }, link = { 0x1F, 0x5E, 0x9C }, green = { 0x2E, 0x9A, 0x1E }, greenDark = { 0x1C, 0x6B, 0x12 },
	tab = { 0x2E, 0x7F, 0xC0 }, tabDark = { 0x1D, 0x5A, 0x8C }, blue = { 0x2B, 0x6C, 0xB0 }, red = { 0xD6, 0x45, 0x41 },
	yellow = { 0xFF, 0xC4, 0x0C }, panel = { 0x8E, 0x8C, 0x85 }, panelLine = { 0xA3, 0xA1, 0x9A }, navy = { 0x2F, 0x3D, 0x66 },
	navyBox = { 0x46, 0x57, 0x8A }, newsText = { 0xE5, 0xEA, 0xF7 }, newsLabel = { 0xC9, 0xD3, 0xEE }, rowAlt = { 0xF4, 0xF9, 0xFC },
	rowLine = { 0xE1, 0xE0, 0xD9 }, disabled = { 0x8A, 0x89, 0x84 }, input = { 0xB9, 0xB8, 0xB0 },
}
local function col(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end

-- --- fonts (made at the size they're drawn, so text stays sharp) ---------------------------------
local fontFiles = { r = "fonts/Ubuntu-Regular.ttf", b = "fonts/Ubuntu-Bold.ttf", m = "fonts/Ubuntu-Medium.ttf", logo = "fonts/LilitaOne-Regular.ttf" }
local fonts = {}
local function font(px, kind)
	kind = kind or "r"
	local size = math.max(6, math.floor(px * s + 0.5))
	local key = kind .. size
	if not fonts[key] then
		local ok, f = pcall(lg.newFont, fontFiles[kind], size)
		fonts[key] = ok and f or lg.newFont(size)
	end
	return fonts[key]
end
-- text at page coordinates; returns its width in page pixels
local function text(t, x, y, px, kind, c, align, w)
	local f = font(px, kind)
	col(c or C.ink)
	t = tostring(t)
	local tw = f:getWidth(t) / s
	if align == "center" then x = x + (w - tw) / 2 elseif align == "right" then x = x + w - tw end
	lg.print(t, f, math.floor(x * s + 0.5) / s, math.floor(y * s + 0.5) / s, 0, 1 / s, 1 / s)
	return tw
end
local function textWidth(t, px, kind) return font(px, kind):getWidth(tostring(t)) / s end
-- several lines in a width; returns the height
local function para(t, x, y, w, px, kind, c, lineH)
	local f = font(px, kind)
	local _, lines = f:getWrap(t, w * s)
	lineH = lineH or px * 1.5
	for i, l in ipairs(lines) do text(l, x, y + (i - 1) * lineH, px, kind, c) end
	return #lines * lineH
end

-- --- shapes -------------------------------------------------------------------------------------------
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
-- a box with soft rounded corners (r: radius; corners: "tl tr bl br" which are round, default all)
local function box(x, y, w, h, r, c, corners)
	col(c)
	r = math.min(r or 0, w / 2, h / 2)
	if r <= 0 then lg.rectangle("fill", x, y, w, h) return end
	local round = function(k) return corners == nil or corners:find(k, 1, true) ~= nil end
	lg.rectangle("fill", x + r, y, w - 2 * r, h)
	lg.rectangle("fill", x, y + r, r, h - 2 * r)
	lg.rectangle("fill", x + w - r, y + r, r, h - 2 * r)
	local img = corner()
	local k = r / img:getWidth()
	if round("tl") then lg.draw(img, x, y, 0, k, k) else lg.rectangle("fill", x, y, r, r) end
	if round("tr") then lg.draw(img, x + w, y, 0, -k, k) else lg.rectangle("fill", x + w - r, y, r, r) end
	if round("bl") then lg.draw(img, x, y + h, 0, k, -k) else lg.rectangle("fill", x, y + h - r, r, r) end
	if round("br") then lg.draw(img, x + w, y + h, 0, -k, -k) else lg.rectangle("fill", x + w - r, y + h - r, r, r) end
end
-- a box with a border of width b
local function framed(x, y, w, h, r, fill, border, b, corners)
	b = b or 1
	box(x, y, w, h, r, border, corners)
	box(x + b, y + b, w - 2 * b, h - 2 * b, math.max(0, (r or 0) - b), fill, corners)
end

-- clickable part: id (for hover), area, what it does
local function region(id, x, y, w, h, fn)
	regions[#regions + 1] = { id = id, x = x, y = y, w = w, h = h, fn = fn }
	return hoverId == id
end

-- the Habbo pictures the game saved (the purse's coins, HC): cut to what's drawn in them
local function habboImage(name)
	if images[name] ~= nil then return images[name] end
	images[name] = false
	if not settings.garrysmod then return false end
	local _, dirs = FS.list(settings.garrysmod .. "/data/bobbahotel/habbo/chat")
	table.sort(dirs, function(a, b) return (tonumber(a:match("%d+")) or 0) > (tonumber(b:match("%d+")) or 0) end)
	for _, d in ipairs(dirs) do
		local bytes = FS.read(settings.garrysmod .. "/data/bobbahotel/habbo/chat/" .. d .. "/ui_" .. name .. ".png")
		if bytes then
			local ok, idata = pcall(love.image.newImageData, love.filesystem.newFileData(bytes, name .. ".png"))
			if ok then
				local w, h = idata:getDimensions()
				local x1, y1 = 0, 0
				for y = 0, h - 1 do for x = 0, w - 1 do
					local _, _, _, a = idata:getPixel(x, y)
					if a > 0 then if x + 1 > x1 then x1 = x + 1 end if y + 1 > y1 then y1 = y + 1 end end
				end end
				local img = lg.newImage(idata)
				img:setFilter("nearest", "nearest")
				images[name] = { img = img, quad = lg.newQuad(0, 0, math.max(1, x1), math.max(1, y1), w, h), w = math.max(1, x1), h = math.max(1, y1) }
				return images[name]
			end
		end
	end
	return false
end
local function icon(name, cx, cy, fallback, fit)
	local im = habboImage(name)
	if im then
		col(C.white)
		local k = math.max(1, math.floor(s + 0.5)) / s
		if fit and math.max(im.w, im.h) * k > fit then k = fit / math.max(im.w, im.h) end
		lg.draw(im.img, im.quad, math.floor((cx - im.w * k / 2) * s) / s, math.floor((cy - im.h * k / 2) * s) / s, 0, k, k)
	elseif fallback then fallback() end
end

-- --- text boxes ----------------------------------------------------------------------------------------
local function field(id, value)
	if not fields[id] then fields[id] = { text = value or "" } end
	return fields[id]
end
local function input(id, x, y, w, h, placeholder, onEnter)
	local f = field(id)
	local focused = focus == id
	framed(x, y, w, h, 4, C.white, focused and C.tab or C.input, 1)
	local px = 13
	local fnt = font(px)
	lg.setScissor(math.floor((x + 6) * s + ox), math.floor(y * s + oy), math.floor((w - 12) * s), math.floor(h * s))
	local tw = fnt:getWidth(f.text) / s
	local shift = math.max(0, tw - (w - 16))
	if f.text == "" and not focused then
		text(placeholder or "", x + 10, y + (h - px * 1.2) / 2, px, "r", C.faint)
	else
		text(f.text, x + 10 - shift, y + (h - px * 1.2) / 2, px, "r", C.ink)
	end
	if focused and love.timer.getTime() % 1 < 0.5 then
		col(C.ink)
		lg.rectangle("fill", x + 10 + tw - shift + 1, y + 7, 1 / s * math.max(1, math.floor(s)), h - 14)
	end
	lg.setScissor()
	region("input:" .. id, x, y, w, h, function() focus = id end)
	f.onEnter = onEnter
	return f
end

-- buttons: kind "green" (big Habbo enter), "blue", "grey"
local function button(id, label, x, y, w, h, kind, fn, px)
	local hover = region(id, x, y, w, h, fn)
	px = px or 15
	if kind == "green" then
		framed(x, y, w, h, 4, hover and { 0x38, 0xAD, 0x26 } or C.green, C.greenDark, 2)
		text(label, x, y + (h - px * 1.2) / 2, px, "b", C.white, "center", w)
	elseif kind == "blue" then
		framed(x, y, w, h, 4, hover and { 0x3A, 0x8E, 0xD2 } or C.tab, C.tabDark, 1)
		text(label, x, y + (h - px * 1.2) / 2, px, "r", C.white, "center", w)
	else
		framed(x, y, w, h, 4, hover and { 0xF0, 0xF0, 0xEB } or { 0xE6, 0xE5, 0xDE }, C.input, 1)
		text(label, x, y + (h - px * 1.2) / 2, px, "r", C.ink, "center", w)
	end
end
local function link(id, label, x, y, px, c, fn, kind)
	local w = textWidth(label, px, kind)
	local hover = region(id, x, y - 2, w, px * 1.4, fn)
	text(label, x, y, px, kind or "r", hover and C.orange or (c or C.link))
	if hover or (c == C.orange) then
		col(hover and C.orange or c)
		lg.rectangle("fill", x, y + px * 1.2, w, 1 / s * math.max(1, math.floor(s)))
	end
	return w
end
local function tag(label, x, y)
	local w = textWidth(label, 12) + 18
	box(x, y, w, 22, 4, C.disabled)
	text(label, x, y + 4, 12, "r", C.white, "center", w)
	return w
end

-- --- what the hotel's database says -----------------------------------------------------------------
local function hotelName() return data.hotelName or "Bobba Hotel" end

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
	local function rows(q) local ok, r = pcall(db.query, db, q) return ok and r or {} end
	data.wallet = row("SELECT * FROM bobbahotel_wallets WHERE key = " .. key)
	data.user = row("SELECT * FROM bobbahotel_users WHERE key = " .. key)
	data.look = row("SELECT * FROM bobbahotel_looks WHERE key = " .. key)
	local name = row("SELECT v FROM bobbahotel_settings WHERE k = 'hotel_name'")
	data.hotelName = name and name.v ~= "" and name.v or nil
	local mine = row("SELECT COUNT(*) AS n FROM bobbahotel_rooms WHERE owner = " .. key)
	data.myRooms = mine and tonumber(mine.n) or 0
	data.lastRoom = row("SELECT id, name FROM bobbahotel_rooms WHERE owner = " .. key .. " ORDER BY id DESC LIMIT 1")
	data.picks = rows("SELECT id, name, owner_name FROM bobbahotel_rooms ORDER BY id LIMIT 3")
	db:close()
	-- your avatar, as the game last drew it
	local bytes = FS.read(opts.save .. "/avatar.png")
	if bytes then
		local ok, img = pcall(function() return lg.newImage(love.image.newImageData(love.filesystem.newFileData(bytes, "avatar.png"))) end)
		if ok then data.avatar = img img:setFilter("nearest", "nearest") end
	end
end

-- --- the page's top: the logo, the links, the tabs ----------------------------------------------------
local TABS = { { "home", nil }, { "hotels", "My hotels" }, { "settings", "Settings" } }
local function header()
	-- (the light blue band goes across the whole window)
	-- the logo: the hotel's name in Habbo's yellow, with a dark outline and shadow
	local name = hotelName()
	local px = 46
	local f = font(px, "logo")
	local x, y = 30, 22
	for _, o in ipairs({ { 3, 3 }, { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 }, { 0, 2 }, { 2, 0 }, { -2, 0 }, { 0, -2 } }) do
		text(name, x + o[1], y + o[2], px, "logo", C.dark)
	end
	text(name, x, y, px, "logo", C.yellow)
	-- the white tab top right
	local links = { { "My hotels ›", function() page = "hotels" end, C.grey, "b" }, { "Settings ›", function() page = "settings" end, C.grey, "b" }, { "Change folder", function() page = "setup" end, C.orange, "r" } }
	local widths, total = {}, 36
	for i, l in ipairs(links) do widths[i] = textWidth(l[1], 13, l[4]) total = total + widths[i] + (i > 1 and 22 or 0) end
	local lx = 1280 - 30 - total
	box(lx, -8, total, 42, 8, C.white)
	local cx = lx + 18
	for i, l in ipairs(links) do
		link("top" .. i, l[1], cx, 9, 13, l[3], l[2], l[4])
		cx = cx + widths[i] + 22
	end
	-- Enter
	local label = "Enter " .. name
	local bw = textWidth(label, 15, "b") + 44
	button("enter-top", label, 1280 - 30 - bw, 50, bw, 38, "green", L.enter)
	-- the tabs
	local tx = 24
	for _, t in ipairs(TABS) do
		local active = (t[1] == "home" and (page == "home" or page == "account")) or page == t[1]
		local label2 = t[2] or (settings.playerName or "You")
		local w = textWidth(label2, 14, "b") + (t[1] == "home" and 72 or 52)
		local h = active and 40 or 34
		local y2 = 110 - h
		if active then
			box(tx, y2, w, h + 4, 6, C.dark, "tl tr")
			box(tx + 2, y2 + 2, w - 4, h + 2, 5, C.white, "tl tr")
		else
			box(tx, y2, w, h, 6, C.tabDark, "tl tr")
			box(tx + 2, y2 + 2, w - 4, h - 2, 5, region("tab:" .. t[1], tx, y2, w, h, function() page = t[1] message = nil end) and { 0x3A, 0x8E, 0xD2 } or C.tab, "tl tr")
		end
		local lx2 = tx + 26
		if t[1] == "home" then
			framed(tx + 20, y2 + (h - 22) / 2, 22, 22, 4, C.yellow, active and C.dark or C.tabDark, 2)
			lx2 = tx + 50
		end
		text(label2, lx2, y2 + (h - 17) / 2, 14, active and "b" or "r", active and C.ink or C.white)
		tx = tx + w + 6
	end
end

-- the white bar under the tabs: the tab's own pages
local function subnav(items)
	box(20, 111, 1240, 36, 6, C.line)
	box(20, 110, 1240, 36, 6, C.white)
	local x = 38
	for i, it in ipairs(items) do
		if i > 1 then col(C.line) lg.rectangle("fill", x, 120, 1, 16) x = x + 16 end
		if it.active then
			x = x + text(it[1], x, 119, 14, "b", C.ink) + 16
		else
			x = x + link("sub" .. i, it[1], x, 119, 14, C.link, it[2]) + 16
		end
	end
end

local function cardTitle(t, x, y, w, c)
	box(x + 6, y + 6, w - 12, 34, 6, c or C.blue)
	text(t, x + 6, y + 14, 16, "b", C.white, "center", w - 12)
end

-- --- Home: your avatar in the hotel view, what you have ------------------------------------------------
local function hotelView(x, y, w, h)
	lg.setScissor(math.floor(x * s + ox), math.floor(y * s + oy), math.floor(w * s), math.floor(h * s))
	-- the sky, the hills, the street
	col({ 0x7F, 0xB8, 0xD6 }) lg.rectangle("fill", x, y, w, h)
	col({ 0x9C, 0xCB, 0xE2 }) lg.rectangle("fill", x, y + h * 0.35, w, h * 0.3)
	col({ 0x8B, 0xBF, 0x5B }) lg.rectangle("fill", x, y + h - 96, w, 96)
	col({ 0xA9, 0xA7, 0x9F }) lg.rectangle("fill", x, y + h - 40, w, 40)
	-- the hotel
	framed(x + 24, y + h - 240, 140, 200, 0, { 0xF2, 0xA2, 0x3A }, C.dark, 3)
	for _, wnd in ipairs({ { 44, 172 }, { 94, 172 }, { 44, 122 }, { 94, 122 }, { 44, 72 } }) do
		framed(x + wnd[1], y + h - wnd[2] - 22, 26, 22, 0, { 0xFC, 0xE5, 0x9A }, C.dark, 2)
	end
	framed(x + 600, y + h - 200, 130, 160, 0, { 0xE7, 0xE2, 0xD5 }, C.dark, 3)
	framed(x + 620, y + h - 180, 34, 28, 0, { 0xBF, 0xE0, 0xF1 }, C.dark, 2)
	framed(x + 676, y + h - 180, 34, 28, 0, { 0xBF, 0xE0, 0xF1 }, C.dark, 2)
	-- where you stand
	col({ 0x5F, 0x5D, 0x57 }) lg.ellipse("fill", x + 250, y + h - 43, 62, 18)
	col({ 0xE3, 0xE1, 0xDA }) lg.ellipse("fill", x + 250, y + h - 43, 60, 16)
	local top = y + h - 175
	if data.avatar then
		-- (twice its size when it fits, pixel-sharp)
		local aw, ah = data.avatar:getDimensions()
		local k = ah * 2 <= 200 and 2 or 1
		col(C.white)
		top = y + h - 38 - ah * k
		lg.draw(data.avatar, math.floor(x + 250 - aw * k / 2), top, 0, k, k)
	else
		-- (until the game has drawn you once)
		col({ 0x5F, 0x5D, 0x57 }, 0.55)
		lg.circle("fill", x + 250, y + h - 150, 18)
		box(x + 228, y + h - 130, 44, 80, 10, { 0x5F, 0x5D, 0x57 })
	end
	-- the burst behind Enter
	local cx, cy = x + 540, y + 116
	local pts = {}
	for i = 0, 39 do
		local a = i / 40 * math.pi * 2
		local r = (i % 2 == 0) and 1 or 0.72
		pts[#pts + 1] = cx + math.cos(a) * 108 * r
		pts[#pts + 1] = cy + math.sin(a) * 76 * r
	end
	col({ 0xFF, 0xE0, 0x4A })
	for i = 1, #pts - 2, 2 do
		lg.polygon("fill", cx, cy, pts[i], pts[i + 1], pts[(i + 1) % #pts + 1], pts[(i + 2) % #pts + 1])
	end
	lg.setScissor()
	-- Enter (a white ring round the green)
	local hover = region("enter-big", x + 400, y + 88, 280, 56, L.enter)
	box(x + 398, y + 86, 284, 60, 8, C.greenDark)
	box(x + 400, y + 88, 280, 56, 7, C.white)
	box(x + 403, y + 91, 274, 50, 5, hover and { 0x38, 0xAD, 0x26 } or C.green)
	local label = "Enter " .. hotelName()
	local tw = textWidth(label, 21, "m")
	text(label, x + 400 + (280 - tw - 30) / 2, y + 102, 21, "m", C.white)
	-- (the arrow)
	col(C.white)
	local ax, ay = x + 400 + (280 + tw - 30) / 2 + 12, y + 116
	lg.polygon("fill", ax, ay - 9, ax + 14, ay, ax, ay + 9)
	-- your name on a plate
	local nm = settings.playerName or ""
	local nw = textWidth(nm, 13, "b") + 20
	box(x + 250 - nw / 2, top - 32, nw, 24, 4, { 0, 0, 0 }, nil)
	text(nm, x + 250 - nw / 2, top - 27, 13, "b", C.white, "center", nw)
end

local function daysLeft(untilTime)
	local t = tonumber(untilTime) or 0
	local left = t - os.time()
	if left <= 0 then return 0 end
	return math.ceil(left / 86400)
end
local function commas(n)
	n = tostring(math.floor(tonumber(n) or 0))
	local out = n:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function homePage()
	subnav({ { "Home", active = page == "home", function() page = "home" end }, { "Account", active = page == "account", function() page = "account" end } })
	if page == "account" then
		-- who you are here
		box(20, 156, 760, 300, 8, C.line)
		box(21, 157, 758, 298, 8, C.white)
		cardTitle("Account", 20, 156, 760)
		local y = 210
		text("Your name in the hotel", 42, y, 13, "r", { 0x4A, 0x4A, 0x46 })
		local f = input("name", 42, y + 22, 360, 32, "Your name", function(t) L.saveName(t) end)
		if f.text == "" and focus ~= "name" then f.text = settings.playerName or "" end
		button("name-save", "Save", 412, y + 22, 90, 32, "blue", function() L.saveName(f.text) end, 13)
		if message and message.where == "name" then text(message.text, 514, y + 30, 13, "r", message.good and C.green or C.red) end
		y = y + 80
		local key = tostring(settings.playerKey or "")
		if key:match("^7656") then
			text("You're the Steam account signed in on this computer:", 42, y, 14)
			text(key, 42, y + 24, 14, "b")
		else
			text("Steam wasn't signed in when this started, so you have an id of your own here:", 42, y, 14)
			text(key, 42, y + 24, 14, "b")
		end
		para("On a hotel someone hosts you'll sign in with Steam the first time (that comes with hosting). Your avatar, furni and friends belong to each hotel.", 42, y + 60, 700, 13, "r", C.faint)
		return
	end
	-- the left: the hotel view and you
	box(20, 156, 760, 548, 8, C.panel)
	hotelView(20, 156, 760, 250)
	local rows = {}
	local w = data.wallet
	rows[#rows + 1] = { icon = "pursearea_credits_icon", circle = { 0xF6, 0xC3, 0x43 },
		parts = { { commas(w and w.credits or 0), "b" }, { " credits · " }, { commas(w and w.duckets or 0), "b" }, { " duckets · " }, { commas(w and w.diamonds or 0), "b" }, { " diamonds" } } }
	local club, vip = daysLeft(w and w.club_until), daysLeft(w and w.vip_until)
	if vip > 0 then
		rows[#rows + 1] = { icon = "pursearea_hc_icon", square = { 0xE8, 0xB8, 0x30 }, parts = { { "Habbo Club VIP: " }, { tostring(vip), "b" }, { vip == 1 and " day left" or " days left" } } }
	elseif club > 0 then
		rows[#rows + 1] = { icon = "pursearea_hc_icon", square = { 0xE8, 0xB8, 0x30 }, parts = { { "Habbo Club: " }, { tostring(club), "b" }, { club == 1 and " day left" or " days left" } } }
	else
		rows[#rows + 1] = { icon = "pursearea_hc_icon", square = { 0xE8, 0xB8, 0x30 }, parts = { { "You're not in Habbo Club (the shop has it)" } } }
	end
	rows[#rows + 1] = { square = { 0x7C, 0xC0, 0xE8 }, parts = { { "Friends come with the friends and messenger part" } } }
	if data.lastRoom then
		rows[#rows + 1] = { icon = "newnavigator_icon_home_yes", square = { 0xF2, 0x8C, 0x5B }, parts = { { "Your rooms: " }, { tostring(data.myRooms), "b" }, { " · the newest: " }, { data.lastRoom.name, "link", function() L.enter(tonumber(data.lastRoom.id)) end } } }
	else
		rows[#rows + 1] = { icon = "newnavigator_icon_home_yes", square = { 0xF2, 0x8C, 0x5B }, parts = { { "You haven't made a room yet (the navigator makes them)" } } }
	end
	local seen = data.user and tonumber(data.user.seen)
	rows[#rows + 1] = { circle = { 0xE5, 0x4B, 0x4B }, parts = { { "Last signed in: " }, { seen and os.date("%d %b %Y, %H:%M", seen) or "never (enter the hotel)", seen and "b" or nil } } }
	local y = 406
	for i, r in ipairs(rows) do
		if i < #rows then col(C.panelLine) lg.rectangle("fill", 20, y + 49, 760, 1) end
		icon(r.icon or "-", 49, y + 25, function()
			if r.circle then
				col({ r.circle[1] * 0.4, r.circle[2] * 0.4, r.circle[3] * 0.4 }) lg.circle("fill", 49, y + 25, 13)
				col(r.circle) lg.circle("fill", 49, y + 25, 11)
			else
				framed(36, y + 12, 26, 26, 4, r.square, { r.square[1] * 0.4, r.square[2] * 0.4, r.square[3] * 0.4 }, 2)
			end
		end)
		local x = 76
		for j, p in ipairs(r.parts) do
			if p[2] == "link" then
				x = x + link("row" .. i .. "_" .. j, p[1], x, y + 16, 14, C.white, p[3])
			else
				x = x + text(p[1], x, y + 16, 14, p[2] == "b" and "b" or "r", C.white)
			end
		end
		y = y + 50
	end
	-- the right: news and the hotel's picks
	local rx = 796
	box(rx, 156, 464, 290, 8, C.line)
	box(rx + 1, 157, 462, 288, 8, C.white)
	box(rx + 1, 157, 462, 168, 8, C.navy, "tl tr")
	text("LATEST NEWS", rx + 16, 173, 12, "r", C.newsLabel)
	text("Welcome to " .. hotelName(), rx + 16, 193, 22, "b", C.white)
	para("This is the hotel on your own computer: everything you do is kept here. Hotels to join, and hosting your own, come next.", rx + 16, 228, 260, 13, "r", C.newsText, 19)
	box(rx + 298, 175, 150, 130, 4, C.navyBox)
	icon("bottom_bar_logo", rx + 373, 240, function() text("[" .. hotelName() .. "]", rx + 298, 232, 12, "r", C.newsLabel, "center", 150) end)
	local ny = 336
	text("The hotel's staff will write the news here", rx + 16, ny, 14, "r", C.ink)
	text("(from the server panel, when hosting comes)", rx + 16, ny + 20, 12, "r", C.faint)
	col(C.rowLine) lg.rectangle("fill", rx + 16, ny + 44, 432, 1)
	text("F1 in the hotel opens the console", rx + 16, ny + 54, 14, "r", C.ink)
	text("(the game's messages, and commands like bobba_give)", rx + 16, ny + 74, 12, "r", C.faint)

	local py = 456
	local picks = data.picks or {}
	local ph = 46 + math.max(1, #picks) * 52 + 6
	box(rx, py, 464, ph, 8, C.line)
	box(rx + 1, py + 1, 462, ph - 2, 8, C.white)
	cardTitle("Hotel picks", rx, py, 464, C.red)
	if #picks == 0 then
		text("No rooms yet: be the first to make one", rx + 16, py + 60, 14, "r", C.faint)
	end
	for i, r in ipairs(picks) do
		local yy = py + 46 + (i - 1) * 52
		local hover = region("pick" .. i, rx + 8, yy, 448, 48, function() L.enter(tonumber(r.id)) end)
		if hover then box(rx + 8, yy, 448, 48, 6, C.rowAlt) end
		framed(rx + 16, yy + 4, 40, 40, 6, { 0xCD, 0xE5, 0xF2 }, { 0x9C, 0xC3, 0xD8 }, 1)
		icon("newnavigator_default_room", rx + 36, yy + 24, nil, 36)
		text(r.name or "?", rx + 68, yy + 6, 14, "b", hover and C.orange or C.ink)
		text("by " .. (r.owner_name or "?"), rx + 68, yy + 26, 12, "r", C.faint)
	end
end

-- --- My hotels ------------------------------------------------------------------------------------------
local function hotelsPage()
	subnav({ { "Hotels", active = true } })
	box(20, 156, 760, 230, 8, C.line)
	box(21, 157, 758, 228, 8, C.white)
	cardTitle("My hotels", 20, 156, 760)
	para("The hotels you've played. Each keeps its own name and logo, and its own account: your avatar, furni and friends are separate in each.", 42, 206, 716, 14, "r", C.ink, 21)
	local y = 254
	col(C.rowLine) lg.rectangle("fill", 21, y, 758, 1)
	box(21, y + 1, 758, 62, 0, C.rowAlt)
	local name = hotelName()
	for _, o in ipairs({ { 2, 2 }, { -1, -1 }, { 1, -1 }, { -1, 1 } }) do text(name, 42 + o[1], y + 18 + o[2], 22, "logo", C.dark) end
	text(name, 42, y + 18, 22, "logo", C.yellow)
	text("My hotel", 214, y + 13, 14, "b")
	text("· on this computer", 214 + textWidth("My hotel ", 14, "b"), y + 13, 14, "r", C.faint)
	local seen = data.user and tonumber(data.user.seen)
	text((seen and ("Last played " .. os.date("%d %b %Y", seen)) or "Not played yet") .. " · as " .. (settings.playerName or ""), 214, y + 35, 12, "r", C.grey)
	button("play-local", "Play", 680, y + 14, 80, 34, "green", L.enter, 15)
	y = y + 63
	col(C.rowLine) lg.rectangle("fill", 21, y, 758, 1)
	framed(42, y + 14, 150, 34, 4, { 0xED, 0xED, 0xE8 }, C.input, 1)
	text("Hotels you join", 42, y + 23, 12, "r", C.faint, "center", 150)
	text("Hotels someone hosts", 214, y + 13, 14, "b")
	text("Joining them comes with the custom server", 214, y + 35, 12, "r", C.grey)
	tag("Coming later", 666, y + 20)

	local rx = 796
	box(rx, 156, 464, 170, 8, C.line)
	box(rx + 1, 157, 462, 168, 8, C.white)
	cardTitle("Add a hotel", rx, 156, 464)
	text("The hotel's address", rx + 16, 210, 13, "r", { 0x4A, 0x4A, 0x46 })
	input("address", rx + 16, 232, 350, 32, "address:port")
	button("add", "Add", rx + 374, 232, 74, 32, "grey", function() message = { text = "Joining other hotels comes with the custom server", where = "add" } end, 13)
	if message and message.where == "add" then text(message.text, rx + 16, 274, 12, "r", C.red)
	else text("You sign in with Steam the first time; after that it remembers you.", rx + 16, 274, 12, "r", C.grey) end
	box(rx, 336, 464, 150, 8, C.line)
	box(rx + 1, 337, 462, 148, 8, C.white)
	cardTitle("Host a hotel", rx, 336, 464, C.red)
	para("Open your own hotel to friends: give it a name and a logo, and share the address you get (through playit.gg, no router setup).", rx + 16, 386, 432, 13, "r", C.ink, 19)
	tag("Coming later", rx + 16, 448)
end

-- --- Settings ----------------------------------------------------------------------------------------------
local function settingsPage()
	subnav({ { "Settings", active = true } })
	box(20, 156, 1240, 320, 8, C.line)
	box(21, 157, 1238, 318, 8, C.white)
	cardTitle("Settings", 20, 156, 1240)
	local y = 210
	text("Garry's Mod folder", 42, y, 14, "b")
	text("The hotel's files (the gamemode, its addons, the Habbo files it downloaded) come from here.", 42, y + 22, 13, "r", C.grey)
	text(settings.garrysmod or "(not set)", 42, y + 46, 14, "r", C.ink)
	link("set-folder", "Change", 42 + textWidth(settings.garrysmod or "(not set)", 14) + 14, y + 46, 14, C.orange, function() page = "setup" end)
	y = y + 90
	text("Window", 42, y, 14, "b")
	local full = love.window.getFullscreen()
	button("fullscreen", full and "Leave full screen" or "Full screen", 42, y + 24, 160, 32, "blue", function()
		love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
		settings.fullscreen = love.window.getFullscreen()
		actions.save()
	end, 13)
	text("(F11 does the same, here and in the hotel)", 214, y + 32, 13, "r", C.grey)
	y = y + 80
	text("This hotel's files", 42, y, 14, "b")
	text(data.folder or "", 42, y + 22, 13, "r", C.grey)
	link("open-folder", "Open the folder", 42, y + 44, 14, C.link, function() FS.mkdirs(data.folder) love.system.openURL("file:///" .. data.folder) end)
end

-- --- First start: finding Garry's Mod ----------------------------------------------------------------------
function L.useFolder(p)
	p = FS.clean(p or "")
	local gm = ST.isGarrysmod(p)
	if gm then
		settings.garrysmod = gm
		actions.save()
		images = {}
		message = nil
		page = "home"
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

local function setupPage()
	local ch = candidate and 400 or 316
	box(20, 156, 1240, ch, 8, C.line)
	box(21, 157, 1238, ch - 2, 8, C.white)
	cardTitle("Where's Garry's Mod?", 20, 156, 1240)
	para("Bobba Hotel plays from your Garry's Mod: its gamemode and addons, and the Habbo files it already downloaded. Show it the garrysmod folder once and it remembers.", 42, 208, 1196, 14, "r", C.ink, 21)
	local y = 262
	if candidate then
		box(42, y, 1196, 64, 6, C.rowAlt)
		text("Found on this computer", 60, y + 12, 13, "r", C.grey)
		text(candidate.path, 60, y + 32, 14, "b")
		if candidate.ok then
			button("use-found", "Use this folder", 1060, y + 15, 160, 34, "green", function() L.useFolder(candidate.path) end, 14)
		else
			text("Bobba Hotel isn't in it yet", 980, y + 24, 13, "r", C.red)
		end
		y = y + 84
	end
	text("Or type where it is", 42, y, 13, "r", { 0x4A, 0x4A, 0x46 })
	local f = input("folder", 42, y + 22, 1000, 34, "e.g. E:\\SteamLibrary\\steamapps\\common\\GarrysMod\\garrysmod", function(t) L.useFolder(t) end)
	button("use-typed", "Use", 1052, y + 22, 90, 34, "blue", function() L.useFolder(f.text) end, 14)
	if message and message.where == "folder" then text(message.text, 42, y + 66, 13, "r", C.red) end
	text("You can also drag the garrysmod folder onto this window.", 42, y + 92, 13, "r", C.grey)
	if settings.garrysmod then link("back", "« Back", 42, y + 126, 14, C.link, function() page = "home" message = nil end) end
end

-- --- Love's events --------------------------------------------------------------------------------------------
function L.start(st, acts)
	settings, actions = st, acts
	if settings.fullscreen then love.window.setFullscreen(true, "desktop") end
	if not (settings.garrysmod and ST.isGarrysmod(settings.garrysmod)) then
		page = "setup"
		local p, ok = ST.findGarrysmod()
		if p then candidate = { path = p, ok = ok } end
	end
	L.refresh()
end

function L.enter(roomId)
	if not (settings.garrysmod and ST.isGarrysmod(settings.garrysmod)) then page = "setup" return end
	actions.play(roomId)
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

function L.draw()
	local W, H = lg.getDimensions()
	s = math.min(W / 1280, H / 720)
	if s > 1 then s = math.floor(s * 4) / 4 end
	ox = math.floor((W - 1280 * s) / 2)
	oy = 0
	regions = {}
	lg.clear(C.page[1] / 255, C.page[2] / 255, C.page[3] / 255)
	col(C.header)
	lg.rectangle("fill", 0, 0, W, 104 * s)
	lg.push()
	lg.translate(ox, oy)
	lg.scale(s, s)
	header()
	if page == "setup" then setupPage()
	elseif page == "hotels" then hotelsPage()
	elseif page == "settings" then settingsPage()
	else homePage() end
	lg.pop()
	-- what's under the mouse (for the next frame's hover look)
	local mx, my = love.mouse.getPosition()
	mx, my = (mx - ox) / s, (my - oy) / s
	hoverId = nil
	for i = #regions, 1, -1 do
		local r = regions[i]
		if mx >= r.x and my >= r.y and mx < r.x + r.w and my < r.y + r.h then hoverId = r.id break end
	end
	love.mouse.setCursor(hoverId and love.mouse.getSystemCursor(hoverId:sub(1, 6) == "input:" and "ibeam" or "hand") or nil)
end

function L.mousepressed(x, y, b)
	if b ~= 1 then return end
	local mx, my = (x - ox) / s, (y - oy) / s
	for i = #regions, 1, -1 do
		local r = regions[i]
		if mx >= r.x and my >= r.y and mx < r.x + r.w and my < r.y + r.h then
			if r.id:sub(1, 6) ~= "input:" then focus = nil end
			r.fn()
			return
		end
	end
	focus = nil
end

function L.textinput(t)
	if not focus then return end
	local f = field(focus)
	f.text = f.text .. t
end

function L.keypressed(key)
	if key == "f11" then
		love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
		settings.fullscreen = love.window.getFullscreen()
		actions.save()
		return
	end
	if not focus then
		if key == "return" and page ~= "setup" then L.enter() end
		return
	end
	local f = field(focus)
	if key == "backspace" then
		f.text = f.text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
	elseif key == "return" or key == "kpenter" then
		if f.onEnter then f.onEnter(f.text) end
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
