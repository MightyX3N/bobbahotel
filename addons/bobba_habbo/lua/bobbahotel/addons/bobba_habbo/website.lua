-- The Habbo pack's own page (client): the hotel's page after checking in (client/website.lua), the way
-- Habbo's website looked: the hotel's name in yellow on the light blue band, the white tab with your
-- name, the hotel view with you in it and the green Enter button, what you have, the news and the
-- hotel's picks. Drawn with the phone's kit (BOBBA.device's PD) in Ubuntu, Nitro's font.

BOBBA.website = BOBBA.website or {}
local W = BOBBA.website

local function rgb(h) return Color(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)) end
local K = {
	page = rgb("E6E5DE"), header = rgb("BFE0F1"), ink = rgb("1E1E1E"), dark = rgb("2A2A2A"), white = Color(255, 255, 255),
	grey = rgb("6C7178"), line = rgb("C9C8C0"), faint = rgb("8A8984"), orange = rgb("E8640C"), green = rgb("2E9A1E"),
	greenDark = rgb("1C6B12"), greenHover = rgb("38AD26"), tab = rgb("2E7FC0"), tabDark = rgb("1D5A8C"), blue = rgb("2B6CB0"),
	red = rgb("D64541"), yellow = rgb("FFC40C"), panel = rgb("8E8C85"), panelLine = rgb("A3A19A"), navy = rgb("2F3D66"),
	navyBox = rgb("46578A"), newsText = rgb("E5EAF7"), newsLabel = rgb("C9D3EE"), rowAlt = rgb("F4F9FC"), rowLine = rgb("E1E0D9"),
}

-- Ubuntu (Nitro's font) for this page: bold made by the font's weight
local fonts = {}
local function ubuntu(px, weight, s)
	local bold = weight == true or (weight or 500) >= 600
	local size = math.max(6, math.floor(px * 1.18 * s + 0.5))
	local name = "BobbaHabboWeb" .. size .. (bold and "b" or "")
	if not fonts[name] then
		surface.CreateFont(name, { font = "Ubuntu Condensed", size = size, weight = bold and 800 or 500, antialias = true, extended = true })
		fonts[name] = true
	end
	return name
end

local function commas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- the hotel view: the sky, the hills, the street, the hotel; you on your spot; the green Enter
local function hotelView(d, x, y, w, h, site, name)
	local data = site.data or {}
	d:clip(x, y, w, h, function()
		d:rect(x, y, w, h, rgb("7FB8D6"))
		d:rect(x, y + h * 0.35, w, h * 0.3, rgb("9CCBE2"))
		d:rect(x, y + h - 96, w, 96, rgb("8BBF5B"))
		d:rect(x, y + h - 40, w, 40, rgb("A9A79F"))
		d:rect(x + 24, y + h - 240, 140, 200, K.dark)
		d:rect(x + 27, y + h - 237, 134, 194, rgb("F2A23A"))
		for _, wnd in ipairs({ { 44, 172 }, { 94, 172 }, { 44, 122 }, { 94, 122 }, { 44, 72 } }) do
			d:rect(x + wnd[1], y + h - wnd[2] - 22, 26, 22, K.dark)
			d:rect(x + wnd[1] + 2, y + h - wnd[2] - 20, 22, 18, rgb("FCE59A"))
		end
		d:rect(x + w - 160, y + h - 200, 130, 160, K.dark)
		d:rect(x + w - 157, y + h - 197, 124, 154, rgb("E7E2D5"))
		-- your spot and you
		d:circle(x + 250, y + h - 43, 30, rgb("5F5D57"))
		d:circle(x + 250, y + h - 43, 28, rgb("E3E1DA"))
		local AE = BOBBA.avatarEditor
		local figure = data.figure or (AE and AE.defaultFigure and AE.defaultFigure())
		if figure then d:avatar(figure, data.gender, 2, x + 250, y + h - 52 - 220, 2) end
		-- the burst behind Enter
		local cx, cy = x + w - 300, y + 116
		local s = d.s
		surface.SetDrawColor(255, 224, 74, 255)
		draw.NoTexture()
		for i = 0, 39 do
			local a0, a1 = i / 40 * math.pi * 2, (i + 1) / 40 * math.pi * 2
			local r0, r1 = (i % 2 == 0) and 1 or 0.72, ((i + 1) % 2 == 0) and 1 or 0.72
			surface.DrawPoly({ { x = (cx + d.ox) * s, y = (cy + d.oy) * s },
				{ x = (cx + math.cos(a0) * 108 * r0 + d.ox) * s, y = (cy + math.sin(a0) * 76 * r0 + d.oy) * s },
				{ x = (cx + math.cos(a1) * 108 * r1 + d.ox) * s, y = (cy + math.sin(a1) * 76 * r1 + d.oy) * s } })
		end
	end)
	-- Enter
	local bx, by = x + w - 440, y + 88
	local hover = d:click(bx, by, 280, 56, function() site.enter() end)
	d:round(8, bx - 2, by - 2, 284, 60, K.greenDark)
	d:round(7, bx, by, 280, 56, K.white)
	d:round(5, bx + 3, by + 3, 274, 50, hover and K.greenHover or K.green)
	d:text(BOBBA.ui.text("bobba.website.habboenter", "Enter %hotel%", { hotel = name }) .. "  ›", 21, bx + 140, by + 28, K.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
	-- your name on a plate
	local me = LocalPlayer and IsValid(LocalPlayer()) and LocalPlayer():Nick() or ""
	local nw = d:textWidth(me, 13, true) + 20
	d:round(4, x + 250 - nw / 2, y + 12, nw, 24, Color(0, 0, 0))
	d:text(me, 13, x + 250, y + 24, K.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
end

local function cardTitle(d, t, x, y, w, c)
	d:round(6, x + 6, y + 6, w - 12, 34, c or K.blue)
	d:text(t, 16, x + w / 2, y + 23, K.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
end

function W.page(d, WW, HH, site)
	d.fontFn = ubuntu
	local data = site.data or {}
	local name = data.name or BOBBA.hotelName or "Bobba Hotel"
	local T = BOBBA.ui.text
	d:rect(0, 0, WW, HH, K.page)
	d:rect(0, 0, WW, 104, K.header)
	local pad = math.max(20, (WW - 1240) / 2)
	-- the hotel's name: Habbo's yellow with a dark outline
	for _, o in ipairs({ { 3, 3 }, { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do d:text(name, 40, pad + 10 + o[1], 22 + o[2], K.dark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true) end
	d:text(name, 40, pad + 10, 22, K.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	-- Enter at the top right
	local label = T("bobba.website.habboenter", "Enter %hotel%", { hotel = name })
	local bw = d:textWidth(label, 15, true) + 44
	local hov = d:click(WW - pad - bw, 50, bw, 38, function() site.enter() end)
	d:round(4, WW - pad - bw, 50, bw, 38, K.greenDark)
	d:round(3, WW - pad - bw + 2, 52, bw - 4, 34, hov and K.greenHover or K.green)
	d:text(label, 15, WW - pad - bw / 2, 69, K.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
	-- your tab
	local me = LocalPlayer and IsValid(LocalPlayer()) and LocalPlayer():Nick() or ""
	local tw = d:textWidth(me, 14, true) + 72
	d:round(6, pad + 4, 64, tw, 44, K.dark, true, true, false, false)
	d:round(5, pad + 6, 66, tw - 4, 42, K.white, true, true, false, false)
	d:round(4, pad + 24, 76, 22, 22, K.dark)
	d:round(3, pad + 26, 78, 18, 18, K.yellow)
	d:text(me, 14, pad + 54, 87, K.ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
	-- the white bar
	d:round(6, pad, 110, WW - pad * 2, 36, K.white)
	d:text(T("bobba.website.home", "Home"), 14, pad + 18, 128, K.ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
	-- the left: the hotel view and what you have
	local lw = math.floor((WW - pad * 2) * 0.613)
	local ly = 156
	d:round(8, pad, ly, lw, 548 - 56, K.panel)
	hotelView(d, pad, ly, lw, 250, site, name)
	local rows = {
		{ "currency-credits", commas(data.credits) .. " " .. T("bobba.website.credits", "credits") },
		{ "currency-hc", T("bobba.website.clubshop", "Habbo Club: the shop has it") },
		{ nil, T("bobba.website.friendsn", "%n% friends online", { n = (function() local n = 0 for _, f in ipairs(site.friends or {}) do if f.online then n = n + 1 end end return n end)() }) },
		{ nil, T("bobba.website.checkedin", "%n% checked in now", { n = data.online or 0 }) },
	}
	local ry = ly + 250
	for i, r in ipairs(rows) do
		if i < #rows then d:rect(pad, ry + 49, lw, 1, K.panelLine) end
		if not (r[1] and d:uiIcon(r[1], pad + 36, ry + 12, 26, 26)) then d:circle(pad + 49, ry + 25, 11, K.yellow) end
		d:text(r[2], 14, pad + 76, ry + 25, K.white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, i == 1)
		ry = ry + 50
	end
	-- the right: the news, the hotel's picks
	local rx = pad + lw + 16
	local rw = WW - pad - rx
	d:round(8, rx, 156, rw, 290, K.line)
	d:round(8, rx + 1, 157, rw - 2, 288, K.white)
	d:round(8, rx + 1, 157, rw - 2, 168, K.navy, true, true, false, false)
	local news = data.news and data.news[1]
	d:text(T("bobba.website.latest", "LATEST NEWS"), 12, rx + 16, 175, K.newsLabel)
	d:text(d:fit(news and news.title or T("bobba.website.welcome", "Welcome to %hotel%", { hotel = name }), 22, rw - 200, true), 22, rx + 16, 196, K.white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	for i, l in ipairs(d:wrap(news and news.text or T("bobba.website.habbonews", "Make a room, meet people, and put on events. The staff's news comes here."), 13, rw - 200)) do
		if i <= 4 then d:text(l, 13, rx + 16, 232 + (i - 1) * 19, K.newsText) end
	end
	d:round(4, rx + rw - 166, 175, 150, 130, K.navyBox)
	if not d:uiIcon("habbo", rx + rw - 166, 175, 150, 130, 2) then d:text(name, 12, rx + rw - 91, 240, K.newsLabel, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
	local ev = data.events and data.events[1]
	d:text(ev and ev.name or T("bobba.website.noevents", "No events on right now"), 14, rx + 16, 345, K.ink)
	d:text(ev and (ev.roomName or "") or T("bobba.website.putone", "Put one on in your room (the phone or the navigator)"), 12, rx + 16, 366, K.faint)
	-- the picks
	local py = 456
	local picks = data.rooms or {}
	local ph = 46 + math.max(1, math.min(4, #picks)) * 52 + 6
	d:round(8, rx, py, rw, ph, K.line)
	d:round(8, rx + 1, py + 1, rw - 2, ph - 2, K.white)
	cardTitle(d, T("bobba.website.picks", "Hotel picks"), rx, py, rw, K.red)
	if #picks == 0 then d:text(T("bobba.website.norooms", "No rooms yet: be the first to make one"), 14, rx + 16, py + 66, K.faint) end
	for i, r in ipairs(picks) do
		if i > 4 then break end
		local yy = py + 46 + (i - 1) * 52
		local hv = d:click(rx + 8, yy, rw - 16, 48, function() site.enter(function() BOBBA.platform.send("room.enter", { id = r.id }) end) end)
		if hv then d:round(6, rx + 8, yy, rw - 16, 48, K.rowAlt) end
		d:round(6, rx + 16, yy + 4, 40, 40, rgb("9CC3D8"))
		d:round(5, rx + 17, yy + 5, 38, 38, rgb("CDE5F2"))
		d:uiIcon("nav-thumbnail", rx + 17, yy + 5, 38, 38, 0.4)
		d:text(d:fit(r.name or "?", 14, rw - 100, true), 14, rx + 68, yy + 8, hv and K.orange or K.ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
		d:text(T("bobba.website.by", "by %owner%", { owner = r.owner or "?" }), 12, rx + 68, yy + 28, K.faint)
	end
end
