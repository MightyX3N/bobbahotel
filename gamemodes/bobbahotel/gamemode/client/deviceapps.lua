-- The hotel's own apps on the phone and the tablet (client/device.lua is the device), its widgets
-- and the shade's tiles.

local DV = BOBBA.device
local U = BOBBA.ui
local HUD = BOBBA.hud
local R = BOBBA.room
local V = BOBBA.view
local P = BOBBA.platform
local C = DV.C
local alpha = DV.alpha
local T = function(k, f, v) return U.text(k, f, v) end

local function act(name, ...)
	local fn = HUD.actions[name]
	if fn then fn(...) end
end
local function inRoom() return V.mode == "room" and V.room ~= nil end
local function money(n)
	local s = tostring(math.floor(n or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
DV.money = money
local function peopleHere()
	local n = 0
	for _, u in pairs(R.units or {}) do if not u.bot and not u.pet then n = n + 1 end end
	return n
end
DV.peopleHere = peopleHere

-- the glyphs (24 x 24 paths, the design's)
DV.G = {
	calls = "M5 4h4l2 5-3 2a11 11 0 0 0 5 5l2-3 5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z",
	messages = "M4 5h16v11H9l-5 4z",
	rooms = "M3 11l9-7 9 7M5 10v10h14V10M10 20v-5h4v5",
	groups = "M5 8a3 3 0 1 1 6 0a3 3 0 1 1-6 0M13 8a3 3 0 1 1 6 0a3 3 0 1 1-6 0M2 20a6 6 0 0 1 12 0M12 20a6 6 0 0 1 10 0",
	furni = "M4 12V8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v4M3 12h18v5H3zM5 17v3M19 17v3",
	clothes = "M8 3l4 3 4-3 5 4-3 3v11H6V10L3 7z",
	club = "M3 8l4 4 5-7 5 7 4-4-2 11H5z",
	bag = "M4 7h16v13H4zM9 7V4h6v3",
	friends = "M9 4.5a3.5 3.5 0 1 1 0 7a3.5 3.5 0 1 1 0-7M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M18.5 20a6.5 6.5 0 0 0-3-5.5",
	camera = "M4 8h4l2-3h4l2 3h4v11H4zM12 10a3 3 0 1 1 0 6a3 3 0 1 1 0-6",
	wallet = "M3 7h16v12H3zM15 13h4M3 7l13-3v3",
	events = "M4 6h16v14H4zM4 10h16M8 3v4M16 3v4",
	videos = "M3 6h18v12H3zM10 9l5 3-5 3z",
	store = "M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM16.5 13v7M13 16.5h7",
	settings = "M12 9a3 3 0 1 1 0 6a3 3 0 1 1 0-6M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2",
	search = "M11 4a7 7 0 1 1 0 14a7 7 0 1 1 0-14M20 20l-4-4",
	plus = "M12 5v14M5 12h14",
	check = "M5 12l5 5 9-10",
	chevron = "M9 5l7 7-7 7",
	moon = "M12 3a9 9 0 1 0 9 9 7 7 0 0 1-9-9z",
	zoom = "M11 4a7 7 0 1 1 0 14a7 7 0 1 1 0-14M20 20l-4-4M8 11h6M11 8v6",
	history = "M4 5h16v11H9l-5 4zM8 9h8M8 12h5",
	info = "M12 3a9 9 0 1 1 0 18a9 9 0 1 1 0-18M12 11v6M12 7.5v.5",
	leave = "M10 4H5v16h5M14 8l4 4-4 4M18 12H9",
	editplan = "M4 4h16v16H4zM4 12h8v8M12 4v8h8",
	lock = "M5 11h14v10H5zM8 11V7a4 4 0 0 1 8 0v4",
	phone = "M8 3h8a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM11 18h2",
	tablet = "M5 3h14a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM11 18h2",
	palette = "M12 3a9 9 0 1 0 0 18c1.5 0 2-1 2-2s-1-2 0-3 2-1 3-1a4 4 0 0 0 4-4c0-4.5-4-8-9-8zM7.5 11h.01M10 7h.01M15 7.5h.01",
	volume = "M4 9h4l5-4v14l-5-4H4zM17 9a4 4 0 0 1 0 6",
	keys = "M3 7h18v10H3zM7 11h.01M11 11h.01M15 11h.01M7 14h10",
	walk = "M13 4a2 2 0 1 1 0 .01M10 21l2-6 3 3v3M9 12l3-3 3 2 3 1M12 9l-1 6",
	diamond = "M6 4h12l3 5-9 11L3 9zM3 9h18",
	duck = "M7 13a5 5 0 0 0 10 0c0-2-1-3-1-3l3-2-4-1a4 4 0 0 0-7 2c-2 0-3 2-3 4",
	coin = "M12 3a9 9 0 1 1 0 18a9 9 0 1 1 0-18M12 7v10M9.5 9.5c0-1 1-1.5 2.5-1.5s2.5.5 2.5 1.5-1 1.5-2.5 2-2.5 1-2.5 2 1 1.5 2.5 1.5 2.5-.5 2.5-1.5",
}
local G = DV.G

-- --- the hotel's apps (Rooms, Bag, the shops, Clothes and the tools are in client/app_*.lua) -------
DV.app({ id = "camera", name = T("bobba.phone.app.camera", "Camera"), color = C.mist, glyph = G.camera, order = 15,
	open = function()
		if not inRoom() then DV.notify({ app = "camera", title = T("bobba.phone.app.camera", "Camera"), text = T("bobba.phone.camera.room", "Go to a room to take photos.") }) return end
		DV.show(false)
		act("camera")
	end })

-- the wallet: what you have
DV.app({ id = "wallet", name = T("bobba.phone.app.wallet", "Wallet"), color = C.peach, glyph = G.wallet, order = 16, bg = C.navy,
	phone = function(ctx)
		local d, W = ctx.d, ctx.w
		d:rect(0, 0, W, ctx.h, C.navy)
		local y = ctx.top + ctx:header(T("bobba.phone.app.wallet", "Wallet"), { dark = true, big = true })
		local p = HUD.purse or {}
		-- the credits card
		d:round(26, 20, y + 10, W - 40, 170, DV.accent())
		d:clip(20, y + 10, W - 40, 170, function() d:circle(W - 50, y + 30, 90, alpha(C.yellow, 0.55)) end)
		d:text(T("bobba.phone.wallet.credits", "CREDITS"), 13, 40, y + 34, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		d:text(money(p.credits), 44, 40, y + 56, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		d:text(T("bobba.phone.wallet.creditsnote", "For furni, clothes and the club"), 13, 40, y + 140, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 600)
		y = y + 200
		y = ctx:rows(20, y, W - 40, {
			{ title = T("bobba.phone.wallet.duckets", "Duckets"), right = money(p.points and p.points[0]), color = C.yellow, glyph = G.duck },
			{ title = T("bobba.phone.wallet.diamonds", "Diamonds"), right = money(p.points and p.points[5]), color = C.sky, glyph = G.diamond },
			{ title = T("bobba.phone.app.club", "Club"), sub = p.club and T("bobba.phone.wallet.clubleft", "%time% left", { time = p.clubText or "" }) or T("bobba.phone.wallet.noclub", "Not a member"),
				right = "chevron", color = C.gold, glyph = G.club, click = function() DV.openApp("club") end },
		}, { bg = C.navy2, fg = C.paper })
	end })

-- --- settings ---------------------------------------------------------------------------------------
local ACCENTS = { "FF9F5A", "6E8BFF", "3FC6A0", "F26B8A", "B98CFF", "FFD166" }
local function settingsView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	d:rect(0, 0, W, H, Color(236, 239, 246))
	local top = ctx.top + ctx:header(T("bobba.phone.app.settings", "Settings"), { big = true })
	local off = d:scroll("settings", 0, top, W, H - top, ctx.state.contentH or H)
	local x, w = 16, W - 32
	if ctx.kind == "tablet" then x, w = math.max(16, (W - 620) / 2), math.min(620, W - 32) end
	d:clip(0, top, W, H - top, function()
		local y = top + 8 - off
		local function section(title)
			d:text(title, 13, x + 16, y + 10, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
			y = y + 24
		end
		-- the phone
		section(T("bobba.phone.settings.phone", "PHONE"))
		local lockOn = DV.lockVar:GetBool()
		local tablet = DV.deviceVar:GetString() == "tablet"
		y = ctx:rows(x, y, w, {
			{ title = T("bobba.phone.settings.lock", "Lock screen"), sub = T("bobba.phone.settings.locksub", "A PIN types itself as it opens"), right = "toggle", on = lockOn,
				color = C.slate, glyph = G.lock, click = function() RunConsoleCommand("bobba_phone_lock", lockOn and "0" or "1") end },
			{ title = T("bobba.phone.settings.device", "Use a tablet"), sub = T("bobba.phone.settings.devicesub", "A big screen instead of the phone"), right = "toggle", on = tablet,
				color = C.blue, glyph = G.tablet, click = function()
					RunConsoleCommand("bobba_phone_device", tablet and "phone" or "tablet")
					DV.home()
					timer.Simple(0, function() DV.switchKind(tablet and "phone" or "tablet") end)
				end },
			{ title = T("bobba.phone.settings.look", "Hotel look"), sub = U.style() == "habbo" and T("bobba.phone.settings.lookhabbo", "Classic") or T("bobba.phone.settings.lookphone", "Phone"),
				right = "chevron", color = C.purple, glyph = G.palette, click = function() ctx:push(DV.lookView) end },
		})
		y = y + 12
		-- the accent colour
		d:round(20, x, y, w, 64, C.white)
		d:text(T("bobba.phone.settings.accent", "Colour"), 15, x + 16, y + 32, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 600)
		local cur = DV.accentVar:GetString():upper()
		for i, hx in ipairs(ACCENTS) do
			local cx = x + w - 16 - 14 - (#ACCENTS - i) * 36
			local hov = d:click(cx - 16, y + 16, 32, 32, function() RunConsoleCommand("bobba_phone_accent", hx) end)
			if cur == hx then d:circle(cx, y + 32, 16, C.navy) d:circle(cx, y + 32, 13.5, C.white) end
			d:circle(cx, y + 32, hov and 12 or 11, DV.hex(hx))
		end
		y = y + 64 + 20
		-- sound
		section(T("bobba.phone.settings.sound", "SOUND"))
		local SET = HUD.settings
		if SET then
			d:round(20, x, y, w, #SET.volumes * 64, C.white)
			for i, v in ipairs(SET.volumes) do
				local ry = y + (i - 1) * 64
				d:text(T(v[2], v[3]), 14, x + 16, ry + 18, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 600)
				d:text(v[1]:GetInt() .. "%", 13, x + w - 16, ry + 18, C.ink2, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 600)
				DV.slider(d, x + 16, ry + 34, w - 32, 16, v[1]:GetInt() / 100, function(val)
					RunConsoleCommand(v[1]:GetName(), tostring(math.floor(val * 100 + 0.5)))
				end, C.blue, C.line)
			end
			y = y + #SET.volumes * 64 + 20
			-- the room and the chat
			section(T("bobba.phone.settings.room", "ROOM AND CHAT"))
			local rows = {}
			for _, c in ipairs(SET.checks) do
				local on = c[1]:GetBool()
				rows[#rows + 1] = { title = T(c[2], c[3]), right = "toggle", on = on, click = function() RunConsoleCommand(c[1]:GetName(), on and "0" or "1") end }
			end
			y = ctx:rows(x, y, w, rows) + 20
		end
		-- moving
		local ST = BOBBA.steering
		if ST then
			section(T("bobba.settings.movement", "Movement"):upper())
			local m = ST.mode()
			local axes = ST.axesVar:GetInt() == 1 and 1 or 0
			local function opt(title, on, fn) return { title = title, right = on and "check" or nil, click = fn } end
			y = ctx:rows(x, y, w, {
				opt(T("bobba.settings.movement.keys.arrows", "Arrow keys"), m == 0, function() RunConsoleCommand("bobba_setting_movekeys", "0") end),
				opt(T("bobba.settings.movement.keys.wasdempty", "WASD while chat is empty"), m == 1, function() RunConsoleCommand("bobba_setting_movekeys", "1") end),
				opt(T("bobba.settings.movement.keys.wasd", "WASD, Enter to chat"), m == 2, function() RunConsoleCommand("bobba_setting_movekeys", "2") end),
			}, { rowH = 48 }) + 12
			y = ctx:rows(x, y, w, {
				opt(T("bobba.settings.movement.axes.screen", "As on the screen"), axes == 0, function() RunConsoleCommand("bobba_setting_moveaxes", "0") end),
				opt(T("bobba.settings.movement.axes.room", "Along the room"), axes == 1, function() RunConsoleCommand("bobba_setting_moveaxes", "1") end),
			}, { rowH = 48 }) + 12
			y = ctx:rows(x, y, w, {
				{ title = T("bobba.controls.title", "Keys and controller"), right = "chevron", color = C.mist, glyph = G.keys, click = function() act("controls") end },
			}) + 20
		end
		if HUD.actions.leaveHotel then
			y = ctx:rows(x, y, w, {
				{ title = T("bobba.phone.settings.leave", "Leave the hotel"), color = C.red, glyph = G.leave, click = function() act("leaveHotel") end },
			}) + 20
		end
		ctx.state.contentH = y + off - top + 20
	end)
end

-- the hotel's look: the phone or the classic one
function DV.lookView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	d:rect(0, 0, W, H, Color(236, 239, 246))
	local y = ctx.top + ctx:header(T("bobba.phone.settings.look", "Hotel look"))
	local x, w = 16, W - 32
	if ctx.kind == "tablet" then x, w = math.max(16, (W - 620) / 2), math.min(620, W - 32) end
	local v = U.styleVar:GetString()
	local packName = U.packStyle == "habbo" and T("bobba.phone.settings.lookhabbo", "Classic") or T("bobba.phone.settings.lookphone", "Phone")
	y = ctx:rows(x, y + 12, w, {
		{ title = T("bobba.phone.settings.lookpack", "The hotel's choice"), sub = packName, right = v == "" and "check" or nil, click = function() RunConsoleCommand("bobba_ui", "") end },
		{ title = T("bobba.phone.settings.lookphone", "Phone"), sub = T("bobba.phone.settings.lookphonesub", "A phone and a tablet"), right = v == "phone" and "check" or nil, click = function() RunConsoleCommand("bobba_ui", "phone") end },
		{ title = T("bobba.phone.settings.lookhabbo", "Classic"), sub = T("bobba.phone.settings.lookhabbosub", "A toolbar and windows"), right = v == "habbo" and "check" or nil, click = function() RunConsoleCommand("bobba_ui", "habbo") end },
	}, { rowH = 60 })
end

DV.app({ id = "settings", name = T("bobba.phone.app.settings", "Settings"), color = C.slate, glyph = G.settings, order = 90, removable = false,
	phone = settingsView, tablet = settingsView, bg = Color(236, 239, 246) })

-- --- the App Store: the apps the hotel's addons bring ------------------------------------------------
local function storeView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	d:rect(0, 0, W, H, C.paper)
	local tab = ctx.state.tab or "all"
	local top = ctx.top + ctx:header(T("bobba.phone.app.store", "App Store"), { big = true, small = T("bobba.phone.store.on", "ON THIS HOTEL") })
	local x, w = 20, W - 40
	if ctx.kind == "tablet" then x, w = math.max(20, (W - 700) / 2), math.min(700, W - 40) end
	local apps = {}
	for _, id in ipairs(DV.appOrder) do
		local a = DV.apps[id]
		if not a.hidden and id ~= "store" then apps[#apps + 1] = a end
	end
	table.sort(apps, function(a, b)
		if (a.store or false) ~= (b.store or false) then return a.store == true end
		return (a.order or 0) < (b.order or 0)
	end)
	local L = DV.layout("phone")
	-- the newest addon app, big at the top
	local featured
	for _, a in ipairs(apps) do if a.store then featured = a break end end
	local off = d:scroll("store", 0, top, W, H - top, ctx.state.contentH or H)
	d:clip(0, top, W, H - top, function()
		local y = top + 6 - off
		if featured then
			d:round(26, x, y, w, 180, featured.color or C.blue)
			d:circle(x + w - 40, y + 170, 90, alpha(C.white, 0.25))
			d:text(T("bobba.phone.store.new", "NEW ON THIS HOTEL"), 12, x + 18, y + 18, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
			d:text(featured.name or "", 24, x + 18, y + 36, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
			for i, l in ipairs(d:wrap(featured.description or "", 14, w * 0.6)) do
				if i <= 2 then d:text(l, 14, x + 18, y + 70 + (i - 1) * 19, C.navy) end
			end
			local got = DV.onHome(featured.id)
			local label = got and T("bobba.phone.store.open", "Open") or T("bobba.phone.store.get", "Get")
			local bw = d:textWidth(label, 14, 800) + 36
			d:click(x + 18, y + 128, bw, 36, function() if got then DV.openApp(featured.id) else DV.getApp(featured.id) end end)
			d:pill(x + 18, y + 128, bw, 36, C.navy)
			d:text(label, 14, x + 18 + bw / 2, y + 146, C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
			y = y + 196
		else
			d:round(26, x, y, w, 96, C.line)
			for i, l in ipairs(d:wrap(T("bobba.phone.store.none", "This hotel's addons haven't added apps yet. The hotel's own apps are below."), 14, w - 36)) do
				d:text(l, 14, x + 18, y + 22 + (i - 1) * 19, C.ink2)
			end
			y = y + 112
		end
		-- the tabs
		local tx = x
		for _, t in ipairs({ { "all", T("bobba.phone.store.all", "All") }, { "addons", T("bobba.phone.store.addons", "From addons") }, { "yours", T("bobba.phone.store.yours", "Yours") } }) do
			local tw = d:textWidth(t[2], 13, 700) + 26
			d:click(tx, y, tw, 30, function() ctx.state.tab = t[1] end)
			d:pill(tx, y, tw, 30, tab == t[1] and C.navy or C.line)
			d:text(t[2], 13, tx + tw / 2, y + 15, tab == t[1] and C.paper or C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
			tx = tx + tw + 8
		end
		y = y + 42
		for _, a in ipairs(apps) do
			local onHome = DV.onHome(a.id)
			local show = tab == "all" or (tab == "addons" and a.store) or (tab == "yours" and onHome)
			if show then
				DV.drawIcon(d, a, x, y + 8, 54, { noBadge = true })
				d:textFit(a.name or "", 15, w - 170, x + 68, y + 24, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
				local what = a.description or (a.store and T("bobba.phone.store.addon", "From this hotel's addons") or T("bobba.phone.store.builtin", "Comes with the hotel"))
				if a.tablet and not a.phone then what = what .. " · " .. T("bobba.phone.store.tablet", "Tablet") end
				d:textFit(what, 12, w - 170, x + 68, y + 44, C.ink2)
				local label, primary, fn
				if onHome then label, fn = T("bobba.phone.store.open", "Open"), function() DV.openApp(a.id) end
				else label, primary, fn = T("bobba.phone.store.get", "Get"), true, function() DV.getApp(a.id) end end
				local bw = math.max(72, d:textWidth(label, 13, 800) + 24)
				local hov = d:click(x + w - bw, y + 19, bw, 32, fn)
				d:pill(x + w - bw, y + 19, bw, 32, hov and C.mist or C.line)
				d:text(label, 13, x + w - bw / 2, y + 35, primary and Color(43, 76, 201) or C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
				d:rect(x + 68, y + 69, w - 68, 1, C.line)
				y = y + 70
			end
		end
		d:text(T("bobba.phone.store.foot", "Apps come from this hotel's addons. Getting one puts it on your home screen."), 12, W / 2, y + 20, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		ctx.state.contentH = y + off - top + 50
	end)
end
DV.app({ id = "store", name = T("bobba.phone.app.store", "App Store"), color = C.blue, glyph = G.store, order = 80, removable = false, phone = storeView, tablet = storeView })

-- --- widgets ----------------------------------------------------------------------------------------
DV.widget({ id = "room", name = T("bobba.phone.widget.room", "Where you are"), size = "wide", bg = C.paper,
	draw = function(d, w, h)
		local c = R.current
		local inR = inRoom() and c
		d:round(17, 18, 18, 52, 52, inR and DV.accent() or C.mist)
		d:glyph(G.rooms, 30, 30, 28, C.navy, 2.2)
		d:text(inR and T("bobba.phone.widget.youin", "YOU'RE IN") or T("bobba.phone.widget.hotelview", "HOTEL VIEW"), 12, 84, 22, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
		d:textFit(inR and (c.name or "") or (BOBBA.hotelName or "Bobba Hotel"), 18, w - 100, 84, 40, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		local sub = inR and T("bobba.phone.widget.here", "%count% here · %owner%", { count = peopleHere(), owner = c.owner or "" }) or T("bobba.phone.widget.pick", "Pick a room to go to")
		d:textFit(sub, 13, w - 100, 84, 64, C.ink2)
		d:text(T("bobba.phone.widget.roomsbtn", "Rooms"), 13, 18, h - 26, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
		d:glyph(G.chevron, 64, h - 34, 16, C.navy, 2.4)
	end,
	click = function() DV.openApp("rooms") end })

DV.widget({ id = "wallet", name = T("bobba.phone.app.wallet", "Wallet"), size = "small",
	draw = function(d, w, h)
		local p = HUD.purse or {}
		d:text(T("bobba.phone.widget.wallet", "WALLET"), 12, 16, 16, C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
		d:text(money(p.credits), 26, 16, 36, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		d:text(T("bobba.phone.widget.credits", "credits"), 12, 16, 72, C.mist)
		d:text(money(p.points and p.points[0]) .. " " .. T("bobba.phone.widget.duckets", "duckets"), 12, 16, h - 30, C.mist)
	end,
	click = function() DV.openApp("wallet") end })

DV.widget({ id = "clock", name = T("bobba.phone.widget.clock", "Clock"), size = "small",
	draw = function(d, w, h)
		d:text(os.date("%A"):upper(), 12, 16, 16, C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
		d:text(os.date("%H:%M"), 34, 16, 34, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		d:text(os.date("%d %B"), 13, 16, h - 30, C.mist)
	end })

DV.widget({ id = "people", name = T("bobba.phone.widget.people", "In the room"), size = "small",
	draw = function(d, w, h)
		d:text(T("bobba.phone.widget.peopletitle", "IN THE ROOM"), 12, 16, 16, C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
		local n = inRoom() and peopleHere() or 0
		d:text(tostring(n), 34, 16, 34, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		local x = 16
		local i = 0
		for _, u in pairs(R.units or {}) do
			if i >= 4 then break end
			if not u.bot and not u.pet then
				d:round(8, x, h - 40, 24, 24, ({ C.blue, C.pink, C.yellow, C.green })[i + 1])
				d:text((u.name or "?"):sub(1, 1):upper(), 12, x + 12, h - 28, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
				x = x + 28
				i = i + 1
			end
		end
	end })

-- --- the shade's tiles ------------------------------------------------------------------------------
DV.tile({ id = "dnd", name = T("bobba.phone.tile.dnd", "Do not disturb"), glyph = G.moon,
	state = function() return DV.dnd and T("bobba.phone.on", "On") or T("bobba.phone.off", "Off") end,
	on = function() return DV.dnd end, click = function() DV.dnd = not DV.dnd end })
DV.tile({ id = "zoom", name = T("bobba.phone.tile.zoom", "Zoom"), glyph = G.zoom, visible = inRoom,
	state = function() return V.zoomed and T("bobba.phone.tile.zoomin", "Close up") or T("bobba.phone.tile.zoomout", "Normal") end,
	on = function() return V.zoomed and true or false end, click = function() act("zoom") end })
DV.tile({ id = "history", name = T("bobba.phone.tile.history", "Chat history"), glyph = G.history, visible = inRoom,
	state = function() return T("bobba.phone.tile.historysub", "What was said") end, click = function() DV.shadeTo = 0 act("chatHistory") end })
DV.tile({ id = "camera", name = T("bobba.phone.app.camera", "Camera"), glyph = G.camera, visible = inRoom,
	state = function() return T("bobba.phone.tile.camerasub", "Take a photo") end, click = function() DV.shadeTo = 0 DV.openApp("camera") end })
DV.tile({ id = "roominfo", name = T("bobba.phone.tile.room", "This room"), glyph = G.info, visible = inRoom,
	state = function() return T("bobba.phone.tile.roomsub", "Info and settings") end, click = function() DV.shadeTo = 0 act("roomSettings") end })
DV.tile({ id = "leave", name = T("bobba.phone.tile.leave", "Leave room"), glyph = G.leave, visible = inRoom,
	state = function() return T("bobba.phone.tile.leavesub", "To the hotel view") end, click = function() DV.shadeTo = 0 act("hotelView") end })

-- --- the room's name at the top left (the phone's look) ----------------------------------------------
U.hud("device.roomname", function(sw, sh)
	if not DV.active() or not inRoom() or not R.current or DV.covering() then return nil end
	local m = math.floor(math.min(sw, sh) * 0.025)
	-- (as wide as the room's name and how many are here)
	local pd = setmetatable({ surf = { clicks = {}, zones = {}, scrolls = {} }, s = U.scale(), ox = 0, oy = 0, a = 1 }, DV.PD)
	local name = pd:fit(R.current.name or "", 15, 520, 700)
	local sub = T("bobba.phone.widget.herecount", "%count% here", { count = peopleHere() })
	return m * 2, m, math.ceil(16 + pd:textWidth(name, 15, 700) + 12 + pd:textWidth(sub, 13, 500) + 16), 46
end, function(w, d)
	local c = R.current
	if not c then return end
	local pd = setmetatable({ surf = { panel = w.panel, clicks = {}, zones = {}, scrolls = {} }, s = d.s, ox = 0, oy = 0, a = 1 }, DV.PD)
	local name = pd:fit(c.name or "", 15, 520, 700)
	local nw = pd:textWidth(name, 15, 700)
	local sub = T("bobba.phone.widget.herecount", "%count% here", { count = peopleHere() })
	local sw2 = pd:textWidth(sub, 13, 500)
	local bw = 16 + nw + 12 + sw2 + 16
	local hover = d:click(0, 0, bw, 46, function() act("roomSettings") end)
	pd:round(18, 0, 0, bw, 46, Color(15, 26, 46, hover and 245 or 217))
	pd:text(name, 15, 16, 23, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
	pd:text(sub, 13, 16 + nw + 12, 23, C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)
