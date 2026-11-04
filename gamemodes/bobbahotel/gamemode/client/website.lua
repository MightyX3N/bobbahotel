-- The hotel's own page (client): what you see after checking in, before going in. It's Lua, part of
-- the hotel: this file has the default one (the phone's look); a pack or an addon makes its own, and
-- the hotel's Manage screen picks which shows (hotel/manage.lua's website.page; else a pack's):
--
--   BOBBA.website.register("my_page", { name = "My page", draw = function(d, W, H, site) ... end, pack = true })
--   (BOBBA.website.page = function ... also still works)
--   draw(d, W, H, site): d is the phone's drawing kit,
--       client/device.lua's PD; d.fontFn sets another font); site.enter() goes in, site.data is what
--       the server says (hotel.page: name, description, online, figure, gender, news, events, rooms,
--       credits), site.friends the friends online, site.state a table of its own
--   BOBBA.website.enabled = false   -- no page: straight in (as before)
--
-- Going in sends room.ready (the server puts you in your home room, or the starter picker).

BOBBA.website = BOBBA.website or {}
local W = BOBBA.website
local P = BOBBA.platform
local U = BOBBA.ui
local DV = BOBBA.device
local C = DV.C
local alpha = DV.alpha
local T = function(k, f, v) return U.text(k, f, v) end

if W.enabled == nil then W.enabled = true end
W.pages = W.pages or {}
W.pageOrder = W.pageOrder or {}
function W.register(id, def)
	if not W.pages[id] then W.pageOrder[#W.pageOrder + 1] = id end
	def.id = id
	W.pages[id] = def
end
for _, w in ipairs(W.waiting or {}) do W.register(w[1], w[2]) end
W.waiting = nil
-- the pages there are to pick from (the Manage screen): { { id, name } }; "" is the pack's
function W.list()
	local out = { { id = "", name = BOBBA.ui.text("bobba.manage.website.auto", "The pack's (or Bobba's own)") }, { id = "default", name = BOBBA.ui.text("bobba.manage.website.default", "Bobba's own") } }
	for _, id in ipairs(W.pageOrder) do out[#out + 1] = { id = id, name = W.pages[id].name or id } end
	return out
end
-- the page that shows: the hotel's pick, else a pack's, else the default
function W.current()
	local want = BOBBA.hotelLook and BOBBA.hotelLook.website or ""
	if want == "default" then return W.defaultPage end
	if want ~= "" and W.pages[want] then return W.pages[want].draw end
	if W.page then return W.page end
	for _, id in ipairs(W.pageOrder) do if W.pages[id].pack then return W.pages[id].draw end end
	return W.defaultPage
end
W.data = W.data or nil
W.state = W.state or {}
W.entered = W.entered or false

function W.wanted() return W.enabled and not W.entered end

P.receive("hotel.page", function(_, data)
	W.data = data
	BOBBA.hotelName = tostring(data.name or BOBBA.hotelName or "Bobba Hotel")
end)

local function me() return LocalPlayer and IsValid(LocalPlayer()) and LocalPlayer():Nick() or "" end

local site = {}
function site.enter(after)
	W.entered = true
	W.hide()
	P.send("room.ready", {})
	if after then timer.Simple(2, after) end
end
W.site = site

-- --- the default page (the phone's look) ------------------------------------------------------------
local function newsCards(d, x, y, w, data)
	local news = data and data.news
	if not news or #news == 0 then
		news = { { title = T("bobba.website.welcome", "Welcome to %hotel%", { hotel = data and data.name or "" }), text = T("bobba.website.welcometext", "Your phone has everything: rooms, the shops, friends, groups and events."), color = "FFD166" } }
		local ev = data and data.events and data.events[1]
		if ev then news[2] = { title = ev.name, text = T("bobba.website.eventon", "On now in %room%", { room = ev.roomName or "" }), color = "9DB4FF", room = ev.room } end
	end
	local n = math.min(2, #news)
	local cw = (w - (n - 1) * 16) / math.max(1, n)
	for i = 1, n do
		local it = news[i]
		local cx = x + (i - 1) * (cw + 16)
		d:round(26, cx, y, cw, 200, C.paper)
		d:round(26, cx, y, cw, 100, DV.hex(it.color or "FFD166"), true, true, false, false)
		d:text(it.date or "", 12, cx + 18, y + 114, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
		d:textFit(it.title or "", 16, cw - 36, cx + 18, y + (it.date and 132 or 116), C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		for j, l in ipairs(d:wrap(it.text or "", 13, cw - 36)) do
			if j <= 2 then d:text(l, 13, cx + 18, y + (it.date and 156 or 142) + (j - 1) * 18, C.ink2) end
		end
	end
	return 200
end

local function defaultPage(d, WW, HH, s)
	local data = W.data or {}
	local SO = BOBBA.social
	d:rect(0, 0, WW, HH, C.navy)
	local acc = DV.accent()
	-- the bar: the hotel, its parts, how many are here
	local pad = math.max(40, (WW - 1200) / 2)
	local name = data.name or BOBBA.hotelName or "Bobba Hotel"
	d:round(12, pad, 18, 36, 36, acc)
	d:text(name:sub(1, 1):upper(), 18, pad + 18, 36, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
	d:text(name, 18, pad + 48, 36, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
	local nx = pad + 70 + d:textWidth(name, 18, 800) + 20
	for i, label in ipairs({ T("bobba.website.home", "Home"), T("bobba.website.news", "News"), T("bobba.website.community", "Community") }) do
		d:text(label, 15, nx, 36, i == 1 and C.paper or C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 600)
		nx = nx + d:textWidth(label, 15, 600) + 28
	end
	local online = T("bobba.website.online", "%n% checked in", { n = data.online or 0 })
	local ow = d:textWidth(online, 14, 600)
	d:circle(WW - pad - ow - 16, 36, 4.5, C.green)
	d:text(online, 14, WW - pad, 36, C.mist, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 600)
	-- the welcome
	local y = 80
	local hw = WW - pad * 2
	local hh = 300
	d:round(36, pad, y, hw, hh, C.navy2)
	d:clip(pad, y, hw, hh, function()
		d:circle(pad + hw + 60 - 180, y - 40 + 180, 180, acc)
		d:circle(pad + hw - 250 - 90, y + 170 + 90, 90, C.blue)
	end)
	local friendsOn = {}
	for _, f in ipairs(SO and SO.friends or {}) do if f.online then friendsOn[#friendsOn + 1] = f end end
	local unread = SO and SO.unreadMessages() or 0
	d:text(T("bobba.website.welcomeback", "Welcome back"), 15, pad + 48, y + 48, C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 600)
	d:textFit(me(), 50, hw * 0.55, pad + 48, y + 66, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	local line
	if #friendsOn > 0 then line = T("bobba.website.friendsin", "%n% friends are here.", { n = #friendsOn }) else line = T("bobba.website.nofriends", "The hotel's waiting for you.") end
	if unread > 0 then line = line .. " " .. T("bobba.website.unread", "You have %n% new messages.", { n = unread }) end
	d:text(line, 16, pad + 48, y + 160, C.mist)
	d:button(pad + 48, y + 204, 200, 56, T("bobba.website.enter", "Enter hotel"), "paper", function() site.enter() end)
	d.bgUnder = C.navy2
	d:button(pad + 262, y + 204, 180, 56, T("bobba.website.looks", "Change looks"), "outlineLight", function()
		site.enter(function() if DV.active() then DV.openApp("clothes") elseif BOBBA.avatarEditor and BOBBA.avatarEditor.open then BOBBA.avatarEditor.open() end end)
	end)
	d.bgUnder = nil
	-- you
	local AE = BOBBA.avatarEditor
	local figure = data.figure or (AE and AE.defaultFigure and AE.defaultFigure())
	if figure then
		d:clip(pad, y, hw, hh, function()
			d:avatar(figure, data.gender, 2, pad + hw - 220, y + hh - 220, 2)
		end)
	end
	y = y + hh + 24
	-- news, and friends online
	local colW = (hw - 20) / 3
	d:text(T("bobba.website.news", "News"), 18, pad, y, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	newsCards(d, pad, y + 32, colW * 2 + 4, data)
	local fx = pad + colW * 2 + 20
	local fh = math.min(HH - y - 40, 232)
	d:round(26, fx, y, colW, fh, C.navy2)
	d:text(T("bobba.website.friendson", "Friends online"), 18, fx + 20, y + 18, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	if #friendsOn == 0 then
		d:text(T("bobba.website.nofriendson", "No friends here right now."), 14, fx + 20, y + 56, C.mist)
	end
	for i, f in ipairs(friendsOn) do
		if i > 3 then break end
		local ry = y + 52 + (i - 1) * 54
		DV.face(d, f.figure, f.gender, f.name, fx + 20, ry, 40)
		d:textFit(f.name or "", 15, colW - 150, fx + 72, ry + 2, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
		d:textFit(f.roomName or T("bobba.website.hotelview", "Hotel view"), 13, colW - 150, fx + 72, ry + 22, C.mist)
		if f.room then
			local hov = d:click(fx + colW - 80, ry + 6, 64, 28, function() site.enter(function() P.send("friends.follow", { key = f.key }) end) end)
			d:text(T("bobba.website.follow", "Follow"), 13, fx + colW - 20, ry + 20, hov and C.paper or C.mist, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 800)
		end
	end
	d:text(T("bobba.website.own", "This page is the hotel's own (its pack or its owner made it)"), 12, WW - pad, HH - 20, C.slate, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end
W.defaultPage = defaultPage

-- (bottom left: "Hotels" back to the start screen in Garry's Mod; "Manage hotel" for its owner and admins)
function W.corner(d, ww, hh)
	local x = 16
	local function pill(label, glyph, fn)
		local w = d:textWidth(label, 13, 700) + (glyph and 46 or 28)
		local hov = d:click(x, hh - 52, w, 36, fn)
		d:pill(x, hh - 52, w, 36, Color(15, 26, 46, hov and 240 or 200))
		if glyph then d:glyph(glyph, x + 12, hh - 52 + 9, 18, C.paper, 2) end
		d:text(label, 13, x + (glyph and 36 or 14), hh - 34, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
		x = x + w + 8
	end
	local PK = BOBBA.picker
	if PK and PK.available and PK.available() then
		pill(T("bobba.website.hotels", "Hotels"), "M15 18l-6-6 6-6", function() W.hide() PK.show() end)
	end
	if W.data and W.data.canManage and BOBBA.manageScreen then
		pill(T("bobba.website.manage", "Manage hotel"), DV.G and DV.G.settings, function() BOBBA.manageScreen.open() end)
	end
end

-- --- showing it -------------------------------------------------------------------------------------
function W.show()
	if IsValid(W.panel) then W.panel:SetVisible(true) return end
	P.send("hotel.get", {})
	P.send("friends.get", {})
	local p = vgui.Create("EditablePanel")
	p:SetPos(0, 0)
	p:SetSize(ScrW(), ScrH())
	p:MakePopup()
	p:SetKeyboardInputEnabled(false)
	W.panel = p
	-- (drawn with the phone's kit, in points: 1280 wide pages scaled to the screen)
	local surf = DV.makeSurface(p, function(d, ww, hh)
		site.data = W.data
		site.state = W.state
		site.friends = BOBBA.social and BOBBA.social.friends or {}
		local page = W.current() or defaultPage
		local ok, err = pcall(page, d, ww, hh, site)
		if not ok then
			ErrorNoHalt("[Bobba] website: " .. tostring(err) .. "\n")
			d:rect(0, 0, ww, hh, C.navy)
			d:button(ww / 2 - 100, hh / 2 - 28, 200, 56, T("bobba.website.enter", "Enter hotel"), "paper", function() site.enter() end)
		end
		-- over any page: the hotel's owner and admins manage it from here; and back to the hotels
		d.fontFn = nil
		W.corner(d, ww, hh)
	end)
	W.surface = surf
	p.Think = function(self)
		if self:GetWide() ~= ScrW() or self:GetTall() ~= ScrH() then self:SetSize(ScrW(), ScrH()) end
		surf.s = math.min(ScrW() / 1280, ScrH() / 760)
		surf.panel:SetPos(0, 0)
		surf.panel:SetSize(ScrW(), ScrH())
	end
	p:Think()
	W.showing = true
	BOBBA.events.emit("websiteShown")
end

function W.hide()
	W.showing = false
	if IsValid(W.panel) then W.panel:Remove() end
	W.panel = nil
end

-- Enter in the page: in
hook.Add("Think", "bobba.website.keys", function()
	if not W.showing or (BOBBA.loading and BOBBA.loading.active) then return end
	local down = input.IsKeyDown(KEY_ENTER)
	if down and not W.enterWas and not (vgui.GetKeyboardFocus and IsValid(vgui.GetKeyboardFocus()) and vgui.GetKeyboardFocus().GetCaretPos) then site.enter() end
	W.enterWas = down
end)
