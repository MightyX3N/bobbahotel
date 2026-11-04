-- The start screen in Garry's Mod (client), as the desktop app has it: pick a hotel to check in to -
-- this one (yours: singleplayer, or a listen server you host) or one you've added (Garry's Mod asks
-- to connect to it) - then the hotel's page (client/website.lua), then the room. Shown only to who
-- hosts the game; joining someone's server goes straight to its page. Its owner and admins manage
-- the hotel from here (client/manage.lua). Same look as the desktop app's: a sunset on the left,
-- the hotel's skyline on the right. 1280 x 760 points scaled to the screen.

BOBBA.picker = BOBBA.picker or {}
local PK = BOBBA.picker
local P = BOBBA.platform
local U = BOBBA.ui
local DV = BOBBA.device
local T = function(k, f, v) return U.text(k, f, v) end

PK.var = CreateClientConVar("bobba_startscreen", "1", true, false, "Show the start screen (pick a hotel) when you host the game: 1 or 0")

local function rgb(h) return Color(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)) end
local K = {
	ink = rgb("2A1206"), ink2 = rgb("4A1A06"), ink3 = rgb("6B3A1E"), card = rgb("FFF9F0"), sel = rgb("FFE2C2"), cream = rgb("FFF6E8"),
	rust = rgb("7A2E0E"), dash = rgb("E3B98F"), green = rgb("1E7A46"), grey = rgb("8A5A3C"),
	top = rgb("FF6B4A"), bottom = rgb("FFC24B"), sky1 = rgb("3B1A3F"), sky2 = rgb("A8432A"), sky3 = rgb("E8873A"),
	sun = rgb("FFC24B"), b1 = rgb("2A1630"), b2 = rgb("331A38"), win = rgb("FFD27A"), mint = rgb("6EE7A8"), field = rgb("F3D9BF"),
	desc = rgb("F6DCCB"),
}
local LETTERS = { rgb("FF9F5A"), rgb("9DB4FF"), rgb("B7E4C7"), rgb("B98CFF"), rgb("F26B8A") }

-- who sees it: whoever hosts the game (not the desktop app: it has its own)
function PK.available()
	if P.isDesktop and P.isDesktop() then return false end
	local lp = LocalPlayer and LocalPlayer()
	return (game.SinglePlayer() or (IsValid(lp) and lp.IsListenServerHost and lp:IsListenServerHost())) and true or false
end
function PK.wanted() return PK.available() and PK.var:GetBool() and not PK.done end

-- --- the hotels you've added (data/bobbahotel/servers.txt) ----------------------------------------------
local function loadServers()
	if PK.servers then return PK.servers end
	local raw = P.readData and P.readData("servers.txt") or nil
	local t = raw and util.JSONToTable(raw) or nil
	PK.servers = type(t) == "table" and t or {}
	return PK.servers
end
local function saveServers() if P.writeData then P.writeData("servers.txt", util.TableToJSON(PK.servers or {})) end end

local function hotelName() return (BOBBA.website and BOBBA.website.data and BOBBA.website.data.name) or BOBBA.hotelName or "Bobba Hotel" end
local function packName()
	local names = {}
	for _, m in pairs(BOBBA.addons and BOBBA.addons.loaded or {}) do names[#names + 1] = m.name end
	table.sort(names)
	return names[1] or T("bobba.picker.nopack", "No pack")
end
local function list()
	local out = { { name = hotelName(), info = (game.SinglePlayer() and T("bobba.picker.single", "On this computer") or T("bobba.picker.listen", "You're hosting it")) .. " · " .. packName(),
		status = T("bobba.picker.ready", "Ready"), statusColor = K.green, here = true } }
	for _, sv in ipairs(loadServers()) do
		out[#out + 1] = { name = (sv.name or "") ~= "" and sv.name or sv.address, info = sv.address, status = T("bobba.picker.away", "Connect"), statusColor = K.grey, address = sv.address, saved = sv }
	end
	return out
end
local function chosen()
	local l = list()
	PK.chosen = math.Clamp(PK.chosen or 1, 1, #l)
	return l[PK.chosen], PK.chosen
end

-- --- drawing ----------------------------------------------------------------------------------------------
local logoFonts = {}
local function logoFont(px, _, s)
	local size = math.max(8, math.floor(px * 1.18 * (s or 1) + 0.5))
	local name = "BobbaLogo" .. size
	if not logoFonts[name] then
		surface.CreateFont(name, { font = "Lilita One", size = size, weight = 400, antialias = true, extended = true })
		logoFonts[name] = true
	end
	return name
end
local function logo(d, cx, y, px)
	d.fontFn = logoFont
	d:text("bobba", px, cx + 8, y + 8, DV.alpha(K.rust, 0.45), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	d:text("bobba", px, cx + 4, y + 4, K.rust, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	d:text("bobba", px, cx, y, K.cream, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	d.fontFn = nil
end
local function gradient(d, x, y, w, h, stops)
	local n = 48
	for i = 0, n - 1 do
		local t = (i + 0.5) / n
		local a, b = stops[1], stops[#stops]
		for j = 1, #stops - 1 do if t >= stops[j][1] and t <= stops[j + 1][1] then a, b = stops[j], stops[j + 1] end end
		local k = (b[1] - a[1]) > 0 and (t - a[1]) / (b[1] - a[1]) or 0
		local c = Color(a[2].r + (b[2].r - a[2].r) * k, a[2].g + (b[2].g - a[2].g) * k, a[2].b + (b[2].b - a[2].b) * k)
		d:rect(x, y + h * i / n, w, h / n + 1, c)
	end
end
local function button(d, label, x, y, w, h, style, fn, size)
	local hov = d:click(x, y, w, h, fn)
	if style == "dark" then d:round(h / 2, x, y, w, h, hov and K.ink2 or K.ink)
	elseif style == "light" then d:round(h / 2, x, y, w, h, hov and K.sel or K.field)
	else d:round(h / 2, x, y, w, h, K.ink3) d:round(h / 2 - 2, x + 2, y + 2, w - 4, h - 4, hov and K.sel or K.card) end
	d:textFit(label, size or 16, w - 24, x + w / 2, y + h / 2, style == "dark" and K.cream or K.ink, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
end

local function serverList(d, cx, y)
	local l = list()
	local _, ci = chosen()
	local w, rowH = 460, 70
	local x = cx - w / 2
	local h = 10 + #l * (rowH + 6) + 56 + 10
	d:round(26, x + 4, y + 14, w, h, DV.alpha(K.rust, 0.18))
	d:round(26, x, y, w, h, K.card)
	local yy = y + 10
	for i, sv in ipairs(l) do
		local on = i == ci
		local hover = d:click(x + 10, yy, w - 20, rowH, function() PK.chosen = i PK.message = nil end)
		if on or hover then d:round(18, x + 10, yy, w - 20, rowH, on and K.sel or DV.alpha(K.sel, 0.55)) end
		d:round(15, x + 24, yy + 12, 46, 46, LETTERS[(i - 1) % #LETTERS + 1])
		d:text(tostring(sv.name):sub(1, 1):upper(), 19, x + 47, yy + 35, K.ink, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
		d:textFit(sv.name, 16, w - 220, x + 84, yy + 14, K.ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
		d:textFit(sv.info, 13, w - 220, x + 84, yy + 37, K.ink3)
		local stw = d:textWidth(sv.status, 13, 700)
		d:circle(x + w - 34 - stw - 10, yy + rowH / 2, 4.5, sv.statusColor)
		d:text(sv.status, 13, x + w - 34 - stw, yy + rowH / 2, sv.statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
		if sv.saved and hover then
			local rx = x + w - 34 - stw - 50
			local hv = d:click(rx, yy + 20, 30, 30, function()
				for j, o in ipairs(PK.servers) do if o == sv.saved then table.remove(PK.servers, j) break end end
				saveServers()
				PK.chosen = 1
			end)
			if hv then d:circle(rx + 15, yy + 35, 15, K.field) end
			d:text("×", 18, rx + 15, yy + 35, K.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
		end
		yy = yy + rowH + 6
	end
	local hover = d:click(x + 10, yy, w - 20, 50, function() PK.sheet = "add" PK.message = nil end)
	d:round(18, x + 10, yy, w - 20, 50, hover and DV.alpha(K.sel, 0.6) or K.cream)
	d:text("+  " .. T("bobba.picker.add", "Add a server"), 15, cx, yy + 25, K.rust, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
	return h
end

local function leftPanel(d, x0, W, H)
	gradient(d, x0, 0, W, H, { { 0, K.top }, { 1, K.bottom } })
	local cx = x0 + W / 2
	local top = math.max(40, (H - 640) / 2)
	logo(d, cx, top + 10, 76)
	d:text(T("bobba.picker.pick", "Pick a hotel to check in"), 15, cx, top + 112, K.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 700)
	local lh = serverList(d, cx, top + 140)
	local sv = chosen()
	local by = top + 140 + lh + 22
	button(d, T("bobba.picker.checkin", "Check in to %name%", { name = sv.name }), cx - 230, by, 460, 58, "dark", function() PK.enter() end, 18)
	local note = PK.message or (sv.here and T("bobba.picker.herenote", "You're hosting this one: it's ready.") or T("bobba.picker.awaynote", "Garry's Mod asks before it leaves this game for that server."))
	local lines = d:wrap(note, 13, 460)
	for i, l in ipairs(lines) do d:text(l, 13, cx, by + 72 + (i - 1) * 18, K.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 700) end
end

local function rightPanel(d, x0, W, H)
	gradient(d, x0, 0, W, H, { { 0, K.sky1 }, { 0.7, K.sky2 }, { 1, K.sky3 } })
	local bx = x0 + W / 2 - 320
	d:circle(bx + 470, H - 190, 120, DV.alpha(K.sun, 0.9))
	for _, b in ipairs({ { 90, 280, 90, K.b1 }, { 190, 340, 120, K.b2 }, { 330, 240, 80, K.b1 }, { 420, 180, 150, K.b2 } }) do
		d:round(6, bx + b[1], H - b[2], b[3], b[2] + 10, b[4])
	end
	for _, wnd in ipairs({ { 110, 250 }, { 146, 250 }, { 110, 210 }, { 212, 310 }, { 246, 310 }, { 280, 270 }, { 212, 230 }, { 246, 190 }, { 350, 210 }, { 380, 170 }, { 444, 150 }, { 480, 150 }, { 516, 110 } }) do
		d:round(2, bx + wnd[1], H - wnd[2], 15, 19, K.win)
	end
	local sv = chosen()
	local x = x0 + 56
	local y = math.max(60, (H - 640) / 2 + 30)
	local pill = sv.here and T("bobba.picker.thisone", "This game") or T("bobba.picker.elsewhere", "Somewhere else")
	local pw = d:textWidth(pill, 13, 700) + 40
	d:round(14, x, y, pw, 30, DV.alpha(K.cream, 0.16))
	d:circle(x + 16, y + 15, 4.5, sv.here and K.mint or K.dash)
	d:text(pill, 13, x + 28, y + 15, K.cream, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
	y = y + 50
	d.fontFn = logoFont
	local lines = d:wrap(sv.name, 56, W - 112)
	for i, l in ipairs(lines) do if i <= 2 then d:text(l, 56, x, y + (i - 1) * 60, K.cream) end end
	d.fontFn = nil
	y = y + math.min(2, #lines) * 60 + 12
	local data = BOBBA.website and BOBBA.website.data or {}
	local desc
	if sv.here then
		desc = (data.description and data.description ~= "") and data.description
			or T("bobba.picker.heredesc", "Your own hotel. Everyone who checks in keeps their rooms, furni and friends here.")
	else
		desc = T("bobba.picker.awaydesc", "Another hotel. Checking in asks Garry's Mod to join it at %address%.", { address = sv.address or "" })
	end
	for i, l in ipairs(d:wrap(desc, 17, math.min(470, W - 112))) do
		if i <= 5 then d:text(l, 17, x, y + (i - 1) * 26, K.desc) end
	end
	y = y + math.min(5, #d:wrap(desc, 17, math.min(470, W - 112))) * 26 + 22
	local tags = sv.here and { packName(), T("bobba.picker.online", "%n% here", { n = #player.GetAll() }), T("bobba.picker.as", "as %name%", { name = LocalPlayer():Nick() }) }
		or { sv.address or "" }
	local tx = x
	for _, t in ipairs(tags) do
		local tw = d:textWidth(t, 13, 700) + 24
		if tx + tw > x0 + W - 40 then tx = x y = y + 40 end
		d:round(12, tx, y, tw, 32, DV.alpha(K.cream, 0.16))
		d:text(t, 13, tx + 12, y + 16, K.cream, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
		tx = tx + tw + 8
	end
	-- the owner's and admins' way in: Manage hotel
	if sv.here and data.canManage then
		y = y + 56
		local hov = d:click(x, y, 200, 46, function() PK.hide(true) BOBBA.manageScreen.open(function() PK.show() end) end)
		d:round(23, x, y, 200, 46, hov and K.cream or DV.alpha(K.cream, 0.9))
		d:glyph(DV.G.settings, x + 16, y + 12, 22, K.ink, 2)
		d:text(T("bobba.picker.manage", "Manage hotel"), 15, x + 46, y + 23, K.ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
	end
end

-- adding a server
local function addSheet(d, cx, y)
	local w, h = 460, 300
	local x = cx - w / 2
	d:rect(0, 0, 4000, 4000, Color(0, 0, 0, 90))
	d:click(0, 0, 4000, 4000, function() PK.sheet = nil end)
	d:click(x, y, w, h, function() end)
	d:round(26, x + 4, y + 14, w, h, DV.alpha(K.rust, 0.2))
	d:round(26, x, y, w, h, K.card)
	d:text(T("bobba.picker.addtitle", "Add a server"), 20, x + 26, y + 24, K.ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	d:text(T("bobba.picker.addname", "Its name (for you)"), 13, x + 26, y + 66, K.ink3, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
	local ne = d:input("addname", x + 26, y + 86, w - 52, 46, { max = 40, bg = K.field, fg = K.ink, placeholder = T("bobba.picker.addnamehint", "e.g. Sunset Hotel") })
	d:text(T("bobba.picker.addaddress", "Its address"), 13, x + 26, y + 144, K.ink3, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
	local ae = d:input("addaddress", x + 26, y + 164, w - 52, 46, { max = 80, bg = K.field, fg = K.ink, placeholder = "address:port" })
	local function add()
		local address = (ae:GetValue() or ""):gsub("%s", "")
		if address == "" then PK.message = T("bobba.picker.needaddress", "It needs an address (like play.example.com:27015).") return end
		loadServers()
		PK.servers[#PK.servers + 1] = { name = (ne:GetValue() or ""):gsub("^%s+", ""):gsub("%s+$", ""), address = address }
		saveServers()
		PK.chosen = #PK.servers + 1
		ne:SetText("") ae:SetText("")
		PK.sheet = nil
		PK.message = nil
	end
	button(d, T("bobba.picker.addok", "Add"), x + w - 26 - 130, y + 232, 130, 46, "dark", add, 16)
	button(d, T("bobba.picker.cancel", "Cancel"), x + 26, y + 232, 130, 46, "outline", function() PK.sheet = nil end, 15)
end

local function draw(d, W, H)
	local half = math.floor(W / 2)
	rightPanel(d, half, W - half, H)
	leftPanel(d, 0, half, H)
	if PK.sheet == "add" then addSheet(d, half / 2, math.max(80, (H - 640) / 2 + 120)) end
end

-- --- checking in --------------------------------------------------------------------------------------
function PK.enter()
	local sv = chosen()
	if not sv.here then
		-- (Garry's Mod asks the player first, then leaves this game for that server)
		if permissions and permissions.AskToConnect then
			permissions.AskToConnect(sv.address)
		else
			SetClipboardText("connect " .. sv.address)
			PK.message = T("bobba.picker.copied", "Copied: open the console (~) and paste it to join.")
		end
		return
	end
	PK.done = true
	PK.hide()
	local W = BOBBA.website
	if W and W.wanted and W.wanted() then W.show() else P.send("room.ready", {}) end
end

function PK.show()
	PK.showing = true
	P.send("hotel.get", {})
	if IsValid(PK.panel) then PK.panel:SetVisible(true) PK.panel:MakePopup() return end
	local p = vgui.Create("EditablePanel")
	p:SetPos(0, 0)
	p:SetSize(ScrW(), ScrH())
	p:MakePopup()
	p:SetKeyboardInputEnabled(true)
	PK.panel = p
	local surf = DV.makeSurface(p, draw)
	PK.surface = surf
	p.Think = function(self)
		if self:GetWide() ~= ScrW() or self:GetTall() ~= ScrH() then self:SetSize(ScrW(), ScrH()) end
		surf.s = math.min(ScrW() / 1280, ScrH() / 760)
		surf.panel:SetPos(0, 0)
		surf.panel:SetSize(ScrW(), ScrH())
	end
	p:Think()
	BOBBA.events.emit("pickerShown")
end

-- (keep: hidden while the Manage screen is over it)
function PK.hide(keep)
	PK.showing = keep and true or false
	if IsValid(PK.panel) then PK.panel:Remove() end
	PK.panel = nil
end

-- Enter checks in
hook.Add("Think", "bobba.picker.keys", function()
	if not IsValid(PK.panel) or (BOBBA.loading and BOBBA.loading.active) or PK.sheet then PK.enterWas = nil return end
	local down = input.IsKeyDown(KEY_ENTER)
	if down and PK.enterWas == false then PK.enter() end
	PK.enterWas = down
end)
