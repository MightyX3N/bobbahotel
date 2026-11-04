-- Events on the phone: the room events on now (hotel/roomevents.lua), going to one, and putting one
-- on in your own room. Also a widget: the next event.

local DV = BOBBA.device
local U = BOBBA.ui
local P = BOBBA.platform
local SO = BOBBA.social
local R = BOBBA.room
local V = BOBBA.view
local C, G = DV.C, DV.G
local alpha = DV.alpha
local T = function(k, f, v) return U.text(k, f, v) end

local function ask(force)
	if (force or not SO.eventsLoaded) and SysTime() - (SO.eventsAskedAt or 0) > (force and 10 or 5) then
		SO.eventsAskedAt = SysTime()
		P.send("events.list", {})
	end
end

local function left(e)
	local s = math.max(0, (e.ends or 0) - os.time())
	if s >= 3600 then return T("bobba.phone.events.hleft", "%h% h %m% min left", { h = math.floor(s / 3600), m = math.floor(s % 3600 / 60) }) end
	return T("bobba.phone.events.mleft", "%m% min left", { m = math.max(1, math.floor(s / 60)) })
end

local function go(e)
	DV.home() DV.show(false)
	local RW = BOBBA.roomWindows
	if RW and RW.visit then RW.visit({ id = e.room, owner = e.owner }) else P.send("room.enter", { id = e.room }) end
end

local COLORS = { C.purple, C.yellow, C.pink, C.green, C.blue, C.peach }

-- putting on an event in the room you're in (yours)
local function newView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local st = ctx.state
	d:rect(0, 0, W, H, C.paper)
	local top = ctx.top + ctx:header(T("bobba.phone.events.new", "Put on an event"))
	local x, w = 20, W - 40
	if ctx.kind == "tablet" then x, w = math.max(20, (W - 560) / 2), math.min(560, W - 40) end
	local me = LocalPlayer and IsValid(LocalPlayer()) and LocalPlayer():Nick()
	local room = V.mode == "room" and R.current and R.current.owner == me and R.current or nil
	if not room then
		for i, l in ipairs(d:wrap(T("bobba.phone.events.yourroom", "Go to one of your rooms first: an event is in the room you're in."), 15, w)) do
			d:text(l, 15, W / 2, top + 60 + (i - 1) * 21, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		end
		d:button(x, top + 130, w, 48, T("bobba.phone.rooms.mine", "Yours"), "primary", function() DV.openApp("rooms") end)
		return
	end
	local y = top + 10
	d:round(20, x, y, w, 60, C.navy)
	d:text(T("bobba.phone.events.in", "IN"), 11, x + 16, y + 14, C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	d:text(d:fit(room.name or "", 16, w - 32, 800), 16, x + 16, y + 30, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	y = y + 76
	d:text(T("bobba.phone.events.name", "What's on"), 13, x + 4, y + 8, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
	local ne = d:input("evname", x, y + 20, w, 46, { max = 60, bg = C.white, placeholder = T("bobba.phone.events.namehint", "Quiz night, a party, a build-off…") })
	y = y + 80
	d:text(T("bobba.phone.events.desc", "A few words"), 13, x + 4, y + 8, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
	local de = d:input("evdesc", x, y + 20, w, 70, { max = 200, bg = C.white, multiline = true, radius = 18 })
	y = y + 104
	d:text(T("bobba.phone.events.long", "How long"), 13, x + 4, y + 8, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
	local chips = {}
	for h = 1, SO.eventsMax or 3 do chips[#chips + 1] = { id = h, label = T("bobba.phone.events.hours", "%h% h", { h = h }) } end
	st.hours = st.hours or 1
	d:chips("evhours", x, y + 22, w, chips, st.hours, function(h) st.hours = h end, { off = C.line })
	y = y + 70
	local name = ne:GetValue() or ""
	local ok = #name:gsub("%s", "") >= 3
	local price = SO.eventsPrice or 0
	local label = price > 0 and T("bobba.phone.events.starts", "Start it · %price%", { price = DV.priceText({ credits = price }) }) or T("bobba.phone.events.start", "Start it")
	d:button(x, y, w, 50, label, ok and "primary" or "light", function()
		P.send("events.create", { room = room.id, name = name, description = de:GetValue() or "", hours = st.hours })
		ctx:pop()
		timer.Simple(0.5, function() ask(true) end)
	end, not ok)
end

local function eventsView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	ask()
	if SysTime() - (SO.eventsAskedAt or 0) > 30 then ask(true) end
	d:rect(0, 0, W, H, C.paper)
	local top = ctx.top + ctx:header(T("bobba.phone.app.events", "Events"), { big = true, right = {
		{ glyph = G.plus, fn = function() ctx:push(newView, {}) end },
	} })
	local x, w = 16, W - 32
	local tablet = ctx.kind == "tablet"
	if tablet then x, w = 40, W - 80 end
	local list = SO.events or {}
	if #list == 0 then
		local cx = W / 2
		d:round(30, cx - 40, top + 50, 80, 80, C.purple)
		d:glyph(G.events, cx - 22, top + 68, 44, C.navy, 2)
		d:text(SO.eventsLoaded and T("bobba.phone.events.none", "Nothing on right now") or T("bobba.phone.loading", "Loading…"), 17, cx, top + 160, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
		for i, l in ipairs(d:wrap(T("bobba.phone.events.nonesub", "Put one on in your room: everyone here gets told it started."), 14, w - 60)) do
			d:text(l, 14, cx, top + 190 + (i - 1) * 20, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		end
		d:button(x + 20, top + 250, w - 40, 48, T("bobba.phone.events.new", "Put on an event"), "primary", function() ctx:push(newView, {}) end)
		return
	end
	local cols = tablet and 2 or 1
	local cw = (w - (cols - 1) * 16) / cols
	local ch = 150
	local y = top + 6
	local off = d:scroll("events", 0, y, W, H - y, math.ceil(#list / cols) * (ch + 14) + 30)
	d:clip(0, y, W, H - y, function()
		for i, e in ipairs(list) do
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			local ex, ey = x + col * (cw + 16), y + row * (ch + 14) - off
			if ey + ch > y and ey < H then
				local bg = COLORS[(e.room or i) % #COLORS + 1]
				d:round(24, ex, ey, cw, ch, bg)
				d:clip(ex, ey, cw, ch, function() d:circle(ex + cw - 30, ey + 10, 70, alpha(C.white, 0.25)) end)
				d:text(left(e):upper(), 11, ex + 18, ey + 16, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
				d:text(d:fit(e.name or "", 20, cw - 36, 800), 20, ex + 18, ey + 34, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
				d:text(d:fit((e.roomName or "") .. " · " .. (e.owner or ""), 13, cw - 36, 600), 13, ex + 18, ey + 62, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 600)
				if (e.description or "") ~= "" then d:text(d:fit(e.description, 13, cw - 36), 13, ex + 18, ey + 82, alpha(C.navy, 0.8)) end
				d:button(ex + 18, ey + ch - 50, 110, 36, T("bobba.phone.events.go", "Go"), "primary", function() go(e) end)
				d:text(T("bobba.phone.widget.herecount", "%count% here", { count = e.users or 0 }), 13, ex + 140, ey + ch - 32, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
				if e.mine then
					d.bgUnder = bg
					d:button(ex + cw - 110, ey + ch - 50, 92, 36, T("bobba.phone.events.end", "End it"), "outline", function()
						P.send("events.end", { room = e.room })
						timer.Simple(0.5, function() ask(true) end)
					end)
					d.bgUnder = nil
				end
			end
		end
	end)
end

DV.app({ id = "events", name = T("bobba.phone.app.events", "Events"), color = C.purple, glyph = G.events, order = 17,
	phone = eventsView, tablet = eventsView })

-- the widget: the event on now
DV.widget({ id = "events", name = T("bobba.phone.app.events", "Events"), size = "small",
	draw = function(d, w, h)
		ask()
		local e = SO.events and SO.events[1]
		d:text(T("bobba.phone.widget.tonight", "ON NOW"), 12, 16, 16, C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
		if not e then
			d:text(T("bobba.phone.events.quiet", "Nothing on"), 16, 16, 36, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
			return
		end
		for i, l in ipairs(d:wrap(e.name or "", 16, w - 28, 800)) do
			if i <= 2 then d:text(l, 16, 16, 36 + (i - 1) * 21, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800) end
		end
		d:text(d:fit(e.roomName or "", 12, w - 28), 12, 16, h - 46, C.mist)
		d:text(left(e), 12, 16, h - 28, C.mist)
	end,
	click = function() DV.openApp("events") end })
