-- Messages (friends and their conversations) and Calls (voice: a dummy until voice chat comes) on
-- the phone. The data: client/social.lua.

local DV = BOBBA.device
local U = BOBBA.ui
local P = BOBBA.platform
local SO = BOBBA.social
local HUD = BOBBA.hud
local C, G = DV.C, DV.G
local alpha = DV.alpha
local hex = DV.hex
local T = function(k, f, v) return U.text(k, f, v) end

local function ask()
	if not SO.loaded and SysTime() - (SO.askedAt or 0) > 5 then SO.askedAt = SysTime() P.send("friends.get", {}) end
end

local function status(f)
	if not f.online then return T("bobba.phone.friends.offline", "Offline") end
	if f.room then return T("bobba.phone.friends.in", "In %room%", { room = f.roomName or "" }) end
	return T("bobba.phone.friends.online2", "Online")
end

local function clock(t)
	if not t then return "" end
	if os.time() - t < 86400 and os.date("%d", t) == os.date("%d") then return os.date("%H:%M", t) end
	return os.date("%d %b", t)
end

-- a dot on the face: online
local function onlineDot(d, x, y, size, on, bg)
	if not on then return end
	d:circle(x + size - 4, y + size - 4, 7, bg or C.paper)
	d:circle(x + size - 4, y + size - 4, 4.5, C.green)
end

-- --- a conversation ---------------------------------------------------------------------------------
local threadView
local profileView

local function bubbles(d, msgs, x, y, w, h, st)
	-- (each bubble's lines; the newest at the bottom, scrolled there as they come)
	local rows, total = {}, 0
	local maxW = w * 0.74
	for i, m in ipairs(msgs) do
		local lines = d:wrap(m.text or "", 15, maxW - 28)
		local bw = 0
		for _, l in ipairs(lines) do bw = math.max(bw, d:textWidth(l, 15)) end
		local gap = (i > 1 and msgs[i - 1].mine == m.mine) and 4 or 12
		rows[i] = { lines = lines, w = bw + 28, h = #lines * 20 + 18, gap = gap }
		total = total + rows[i].h + gap
	end
	local surf = d.surf
	local sc = surf.scrolls.thread
	local atBottom = not sc or sc.offset >= (sc.max or 0) - 4 or st.count ~= #msgs
	st.count = #msgs
	local off = d:scroll("thread", x, y, w, h, total + 16)
	if atBottom then surf.scrolls.thread.offset = surf.scrolls.thread.max off = surf.scrolls.thread.max end
	d:clip(x, y, w, h, function()
		local yy = y + 8 - off + math.max(0, h - total - 16)
		for i, m in ipairs(msgs) do
			local r = rows[i]
			yy = yy + r.gap
			if yy + r.h > y and yy < y + h then
				local bx = m.mine and (x + w - r.w) or x
				d:round(18, bx, yy, r.w, r.h, m.mine and C.navy or C.white)
				for j, l in ipairs(r.lines) do d:text(l, 15, bx + 14, yy + 9 + (j - 1) * 20, m.mine and C.paper or C.navy) end
			end
			yy = yy + r.h
			-- (the time under the last of a run)
			if not msgs[i + 1] or msgs[i + 1].mine ~= m.mine then
				if yy + 14 > y and yy < y + h then d:text(clock(m.at), 11, m.mine and (x + w - 4) or (x + 4), yy + 3, C.ink2, m.mine and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 600) end
				yy = yy + 16
			end
		end
	end)
end

threadView = function(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local key = ctx.state.key
	local f = SO.friend(key) or { key = key, name = ctx.state.name or "?" }
	if SO.open.thread ~= key then SO.openThread(key) end
	d:rect(0, 0, W, H, Color(236, 239, 246))
	-- the header: back, their face, name and where they are
	local y = ctx.top
	local hov = d:click(6, y, 44, 52, function() SO.closeThread() ctx:pop() end)
	d:glyph("M15 5l-7 7 7 7", 12, y + 14, 24, alpha(C.navy, hov and 0.6 or 1), 2.4)
	d:click(48, y, W - 150, 52, function() ctx:push(profileView, { key = key }) end)
	DV.face(d, f.figure, f.gender, f.name, 48, y + 6, 40)
	onlineDot(d, 48, y + 6, 40, f.online, Color(236, 239, 246))
	d:textFit(f.name or "", 16, W - 200, 98, y + 16, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	d:textFit(status(f), 12, W - 200, 98, y + 36, C.ink2)
	-- (going to their room; calling them)
	if f.room then
		local hv = d:click(W - 104, y + 6, 40, 40, function() DV.home() DV.show(false) P.send("friends.follow", { key = key }) end)
		d:circle(W - 84, y + 26, 20, hv and C.mist or C.white)
		d:glyph(G.rooms, W - 95, y + 15, 22, C.navy, 2.2)
	end
	local hc = d:click(W - 56, y + 6, 40, 40, function() DV.openApp("calls") DV.startCall(f) end)
	d:circle(W - 36, y + 26, 20, hc and C.mist or C.white)
	d:glyph(G.calls, W - 47, y + 15, 22, C.navy, 2.2)
	y = y + 58
	d:rect(0, y - 1, W, 1, C.line)
	local inputH = 50
	local th = SO.threads[key]
	local msgs = th and th.messages or {}
	if not th or not th.loaded then
		d:text(T("bobba.phone.loading", "Loading…"), 14, W / 2, y + 60, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
	elseif #msgs == 0 then
		d:text(T("bobba.phone.messages.first", "Say hi to %name%!", { name = f.name or "" }), 14, W / 2, y + 60, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
	end
	local side = ctx.kind == "tablet" and math.max(16, (W - 760) / 2) or 14
	bubbles(d, msgs, side, y, W - side * 2, H - y - inputH - 34, ctx.state)
	-- the box to write in
	local iy = H - inputH - 26
	local send
	local e = d:input("msg", side, iy, W - side * 2 - 56, inputH, { placeholder = T("bobba.phone.messages.write", "Message"), max = 500, bg = C.white,
		onEnter = function(t) send(t) end })
	send = function(t)
		t = t or e:GetValue() or ""
		if t:gsub("%s", "") == "" then return end
		P.send("messenger.send", { to = key, text = t })
		e:SetText("")
		timer.Simple(0, function() if IsValid(e) then e:RequestFocus() end end)
	end
	local hs = d:click(W - side - 50, iy, 50, inputH, function() send() end)
	d:circle(W - side - 25, iy + inputH / 2, 25, hs and C.navy3 or C.navy)
	d:glyph("M5 12h14M13 6l6 6-6 6", W - side - 36, iy + inputH / 2 - 11, 22, C.paper, 2.4)
end

profileView = function(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local key = ctx.state.key
	local f = SO.friend(key)
	d:rect(0, 0, W, H, C.paper)
	local top = ctx.top + ctx:header("")
	if not f then
		d:text(T("bobba.phone.friends.gone", "Not your friend any more."), 14, W / 2, top + 80, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		return
	end
	local x, w = 20, W - 40
	if ctx.kind == "tablet" then x, w = (W - 480) / 2, 480 end
	d:round(30, x, top + 10, w, 240, C.sky)
	d:clip(x, top + 10, w, 240, function() d:avatar(f.figure, f.gender, 2, x + w / 2, top + 10 + 240 - 30 - 230, 2) end)
	local y = top + 270
	d:text(f.name or "", 26, x, y, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	d:text(status(f), 14, x, y + 36, f.online and C.green or C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
	y = y + 76
	d:button(x, y, w, 50, T("bobba.phone.friends.message", "Message"), "primary", function() ctx:push(threadView, { key = key }) end)
	y = y + 60
	if f.room then
		d:button(x, y, w, 50, T("bobba.phone.friends.goto", "Go to %name%", { name = f.name }), "light", function() DV.home() DV.show(false) P.send("friends.follow", { key = key }) end)
		y = y + 60
	end
	d:button(x, y, w, 50, T("bobba.phone.calls.call", "Call"), "light", function() DV.openApp("calls") DV.startCall(f) end)
	y = y + 60
	d.bgUnder = C.paper
	d:button(x, y, w, 46, T("bobba.phone.friends.remove", "Remove friend"), "outline", function()
		DV.ask({ title = T("bobba.phone.friends.removeq", "Remove %name%?", { name = f.name }), text = T("bobba.phone.friends.removetext", "You won't see each other in your friends any more."),
			ok = T("bobba.phone.friends.remove", "Remove friend"), danger = true, fn = function() P.send("friends.remove", { key = key }) ctx:pop() end })
	end)
	d.bgUnder = nil
end

-- making a friend: their name
local function addView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	d:rect(0, 0, W, H, C.paper)
	local top = ctx.top + ctx:header(T("bobba.phone.friends.add", "Add a friend"))
	local x, w = 20, W - 40
	if ctx.kind == "tablet" then x, w = (W - 480) / 2, 480 end
	local st = ctx.state
	local go
	local e = d:input("friendname", x, top + 16, w, 50, { placeholder = T("bobba.phone.friends.name", "Their name"), max = 40, bg = C.white, onEnter = function() go() end })
	go = function()
		local name = (e:GetValue() or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" then return end
		st.sentTo, st.at = name, SysTime()
		P.send("friends.request", { name = name })
		e:SetText("")
	end
	d:button(x, top + 80, w, 50, T("bobba.phone.friends.send", "Send a friend request"), "primary", go)
	local y = top + 150
	if st.sentTo then
		local failed = SO.lastError and SO.lastError.at > st.at
		local sent = false
		for _, s in ipairs(SO.sent) do if s.name:lower() == st.sentTo:lower() then sent = true end end
		local made = false
		for _, f in ipairs(SO.friends) do if f.name:lower() == st.sentTo:lower() then made = true end end
		local txt = failed and SO.lastError.text or made and T("bobba.phone.friends.made", "You're friends with %name% now.", { name = st.sentTo })
			or sent and T("bobba.phone.friends.asked", "Asked %name%. They'll see it next time they're here.", { name = st.sentTo }) or T("bobba.phone.loading", "Loading…")
		for i, l in ipairs(d:wrap(txt, 14, w)) do d:text(l, 14, x, y + (i - 1) * 20, failed and C.red or C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 600) end
		y = y + 60
	end
	if #SO.sent > 0 then
		d:text(T("bobba.phone.friends.waiting", "WAITING FOR AN ANSWER"), 12, x + 4, y, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		y = y + 22
		local rows = {}
		for _, s in ipairs(SO.sent) do rows[#rows + 1] = { title = s.name } end
		ctx:rows(x, y, w, rows, { rowH = 48 })
	end
end

local function messagesView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local st = ctx.state
	ask()
	SO.closeThread()
	d:rect(0, 0, W, H, C.paper)
	local top = ctx.top + ctx:header(T("bobba.phone.app.messages", "Messages"), { big = true, right = {
		{ glyph = "M9 4.5a3.5 3.5 0 1 1 0 7a3.5 3.5 0 1 1 0-7M2.5 20a6.5 6.5 0 0 1 13 0M19 8v6M16 11h6", fn = function() ctx:push(addView, {}) end },
	} })
	local x, w = 16, W - 32
	if ctx.kind == "tablet" then x, w = math.max(16, (W - 760) / 2), math.min(760, W - 32) end
	st.tab = st.tab or "chats"
	local nReq = #SO.requests
	local tabs = { { id = "chats", label = T("bobba.phone.messages.chats", "Chats") }, { id = "friends", label = T("bobba.phone.messages.friends", "Friends") },
		{ id = "requests", label = nReq > 0 and T("bobba.phone.messages.requestsn", "Requests (%n%)", { n = nReq }) or T("bobba.phone.messages.requests", "Requests") } }
	d:chips("msgtabs", x, top + 4, w, tabs, st.tab, function(id) st.tab = id end)
	local y = top + 4 + 32 + 12
	local list = {}
	if st.tab == "chats" then
		for _, f in ipairs(SO.friends) do list[#list + 1] = f end
		table.sort(list, function(a, b)
			local ta, tb = a.last and a.last.at or 0, b.last and b.last.at or 0
			if ta ~= tb then return ta > tb end
			if a.online ~= b.online then return a.online end
			return (a.name or "") < (b.name or "")
		end)
	elseif st.tab == "friends" then
		for _, f in ipairs(SO.friends) do list[#list + 1] = f end
		table.sort(list, function(a, b) if a.online ~= b.online then return a.online end return (a.name or ""):lower() < (b.name or ""):lower() end)
	else
		list = SO.requests
	end
	if #list == 0 then
		local msg = st.tab == "requests" and T("bobba.phone.messages.noreq", "No one's asked yet.") or T("bobba.phone.messages.nofriends", "No friends yet. Add someone by their name with the button at the top.")
		for i, l in ipairs(d:wrap(msg, 14, w - 40)) do d:text(l, 14, W / 2, y + 50 + (i - 1) * 20, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600) end
		return
	end
	local rowH = 74
	local off = d:scroll("msglist", 0, y, W, H - y, #list * rowH + 30)
	d:clip(0, y, W, H - y, function()
		for i, f in ipairs(list) do
			local ry = y + (i - 1) * rowH - off
			if ry + rowH > y and ry < H then
				if st.tab == "requests" then
					d:round(20, x, ry, w, rowH - 8, C.white)
					DV.face(d, f.figure, f.gender, f.name, x + 10, ry + 10, 46)
					d:textFit(f.name or "", 15, w - 260, x + 68, ry + 20, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
					d:text(T("bobba.phone.friends.wants", "wants to be your friend"), 12, x + 68, ry + 40, C.ink2)
					d:button(x + w - 186, ry + 15, 88, 36, T("bobba.phone.friends.accept", "Accept"), "primary", function() P.send("friends.accept", { key = f.key }) end)
					d.bgUnder = C.white
					d:button(x + w - 92, ry + 15, 82, 36, T("bobba.phone.friends.decline", "Decline"), "outline", function() P.send("friends.decline", { key = f.key }) end)
					d.bgUnder = nil
				else
					local hov = d:click(x, ry, w, rowH - 8, function()
						if st.tab == "chats" then ctx:push(threadView, { key = f.key }) else ctx:push(profileView, { key = f.key }) end
					end)
					if hov then d:round(20, x, ry, w, rowH - 8, C.line) end
					DV.face(d, f.figure, f.gender, f.name, x + 8, ry + 8, 50)
					onlineDot(d, x + 8, ry + 8, 50, f.online, hov and C.line or C.paper)
					local unread = (f.unread or 0) > 0
					d:textFit(f.name or "", 16, w - 150, x + 72, ry + 16, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, unread and 800 or 700)
					local sub
					if st.tab == "chats" and f.last then sub = (f.last.mine and (T("bobba.phone.messages.you", "You") .. ": ") or "") .. f.last.text
					else sub = status(f) end
					d:textFit(sub, 13, w - 130, x + 72, ry + 38, unread and C.navy or C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, unread and 700 or 500)
					if st.tab == "chats" and f.last then d:text(clock(f.last.at), 12, x + w - 12, ry + 18, C.ink2, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 600) end
					if unread then
						local t = tostring(f.unread)
						local bw = math.max(22, d:textWidth(t, 12, 800) + 12)
						d:pill(x + w - 12 - bw, ry + 38, bw, 22, C.red)
						d:text(t, 12, x + w - 12 - bw / 2, ry + 49, C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
					end
				end
			end
		end
	end)
end

DV.app({ id = "messages", name = T("bobba.phone.app.messages", "Messages"), color = C.blue, glyph = G.messages, dock = true, order = 2, removable = false,
	badge = function() return SO.unreadMessages() + #SO.requests end,
	phone = messagesView, tablet = messagesView })

-- a conversation opened from elsewhere (a notification)
function DV.openThread(key)
	DV.openApp("messages")
	local st = DV.stack
	if st.screens then st.screens[#st.screens + 1] = { view = threadView, state = { key = key }, at = SysTime() } end
end

-- (the friends: the Messages app in the phone's look)
local friendsWindow = HUD.actions.friends
HUD.actions.friends = function()
	if DV.active() then DV.openApp("messages") return end
	if friendsWindow then friendsWindow() end
end

-- --- Calls: a dummy until voice chat comes -----------------------------------------------------------
DV.call = DV.call or nil
function DV.startCall(f)
	DV.call = { friend = f, at = SysTime(), muted = false }
end

local GREEN, GREEN2, GREEN3 = hex("123B33"), hex("17493F"), hex("1C574B")
local function callScreen(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local call = DV.call
	local f = call.friend
	local t = SysTime() - call.at
	d:rect(0, 0, W, H, GREEN)
	d:circle(W / 2, H * 0.42, 260, GREEN2)
	d:circle(W / 2, H * 0.42, 180, GREEN3)
	-- (rings going out while it rings)
	local ringing = t < 5
	if ringing then
		for i = 0, 2 do
			local p = ((t + i * 0.6) % 1.8) / 1.8
			d:ring(W / 2, H * 0.27 + 75, 80 + p * 70, 3, alpha(C.green, 1 - p))
		end
	end
	local cy = H * 0.27
	DV.face(d, f.figure, f.gender, f.name, W / 2 - 75, cy, 150, C.sky)
	d:text(f.name or "", 30, W / 2, cy + 180, C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 800)
	local line = ringing and (T("bobba.phone.calls.calling", "Calling") .. string.rep(".", math.floor(t * 2) % 4))
		or T("bobba.phone.calls.notyet", "Voice chat isn't on in this hotel yet")
	d:text(line, 15, W / 2, cy + 222, hex("CDEBE2"), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 600)
	if not ringing then
		for i, l in ipairs(d:wrap(T("bobba.phone.calls.soon", "When it comes, calls ring here. Send a message for now."), 13, W - 80)) do
			d:text(l, 13, W / 2, cy + 248 + (i - 1) * 18, hex("CDEBE2"), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end
	end
	-- the buttons
	local btns = {
		{ T("bobba.phone.calls.mute", "Mute"), "M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3zM5 11a7 7 0 0 0 14 0M12 18v3", function() call.muted = not call.muted end, call.muted },
		{ T("bobba.phone.calls.ptt", "Push to talk"), "M8 13V5a2 2 0 0 1 4 0v6M12 11V4a2 2 0 0 1 4 0v7M16 11a2 2 0 0 1 4 0v3a7 7 0 0 1-7 7h-1a7 7 0 0 1-6-3l-2-4a2 2 0 0 1 3-2l1 1", function() end, false },
		{ T("bobba.phone.calls.add", "Add people"), "M9 4.5a3.5 3.5 0 1 1 0 7a3.5 3.5 0 1 1 0-7M2.5 20a6.5 6.5 0 0 1 13 0M19 8v6M16 11h6", function() end, false },
		{ T("bobba.phone.calls.goto", "Go to %name%", { name = f.name }), G.chevron, function() DV.call = nil DV.home() DV.show(false) P.send("friends.follow", { key = f.key }) end, false, not f.room },
		{ T("bobba.phone.calls.end", "End"), "M3 14a14 14 0 0 1 18 0l-2 3-4-1v-3a9 9 0 0 0-6 0v3l-4 1z", function() DV.call = nil end, false, false, true },
		{ T("bobba.phone.app.messages", "Messages"), G.messages, function() DV.call = nil DV.openThread(f.key) end, false },
	}
	local cols = 3
	local bw = W / cols
	local by = H - 70 - 2 * 104
	for i, b in ipairs(btns) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local cx, y = col * bw + bw / 2, by + row * 104
		local disabled = b[5]
		local hov = (not disabled) and d:click(cx - 36, y, 72, 72, b[3]) or false
		local bg = b[6] and C.red or (b[4] and C.paper or alpha(C.paper, hov and 0.26 or 0.16))
		d:circle(cx, y + 36, 36, disabled and alpha(C.paper, 0.06) or bg)
		d:glyph(b[2], cx - 14, y + 22, 28, b[4] and C.navy or (disabled and alpha(C.paper, 0.4) or C.white), 2)
		d:textFit(b[1], 12, bw - 8, cx, y + 84, disabled and alpha(C.paper, 0.4) or C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
	end
end

local function callsView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	ask()
	if DV.call then return callScreen(ctx) end
	d:rect(0, 0, W, H, C.paper)
	local top = ctx.top + ctx:header(T("bobba.phone.app.calls", "Calls"), { big = true })
	local x, w = 16, W - 32
	if ctx.kind == "tablet" then x, w = math.max(16, (W - 760) / 2), math.min(760, W - 32) end
	d:round(20, x, top + 4, w, 64, hex("CDEBE2"))
	for i, l in ipairs(d:wrap(T("bobba.phone.calls.note", "Voice calls are coming. You can already ring your friends: they'll see it when voice chat is on."), 13, w - 32)) do
		if i <= 2 then d:text(l, 13, x + 16, top + 16 + (i - 1) * 18, hex("123B33"), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 600) end
	end
	local y = top + 84
	d:text(T("bobba.phone.calls.contacts", "FRIENDS"), 12, x + 4, y, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	y = y + 22
	local list = {}
	for _, f in ipairs(SO.friends) do list[#list + 1] = f end
	table.sort(list, function(a, b) if a.online ~= b.online then return a.online end return (a.name or ""):lower() < (b.name or ""):lower() end)
	if #list == 0 then
		d:text(T("bobba.phone.messages.nofriends2", "No friends yet: add them in Messages."), 14, W / 2, y + 40, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		return
	end
	local rowH = 66
	local off = d:scroll("calls", 0, y, W, H - y, #list * rowH + 30)
	d:clip(0, y, W, H - y, function()
		for i, f in ipairs(list) do
			local ry = y + (i - 1) * rowH - off
			if ry + rowH > y and ry < H then
				DV.face(d, f.figure, f.gender, f.name, x + 4, ry + 8, 46)
				onlineDot(d, x + 4, ry + 8, 46, f.online)
				d:textFit(f.name or "", 16, w - 150, x + 64, ry + 14, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
				d:textFit(status(f), 12, w - 150, x + 64, ry + 36, C.ink2)
				local hv = d:click(x + w - 50, ry + 10, 44, 44, function() DV.startCall(f) end)
				d:circle(x + w - 28, ry + 32, 22, hv and C.green or hex("CDEBE2"))
				d:glyph(G.calls, x + w - 39, ry + 21, 22, hex("123B33"), 2.2)
				d:rect(x + 64, ry + rowH - 1, w - 64, 1, C.line)
			end
		end
	end)
end

DV.app({ id = "calls", name = T("bobba.phone.app.calls", "Calls"), color = C.green, glyph = G.calls, dock = true, order = 1, removable = false,
	bg = function() return DV.call and GREEN or C.paper end,
	phone = callsView, onClose = function() DV.call = nil end })

