-- The hotel's loading screen (client): after GMod's own loading screen, until the first room is
-- ready to show complete (its floor and walls, its furni and everyone in it), like Habbo's loading
-- screen before the hotel. Drawn the way nitro-react's LoadingView is: $primary, the percentage and
-- a large progress bar at the bottom. Addons say what to wait for:
--
--   BOBBA.loading.add(id, function() return done, fraction end)   -- fraction 0..1, optional
--   BOBBA.loading.active   true while it's shown
--
-- It never waits longer than BOBBA.loading.MAX_WAIT seconds (then the room shows as it is).

BOBBA.loading = BOBBA.loading or { checks = {}, order = {} }
local LD = BOBBA.loading
local R = BOBBA.room
local U = BOBBA.ui

LD.MAX_WAIT = 60
LD.started = LD.started or SysTime()
if LD.active == nil then LD.active = true end

function LD.add(id, fn)
	if not LD.checks[id] then LD.order[#LD.order + 1] = id end
	LD.checks[id] = fn
end

-- how far it is: 0..1 (the room counts as one step, each check as one; the room is only there when
-- the server has said what all its furni are)
function LD.progress()
	-- (or the hotel view: a new player picking a room, someone waiting at a doorbell)
	local roomThere = (R and R.current and not (R.itemsComing and next(R.itemsComing))) or (BOBBA.view and BOBBA.view.mode == "hotelview")
		or (BOBBA.website and BOBBA.website.showing and BOBBA.website.data ~= nil)
	local total, done = 1, roomThere and 1 or 0
	local allDone = done == 1
	for _, id in ipairs(LD.order) do
		local ok, isDone, fraction = pcall(LD.checks[id])
		total = total + 1
		if ok and isDone then
			done = done + 1
		else
			allDone = false
			if ok and fraction then done = done + math.Clamp(fraction, 0, 0.99) end
		end
	end
	return done / total, allDone
end

local shown = 0 -- (the bar glides, like Nitro's transition: all 1s)

-- the phone's look: checking in (a sunset with the steps on the left, the hotel's skyline on the right)
local function lerpC(a, b, t) return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t) end
local function bands(x, y, w, h, stops)
	local n = 48
	for i = 0, n - 1 do
		local t = (i + 0.5) / n
		local c
		for j = 1, #stops - 1 do
			if t >= stops[j][1] and t <= stops[j + 1][1] then c = lerpC(stops[j][2], stops[j + 1][2], (t - stops[j][1]) / (stops[j + 1][1] - stops[j][1])) end
		end
		c = c or stops[#stops][2]
		surface.SetDrawColor(c.r, c.g, c.b, 255)
		local y0, y1 = math.floor(y + h * i / n), math.floor(y + h * (i + 1) / n)
		surface.DrawRect(math.floor(x), y0, math.ceil(w), y1 - y0)
	end
end
local function phonePaint(w, h)
	local DV = BOBBA.device
	local PD = DV and DV.newDraw
	local target, allDone = LD.progress()
	shown = shown + (target - shown) * math.min(1, RealFrameTime() * 3)
	local half = math.floor(w / 2)
	local hx = function(s) return DV.hex(s) end
	bands(0, 0, half, h, { { 0, hx("FF6B4A") }, { 1, hx("FFC24B") } })
	bands(half, 0, w - half, h, { { 0, hx("3B1A3F") }, { 0.7, hx("A8432A") }, { 1, hx("E8873A") } })
	if not PD then return end
	local s = math.min(w / 1280, h / 800)
	local d = PD({ panel = LD.panel, clicks = {}, zones = {}, scrolls = {} }, s)
	local PW, PH = w / s, h / s
	local cx = PW / 4
	-- the skyline
	local bx, base = PW * 0.75 - 320, PH
	d:circle(bx + 470, base - 190, 120, Color(255, 194, 75, 230))
	for _, b in ipairs({ { 90, 280, 90, "2A1630" }, { 190, 340, 120, "331A38" }, { 330, 240, 80, "2A1630" }, { 420, 180, 150, "331A38" } }) do
		d:round(6, bx + b[1], base - b[2], b[3], b[2] + 10, hx(b[4]))
	end
	for _, wnd in ipairs({ { 212, 310 }, { 246, 310 }, { 280, 270 }, { 110, 250 }, { 444, 150 } }) do d:round(2, bx + wnd[1], base - wnd[2], 15, 19, hx("FFD27A")) end
	-- (the spinner)
	local a0 = SysTime() * 4
	d:ring(PW * 0.75, PH * 0.37, 44, 10, Color(255, 246, 232, 46))
	for i = 0, 11 do
		local a = a0 + i / 12 * math.pi * 0.5
		d:circle(PW * 0.75 + math.cos(a) * 39, PH * 0.37 + math.sin(a) * 39, 5, hx("FFF6E8"))
	end
	-- the logo and the card
	local ly = PH * 0.2
	d:text("bobba", 76, cx + 8, ly + 8, Color(122, 46, 14, 115), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 800)
	d:text("bobba", 76, cx + 4, ly + 4, hx("7A2E0E"), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 800)
	d:text("bobba", 76, cx, ly, hx("FFF6E8"), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 800)
	local cw, ch = 420, 286
	local x, y = cx - cw / 2, ly + 130
	d:round(26, x + 4, y + 14, cw, ch, Color(122, 46, 14, 64))
	d:round(26, x, y, cw, ch, hx("FFF9F0"))
	local ink = hx("2A1206")
	local name = BOBBA.hotelName or (BOBBA.website and BOBBA.website.data and BOBBA.website.data.name) or "the hotel"
	d:text(d:fit(U.text("bobba.loading.checking", "Checking in to %hotel%", { hotel = name }), 18, cw - 52, 800), 18, x + 26, y + 24, ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	local pack = 0
	local nChecks = #LD.order
	if nChecks > 0 then
		local done = 0
		for _, id in ipairs(LD.order) do
			local ok, isDone, fraction = pcall(LD.checks[id])
			if ok and isDone then done = done + 1 elseif ok and fraction then done = done + math.Clamp(fraction, 0, 0.99) end
		end
		pack = done / nChecks
	else pack = 1 end
	local siteDone = BOBBA.website and BOBBA.website.showing and BOBBA.website.data ~= nil
	local steps = {
		{ U.text("bobba.loading.connected", "Connected"), 1 },
		{ U.text("bobba.loading.signedin", "Signed in"), 1 },
		{ U.text("bobba.loading.pack", "The hotel's pack"), pack },
		{ (BOBBA.website and BOBBA.website.wanted and (BOBBA.website.wanted() or BOBBA.website.showing)) and U.text("bobba.loading.website", "The hotel's page") or U.text("bobba.loading.room", "Your room"), (siteDone or (R and R.current)) and 1 or 0 },
	}
	local sy = y + 66
	local current = false
	for _, st in ipairs(steps) do
		local done = st[2] >= 1
		local now = not done and not current
		if now then current = true end
		local dot = done and hx("1E7A46") or now and hx("FF6B4A") or hx("F3D9BF")
		d:circle(x + 37, sy + 11, 11, dot)
		if done then d:glyph("M5 12l5 5 9-10", x + 31, sy + 5, 12, hx("FFF9F0"), 3.5) end
		local fg = (done or now) and ink or hx("A07052")
		d:text(st[1], 14, x + 58, sy + 11, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 600)
		if now and st[2] > 0 then d:text(math.floor(st[2] * 100) .. "%", 14, x + cw - 26, sy + 11, fg, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 600) end
		sy = sy + 36
	end
	d:pill(x + 26, sy + 6, cw - 52, 10, hx("F3D9BF"))
	d:pill(x + 26, sy + 6, math.max(10, (cw - 52) * shown), 10, hx("FF6B4A"))
	d:text(U.text("bobba.loading.kept", "The hotel's pack is downloaded once, then kept."), 13, x + 26, sy + 30, hx("6B3A1E"))
end

local function paint(w, h)
	if BOBBA.ui and BOBBA.ui.style and BOBBA.ui.style() ~= "habbo" and BOBBA.device and BOBBA.device.newDraw then return phonePaint(w, h) end
	local s = U and U.scale() or 1
	local C = U and U.C or { primary = Color(30, 114, 149), white = Color(255, 255, 255) }
	surface.SetDrawColor(C.primary.r, C.primary.g, C.primary.b, 255)
	surface.DrawRect(0, 0, w, h)
	local target = LD.progress()
	shown = shown + (target - shown) * math.min(1, RealFrameTime() * 3)
	-- the bottom middle: half the width of Bootstrap's container (1320 / 1140 / 960 / 720 / 540)
	local cw = w / s
	local container = cw >= 1400 and 1320 or cw >= 1200 and 1140 or cw >= 992 and 960 or cw >= 768 and 720 or cw >= 576 and 540 or cw
	local bw = (container - 24) / 2
	local bx = (cw - bw) / 2
	local by = h / s - 24 - 30
	local function R2(x, y, ww, hh, r, c) draw.RoundedBox(math.floor(r * s), math.floor(x * s), math.floor(y * s), math.floor(ww * s), math.floor(hh * s), c) end
	-- .nitro-progress-bar.large: 30 high, a white border, 2 inside, the bar in two blues
	R2(bx, by, bw, 30, 4, C.white)
	R2(bx + 1, by + 1, bw - 2, 28, 3, C.primary)
	local iw = math.floor((bw - 6) * shown)
	if iw > 0 then
		R2(bx + 3, by + 3, iw, 12, 2, Color(45, 171, 194))
		R2(bx + 3, by + 15, iw, 12, 2, Color(43, 145, 167))
	end
	-- the percentage above it (fs-4, white, text-shadow 0 4px 4px rgba(0,0,0,.25))
	local font = U and U.font(21.6) or "DermaLarge"
	local text = string.format("%d%%", math.floor(target * 100))
	draw.SimpleText(text, font, math.floor(cw / 2 * s), math.floor((by - 8) * s) + math.floor(2 * s), Color(0, 0, 0, 64), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
	draw.SimpleText(text, font, math.floor(cw / 2 * s), math.floor((by - 8) * s), C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
end
LD.paint = paint

-- a panel over everything while it loads (it also keeps clicks and typing from the room)
hook.Add("Think", "bobba.loading", function()
	if not LD.active then return end
	if not IsValid(LD.panel) then
		local p = vgui.Create("EditablePanel")
		p:SetPos(0, 0)
		p:SetSize(ScrW(), ScrH())
		p:MakePopup()
		p.Paint = function(self, w, h) paint(w, h) end
		LD.panel = p
	end
	-- (the game's window changed size)
	if LD.panel:GetWide() ~= ScrW() or LD.panel:GetTall() ~= ScrH() then LD.panel:SetSize(ScrW(), ScrH()) end
	-- (over everything: the hotel's page opens under it)
	LD.panel:MoveToFront()
	local _, allDone = LD.progress()
	if allDone or SysTime() - LD.started > LD.MAX_WAIT then
		LD.active = false
		if IsValid(LD.panel) then LD.panel:Remove() end
		BOBBA.events.emit("loadingDone")
	end
end)
