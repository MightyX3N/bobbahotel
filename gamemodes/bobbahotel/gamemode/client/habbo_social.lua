-- Friends, the messenger, profiles and groups in the classic look (client), as nitro-react has them:
-- the friend list (FriendsListView: friends, offline friends, requests, search), room invites and
-- removing friends, the messenger (FriendsMessengerView: open chats on the left, the chat on the
-- right; groups' chats too), the user profile (UserProfileView), and groups (GroupInformationView,
-- GroupMembersView, GroupCreatorView, GroupManagerView). The data is client/social.lua's, the same the
-- phone's apps use (hotel/friends.lua, hotel/groups.lua, hotel/profiles.lua on the server).

BOBBA.habboSocial = BOBBA.habboSocial or {}
local HS = BOBBA.habboSocial
local SO = BOBBA.social
local P = BOBBA.platform
local U = BOBBA.ui
local HUD = BOBBA.hud
local R = BOBBA.room
local T = function(k, f, v) return U.text(k, f, v) end
local BLACK, WHITE = U.C.black, U.C.white
local MUTED = Color(182, 190, 197)
local LIGHTBG = Color(223, 223, 223)

local function classic() return U.style() == "habbo" end
local function myName() return LocalPlayer and IsValid(LocalPlayer()) and LocalPlayer():Nick() or "" end
local function hex(h)
	h = tostring(h or ""):gsub("[^%x]", "")
	if #h ~= 6 then return Color(185, 140, 255) end
	return Color(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16))
end

-- --- small parts --------------------------------------------------------------------------------------
-- a head (Habbo's head picture) in a square
local function head(d, figure, gender, x, y, size, dir)
	local AE = BOBBA.avatarEditor
	if not (figure and AE and AE.drawHead) then return end
	d:clip(x, y, size, size, function() AE.drawHead(figure, gender or "M", dir or 2, x * d.s, y * d.s, size * d.s) end)
end
HS.head = head
-- a whole avatar, its feet at the bottom of x, y, w, h
local function avatar(d, figure, gender, x, y, w, h, dir)
	local AE = BOBBA.avatarEditor
	if not (figure and AE and AE.drawPreview) then return end
	d:clip(x, y, w, h, function() AE.drawPreview(figure, gender or "M", dir or 2, (x + w / 2) * d.s, (y + h - 112) * d.s, d.s) end)
end
-- a group's badge: its colour and its letter (the hotel's groups have no badge editor yet)
local function badge(d, g, x, y, size)
	local c = hex(g and g.color)
	d:round(size * 0.18, x, y, size, size, Color(0, 0, 0, 60))
	d:round(size * 0.18, x + 1, y + 1, size - 2, size - 2, c)
	d:round(size * 0.18, x + 1, y + 1, size - 2, (size - 2) / 2, Color(255, 255, 255, 40), true, true, false, false)
	d:text(tostring(g and g.name or "?"):sub(1, 1):upper(), size * 0.5, x + size / 2, y + size / 2, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
end
HS.badge = badge
-- a button with its label (Bootstrap's btn-sm in the colour)
local function button(d, x, y, w, h, color, label, fn, disabled)
	d:btn(x, y, w, h, color, fn, disabled)
	d:text(d:fit(label, 12.6, w - 8), 12.6, x + w / 2, y + h / 2, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
-- an icon that's clicked (its picture, or a letter when the pack has none)
local function iconButton(d, name, x, y, w, h, fn, fallback)
	local hover = d:click(x, y, w, h, fn)
	if not d:icon(name, x, y, w, h, { shadow = hover }) and fallback then
		d:text(fallback, 12, x + w / 2, y + h / 2, hover and U.C.primary or BLACK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
	end
	return hover
end
-- Habbo's texts with <b>bold</b> in them: the bold parts bold, the rest not (one line, cut to w)
local function boldText(d, t, size, x, y, w)
	t = tostring(t or ""):gsub("<br%s*/?>", " ")
	local cx = x
	local pos = 1
	while pos <= #t and cx < x + w do
		local s1, e1, inner = t:find("<b>(.-)</b>", pos)
		local plain = s1 and t:sub(pos, s1 - 1) or t:sub(pos)
		plain = plain:gsub("<[^>]+>", "")
		if plain ~= "" then
			local p2 = d:fit(plain, size, x + w - cx)
			d:text(p2, size, cx, y, BLACK)
			cx = cx + d:textWidth(p2, size)
		end
		if not s1 then break end
		inner = inner:gsub("<[^>]+>", "")
		local i2 = d:fit(inner, size, x + w - cx, true)
		d:text(i2, size, cx, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
		cx = cx + d:textWidth(i2, size, true)
		pos = e1 + 1
	end
end

-- "x minutes ago" (FriendlyTime)
local function ago(seconds)
	seconds = math.max(0, seconds or 0)
	local units = { { "years", 31536000 }, { "months", 2592000 }, { "days", 86400 }, { "hours", 3600 }, { "minutes", 60 } }
	for _, u in ipairs(units) do
		if seconds >= u[2] then
			local n = math.floor(seconds / u[2])
			return T("friendlytime." .. u[1] .. ".ago", "%amount% " .. u[1] .. " ago", { amount = n })
		end
	end
	return T("friendlytime.seconds.ago", "%amount% seconds ago", { amount = math.floor(seconds) })
end

-- --- the friend list (FriendsListView: 250 x 300) --------------------------------------------------------
HS.FL = HS.FL or { open = { true, false, true, false }, selected = {} }
local FL = HS.FL
local RELS = { [1] = "friends-heart", [2] = "friends-smile", [3] = "friends-bobba" }

local function onlineFriends()
	local on, off = {}, {}
	for _, f in ipairs(SO.friends) do if f.online then on[#on + 1] = f else off[#off + 1] = f end end
	local byName = function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end
	table.sort(on, byName) table.sort(off, byName)
	return on, off
end
HS.onlineFriends = onlineFriends

local function selectedKeys()
	local out = {}
	for k in pairs(FL.selected) do if SO.friend(k) then out[#out + 1] = k end end
	return out
end

-- one friend's row: profile icon, name; follow, chat, relationship (or the choice of them)
local function friendRow(d, f, x, y, w)
	local sel = FL.selected[f.key]
	d:click(x, y, w, 25, function() FL.selected[f.key] = (not FL.selected[f.key]) or nil end)
	if sel then d:rect(x, y, w, 25, U.C.primary) end
	local fg = sel and WHITE or BLACK
	iconButton(d, "friends-profile", x + 8, y + 7, 13, 11, function() HS.openProfile(f.key) end, "i")
	d:text(d:fit(f.name or "", 13, w - 110), 13, x + 26, y + 12.5, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local ix = x + w - 8
	if FL.relFor == f.key then
		for rel = 0, 3 do
			ix = ix - 16
			iconButton(d, RELS[rel] or "friends-none", ix, y + 5.5, 16, 14, function()
				P.send("friends.relationship", { key = f.key, rel = rel })
				f.rel = rel
				FL.relFor = nil
			end)
			ix = ix - 4
		end
		return
	end
	ix = ix - 16
	iconButton(d, RELS[f.rel or 0] or "friends-none", ix, y + 5.5, 16, 14, function() FL.relFor = f.key end)
	if f.online then
		ix = ix - 4 - 17
		iconButton(d, "friends-chat", ix, y + 4.5, 17, 16, function() HS.openChat(f.key) end, "@")
	end
	if f.room then
		ix = ix - 4 - 16
		iconButton(d, "friends-follow", ix, y + 5.5, 16, 14, function() P.send("friends.follow", { key = f.key }) end, ">")
	end
end

local function drawFriendList(w, d)
	d:slimCard(T("friendlist.friends", "Friends"))
	local on, off = onlineFriends()
	local reqs = SO.requests or {}
	local sets = {
		{ id = 1, label = T("friendlist.friends", "Friends") .. " (" .. #on .. ")" },
		{ id = 2, label = T("friendlist.friends.offlinecaption", "Offline Friends") .. " (" .. #off .. ")" },
	}
	if #reqs > 0 then sets[#sets + 1] = { id = 3, label = T("friendlist.tab.friendrequests", "Friend Requests") .. " (" .. #reqs .. ")" } end
	sets[#sets + 1] = { id = 4, label = T("people.search.title", "Search Habbos") }
	local sel = selectedKeys()
	local bottomBar = #sel > 0 and 36 or 0
	local top, bottom = 29, d.height - 1 - bottomBar
	local openCount = 0
	for _, st in ipairs(sets) do if FL.open[st.id] then openCount = openCount + 1 end end
	local share = openCount > 0 and ((bottom - top) - #sets * 25) / openCount or 0
	local y = top
	local W = d.width
	for _, st in ipairs(sets) do
		local h = 25 + (FL.open[st.id] and share or 0)
		if FL.open[st.id] then
			d:rect(1, y, W - 2, h, Color(255, 255, 255, 128))
			d:rect(1, y + h - 1, W - 2, 1, Color(0, 0, 0, 51))
		end
		d:click(1, y, W - 2, 25, function() FL.open[st.id] = not FL.open[st.id] end)
		d:text(st.label, 14.4, 9, y + 12, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		d:rect(1, y + 24, W - 2, 1, Color(0, 0, 0, 51))
		d:fa(FL.open[st.id] and "caret-up" or "caret-down", W - 1 - 8 - 12, y + 6, 12, BLACK)
		if FL.open[st.id] and share > 0 then
			local by, bh = y + 25, share - 1
			if st.id == 1 or st.id == 2 then
				local list = st.id == 1 and on or off
				local off2 = d:scroll("fl" .. st.id, 1, by, W - 2, bh, #list * 25)
				d:clip(1, by, W - 2, bh, function()
					for i, f in ipairs(list) do
						local ry = by + (i - 1) * 25 - off2
						if ry + 25 > by and ry < by + bh then friendRow(d, f, 1, ry, W - 2) end
					end
				end)
			elseif st.id == 3 then
				local off2 = d:scroll("fl3", 1, by, W - 2, bh - 34, #reqs * 25)
				d:clip(1, by, W - 2, bh - 34, function()
					for i, q in ipairs(reqs) do
						local ry = by + (i - 1) * 25 - off2
						iconButton(d, "friends-profile", 9, ry + 7, 13, 11, function() HS.openProfile(q.key) end, "i")
						d:text(d:fit(q.name or "", 13, W - 90), 13, 27, ry + 12.5, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						iconButton(d, "friends-accept", W - 9 - 13 - 4 - 13, ry + 5.5, 13, 14, function() P.send("friends.accept", { key = q.key }) end, "+")
						iconButton(d, "friends-deny", W - 9 - 13, ry + 5.5, 13, 14, function() P.send("friends.decline", { key = q.key }) end, "x")
					end
				end)
				local bw = d:textWidth(T("friendlist.requests.dismissall", "Dismiss all requests"), 12.6) + 20
				button(d, (W - bw) / 2, by + bh - 30, bw, 26, U.C.primary, T("friendlist.requests.dismissall", "Dismiss all requests"), function()
					for _, q in ipairs(reqs) do P.send("friends.decline", { key = q.key }) end
				end)
			else
				HS.searchSection(d, 1, by, W - 2, bh)
			end
		end
		y = y + h
	end
	-- selected friends: invite them, or remove them
	if #sel > 0 then
		local bw = (W - 8 - 4) / 2
		button(d, 4, d.height - 32, bw, 28, U.C.primary, T("friendlist.tip.invite", "Invite"), function() HS.openInvite() end)
		button(d, 4 + bw + 4, d.height - 32, bw, 28, U.C.danger, T("generic.delete", "Delete"), function() HS.openRemove() end)
	end
end

-- the search: friends found, other Habbos found (HabboSearchResultEvent)
HS.search = HS.search or { query = "" }
P.receive("users.results", function(_, data) HS.search.results = data end)
function HS.searchSection(d, x, y, w, h)
	local e = d:input("flsearch", x, y, w, 26, { placeholder = T("generic.search", "Search"), max = 50 })
	local q = e:GetValue() or ""
	if q ~= HS.search.query then HS.search.query = q HS.search.at = SysTime() HS.search.sent = false end
	if not HS.search.sent and q ~= "" and SysTime() - (HS.search.at or 0) > 0.5 then
		HS.search.sent = true
		P.send("users.search", { query = q })
	end
	local res = HS.search.results
	if not res or q == "" then return end
	local rows = {}
	local function caption(t) rows[#rows + 1] = { caption = t } end
	if #(res.friends or {}) == 0 then caption(T("friendlist.search.nofriendsfound", "No friends found"))
	else
		caption(T("friendlist.search.friendscaption", "Friends (%cnt%)", { cnt = #res.friends }))
		for _, r in ipairs(res.friends) do rows[#rows + 1] = { user = r, friend = true } end
	end
	if #(res.others or {}) == 0 then caption(T("friendlist.search.noothersfound", "No other Habbos found"))
	else
		caption(T("friendlist.search.otherscaption", "Other Habbos (%cnt%)", { cnt = #res.others }))
		for _, r in ipairs(res.others) do rows[#rows + 1] = { user = r } end
	end
	local top = y + 28
	local off = d:scroll("flsearchres", x, top, w, h - 28, #rows * 25)
	d:clip(x, top, w, h - 28, function()
		local sent = {}
		for _, s in ipairs(SO.sent or {}) do sent[s.key] = true end
		for i, r in ipairs(rows) do
			local ry = top + (i - 1) * 25 - off
			if r.caption then
				d:text(r.caption, 12, x + 8, ry + 12.5, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
				d:rect(x + 8, ry + 23, w - 16, 1, Color(0, 0, 0, 60))
			else
				local u = r.user
				iconButton(d, "friends-profile", x + 8, ry + 7, 13, 11, function() HS.openProfile(u.key) end, "i")
				d:text(d:fit(u.name or "", 13, w - 70), 13, x + 26, ry + 12.5, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				if r.friend and u.online then
					iconButton(d, "friends-chat", x + w - 8 - 17, ry + 4.5, 17, 16, function() HS.openChat(u.key) end, "@")
				elseif not r.friend and not sent[u.key] then
					iconButton(d, "friends-add", x + w - 8 - 16, ry + 5, 16, 15, function()
						P.send("friends.request", { name = u.name })
						SO.sent = SO.sent or {}
						SO.sent[#SO.sent + 1] = { key = u.key, name = u.name }
					end, "+")
				end
			end
		end
	end)
end

function HS.openFriends(search)
	if search then FL.open[4] = true end
	if U.isOpen("friends") then return end
	P.send("friends.get", {})
	U.window("friends", 250, 300, drawFriendList)
end

-- inviting the selected friends to your room (FriendsRoomInviteView)
function HS.openInvite()
	U.window("friends-invite", 250, 230, function(w, d)
		d:slimCard(T("friendlist.invite.title", "Invite friends"))
		local keys = selectedKeys()
		local W = d.width
		local y = 31 + 8
		local lines = d:wrap(T("friendlist.invite.summary", "Invite %count% friends to this room", { count = #keys }), 13, W - 18)
		for i, l in ipairs(lines) do d:text(l, 13, 9, y + (i - 1) * 18, BLACK) end
		y = y + #lines * 18 + 6
		local e = d:input("invitetext", 9, y, W - 18, 60, { multiline = true, max = 255 })
		y = y + 66
		d:round(4, 9, y, W - 18, 26, MUTED)
		d:text(d:fit(T("friendlist.invite.note", "Only friends who are online get it."), 12, W - 26), 12, W / 2, y + 13, BLACK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		y = y + 32
		w:setHeight(y + 28 + 9)
		local bw = (W - 18 - 4) / 2
		local text = e:GetValue() or ""
		button(d, 9, y, bw, 28, U.C.success, T("friendlist.invite.send", "Send"), function()
			P.send("friends.invite", { keys = keys, text = text })
			w:close()
		end, text == "" or #keys == 0)
		button(d, 9 + bw + 4, y, bw, 28, U.C.primary, T("generic.cancel", "Cancel"), function() w:close() end)
	end)
end

-- removing the selected friends (FriendsRemoveConfirmationView)
function HS.openRemove()
	U.window("friends-remove", 250, 130, function(w, d)
		d:slimCard(T("friendlist.removefriendconfirm.title", "Remove friends"))
		local keys = selectedKeys()
		local names = {}
		for _, k in ipairs(keys) do local f = SO.friend(k) names[#names + 1] = f and f.name or k end
		local W = d.width
		local lines = d:wrap(T("friendlist.removefriendconfirm.userlist", "Do you want to remove %user_names%?", { user_names = table.concat(names, ", ") }), 13, W - 18)
		for i, l in ipairs(lines) do d:text(l, 13, 9, 39 + (i - 1) * 18, BLACK) end
		local y = 39 + #lines * 18 + 8
		w:setHeight(y + 28 + 9)
		local bw = (W - 18 - 4) / 2
		button(d, 9, y, bw, 28, U.C.danger, T("generic.ok", "OK"), function()
			for _, k in ipairs(keys) do P.send("friends.remove", { key = k }) end
			FL.selected = {}
			w:close()
		end, #keys == 0)
		button(d, 9 + bw + 4, y, bw, 28, U.C.primary, T("generic.cancel", "Cancel"), function() w:close() end)
	end)
end

-- --- the messenger (FriendsMessengerView: 500 x 370) --------------------------------------------------------
-- open chats: { id = "f:<key>" } with a friend, { id = "g:<group id>" } a group's chat
HS.threads = HS.threads or {}
HS.invites = HS.invites or {} -- friend key -> { { text, at, name, room, roomName } }
HS.unseen = HS.unseen or {}   -- thread id -> true

local function threadOf(id)
	for _, t in ipairs(HS.threads) do if t.id == id then return t end end
end
local function addThread(id)
	local t = threadOf(id)
	if not t then t = { id = id } HS.threads[#HS.threads + 1] = t end
	return t
end
local function groupOf(id) for _, g in ipairs(SO.groups) do if g.id == id then return g end end end
-- a group's chat: its first text channel
local function groupChannel(gid)
	local info = SO.groupInfo[gid]
	for _, c in ipairs(info and info.channels or {}) do if c.kind == "text" then return c.id end end
end

-- the toolbar's messenger icon: hidden, shown (chats open) or unread
function HS.iconState()
	if #HS.threads == 0 then return nil end
	for _ in pairs(HS.unseen) do return "unread" end
	return "show"
end

local function activate(t)
	if not t then return end
	HS.active = t.id
	HS.unseen[t.id] = nil
	local kind, ref = t.id:match("^(%a):(.+)$")
	if kind == "f" then
		SO.closeChannel()
		SO.openThread(ref)
	else
		SO.closeThread()
		local gid = tonumber(ref)
		local ch = groupChannel(gid)
		if ch then SO.openChannel(ch) else P.send("groups.get", { id = gid }) t.waiting = true end
	end
	HS.scrollDown = true
end

function HS.openChat(key)
	local t = key and addThread((type(key) == "number") and ("g:" .. key) or ("f:" .. key)) or (HS.threads[1])
	HS.openMessenger(t)
end
function HS.openGroupChat(gid) HS.openMessenger(addThread("g:" .. gid)) end

local function closeThread(id)
	for i, t in ipairs(HS.threads) do if t.id == id then table.remove(HS.threads, i) break end end
	HS.unseen[id] = nil
	if HS.active == id then
		HS.active = nil
		SO.closeThread() SO.closeChannel()
		if HS.threads[1] then activate(HS.threads[1]) end
	end
end

-- the messages of a chat as Nitro groups them: one sender's in a row together; invites on their own
local function chatGroups(t)
	local kind, ref = t.id:match("^(%a):(.+)$")
	local items = {}
	if kind == "f" then
		local th = SO.threads[ref]
		for _, m in ipairs(th and th.messages or {}) do items[#items + 1] = { mine = m.mine, text = m.text, at = m.at or 0, id = m.id or 0 } end
		for _, inv in ipairs(HS.invites[ref] or {}) do items[#items + 1] = { invite = inv, at = inv.at or 0, id = math.huge } end
		table.sort(items, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.id < b.id end)
	else
		local ch = groupChannel(tonumber(ref))
		local c = ch and SO.channels[ch]
		local me = myName()
		for _, m in ipairs(c and c.messages or {}) do
			items[#items + 1] = { mine = m.name == me, text = m.text, at = m.at, name = m.name, figure = m.figure, gender = m.gender, key = m.key }
		end
	end
	local groups = {}
	for _, it in ipairs(items) do
		local last = groups[#groups]
		if it.invite then groups[#groups + 1] = { invite = it.invite }
		elseif last and not last.invite and last.mine == it.mine and last.key == it.key then last.lines[#last.lines + 1] = it.text
		else groups[#groups + 1] = { mine = it.mine, name = it.name, figure = it.figure, gender = it.gender, key = it.key, lines = { it.text } } end
	end
	return groups
end

local function participant(t)
	local kind, ref = t.id:match("^(%a):(.+)$")
	if kind == "f" then
		local f = SO.friend(ref)
		return { name = f and f.name or ref, figure = f and f.figure, gender = f and f.gender, friend = f }
	end
	local g = groupOf(tonumber(ref)) or SO.groupInfo[tonumber(ref)]
	return { name = g and g.name or "", group = g }
end

local function drawMessenger(w, d)
	local W, H = d.width, d.height
	d:slimCard(T("messenger.window.title", "Friends Messenger (%OPEN_CHAT_COUNT%)", { OPEN_CHAT_COUNT = #HS.threads }))
	if not HS.active and HS.threads[1] then activate(HS.threads[1]) end
	local t = HS.active and threadOf(HS.active)
	if t and t.waiting and groupChannel(tonumber(t.id:sub(3))) then t.waiting = nil activate(t) end
	-- the left: open chats (Column size 4)
	local lx, lw = 9, (W - 18 - 8) * 4 / 12
	local top = 31 + 8
	d:text(T("toolbar.icon.label.messenger", "Messenger"), 14.4, lx, top, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	local listTop = top + 24
	local listH = H - listTop - 9
	local off = d:scroll("threads", lx, listTop, lw, listH, #HS.threads * 54)
	d:clip(lx, listTop, lw, listH, function()
		for i, th in ipairs(HS.threads) do
			local y = listTop + (i - 1) * 54 - off
			local active = th.id == HS.active
			d:click(lx, y, lw, 50, function() activate(th) end)
			d:gridItem(lx, y, lw, 50, active)
			local pt = participant(th)
			if pt.group then badge(d, pt.group, lx + 6, y + 9, 32) else head(d, pt.figure, pt.gender, lx + 2, y + 2, 46, 3) end
			d:text(d:fit(pt.name, 13, lw - 60), 13, lx + 52, y + 25, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			if HS.unseen[th.id] then U.countBadge(d, 1, lx + lw - 4, y + 4) end
		end
	end)
	-- the right: the chat (Column size 8)
	local rx = lx + lw + 8
	local rw = W - 9 - rx
	if not t then return end
	local pt = participant(t)
	d:text(d:fit(T("messenger.window.separator", "Chat with %FRIEND_NAME%", { FRIEND_NAME = pt.name }), 14.4, rw, true), 14.4, rx + rw / 2, top, BLACK, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, true)
	local by = top + 24
	-- follow and profile (a friend), or the group's page; and closing the chat
	if pt.friend then
		d:button(rx, by, 30, 26, U.C.primary, function() P.send("friends.follow", { key = pt.friend.key }) end, { true, false, true, false })
		d:icon("friends-follow", rx + 7, by + 6, 16, 14)
		d:button(rx + 30, by, 30, 26, U.C.primary, function() HS.openProfile(pt.friend.key) end, { false, true, false, true })
		d:icon("friends-profile", rx + 38.5, by + 7.5, 13, 11)
	elseif pt.group then
		button(d, rx, by, 90, 26, U.C.primary, T("group.window.title", "Group info"), function() HS.openGroup(pt.group.id) end)
	end
	d:btn(rx + rw - 30, by, 30, 26, U.C.primary, function() closeThread(t.id) end)
	d:fa("times", rx + rw - 30 + 9, by + 7, 12, WHITE)
	-- the messages (bg-muted, rounded)
	local my = by + 26 + 6
	local inputH = 28
	local mh = H - 9 - inputH - 6 - my
	d:round(4, rx, my, rw, mh, MUTED)
	local groups = chatGroups(t)
	-- (how tall each group is: its lines wrapped in the bubble)
	local bubbleW = rw - 16 - 50 - 8 - 10
	local heights, total = {}, 8
	for i, g in ipairs(groups) do
		local h
		if g.invite then
			g.wrapped = d:wrap(T("messenger.invitation", "Invitation:") .. " " .. g.invite.text, 12, rw - 16 - 40)
			h = math.max(32, #g.wrapped * 16 + 10)
		else
			g.wrapped = {}
			for _, l in ipairs(g.lines) do for _, wl in ipairs(d:wrap(l, 12.6, bubbleW - 16)) do g.wrapped[#g.wrapped + 1] = wl end end
			h = math.max(50, 8 + 18 + #g.wrapped * 17 + 6)
		end
		heights[i] = h
		total = total + h + 8
	end
	local soff = d:scroll("chat", rx, my, rw, mh, total)
	if HS.scrollDown or (HS.lastCount ~= #groups) then
		local sc = w.scrolls.chat
		if sc then sc.offset = math.max(0, total - mh) end
		HS.scrollDown = false
		HS.lastCount = #groups
	end
	d:clip(rx, my, rw, mh, function()
		local y = my + 8 - soff
		for i, g in ipairs(groups) do
			local h = heights[i]
			if y + h > my and y < my + mh then
				if g.invite then
					d:round(4, rx + 8, y, rw - 16, h, Color(248, 249, 250))
					d:icon("messenger-notification", rx + 14, y + (h - 25) / 2, 25, 25)
					for j, l in ipairs(g.wrapped) do d:text(l, 12, rx + 46, y + 5 + (j - 1) * 16, BLACK) end
					if g.invite.room then d:click(rx + 8, y, rw - 16, h, function() P.send("room.enter", { id = g.invite.room }) end) end
				else
					local mine = g.mine
					local bx = mine and (rx + rw - 8 - 50 - 8 - bubbleW) or (rx + 8 + 50 + 8)
					-- the avatar: theirs on the left, yours on the right
					local fig, gen = g.figure, g.gender
					if not mine and not fig then fig, gen = pt.figure, pt.gender end
					if mine then
						local AE = BOBBA.avatarEditor
						local u = R.units and R.you and R.units[R.you]
						fig, gen = u and u.figure or (BOBBA.website and BOBBA.website.data and BOBBA.website.data.figure), u and u.gender
					end
					head(d, fig, gen, mine and (rx + rw - 8 - 50) or (rx + 8), y, 50, mine and 4 or 2)
					local bh = h
					d:round(4, bx, y, bubbleW, bh, Color(248, 249, 250))
					-- (the little point towards the avatar)
					local px = mine and (bx + bubbleW) or bx
					local dir = mine and 1 or -1
					draw.NoTexture()
					surface.SetDrawColor(248, 249, 250, 255)
					local s = d.s
					surface.DrawPoly(mine and { { x = px * s, y = (y + 10) * s }, { x = (px + 8) * s, y = (y + 18) * s }, { x = px * s, y = (y + 26) * s } }
						or { { x = px * s, y = (y + 10) * s }, { x = px * s, y = (y + 26) * s }, { x = (px - 8) * s, y = (y + 18) * s } })
					d:text(mine and myName() or (g.name or pt.name), 12.6, bx + 8, y + 5, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
					for j, l in ipairs(g.wrapped) do d:text(l, 12.6, bx + 8, y + 23 + (j - 1) * 17, BLACK) end
				end
			end
			y = y + h + 8
		end
	end)
	-- writing
	local iy = H - 9 - inputH
	local sayW = 60
	local function send(text)
		text = tostring(text or "")
		if text == "" then return end
		local kind, ref = t.id:match("^(%a):(.+)$")
		if kind == "f" then P.send("messenger.send", { to = ref, text = text })
		else
			local ch = groupChannel(tonumber(ref))
			if ch then P.send("groups.send", { channel = ch, text = text }) end
		end
		local e = w.inputs and w.inputs.msg
		if IsValid(e) then e:SetText("") e:RequestFocus() end
		HS.scrollDown = true
	end
	local e = d:input("msg", rx, iy, rw - sayW - 4, inputH, { max = 255, placeholder = T("messenger.window.input.default", "Write a message to %FRIEND_NAME%...", { FRIEND_NAME = pt.name }), onEnter = send })
	button(d, rx + rw - sayW, iy, sayW, inputH, U.C.success, T("widgets.chatinput.say", "Say"), function() send(e:GetValue()) end)
end

function HS.openMessenger(t)
	if t then activate(t) end
	if U.isOpen("messenger") then return end
	P.send("groups.mine", {})
	U.window("messenger", 500, 370, drawMessenger).onClose = function()
		SO.closeThread() SO.closeChannel()
		HS.active = nil
	end
end

-- (in the classic look: a message opens a chat in the messenger and lights the toolbar's icon, as
-- Habbo's; no bubble)
function SO.classicMessage(data)
	if not classic() then return false end
	local id = "f:" .. data.with
	local t = threadOf(id)
	if not t then
		t = addThread(id)
		if BOBBA.sounds and BOBBA.sounds.play then pcall(BOBBA.sounds.play, "messenger_new_thread") end
	elseif BOBBA.sounds and BOBBA.sounds.play then pcall(BOBBA.sounds.play, "messenger_message_received") end
	if not (U.isOpen("messenger") and HS.active == id) then HS.unseen[id] = true end
	return true
end
function SO.classicGroupMessage(data)
	if not classic() then return false end
	local id = "g:" .. data.group
	local t = threadOf(id)
	-- (a group's chat comes up only when it's open, or once someone writes in it)
	if not t then t = addThread(id) end
	if not (U.isOpen("messenger") and HS.active == id) then HS.unseen[id] = true end
	return true
end
P.receive("messenger.invite", function(_, data)
	HS.invites[data.with] = HS.invites[data.with] or {}
	table.insert(HS.invites[data.with], data)
	if classic() then
		local id = "f:" .. data.with
		addThread(id)
		if not (U.isOpen("messenger") and HS.active == id) then HS.unseen[id] = true end
		if BOBBA.sounds and BOBBA.sounds.play then pcall(BOBBA.sounds.play, "messenger_message_received") end
	else
		SO.notify({ app = "messages", title = data.name, text = T("bobba.phone.friends.invites", "invites you to their room: %text%", { text = data.text }),
			actions = data.room and { { T("bobba.phone.friends.go", "Go"), function() P.send("room.enter", { id = data.room }) end } } or nil })
	end
end)

-- --- the user profile (UserProfileView: 470 x 460) ------------------------------------------------------------
HS.profile = HS.profile or nil
P.receive("user.profile", function(_, data)
	HS.profile = data
	HS.profileGroup = data.groups and data.groups[1] and data.groups[1].id or nil
	if HS.profileGroup then P.send("groups.get", { id = HS.profileGroup }) end
	if not U.isOpen("user-profile") then HS.showProfile() end
end)
function HS.openProfile(key)
	if not key then return end
	P.send("user.profile", { key = key })
end
function HS.openProfileByName(name) P.send("user.profile", { name = name }) end

local REL_ORDER = { { "heart", "friends-heart" }, { "smile", "friends-smile" }, { "bobba", "friends-bobba" } }
local function drawProfile(w, d)
	local pr = HS.profile
	d:slimCard(T("extendedprofile.caption", "Profile"))
	if not pr then return end
	local W, H = d.width, d.height
	local x, y = 9, 31 + 8
	local leftW = (W - 18 - 8) * 7 / 12
	-- the avatar and what they are
	avatar(d, pr.figure, pr.gender, x, y, 75, 120, 2)
	local tx = x + 75 + 8
	d:text(d:fit(pr.name or "", 14.4, leftW - 85, true), 14.4, tx, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	d:text(d:fit(pr.motto or "", 12, leftW - 85), 12, tx, y + 20, BLACK)
	local ly = y + 42
	local function line(key, label, var, value)
		local t = T(key, "<b>" .. label .. "</b> %" .. var .. "%", { [var] = value })
		-- (Habbo's own text may be just the label: in bold, the value after it)
		if not t:find(tostring(value), 1, true) then t = "<b>" .. t:gsub("<[^>]+>", "") .. "</b> " .. tostring(value) end
		boldText(d, t, 12, tx, ly, leftW - 85)
		ly = ly + 17
	end
	line("extendedprofile.created", "Created:", "created", pr.since and pr.since > 0 and os.date("%d-%m-%Y", pr.since) or "-")
	line("extendedprofile.last.login", "Last login:", "lastlogin", pr.online and T("extendedprofile.online", "online now") or ago((pr.now or os.time()) - (pr.seen or 0)))
	line("extendedprofile.achievementscore", "Achievement score:", "score", "0")
	ly = ly + 4
	-- online, and friends or not
	d:circle(tx + 6, ly + 7, 5, pr.online and Color(0, 160, 30) or Color(170, 40, 40))
	local fx = tx + 18
	if not pr.me and not pr.isFriend and not pr.requestSent and not HS.requested then
		local label = T("extendedprofile.addasafriend", "Add as a friend")
		local hov = d:click(fx, ly, d:textWidth(label, 12), 15, function() P.send("friends.request", { name = pr.name }) HS.requested = true end)
		d:text(label, 12, fx, ly, hov and U.C.primary or BLACK)
		d:rect(fx, ly + 14, d:textWidth(label, 12), 1, BLACK)
	else
		local label = pr.me and T("extendedprofile.me", "This is me") or (pr.isFriend and T("extendedprofile.friend", "Friend")) or T("extendedprofile.friendrequestsent", "Friend request sent")
		d:icon("tick", fx, ly + 1, 12, 12)
		d:text(label, 12, fx + 16, ly, BLACK)
	end
	-- badges (none yet)
	local bgY = y + 128
	d:round(4, x, bgY, leftW, 50, MUTED)
	-- the right: friends and relationships
	local rx = x + leftW + 8
	d:rect(rx - 4, y, 1, 178, Color(128, 128, 128))
	boldText(d, T("extendedprofile.friends.count", "<b>Friends:</b> %count%", { count = pr.friends or 0 }), 12, rx + 4, y, W - rx - 12)
	d:text(T("extendedprofile.relstatus", "Relationship status"), 12, rx + 4, y + 20, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	local ry = y + 40
	for _, r in ipairs(REL_ORDER) do
		local rel = pr.relationships and pr.relationships[r[1]]
		d:icon(r[2], rx + 4, ry + 4, 16, 14)
		if rel then
			local hov = d:click(rx + 26, ry, W - rx - 30, 22, function() HS.openProfile(rel.key) end)
			d:text(d:fit(rel.name, 12, W - rx - 40), 12, rx + 26, ry + 3, hov and U.C.primary or BLACK)
			if rel.count > 1 then d:text(T("extendedprofile.relstatus.others", "and %count% others", { count = rel.count - 1 }), 11, rx + 26, ry + 17, Color(147, 147, 146)) end
		else
			d:text(T("extendedprofile.add.friends", "Add friends"), 12, rx + 26, ry + 3, Color(147, 147, 146))
		end
		ry = ry + 36
	end
	-- the rooms
	local roomsY = y + 186
	d:rect(1, roomsY, W - 2, 1, Color(128, 128, 128))
	d:rect(1, roomsY + 28, W - 2, 1, Color(128, 128, 128))
	d:icon("profile-rooms", x + 4, roomsY + 2)
	local rl = T("extendedprofile.rooms", "Rooms")
	local hov = d:click(x + 40, roomsY + 4, d:textWidth(rl, 13, true), 20, function()
		local NAV = BOBBA.navigator
		if NAV and NAV.open then NAV.open("hotel_view", "owner:" .. pr.name) end
	end)
	d:text(rl, 13, x + 40, roomsY + 14, hov and U.C.primary or BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
	-- the groups
	local gy = roomsY + 36
	local gh = H - 9 - gy
	local groups = pr.groups or {}
	if #groups == 0 then
		d:text(pr.me and T("extendedprofile.nogroups.me", "You're not in any groups yet.") or T("extendedprofile.nogroups", "Not in any groups."), 13, W / 2, gy + gh / 2 - 20, BLACK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		if pr.me then
			button(d, W / 2 - 120, gy + gh / 2, 116, 28, U.C.success, T("group.create", "Create a group"), function() HS.openCreator() end)
			button(d, W / 2 + 4, gy + gh / 2, 116, 28, U.C.primary, T("group.showgroups", "Find groups"), function() HS.openGroupSearch() end)
		end
		return
	end
	local off = d:scroll("pgroups", x, gy, 56, gh, #groups * 56)
	d:clip(x, gy, 56, gh, function()
		for i, g in ipairs(groups) do
			local iy = gy + (i - 1) * 56 - off
			d:click(x, iy, 52, 52, function() HS.profileGroup = g.id P.send("groups.get", { id = g.id }) end)
			d:gridItem(x, iy, 52, 52, HS.profileGroup == g.id)
			badge(d, g, x + 8, iy + 8, 36)
		end
	end)
	local info = HS.profileGroup and SO.groupInfo[HS.profileGroup]
	if info then HS.groupInfoView(d, x + 64, gy, W - 9 - x - 64, gh, info, function() P.send("user.profile", { key = pr.key }) end) end
end
function HS.showProfile()
	P.send("groups.mine", {})
	U.window("user-profile", 470, 460, drawProfile)
end

-- --- a group's information (GroupInformationView) ---------------------------------------------------------
-- (onLeave: after leaving it)
function HS.groupInfoView(d, x, y, w, h, info, onLeave)
	local leftW = w * 3 / 12
	badge(d, info, x + (leftW - 78) / 2, y, 78)
	local ly = y + 86
	local function link(label, fn)
		local tw = d:textWidth(label, 12)
		local hov = d:click(x + (leftW - tw) / 2, ly, tw, 15, fn)
		d:text(label, 12, x + leftW / 2, ly, hov and U.C.primary or BLACK, TEXT_ALIGN_CENTER)
		d:rect(x + (leftW - tw) / 2, ly + 14, tw, 1, BLACK)
		ly = ly + 18
	end
	link(T("group.membercount", "%totalMembers% members", { totalMembers = info.members or 0 }), function() HS.openMembers(info.id) end)
	if (info.pending or 0) > 0 then link(T("group.pendingmembercount", "%amount% pending", { amount = info.pending }), function() HS.openMembers(info.id, "pending") end) end
	if (info.rank or -1) >= 1 then link(T("group.manage", "Manage"), function() HS.openManager(info.id) end) end
	-- your role
	if info.rank then
		local ic = info.rank == 2 and "group-owner" or (info.rank == 1 and "group-admin" or nil)
		if ic then d:icon(ic, x + leftW / 2 - 8, ly + 4, 16, 16) end
	end
	-- the right
	local rx, rw = x + leftW + 8, w - leftW - 8
	d:text(d:fit(info.name or "", 14.4, rw - 40, true), 14.4, rx, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	d:text(T("group.created", "Since %date%, by %owner%", { date = (info.created or 0) > 0 and os.date("%d-%m-%Y", info.created) or "-", owner = info.ownerName or "" }), 11, rx, y + 20, BLACK)
	local dy = y + 40
	for i, l in ipairs(d:wrap(info.description or "", 12, rw)) do
		if i <= 4 then d:text(l, 12, rx, dy + (i - 1) * 15, BLACK) end
	end
	local by = y + h - 28
	local ly2 = by - 8 - 18 * 2
	local function link2(label, fn)
		local tw = d:textWidth(label, 12)
		local hov = d:click(rx, ly2, tw, 15, fn)
		d:text(label, 12, rx, ly2, hov and U.C.primary or BLACK)
		d:rect(rx, ly2 + 14, tw, 1, BLACK)
		ly2 = ly2 + 18
	end
	if info.room then link2(T("group.linktobase", "Go to the group's room"), function() P.send("room.enter", { id = info.room }) end) end
	link2(T("group.showgroups", "Show groups"), function() HS.openGroupSearch() end)
	-- join, leave, ask (or you own it)
	local label, fn, disabled
	if info.rank == 2 then label, disabled = T("group.youareowner", "You own this group"), true
	elseif info.rank then label, fn = T("group.leave", "Leave group"), function()
		U.confirm(T("group.leaveconfirm.title", "Leave group"), T("group.leaveconfirm.desc", "Do you want to leave this group?"), function()
			P.send("groups.leave", { id = info.id })
			if onLeave then onLeave() end
		end)
	end
	elseif info.requested then label, disabled = T("group.membershippending", "Request sent"), true
	elseif info.open then label, fn = T("group.join", "Join group"), function() P.send("groups.join", { id = info.id }) end
	else label, fn = T("group.requestmembership", "Ask to join"), function() P.send("groups.join", { id = info.id }) end end
	button(d, rx, by, rw, 28, U.C.primary, label, fn or function() end, disabled)
	-- (a member: the group's chat in the messenger)
	if info.rank then
		local cl = T("bobba.group.chat", "Chat")
		local cw = d:textWidth(cl, 12) + 4
		local hov = d:click(rx + rw - cw, y + 20, cw, 15, function() HS.openGroupChat(info.id) end)
		d:text(cl, 12, rx + rw, y + 20, hov and U.C.primary or BLACK, TEXT_ALIGN_RIGHT)
	end
end

-- a group's own window (GroupInformationStandaloneView: 500 wide)
function HS.openGroup(id)
	P.send("groups.get", { id = id })
	HS.standalone = id
	U.window("group-info", 500, 230, function(w, d)
		d:slimCard(T("group.window.title", "Group info"))
		local info = SO.groupInfo[HS.standalone]
		if not info then return end
		HS.groupInfoView(d, 9, 31 + 8, d.width - 18, d.height - 31 - 8 - 9, info, function() w:close() end)
	end)
end

-- finding groups (the navigator's group search in Habbo; here a small window)
function HS.openGroupSearch()
	P.send("groups.search", { query = "" })
	U.window("group-search", 300, 340, function(w, d)
		d:slimCard(T("bobba.group.find", "Find groups"))
		local e = d:input("q", 9, 39, d.width - 18, 26, { placeholder = T("generic.search", "Search"), max = 40, onEnter = function(t) P.send("groups.search", { query = t or "" }) end })
		local res = SO.results and SO.results.groups or {}
		local top = 39 + 34
		local h = d.height - 9 - top
		local off = d:scroll("res", 9, top, d.width - 18, h, #res * 54)
		d:clip(9, top, d.width - 18, h, function()
			for i, g in ipairs(res) do
				local y = top + (i - 1) * 54 - off
				d:click(9, y, d.width - 18, 50, function() HS.openGroup(g.id) end)
				d:gridItem(9, y, d.width - 18, 50, false)
				badge(d, g, 15, y + 7, 36)
				d:text(d:fit(g.name or "", 13, d.width - 90, true), 13, 59, y + 16, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
				d:text(T("group.membercount", "%totalMembers% members", { totalMembers = g.members or 0 }), 11, 59, y + 34, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end)
	end)
end

-- --- a group's members (GroupMembersView: 400 wide) --------------------------------------------------------
function HS.openMembers(id, filter)
	P.send("groups.members", { id = id })
	P.send("groups.get", { id = id })
	HS.membersOf, HS.membersFilter = id, filter or "all"
	U.window("group-members", 400, 380, function(w, d)
		local gid = HS.membersOf
		local info = SO.groupInfo[gid]
		d:slimCard(T("group.members.title", "Group members: %groupName%", { groupName = info and info.name or "" }))
		local W = d.width
		local y = 31 + 8
		if info then badge(d, info, 9, y, 40) end
		local e = d:input("q", 57, y, W - 57 - 130, 26, { placeholder = T("generic.search", "Search"), max = 30 })
		local isAdmin = info and (info.rank or -1) >= 1
		local opts = { { "all", T("group.members.search.all", "All members") }, { "admins", T("group.members.search.admins", "Admins") } }
		if isAdmin then opts[#opts + 1] = { "pending", T("group.members.search.pending", "Pending members") } end
		d:select("filter", W - 9 - 120, y, 120, 26, opts, HS.membersFilter, function(v) HS.membersFilter = v end)
		y = y + 48
		local m = SO.members[gid]
		local q = (e:GetValue() or ""):lower()
		local list = {}
		if HS.membersFilter == "pending" then
			for _, r in ipairs(m and m.requests or {}) do list[#list + 1] = { key = r.key, name = r.name, pending = true } end
		else
			for _, r in ipairs(m and m.members or {}) do
				if HS.membersFilter ~= "admins" or (r.rank or 0) >= 1 then list[#list + 1] = r end
			end
		end
		if q ~= "" then
			local f = {}
			for _, r in ipairs(list) do if tostring(r.name):lower():find(q, 1, true) then f[#f + 1] = r end end
			list = f
		end
		local cw = (W - 18 - 8) / 2
		local rows = math.ceil(#list / 2)
		local h = d.height - 9 - y
		local off = d:scroll("members", 9, y, W - 18, h, rows * 58)
		d:clip(9, y, W - 18, h, function()
			for i, r in ipairs(list) do
				local cx = 9 + ((i - 1) % 2) * (cw + 8)
				local cy = y + math.floor((i - 1) / 2) * 58 - off
				d:round(4, cx, cy, cw, 50, LIGHTBG)
				head(d, r.figure, r.gender, cx, cy, 44, 2)
				local hov = d:click(cx + 44, cy + 6, cw - 80, 16, function() HS.openProfile(r.key) end)
				d:text(d:fit(r.name or "", 13, cw - 90, true), 13, cx + 46, cy + 14, hov and U.C.primary or BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
				if r.pending then
					d:text(T("group.members.pending", "Wants to join"), 11, cx + 46, cy + 32, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					iconButton(d, "friends-accept", cx + cw - 36, cy + 18, 13, 14, function() P.send("groups.accept", { id = gid, key = r.key }) end, "+")
					iconButton(d, "friends-deny", cx + cw - 18, cy + 18, 13, 14, function() P.send("groups.kick", { id = gid, key = r.key }) end, "x")
				else
					local rank = r.rank or 0
					local ic = rank == 2 and "group-owner" or (rank == 1 and "group-admin" or nil)
					if ic then d:icon(ic, cx + cw - 22, cy + 6, 16, 16) end
					d:text(rank == 2 and T("group.members.owner", "Owner") or (rank == 1 and T("group.members.admin", "Admin") or T("group.members.member", "Member")), 11, cx + 46, cy + 32, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					-- the owner makes admins; admins remove members
					if info and info.rank == 2 and rank < 2 then
						local label = rank == 1 and "-" or "+"
						iconButton(d, rank == 1 and "group-admin" or "group-admin:gray", cx + cw - 40, cy + 28, 16, 16, function() P.send("groups.rank", { id = gid, key = r.key, rank = rank == 1 and 0 or 1 }) end, label)
					end
					if info and (info.rank or -1) > rank and r.name ~= myName() then
						iconButton(d, "friends-deny", cx + cw - 20, cy + 30, 13, 14, function()
							U.confirm(T("group.kickconfirm.title", "Remove member"), T("group.kickconfirm.desc", "Remove %user% from the group?", { user = r.name }), function() P.send("groups.kick", { id = gid, key = r.key }) end)
						end, "x")
					end
				end
			end
		end)
	end)
end

-- --- making a group (GroupCreatorView: 383 wide; tabs: identity, colours, settings, confirm) ---------------------
local COLORS = { "B98CFF", "FFD166", "FF9F5A", "3FC6A0", "6E8BFF", "F26B8A", "9DB4FF", "E8C26A", "C9D2E5" }
HS.creator = HS.creator or nil
local function tabsHeader(d, steps, current, y)
	local W = d.width
	local n = #steps
	local sw = (W - 18) / n
	for i, label in ipairs(steps) do
		local x = 9 + (i - 1) * sw
		local on = i == current
		d:round(4, x + 2, y, sw - 4, 26, on and U.C.primary or (i < current and Color(80, 150, 180) or MUTED))
		d:text(i .. ". " .. label, 12, x + sw / 2, y + 13, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, on)
	end
end

-- the group's identity: name, description, its room (one of yours)
local function identityForm(d, st, y, W)
	d:text(T("group.edit.name", "Group name"), 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	local ne = d:input("name", 9, y + 18, W - 18, 26, { max = 40, value = st.name })
	st.name = ne:GetValue() or ""
	y = y + 52
	d:text(T("group.edit.desc", "Group description"), 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	local de = d:input("desc", 9, y + 18, W - 18, 56, { max = 255, multiline = true, value = st.description })
	st.description = de:GetValue() or ""
	y = y + 82
	return y
end

local function colorsForm(d, st, y, W)
	d:text(T("group.edit.color.guild.color", "Group colour"), 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	y = y + 20
	for i, hx in ipairs(COLORS) do
		local x = 9 + (i - 1) * 36
		d:click(x, y, 30, 30, function() st.color = hx end)
		if st.color == hx then d:round(4, x - 3, y - 3, 36, 36, U.C.primary) end
		d:round(4, x, y, 30, 30, hex(hx))
	end
	y = y + 44
	badge(d, { name = st.name ~= "" and st.name or "?", color = st.color }, (W - 64) / 2, y, 64)
	return y + 72
end

function HS.openCreator()
	P.send("groups.mine", {})
	HS.creator = { step = 1, name = "", description = "", color = COLORS[1], useRoom = true }
	U.window("group-creator", 383, 330, function(w, d)
		local st = HS.creator
		d:slimCard(T("group.create.title", "Create a group"))
		local W = d.width
		local steps = { T("group.create.stepcaption.1", "Identity"), T("group.create.stepcaption.3", "Colours"), T("group.create.stepcaption.4", "Confirm") }
		tabsHeader(d, steps, st.step, 31 + 8)
		local y = 31 + 8 + 36
		if st.step == 1 then
			y = identityForm(d, st, y, W)
			-- its room: the one you're in, when it's yours
			local mine = R.current and R.current.owner == myName() and R.current or nil
			if mine then
				d:check(9, y, st.useRoom, false, function() st.useRoom = not st.useRoom end)
				d:text(d:fit(T("bobba.group.useroom", "Its room: %room%", { room = mine.name or "" }), 12.6, W - 40), 12.6, 30, y + 7, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			else
				d:text(d:fit(T("bobba.group.noroom", "Be in one of your rooms to give the group a room."), 11, W - 18), 11, 9, y + 7, Color(108, 117, 125), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			st.room = (mine and st.useRoom) and mine.id or 0
			st.roomName = mine and mine.name or nil
		elseif st.step == 2 then
			colorsForm(d, st, y, W)
		else
			badge(d, { name = st.name, color = st.color }, 9, y, 64)
			d:text(d:fit(st.name, 14.4, W - 100, true), 14.4, 83, y + 4, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
			for i, l in ipairs(d:wrap(st.description, 12, W - 92)) do if i <= 3 then d:text(l, 12, 83, y + 24 + (i - 1) * 15, BLACK) end end
			y = y + 80
			local price = SO.groupPrice or 100
			d:round(4, 9, y, W - 18, 46, MUTED)
			d:text(T("group.create.confirm.buyinfo", "Making the group costs %amount% credits.", { amount = price }), 12.6, W / 2, y + 23, BLACK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
		end
		-- back, next / buy
		local by = d.height - 9 - 28
		local bw = (W - 18 - 4) / 2
		if st.step > 1 then button(d, 9, by, bw, 28, U.C.primary, T("group.create.previousstep", "Back"), function() st.step = st.step - 1 end)
		else button(d, 9, by, bw, 28, U.C.danger, T("generic.cancel", "Cancel"), function() w:close() end) end
		local okName = #st.name:gsub("%s", "") >= 3
		if st.step < 3 then
			button(d, 9 + bw + 4, by, bw, 28, U.C.primary, T("group.create.nextstep", "Next"), function() st.step = st.step + 1 end, not okName)
		else
			button(d, 9 + bw + 4, by, bw, 28, U.C.success, st.making and T("bobba.group.making", "Making it...") or T("group.create.confirm.buy", "Buy"), function()
				if st.making then return end
				st.making = SysTime()
				SO.justMade = nil
				P.send("groups.create", { name = st.name, description = st.description, color = st.color, room = st.room or 0 })
			end, not okName or st.making ~= nil)
			-- (made: its page; an error: try again)
			if st.making and SO.justMade then
				local id = SO.justMade
				SO.justMade = nil
				w:close()
				HS.openGroup(id)
				if st.room and st.room > 0 then P.send("room.enter", { id = st.room }) end
			elseif st.making and ((SO.groupErrorAt or 0) > st.making or SysTime() - st.making > 8) then
				st.making = nil
			end
		end
	end)
end

-- --- managing a group (GroupManagerView: 390 x 355; tabs: identity, colours, settings) ---------------------------
function HS.openManager(id)
	P.send("groups.get", { id = id })
	HS.manager = { id = id, tab = 1 }
	U.window("group-manager", 390, 355, function(w, d)
		local st = HS.manager
		local info = SO.groupInfo[st.id]
		d:slimCard(T("group.window.title", "Group") .. (info and (": " .. info.name) or ""))
		if not info then return end
		if not st.loaded then
			st.loaded = true
			st.name, st.description, st.color, st.open = info.name or "", info.description or "", info.color or COLORS[1], info.open
		end
		local W = d.width
		local tabs = { T("group.edit.tab.1", "Identity"), T("group.edit.tab.3", "Colours"), T("group.edit.tab.5", "Settings") }
		local tw = (W - 18) / 3
		for i, t in ipairs(tabs) do
			local x = 9 + (i - 1) * tw
			d:click(x, 39, tw, 26, function() st.tab = i end)
			d:round(4, x + 2, 39, tw - 4, 26, st.tab == i and U.C.primary or MUTED)
			d:text(t, 12.6, x + tw / 2, 52, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, st.tab == i)
		end
		local y = 39 + 36
		if st.tab == 1 then
			identityForm(d, st, y, W)
		elseif st.tab == 2 then
			colorsForm(d, st, y, W)
		else
			d:text(T("group.edit.settings.type.caption", "Who can join"), 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
			y = y + 22
			d:check(9, y, st.open, true, function() st.open = true end)
			d:text(T("group.edit.settings.type.regular.label", "Regular: anyone can join"), 12.6, 30, y + 7, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
			y = y + 26
			d:check(9, y, not st.open, true, function() st.open = false end)
			d:text(T("group.edit.settings.type.exclusive.label", "Exclusive: they ask, an admin lets them in"), 12.6, 30, y + 7, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
			y = y + 40
			if info.rank == 2 then
				button(d, 9, y, 150, 28, U.C.danger, T("group.delete", "Delete group"), function()
					U.confirm(T("group.deleteconfirm.title", "Delete group"), T("group.deleteconfirm.desc", "Delete the group? Its members and chat go too. This can't be undone."), function()
						P.send("groups.delete", { id = st.id })
						w:close()
					end)
				end)
			end
		end
		local by = d.height - 9 - 28
		button(d, d.width - 9 - 120, by, 120, 28, U.C.success, T("group.edit.save", "Save"), function()
			P.send("groups.edit", { id = st.id, name = st.name, description = st.description, color = st.color, open = st.open })
		end, #tostring(st.name):gsub("%s", "") < 3)
		button(d, 9, by, 120, 28, U.C.primary, T("generic.close", "Close"), function() w:close() end)
	end)
end

-- --- the toolbar's ways in (the classic look) -----------------------------------------------------------------
local oldFriends = HUD.actions.friends
HUD.actions.friends = function()
	if classic() then
		if U.isOpen("friends") then U.windows.friends:close() else HS.openFriends() end
		return
	end
	if oldFriends then oldFriends() end
end
HUD.actions.findFriends = function()
	if classic() then HS.openFriends(true) return end
	if oldFriends then oldFriends() end
end
HUD.actions.messenger = function()
	if U.isOpen("messenger") then U.windows.messenger:close() return end
	HS.openMessenger(HS.active and threadOf(HS.active) or HS.threads[1])
end
HUD.actions.profile = function()
	local key = LocalPlayer and IsValid(LocalPlayer()) and (P.playerKey and P.playerKey(LocalPlayer()) or nil)
	if key then HS.openProfile(key) else HS.openProfileByName(myName()) end
end
