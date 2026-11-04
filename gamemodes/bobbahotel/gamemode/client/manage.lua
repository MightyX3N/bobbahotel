-- The hotel's Manage screen (client; hotel/manage.lua is the server's side): for its owner and admins,
-- from the start screen (client/picker.lua), the hotel's page and the desktop app's start screen.
-- Four parts: the look (name, what it's about, the UI it starts in, its colour, its page, its news),
-- the addons (on or off from the next start; their settings), the hotel's own settings, and the
-- money log (hotel/economy.lua: who got or lost money, club days or furni, why, with whom).
-- Drawn with the phone's kit, full screen, 1280 x 760 points scaled to the screen.

BOBBA.manageScreen = BOBBA.manageScreen or {}
local MS = BOBBA.manageScreen
local P = BOBBA.platform
local U = BOBBA.ui
local DV = BOBBA.device
local C, G = DV.C, DV.G
local alpha, hex = DV.alpha, DV.hex
local T = function(k, f, v) return U.text(k, f, v) end

MS.state = MS.state or nil     -- manage.state from the server
MS.tab = MS.tab or "look"      -- look, addons, settings (a section's id: MS.section)
MS.drafts = MS.drafts or {}

P.receive("manage.state", function(_, data) MS.state = data MS.gotAt = SysTime() end)
P.receive("manage.error", function(_, data)
	MS.error = { text = (tostring(data.message or ""):gsub("^%l", string.upper)), at = SysTime() }
end)
-- the money log: a page of lines (more: older ones to ask for)
MS.log = MS.log or { who = "", rows = {}, more = false }
P.receive("manage.log", function(_, data)
	local L = MS.log
	if (tonumber(data.before) or 0) > 0 and L.who == (data.who or "") then
		for _, r in ipairs(data.rows or {}) do L.rows[#L.rows + 1] = r end
	else
		L.rows = data.rows or {}
	end
	L.who, L.more, L.missing, L.loading = data.who or "", data.more, data.missing, false
end)
function MS.askLog(who, before)
	MS.log.loading = true
	P.send("manage.log", { who = who or "", before = before })
end

P.receive("manage.saved", function(_, data) MS.saved = { key = data.key, at = SysTime() } end)
P.receive("manage.restarting", function()
	MS.restarting = SysTime()
	-- (the desktop app: back to its start screen, where checking in starts the hotel again)
	if P.isDesktop and P.isDesktop() then
		timer.Simple(1.5, function() if BOBBA.hud and BOBBA.hud.actions and BOBBA.hud.actions.leaveHotel then BOBBA.hud.actions.leaveHotel() end end)
	end
end)

local function set(key, value) MS.error = nil P.send("manage.set", { key = key, value = value }) end

-- --- small parts ----------------------------------------------------------------------------------------
local function card(d, x, y, w, h) d:round(22, x, y, w, h, C.white) end
local function label(d, t, x, y) d:text(t, 13, x, y, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700) end
local function para(d, t, x, y, w, size, c)
	local lines = d:wrap(t or "", size or 13, w)
	for i, l in ipairs(lines) do d:text(l, size or 13, x, y + (i - 1) * math.floor((size or 13) * 1.45), c or C.ink2) end
	return #lines * math.floor((size or 13) * 1.45)
end
local function savedTick(d, key, x, y)
	if MS.saved and MS.saved.key == key and SysTime() - MS.saved.at < 2 then
		d:text(T("bobba.manage.saved", "Saved"), 12, x, y, C.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
	end
end
-- a text box with Save: draft kept while it's being changed
local function field(d, key, x, y, w, value, opts)
	opts = opts or {}
	local h = opts.h or 44
	local e = d:input("f:" .. key, x, y, w - 100, h, { value = tostring(value or ""), max = opts.max or 200, multiline = opts.multiline, bg = C.paper,
		radius = opts.multiline and 16 or nil, placeholder = opts.placeholder, onEnter = function(t) set(key, t) end })
	-- (the box shows the saved value until it's typed in)
	if not e:HasFocus() and e.bobbaShown ~= tostring(value or "") and not e.bobbaTyped then
		e:SetText(tostring(value or "")) e.bobbaShown = tostring(value or "")
	end
	e.bobbaChange = function() e.bobbaTyped = true end
	d:button(x + w - 90, y + (opts.multiline and 0 or 0), 90, 44, T("bobba.manage.save", "Save"), "primary", function()
		e.bobbaTyped = nil
		e.bobbaShown = nil
		set(key, e:GetValue() or "")
	end)
	savedTick(d, key, x + w - 90, y + 56)
	return h
end

-- what a setting says under its name: its description, and for a number what it can be
function MS.describe(s)
	local hint = s.type == "number" and (s.min or s.max) and T("bobba.manage.range", "%min% to %max%", { min = s.min or "", max = s.max or "" }) or nil
	if s.description and hint then return s.description .. " (" .. hint .. ")" end
	return s.description or hint
end

-- one setting's control: true/false, a number, choices or words. Returns its height.
local function settingRow(d, s, x, y, w)
	local key = s.key
	d:text(s.name, 15, x + 18, y + 16, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
	local h = 50
	local desc = MS.describe(s)
	if desc then h = h + para(d, desc, x + 18, y + 38, w * 0.5 - 30, 12, C.ink2) + 4 end
	local cx, cw = x + w * 0.5, w * 0.5 - 18
	if s.type == "bool" then
		DV.switch(d, x + w - 18 - 50, y + 14, s.value)
		d:click(x + w - 18 - 50, y + 14, 50, 30, function() set(key, not s.value) end)
		savedTick(d, key, x + w - 18 - 50 - 60, y + 29)
	elseif s.type == "choice" then
		local items = {}
		for _, c in ipairs(s.choices or {}) do items[#items + 1] = { id = tostring(c[1]), label = tostring(c[2] or c[1]) } end
		d:chips("c:" .. key, cx, y + 12, cw, items, tostring(s.value), function(id) set(key, id) end, { h = 34 })
		savedTick(d, key, cx, y + 56)
		h = math.max(h, 70)
	else
		local e = d:input("s:" .. key, cx, y + 10, cw - 100, 40, { value = tostring(s.value), max = s.max or 200, bg = C.paper,
			onEnter = function(t) set(key, t) end })
		if not e:HasFocus() and not e.bobbaTyped and e.bobbaShown ~= tostring(s.value) then e:SetText(tostring(s.value)) e.bobbaShown = tostring(s.value) end
		e.bobbaChange = function() e.bobbaTyped = true end
		d:button(cx + cw - 90, y + 10, 90, 40, T("bobba.manage.save", "Save"), "primary", function()
			e.bobbaTyped, e.bobbaShown = nil, nil
			set(key, e:GetValue() or "")
		end)
		savedTick(d, key, cx + cw - 150, y + 30)
	end
	return math.max(h, 60)
end

-- --- the look ------------------------------------------------------------------------------------------
local ACCENTS = { "FF9F5A", "6E8BFF", "3FC6A0", "F26B8A", "B98CFF", "FFD166", "E8C26A", "4FB3E8" }
local function lookView(d, x, y, w, st)
	local look = st.look or {}
	local col = (w - 20) / 2
	-- left column: name, about, news
	local lx, ly = x, y
	card(d, lx, ly, col, 300)
	label(d, T("bobba.manage.name", "THE HOTEL'S NAME"), lx + 20, ly + 18)
	field(d, "look.name", lx + 20, ly + 40, col - 40, look.name, { max = 32 })
	label(d, T("bobba.manage.about", "WHAT IT'S ABOUT (ITS PAGE AND THE START SCREEN)"), lx + 20, ly + 112)
	field(d, "look.description", lx + 20, ly + 134, col - 40, look.description, { max = 400, multiline = true, h = 120 })
	ly = ly + 316
	-- the news
	local news = look.news or {}
	local nh = 70 + #news * 64 + 230
	card(d, lx, ly, col, nh)
	label(d, T("bobba.manage.news", "NEWS ON THE HOTEL'S PAGE"), lx + 20, ly + 18)
	local ny = ly + 44
	if #news == 0 then d:text(T("bobba.manage.nonews", "No news yet: the page says welcome."), 13, lx + 20, ny + 4, C.slate) ny = ny + 30 end
	for i, it in ipairs(news) do
		d:round(14, lx + 20, ny, col - 40, 56, C.paper)
		d:round(8, lx + 32, ny + 14, 28, 28, hex(it.color or "FFD166"))
		d:textFit(it.title or "", 14, col - 190, lx + 72, ny + 10, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
		d:textFit(it.text or "", 12, col - 190, lx + 72, ny + 30, C.ink2)
		d:button(lx + col - 20 - 86, ny + 12, 76, 32, T("bobba.manage.remove", "Remove"), "light", function()
			local copy = {}
			for j, o in ipairs(news) do if j ~= i then copy[#copy + 1] = o end end
			set("look.news", copy)
		end)
		ny = ny + 64
	end
	-- adding one
	local dr = MS.drafts
	dr.newsColor = dr.newsColor or "FFD166"
	local te = d:input("newstitle", lx + 20, ny + 6, col - 40, 40, { max = 80, bg = C.paper, placeholder = T("bobba.manage.newstitle", "Title") })
	local xe = d:input("newstext", lx + 20, ny + 54, col - 40, 70, { max = 400, bg = C.paper, multiline = true, radius = 16, placeholder = T("bobba.manage.newstext", "What's new") })
	local cy = ny + 140
	for i, hx in ipairs({ "FFD166", "9DB4FF", "B7E4C7", "F26B8A", "B98CFF" }) do
		local ccx = lx + 34 + (i - 1) * 34
		d:click(ccx - 14, cy - 14, 28, 28, function() dr.newsColor = hx end)
		if dr.newsColor == hx then d:circle(ccx, cy, 15, C.navy) d:circle(ccx, cy, 12.5, C.white) end
		d:circle(ccx, cy, 10, hex(hx))
	end
	d:button(lx + col - 20 - 130, cy - 20, 130, 40, T("bobba.manage.addnews", "Add news"), "primary", function()
		local t = te:GetValue() or ""
		if t == "" then return end
		local copy = {}
		local item = { title = t, text = xe:GetValue() or "", date = os.date("%d %b %Y"), color = dr.newsColor }
		copy[1] = item
		for _, o in ipairs(news) do copy[#copy + 1] = o end
		set("look.news", copy)
		te:SetText("") xe:SetText("")
	end)
	ly = ly + nh + 16
	-- right column: the UI, the colour, the page
	local rx, ry = x + col + 20, y
	card(d, rx, ry, col, 150)
	label(d, T("bobba.manage.style", "THE LOOK PLAYERS START IN"), rx + 20, ry + 18)
	local styles = { { id = "", label = T("bobba.manage.style.pack", "The pack's choice") }, { id = "phone", label = T("bobba.manage.style.phone", "Phone and tablet") },
		{ id = "habbo", label = T("bobba.manage.style.classic", "Classic windows") } }
	d:chips("style", rx + 20, ry + 44, col - 40, styles, look.style or "", function(id) set("look.style", id) end, { h = 38, size = 14 })
	para(d, T("bobba.manage.stylenote", "Players can still pick their own in their settings."), rx + 20, ry + 96, col - 40, 12, C.slate)
	savedTick(d, "look.style", rx + col - 70, ry + 26)
	ry = ry + 166
	card(d, rx, ry, col, 130)
	label(d, T("bobba.manage.accent", "THE HOTEL'S COLOUR"), rx + 20, ry + 18)
	local cur = tostring(look.accent or ""):upper()
	for i, hx in ipairs(ACCENTS) do
		local ccx = rx + 40 + (i - 1) * 44
		local hov = d:click(ccx - 18, ry + 48, 36, 36, function() set("look.accent", hx) end)
		if cur == hx or (cur == "" and hx == "FF9F5A") then d:circle(ccx, ry + 66, 19, C.navy) d:circle(ccx, ry + 66, 16, C.white) end
		d:circle(ccx, ry + 66, hov and 14 or 13, hex(hx))
	end
	para(d, T("bobba.manage.accentnote", "The phone's and the page's colour. Players can pick their own."), rx + 20, ry + 96, col - 40, 12, C.slate)
	savedTick(d, "look.accent", rx + col - 70, ry + 26)
	ry = ry + 146
	-- the page
	local W = BOBBA.website
	local pages = W and W.list and W.list() or {}
	card(d, rx, ry, col, 60 + #pages * 52)
	label(d, T("bobba.manage.page", "THE HOTEL'S PAGE (AFTER CHECKING IN)"), rx + 20, ry + 18)
	local py = ry + 44
	for _, pg in ipairs(pages) do
		local on = (look.website or "") == pg.id
		local hov = d:click(rx + 20, py, col - 40, 44, function() set("look.website", pg.id) end)
		d:round(14, rx + 20, py, col - 40, 44, on and alpha(C.blue, 0.15) or (hov and C.paper or C.white))
		d:circle(rx + 42, py + 22, 9, on and C.blue or C.mist)
		if on then d:circle(rx + 42, py + 22, 4, C.white) end
		d:text(pg.name, 14, rx + 62, py + 22, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, on and 700 or 500)
		py = py + 52
	end
	savedTick(d, "look.website", rx + col - 70, ry + 26)
	ry = py + 16
	return math.max(ly, ry) - y
end

-- --- addons --------------------------------------------------------------------------------------------
local function addonsView(d, x, y, w, st)
	local yy = y
	para(d, T("bobba.manage.addonsnote", "Addons come from the Steam Workshop or the garrysmod/addons folder. Switching one on or off takes effect when the hotel starts again."), x, yy, w, 13, C.ink2)
	yy = yy + 46
	for _, a in ipairs(st.addons or {}) do
		local descH = a.description and #d:wrap(a.description, 13, w - 260) * 19 or 0
		local h = 86 + descH
		card(d, x, yy, w, h)
		d:round(14, x + 20, yy + 20, 46, 46, a.on and C.blue or C.mist)
		d:text((a.name or "?"):sub(1, 1):upper(), 20, x + 43, yy + 43, C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
		d:textFit(a.name or a.id, 17, w - 330, x + 82, yy + 18, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		local sub = (a.version and ("v" .. a.version .. " · ") or "") .. a.id .. (a.author and (" · " .. a.author) or "")
		d:textFit(sub, 12, w - 330, x + 82, yy + 42, C.slate)
		if a.description then para(d, a.description, x + 82, yy + 64, w - 260, 13, C.ink2) end
		-- what it's doing
		local status, sc
		if a.broken then status, sc = T("bobba.manage.broken", "Can't load: %why%", { why = a.why or "" }), C.red
		elseif a.on and a.loaded then status, sc = T("bobba.manage.running", "Running"), C.green
		elseif a.on and not a.loaded and a.why and a.why ~= "switched off by the server" then status, sc = T("bobba.manage.wontload", "Won't load: %why%", { why = a.why }), C.red
		elseif a.on then status, sc = T("bobba.manage.onnext", "On when the hotel starts again"), C.orange
		elseif a.loaded then status, sc = T("bobba.manage.offnext", "Off when the hotel starts again"), C.orange
		else status, sc = T("bobba.manage.off", "Off"), C.slate end
		d:textFit(status, 12, 230, x + w - 20, yy + 66 + descH, sc, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 700)
		if not a.broken then
			DV.switch(d, x + w - 20 - 50, yy + 22, a.on)
			d:click(x + w - 20 - 50, yy + 22, 50, 30, function() P.send("manage.addon", { id = a.id, on = not a.on }) end)
		end
		if a.hasSettings then
			d:button(x + w - 20 - 50 - 120, yy + 18, 106, 38, T("bobba.manage.settings", "Settings"), "light", function() MS.tab = "settings" MS.section = a.id end)
		end
		yy = yy + h + 12
	end
	return yy - y
end

-- --- settings (the hotel's, or an addon's) ------------------------------------------------------------
local function settingsView(d, x, y, w, st)
	local sec
	for _, s in ipairs(st.sections or {}) do if s.id == (MS.section or "core") then sec = s end end
	sec = sec or (st.sections or {})[1]
	if not sec then return 0 end
	-- which: chips of the sections
	local items = {}
	for _, s in ipairs(st.sections or {}) do items[#items + 1] = { id = s.id, label = s.id == "core" and T("bobba.manage.thehotel", "The hotel") or s.name } end
	d:chips("sections", x, y, w, items, sec.id, function(id) MS.section = id end, { h = 36, size = 14 })
	local yy = y + 52
	local group
	for _, s in ipairs(sec.settings) do
		if s.group ~= group then
			group = s.group
			if group then label(d, group:upper(), x + 4, yy + 6) yy = yy + 28 end
		end
		local h = 60
		-- (measured first: a description makes a row taller)
		local desc = MS.describe(s)
		if desc then h = 50 + #d:wrap(desc, 12, w * 0.5 - 30) * 17 + 4 end
		h = math.max(h, s.type == "choice" and 70 or 60)
		card(d, x, yy, w, h)
		settingRow(d, s, x, yy, w)
		yy = yy + h + 8
	end
	return yy - y
end

-- --- the money log -------------------------------------------------------------------------------------
local WHAT = { credits = "credits", duckets = "duckets", diamonds = "diamonds", hc = "days of club", vip = "days of VIP" }
local function logView(d, x, y, w)
	local L = MS.log
	local yy = y
	para(d, T("bobba.manage.lognote", "Every time someone gets or loses money, club days or furni: buying, gifts, trades, staff giving. Being paid for being online isn't in it."), x, yy, w, 13, C.ink2)
	yy = yy + 40
	local e = d:input("log:who", x, yy, w - 230, 44, { placeholder = T("bobba.manage.logwho", "Someone's name (empty: everyone)"), max = 40, bg = C.white,
		onEnter = function(t) MS.askLog(t) end })
	d:button(x + w - 220, yy, 105, 44, T("bobba.manage.logshow", "Show"), "primary", function() MS.askLog(e:GetValue()) end)
	d:button(x + w - 105, yy, 105, 44, T("bobba.manage.logall", "Everyone"), "light", function() e:SetText("") MS.askLog("") end)
	yy = yy + 60
	if L.missing then
		d:text(T("bobba.manage.lognoone", "No one's called that."), 14, x + 4, yy, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 600)
		return yy + 30 - y
	end
	if #L.rows == 0 then
		d:text(L.loading and T("bobba.manage.loading", "Loading...") or T("bobba.manage.lognothing", "Nothing yet."), 14, x + 4, yy, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 600)
		return yy + 30 - y
	end
	card(d, x, yy, w, #L.rows * 48 + 12)
	local ry = yy + 6
	for i, r in ipairs(L.rows) do
		if i > 1 then d:rect(x + 20, ry, w - 40, 1, C.mist) end
		d:text(os.date("%d %b %H:%M", r.at or 0), 12, x + 20, ry + 24, C.slate, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 600)
		d:textFit(r.name or r.key or "?", 14, 180, x + 130, ry + 24, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
		local n = tonumber(r.amount) or 0
		local amt = (n > 0 and "+" or "") .. n .. " " .. (r.what == "furni" and (BOBBA.shop and BOBBA.shop.furniName and BOBBA.shop.furniName(r.item or "") or r.item or "furni") or (WHAT[r.what] or r.what))
		d:textFit(amt, 14, w * 0.36, x + 330, ry + 24, n >= 0 and C.green or C.red, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
		local why = tostring(r.why or ""):gsub("^%l", string.upper) .. (r.otherName and (" · " .. T("bobba.manage.logwith", "with %name%", { name = r.otherName })) or "")
		d:textFit(why, 13, w - 330 - w * 0.36 - 40, x + w - 20, ry + 24, C.ink2, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 600)
		ry = ry + 48
	end
	yy = yy + #L.rows * 48 + 24
	if L.more then
		d:button(x + w / 2 - 80, yy, 160, 40, T("bobba.manage.logolder", "Older"), "light", function()
			MS.askLog(L.who, L.rows[#L.rows].id)
		end)
		yy = yy + 52
	end
	return yy - y
end

-- --- the screen -----------------------------------------------------------------------------------------
local function draw(d, W, H)
	d:rect(0, 0, W, H, C.paper)
	local st = MS.state
	-- the bar
	d:rect(0, 0, W, 72, C.navy)
	local acc = DV.accent()
	d:round(12, 24, 18, 36, 36, acc)
	d:glyph(G.settings, 31, 25, 22, C.navy, 2)
	local name = st and st.look and st.look.name or BOBBA.hotelName or "Bobba Hotel"
	d:textFit(T("bobba.manage.title", "Manage %hotel%", { hotel = name }), 20, W / 2 - 248 - 90, 74, 36, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
	d:button(W - 24 - 110, 16, 110, 40, T("bobba.manage.done", "Done"), "paper", function() MS.close() end)
	if not st then
		d:text(T("bobba.manage.loading", "Loading..."), 16, W / 2, H / 2, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		return
	end
	if st.denied then
		d:text(T("bobba.manage.denied", "Only the hotel's owner and its admins can manage it."), 16, W / 2, H / 2, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		return
	end
	-- the tabs
	local tabs = { { id = "look", label = T("bobba.manage.tab.look", "Look") }, { id = "addons", label = T("bobba.manage.tab.addons", "Addons") },
		{ id = "settings", label = T("bobba.manage.tab.settings", "Settings") }, { id = "log", label = T("bobba.manage.tab.log", "Money log") } }
	local tx = W / 2 - #tabs * 62 + 4
	for _, t in ipairs(tabs) do
		local on = MS.tab == t.id
		local hov = d:click(tx, 18, 116, 36, function()
			MS.tab = t.id
			if t.id == "settings" then MS.section = MS.section or "core" end
			if t.id == "log" then MS.askLog(MS.log.who) end
		end)
		d:pill(tx, 18, 116, 36, on and C.paper or (hov and C.navy3 or C.navy2))
		d:text(t.label, 14, tx + 58, 36, on and C.navy or C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
		tx = tx + 124
	end
	-- (addons changed: start again)
	local top = 72
	if st.restart or MS.restarting then
		d:rect(0, top, W, 56, alpha(C.orange, 0.2))
		local msg = MS.restarting and T("bobba.manage.restarting", "Starting the hotel again...")
			or T("bobba.manage.restartnote", "Addons were switched on or off: they change when the hotel starts again.")
		d:text(msg, 14, 24, top + 28, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
		if not MS.restarting and st.canRestart then
			local label2 = (P.isDesktop and P.isDesktop()) and T("bobba.manage.restartdesktop", "Start it again") or T("bobba.manage.restartnow", "Restart now")
			d:button(W - 24 - 170, top + 8, 170, 40, label2, "primary", function()
				DV.ask({ title = T("bobba.manage.restartq", "Start the hotel again?"),
					text = T("bobba.manage.restartqtext", "Everyone in it is sent back to the start for a moment while it loads again."),
					ok = T("bobba.manage.restartyes", "Start again"), fn = function() P.send("manage.restart", {}) end })
			end)
		end
		top = top + 56
	end
	-- the part shown, scrolled
	local cw = math.min(1100, W - 48)
	local cx = (W - cw) / 2
	local viewH = H - top
	local off = d:scroll("manage:" .. MS.tab, 0, top, W, viewH, MS.contentH or viewH)
	d:clip(0, top, W, viewH, function()
		d:translate(0, -off, function()
			local h
			if MS.tab == "addons" then h = addonsView(d, cx, top + 24, cw, st)
			elseif MS.tab == "settings" then h = settingsView(d, cx, top + 24, cw, st)
			elseif MS.tab == "log" then h = logView(d, cx, top + 24, cw)
			else h = lookView(d, cx, top + 24, cw, st) end
			MS.contentH = h + 60
		end)
	end)
	-- (text boxes scrolled out of sight are hidden: they'd show over the bar)
	for _, e in pairs(d.surf.inputs or {}) do
		if IsValid(e) and e:IsVisible() then
			local _, ey = e:GetPos()
			if ey < top * d.s or ey + e:GetTall() > H * d.s then e:SetVisible(false) end
		end
	end
	-- an error
	if MS.error and SysTime() - MS.error.at < 5 then
		local tw = d:textWidth(MS.error.text, 14, 700) + 48
		d:pill(W / 2 - tw / 2, H - 70, tw, 44, C.red)
		d:text(MS.error.text, 14, W / 2, H - 48, C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
	end
	-- a question (restarting)
	if DV.drawQuestion then DV.drawQuestion(d, W, H) end
end

-- --- opening and closing ---------------------------------------------------------------------------------
function MS.open(onClose)
	MS.onClose = onClose
	P.send("manage.get", {})
	if IsValid(MS.panel) then MS.panel:SetVisible(true) MS.panel:MakePopup() return end
	local p = vgui.Create("EditablePanel")
	p:SetPos(0, 0)
	p:SetSize(ScrW(), ScrH())
	p:SetZPos(30000)
	p:MakePopup()
	p:SetKeyboardInputEnabled(true)
	MS.panel = p
	local surf = DV.makeSurface(p, draw)
	MS.surface = surf
	p.Think = function(self)
		if self:GetWide() ~= ScrW() or self:GetTall() ~= ScrH() then self:SetSize(ScrW(), ScrH()) end
		surf.s = math.min(ScrW() / 1280, ScrH() / 760)
		surf.panel:SetPos(0, 0)
		surf.panel:SetSize(ScrW(), ScrH())
		self:MoveToFront()
	end
	p:Think()
	MS.showing = true
end

function MS.close()
	MS.showing = false
	if IsValid(MS.panel) then MS.panel:Remove() end
	MS.panel = nil
	DV.question = nil
	local fn = MS.onClose
	MS.onClose = nil
	if fn then fn() end
end

-- (the console: bobba_manage)
concommand.Add("bobba_manage", function() MS.open() end)
