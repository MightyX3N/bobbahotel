-- Groups on the phone (Discord-like): your groups down the side, the open one's banner, its room,
-- its text channels (with unread counts) and voice channels; a channel's messages; finding, making
-- and running a group. The data: client/social.lua; the server: hotel/groups.lua.

local DV = BOBBA.device
local U = BOBBA.ui
local P = BOBBA.platform
local SO = BOBBA.social
local R = BOBBA.room
local C, G = DV.C, DV.G
local alpha = DV.alpha
local hex = DV.hex
local T = function(k, f, v) return U.text(k, f, v) end

local COLORS = { "B98CFF", "FFD166", "FF9F5A", "3FC6A0", "6E8BFF", "F26B8A", "9DB4FF", "E8C26A" }
local function colorOf(g) return hex(g and g.color or "B98CFF") end

local function askList()
	if not SO.groupsLoaded and SysTime() - (SO.groupsAskedAt or 0) > 5 then SO.groupsAskedAt = SysTime() P.send("groups.mine", {}) end
end
local function info(id, refresh)
	local i = SO.groupInfo[id]
	if (not i or refresh) and SysTime() - (SO["infoAt" .. id] or 0) > 3 then
		SO["infoAt" .. id] = SysTime()
		P.send("groups.get", { id = id })
	end
	return i
end

local function clock(t) return t and os.date("%H:%M", t) or "" end

-- --- a channel's messages ---------------------------------------------------------------------------
local function channelBody(ctx, d, group, channel, x, y, w, h, st)
	local ch = SO.channels[channel.id]
	if SO.open.channel ~= channel.id then SO.openChannel(channel.id) end
	channel.unread = 0
	local msgs = ch and ch.messages or {}
	local inputH = 48
	local listH = h - inputH - 16
	-- each message: a face, the name and time, the lines (a run from one person shares the face)
	local rows, total = {}, 0
	for i, m in ipairs(msgs) do
		local lines = d:wrap(m.text or "", 14, w - 64)
		local cont = i > 1 and msgs[i - 1].key == m.key and (m.at or 0) - (msgs[i - 1].at or 0) < 300
		rows[i] = { lines = lines, cont = cont, h = (cont and 0 or 22) + #lines * 19 + (cont and 4 or 10) }
		total = total + rows[i].h
	end
	local surf = d.surf
	local sc = surf.scrolls.channel
	local atBottom = not sc or sc.offset >= (sc.max or 0) - 4 or st.count ~= #msgs
	st.count = #msgs
	local off = d:scroll("channel", x, y, w, listH, total + 10)
	if atBottom then surf.scrolls.channel.offset = surf.scrolls.channel.max off = surf.scrolls.channel.max end
	d:clip(x, y, w, listH, function()
		local yy = y + 6 - off + math.max(0, listH - total - 10)
		if not ch or not ch.loaded then d:text(T("bobba.phone.loading", "Loading…"), 14, x + w / 2, y + 40, C.mist, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600) end
		if ch and ch.loaded and #msgs == 0 then
			d:text(T("bobba.phone.groups.first", "This is the start of #%name%.", { name = channel.name }), 14, x + w / 2, y + listH - 30, C.mist, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		end
		for i, m in ipairs(msgs) do
			local r = rows[i]
			if yy + r.h > y and yy < y + listH then
				local ty = yy + (r.cont and 0 or 4)
				if not r.cont then
					DV.face(d, m.figure, m.gender, m.name, x, yy + 4, 38)
					d:text(m.name or "", 14, x + 50, yy + 4, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
					d:text(clock(m.at), 11, x + 54 + d:textWidth(m.name or "", 14, 800), yy + 7, C.slate, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 600)
					ty = yy + 24
				end
				for j, l in ipairs(r.lines) do d:text(l, 14, x + 50, ty + (j - 1) * 19, C.line) end
			end
			yy = yy + r.h
		end
	end)
	local iy = y + h - inputH
	local send
	local e = d:input("chmsg", x, iy, w - 54, inputH, { placeholder = T("bobba.phone.groups.write", "Message #%name%", { name = channel.name }), max = 500, bg = C.navy3, fg = C.paper,
		onEnter = function(t) send(t) end })
	send = function(t)
		t = t or e:GetValue() or ""
		if t:gsub("%s", "") == "" then return end
		P.send("groups.send", { channel = channel.id, text = t })
		e:SetText("")
		timer.Simple(0, function() if IsValid(e) then e:RequestFocus() end end)
	end
	local hs = d:click(x + w - 48, iy, 48, inputH, function() send() end)
	d:circle(x + w - 24, iy + inputH / 2, 24, hs and C.paper or C.mist)
	d:glyph("M5 12h14M13 6l6 6-6 6", x + w - 35, iy + inputH / 2 - 11, 22, C.navy, 2.4)
end

local function channelView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local g = info(ctx.state.group)
	local channel
	for _, c in ipairs(g and g.channels or {}) do if c.id == ctx.state.channel then channel = c end end
	d:rect(0, 0, W, H, C.navy2)
	local top = ctx.top + ctx:header("#" .. (channel and channel.name or ""), { dark = true, back = function() SO.closeChannel() ctx:pop() end })
	if not channel then return end
	channelBody(ctx, d, g, channel, 16, top + 4, W - 32, H - top - 34, ctx.state)
end

-- --- a group's settings: its name, colour, room, open; channels; members ---------------------------------
local function settingsView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local id = ctx.state.group
	local g = info(id)
	local st = ctx.state
	d:rect(0, 0, W, H, Color(236, 239, 246))
	local top = ctx.top + ctx:header(g and g.name or "")
	if not g then return end
	if not st.membersAsked then st.membersAsked = true P.send("groups.members", { id = id }) end
	local admin = (g.rank or 0) >= 1
	local x, w = 16, W - 32
	if ctx.kind == "tablet" then x, w = math.max(16, (W - 620) / 2), math.min(620, W - 32) end
	local off = d:scroll("gset", 0, top, W, H - top, st.contentH or H)
	d:clip(0, top, W, H - top, function()
		local y = top + 8 - off
		local function section(t) d:text(t, 12, x + 4, y + 8, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800) y = y + 22 end
		if admin then
			section(T("bobba.phone.groups.about", "ABOUT"))
			local ne = d:input("gname", x, y, w, 46, { value = g.name, max = 40, bg = C.white, placeholder = T("bobba.phone.groups.name", "Name") })
			y = y + 54
			local de = d:input("gdesc", x, y, w, 70, { value = g.description, max = 255, bg = C.white, multiline = true, radius = 18, placeholder = T("bobba.phone.groups.desc", "What it's about") })
			y = y + 78
			-- the colour
			st.color = st.color or g.color
			for i, hx in ipairs(COLORS) do
				local cx = x + 18 + (i - 1) * 40
				d:click(cx - 16, y, 32, 32, function() st.color = hx end)
				if st.color == hx then d:circle(cx, y + 16, 17, C.navy) d:circle(cx, y + 16, 14.5, C.white) end
				d:circle(cx, y + 16, 12, hex(hx))
			end
			y = y + 44
			local rows = {
				{ title = T("bobba.phone.groups.open", "Anyone can join"), sub = T("bobba.phone.groups.opensub", "Off: people ask, an admin lets them in"), right = "toggle", on = g.open,
					click = function() P.send("groups.edit", { id = id, open = not g.open }) g.open = not g.open end },
			}
			local mine = R.current and R.current.owner == (LocalPlayer and IsValid(LocalPlayer()) and LocalPlayer():Nick())
			if mine and R.current.id ~= g.room then
				rows[#rows + 1] = { title = T("bobba.phone.groups.useroom", "Make %room% its room", { room = R.current.name or "" }), right = "chevron",
					click = function() P.send("groups.edit", { id = id, room = R.current.id }) end }
			end
			y = ctx:rows(x, y, w, rows) + 10
			d:button(x, y, w, 46, T("bobba.phone.groups.save", "Save"), "primary", function()
				P.send("groups.edit", { id = id, name = ne:GetValue(), description = de:GetValue(), color = st.color })
			end)
			y = y + 60
			-- channels
			section(T("bobba.phone.groups.channels", "CHANNELS"))
			local crow = {}
			for _, c in ipairs(g.channels or {}) do
				crow[#crow + 1] = { title = (c.kind == "voice" and "" or "#") .. c.name, sub = c.kind == "voice" and T("bobba.phone.groups.voice", "Voice") or nil, right = T("bobba.phone.groups.remove", "Remove"),
					click = function() DV.ask({ title = T("bobba.phone.groups.removech", "Remove %name%?", { name = c.name }), text = T("bobba.phone.groups.removechtext", "Its messages go too."), danger = true,
						ok = T("bobba.phone.groups.remove", "Remove"), fn = function() P.send("groups.channel.remove", { channel = c.id }) end }) end }
			end
			if #crow > 0 then y = ctx:rows(x, y, w, crow, { rowH = 48 }) + 10 end
			local ce = d:input("newch", x, y, w - 200, 44, { max = 30, bg = C.white, placeholder = T("bobba.phone.groups.newch", "New channel") })
			d:button(x + w - 192, y, 92, 44, T("bobba.phone.groups.text", "Text"), "light", function() P.send("groups.channel.add", { id = id, name = ce:GetValue(), kind = "text" }) ce:SetText("") end)
			d:button(x + w - 94, y, 94, 44, T("bobba.phone.groups.voice", "Voice"), "light", function() P.send("groups.channel.add", { id = id, name = ce:GetValue(), kind = "voice" }) ce:SetText("") end)
			y = y + 60
		end
		-- the members (and who's asking)
		local m = SO.members[id]
		if m and #m.requests > 0 and admin then
			section(T("bobba.phone.groups.asking", "ASKING TO JOIN"))
			local rr = {}
			for _, q in ipairs(m.requests) do rr[#rr + 1] = { title = q.name, right = T("bobba.phone.friends.accept", "Accept"), click = function() P.send("groups.accept", { id = id, key = q.key }) st.membersAsked = false end } end
			y = ctx:rows(x, y, w, rr, { rowH = 48 }) + 14
		end
		section(T("bobba.phone.groups.members", "MEMBERS (%n%)", { n = g.members or 0 }))
		if m then
			local rr = {}
			local RANKS = { [0] = T("bobba.phone.groups.member", "Member"), [1] = T("bobba.phone.groups.admin", "Admin"), [2] = T("bobba.phone.groups.owner", "Owner") }
			for _, mem in ipairs(m.members) do
				local r = { title = mem.name, sub = (mem.online and T("bobba.phone.friends.online2", "Online") or T("bobba.phone.friends.offline", "Offline")), right = RANKS[mem.rank] }
				if (g.rank or 0) == 2 and mem.rank < 2 then
					r.click = function()
						DV.ask({ title = mem.name, text = T("bobba.phone.groups.memberq", "Make them an admin, or a member again; or remove them from the group."),
							ok = mem.rank == 1 and T("bobba.phone.groups.makemember", "Make member") or T("bobba.phone.groups.makeadmin", "Make admin"),
							fn = function() P.send("groups.rank", { id = id, key = mem.key, rank = mem.rank == 1 and 0 or 1 }) st.membersAsked = false end,
							alt = { T("bobba.phone.groups.kick", "Remove from the group"), function() P.send("groups.kick", { id = id, key = mem.key }) st.membersAsked = false end } })
					end
					r.right = "chevron"
					r.sub = r.sub .. " · " .. RANKS[mem.rank]
				end
				rr[#rr + 1] = r
			end
			y = ctx:rows(x, y, w, rr, { rowH = 54 }) + 20
		end
		-- leaving / deleting
		if (g.rank or 0) == 2 then
			d:button(x, y, w, 46, T("bobba.phone.groups.delete", "Delete the group"), "danger", function()
				DV.ask({ title = T("bobba.phone.groups.deleteq", "Delete %name%?", { name = g.name }), text = T("bobba.phone.groups.deletetext", "Its channels and messages go too. This can't be undone."),
					ok = T("bobba.phone.groups.delete", "Delete the group"), danger = true, fn = function() P.send("groups.delete", { id = id }) ctx:pop() end })
			end)
		else
			d:button(x, y, w, 46, T("bobba.phone.groups.leave", "Leave the group"), "danger", function()
				DV.ask({ title = T("bobba.phone.groups.leaveq", "Leave %name%?", { name = g.name }), danger = true, ok = T("bobba.phone.groups.leave", "Leave the group"),
					fn = function() P.send("groups.leave", { id = id }) ctx:pop() end })
			end)
		end
		y = y + 70
		st.contentH = y + off - top
	end)
end

-- --- finding and making a group ---------------------------------------------------------------------
local function findView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local st = ctx.state
	d:rect(0, 0, W, H, C.paper)
	local top = ctx.top + ctx:header(T("bobba.phone.groups.find", "Find or make a group"))
	local x, w = 16, W - 32
	if ctx.kind == "tablet" then x, w = math.max(16, (W - 620) / 2), math.min(620, W - 32) end
	st.tab = st.tab or "find"
	d:chips("gtabs", x, top + 4, w, { { id = "find", label = T("bobba.phone.groups.findtab", "Find") }, { id = "make", label = T("bobba.phone.groups.maketab", "Make one") } }, st.tab, function(id) st.tab = id end)
	local y = top + 48
	if st.tab == "find" then
		if not st.searched then st.searched = true P.send("groups.search", { query = "" }) end
		d:input("gsearch", x, y, w, 44, { placeholder = T("bobba.phone.groups.search", "Search groups"), max = 40, onEnter = function(t) P.send("groups.search", { query = t or "" }) end })
		y = y + 56
		local res = SO.results and SO.results.groups or {}
		local rowH = 74
		local off = d:scroll("gres", 0, y, W, H - y, #res * rowH + 30)
		d:clip(0, y, W, H - y, function()
			if #res == 0 then d:text(T("bobba.phone.groups.none", "No groups yet. Make the first one!"), 14, W / 2, y + 40, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600) end
			for i, g in ipairs(res) do
				local ry = y + (i - 1) * rowH - off
				if ry + rowH > y and ry < H then
					d:round(18, x, ry + 4, 52, 52, colorOf(g))
					d:text((g.name or "?"):sub(1, 1):upper(), 22, x + 26, ry + 30, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
					d:text(d:fit(g.name or "", 15, w - 190, 800), 15, x + 66, ry + 12, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
					d:text(d:fit(T("bobba.phone.groups.count", "%n% members", { n = g.members }) .. ((g.description or "") ~= "" and (" · " .. g.description) or ""), 12, w - 190), 12, x + 66, ry + 34, C.ink2)
					local inIt = false
					for _, m in ipairs(SO.groups) do if m.id == g.id then inIt = true end end
					if inIt then
						d:button(x + w - 100, ry + 12, 96, 36, T("bobba.phone.store.open", "Open"), "light", function() DV.groupOpen = g.id ctx:pop() end)
					else
						d:button(x + w - 100, ry + 12, 96, 36, g.open and T("bobba.phone.groups.join", "Join") or T("bobba.phone.groups.ask", "Ask"), "primary", function()
							P.send("groups.join", { id = g.id })
							if g.open then DV.groupOpen = g.id ctx:pop() else SO.notify({ app = "groups", title = g.name, text = T("bobba.phone.groups.asked", "Asked to join. An admin will let you in.") }) end
						end)
					end
				end
			end
		end)
		return
	end
	-- making one
	st.color = st.color or COLORS[1]
	d:text(T("bobba.phone.groups.name", "Name"), 13, x + 4, y + 8, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
	local ne = d:input("newname", x, y + 20, w, 46, { max = 40, bg = C.white, placeholder = T("bobba.phone.groups.namehint", "At least 3 letters") })
	y = y + 78
	d:text(T("bobba.phone.groups.desc", "What it's about"), 13, x + 4, y + 8, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
	local de = d:input("newdesc", x, y + 20, w, 70, { max = 255, bg = C.white, multiline = true, radius = 18 })
	y = y + 104
	for i, hx in ipairs(COLORS) do
		local cx = x + 18 + (i - 1) * 40
		d:click(cx - 16, y, 32, 32, function() st.color = hx end)
		if st.color == hx then d:circle(cx, y + 16, 17, C.navy) d:circle(cx, y + 16, 14.5, C.white) end
		d:circle(cx, y + 16, 12, hex(hx))
	end
	y = y + 48
	-- the room: the one you're in, when it's yours
	local me = LocalPlayer and IsValid(LocalPlayer()) and LocalPlayer():Nick()
	local mineRoom = R.current and R.current.owner == me and R.current or nil
	if mineRoom then
		st.useRoom = st.useRoom == nil and true or st.useRoom
		y = ctx:rows(x, y, w, { { title = T("bobba.phone.groups.roomis", "Its room: %room%", { room = mineRoom.name or "" }), right = "toggle", on = st.useRoom, click = function() st.useRoom = not st.useRoom end } }) + 14
	end
	local price = SO.groupPrice or 10
	local name = ne:GetValue() or ""
	local ok = #name:gsub("%s", "") >= 3
	d:button(x, y, w, 50, T("bobba.phone.groups.make", "Make the group · %price%", { price = DV.priceText({ credits = price }) }), ok and "primary" or "light", function()
		P.send("groups.create", { name = name, description = de:GetValue() or "", color = st.color, room = (mineRoom and st.useRoom) and mineRoom.id or 0 })
		st.made = SysTime()
	end, not ok)
end

-- --- the app ----------------------------------------------------------------------------------------
local function groupsView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local st = ctx.state
	askList()
	SO.closeChannel()
	d:rect(0, 0, W, H, C.navy)
	local tablet = ctx.kind == "tablet"
	local top = ctx.top
	-- (a group just made or joined: that one)
	if SO.justMade then DV.groupOpen = SO.justMade SO.justMade = nil end
	if DV.groupOpen then st.group = DV.groupOpen DV.groupOpen = nil end
	local list = SO.groups
	if not st.group or not (function() for _, g in ipairs(list) do if g.id == st.group then return true end end end)() then st.group = list[1] and list[1].id end
	-- the rail
	local railW = 76
	local y = top + 8
	local railH = H - top
	local roff = d:scroll("grail", 0, top, railW, railH, (#list + 1) * 64 + 30)
	d:clip(0, top, railW, railH, function()
		local yy = y - roff
		for _, g in ipairs(list) do
			local on = g.id == st.group
			d:click(10, yy, 56, 56, function() st.group = g.id st.channel = nil d.surf.scrolls.channel = nil end)
			if on then d:pill(0, yy + 10, 5, 36, C.paper) end
			d:round(on and 18 or 26, 12, yy + 2, 52, 52, colorOf(g))
			d:text((g.name or "?"):sub(1, 1):upper(), 20, 38, yy + 28, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
			if (g.unread or 0) > 0 then
				local t = tostring(g.unread)
				local bw = math.max(20, d:textWidth(t, 11, 800) + 10)
				d:pill(64 - bw + 6, yy + 38, bw + 4, 24, C.navy)
				d:pill(64 - bw + 8, yy + 40, bw, 20, C.red)
				d:text(t, 11, 64 - bw / 2 + 8, yy + 50, C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
			end
			yy = yy + 64
		end
		local hv = d:click(12, yy + 2, 52, 52, function() ctx:push(findView, {}) end)
		d:round(26, 12, yy + 2, 52, 52, hv and C.navy3 or C.navy)
		d:ring(38, yy + 28, 26, 2, C.ink2)
		d:glyph(G.plus, 28, yy + 18, 20, C.green, 2.6)
	end)
	-- the group
	local px = railW
	local pw = tablet and 330 or (W - railW)
	d:round(26, px, top, pw + 30, H - top + 30, C.navy2, true, false, false, false)
	if #list == 0 then
		local cx = px + pw / 2
		d:text(T("bobba.phone.app.groups", "Groups"), 22, cx, top + 80, C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
		for i, l in ipairs(d:wrap(T("bobba.phone.groups.empty", "Groups have their own room and channels to talk in. Find one, or make your own."), 14, pw - 50)) do
			d:text(l, 14, cx, top + 120 + (i - 1) * 20, C.mist, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		end
		d:button(px + 24, top + 200, pw - 48, 48, T("bobba.phone.groups.find", "Find or make a group"), "paper", function() ctx:push(findView, {}) end)
		return
	end
	local g = info(st.group)
	if not g then
		d:text(T("bobba.phone.loading", "Loading…"), 14, px + pw / 2, top + 80, C.mist, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		return
	end
	local x, w = px + 16, pw - 32
	local yy = top + 16
	d:round(20, x, yy, w, 96, colorOf(g))
	d:round(18, x + 14, yy + 64, 52, 52, C.paper)
	d:round(16, x + 16, yy + 66, 48, 48, colorOf(g))
	d:text((g.name or "?"):sub(1, 1):upper(), 20, x + 40, yy + 90, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
	yy = yy + 126
	d:text(d:fit(g.name or "", 20, w, 800), 20, x, yy, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	local sub = T("bobba.phone.groups.counts", "%n% members · %on% online", { n = g.members or 0, on = g.online or 0 })
	if g.roomName then sub = sub .. " · " .. T("bobba.phone.groups.roomline", "Group room: %room%", { room = g.roomName }) end
	local subLines = d:wrap(sub, 12, w)
	for i, l in ipairs(subLines) do d:text(l, 12, x, yy + 28 + (i - 1) * 16, C.mist) end
	yy = yy + 30 + #subLines * 16 + 8
	if g.room then
		d:button(x, yy, w - 46, 38, T("bobba.phone.groups.goroom", "Go to the room"), "paper", function()
			DV.home() DV.show(false)
			local RW = BOBBA.roomWindows
			if RW and RW.visit then RW.visit({ id = g.room, owner = g.ownerName }) else P.send("room.enter", { id = g.room }) end
		end)
	else
		d:round(19, x, yy, w - 46, 38, C.navy3)
		d:text(T("bobba.phone.groups.noroom", "No room yet"), 13, x + (w - 46) / 2, yy + 19, C.mist, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
	end
	local hs = d:click(x + w - 38, yy, 38, 38, function() ctx:push(settingsView, { group = g.id }) end)
	d:circle(x + w - 19, yy + 19, 19, hs and C.ink2 or C.navy3)
	for i = -1, 1 do d:circle(x + w - 19 + i * 7, yy + 19, 2.2, C.paper) end
	yy = yy + 52
	if not g.rank then
		d:button(x, yy, w, 44, g.requested and T("bobba.phone.groups.waiting", "Waiting to be let in") or (g.open and T("bobba.phone.groups.join", "Join") or T("bobba.phone.groups.ask", "Ask")), "green",
			function() if not g.requested then P.send("groups.join", { id = g.id }) end end, g.requested)
		return
	end
	-- the channels
	local chH = H - yy - 20
	local coff = d:scroll("gchans", px, yy, pw, chH, st.chansH or chH)
	d:clip(px, yy, pw, chH, function()
		local cy = yy - coff
		for _, kind in ipairs({ "text", "voice" }) do
			d:text(kind == "text" and T("bobba.phone.groups.textch", "TEXT") or T("bobba.phone.groups.voicech", "VOICE"), 12, x + 2, cy + 8, C.slate, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
			cy = cy + 22
			for _, c in ipairs(g.channels or {}) do
				if c.kind == kind then
					local on = tablet and st.channel == c.id
					local hov = d:click(x - 4, cy, w + 8, 42, function()
						if kind == "voice" then
							SO.notify({ app = "groups", title = c.name, text = T("bobba.phone.groups.voicesoon", "Voice channels open when voice chat comes to this hotel.") })
						elseif tablet then st.channel = c.id d.surf.scrolls.channel = nil
						else ctx:push(channelView, { group = g.id, channel = c.id }) end
					end)
					if on or hov then d:round(14, x - 4, cy, w + 8, 42, on and C.navy3 or alpha(C.navy3, 0.6)) end
					if kind == "text" then d:text("#", 18, x + 10, cy + 21, C.slate, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
					else d:glyph(G.volume, x + 6, cy + 11, 20, C.green, 2.2) end
					local unread = (c.unread or 0) > 0
					d:text(d:fit(c.name, 15, w - 80, unread and 800 or 600), 15, x + 34, cy + 21, unread and C.paper or C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, unread and 800 or 600)
					if unread then
						local t = tostring(c.unread)
						local bw = math.max(20, d:textWidth(t, 11, 800) + 10)
						d:pill(x + w - bw - 4, cy + 11, bw, 20, C.red)
						d:text(t, 11, x + w - bw / 2 - 4, cy + 21, C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
					end
					cy = cy + 46
				end
			end
			cy = cy + 8
		end
		st.chansH = cy + coff - yy
	end)
	-- the tablet: the open channel beside it
	if tablet then
		local cx = px + pw + 30
		local cw = W - cx - 24
		local channel
		for _, c in ipairs(g.channels or {}) do if c.id == st.channel and c.kind == "text" then channel = c end end
		if not channel then for _, c in ipairs(g.channels or {}) do if c.kind == "text" and not channel then channel = c st.channel = c.id end end end
		if channel then
			d:text("#" .. channel.name, 18, cx, top + 26, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
			d:rect(cx, top + 50, cw, 1, C.navy3)
			channelBody(ctx, d, g, channel, cx, top + 60, cw, H - top - 90, st)
		end
	end
end

DV.app({ id = "groups", name = T("bobba.phone.app.groups", "Groups"), color = C.purple, glyph = G.groups, dock = true, order = 4, removable = false, bg = C.navy,
	badge = function() return SO.unreadGroups() end,
	phone = groupsView, tablet = groupsView,
	onClose = function() SO.closeChannel() end })

-- a channel opened from a notification
function DV.openChannel(group, channel)
	DV.groupOpen = group
	DV.openApp("groups")
	local st = DV.stack
	if not st.screens then return end
	if DV.kind == "tablet" then st.screens[1].state.channel = channel
	else st.screens[#st.screens + 1] = { view = channelView, state = { group = group, channel = channel }, at = SysTime() } end
end
