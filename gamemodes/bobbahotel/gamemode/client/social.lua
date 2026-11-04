-- Friends, messages, groups and room events on the client: what the server says (hotel/friends.lua,
-- hotel/groups.lua, hotel/roomevents.lua), kept for the phone's apps (client/app_social.lua,
-- client/app_groups.lua, client/app_events.lua), and the notifications they bring.

BOBBA.social = BOBBA.social or {}
local SO = BOBBA.social
local P = BOBBA.platform
local U = BOBBA.ui
local T = function(k, f, v) return U.text(k, f, v) end

SO.friends = SO.friends or {}
SO.requests = SO.requests or {}
SO.sent = SO.sent or {}
SO.threads = SO.threads or {}     -- key -> { messages = {...}, loaded }
SO.groups = SO.groups or {}
SO.groupInfo = SO.groupInfo or {} -- id -> info
SO.members = SO.members or {}     -- id -> { members, requests }
SO.channels = SO.channels or {}   -- channel id -> { messages, loaded }
SO.events = SO.events or {}
SO.open = SO.open or {}           -- what's being looked at: { thread = key } / { channel = id }

-- a notification (the phone's, or the classic look's bubble)
local function notify(n)
	-- (the server's words start small: "you need ..." reads as "You need ...")
	if type(n.text) == "string" then n.text = n.text:gsub("^%l", string.upper) end
	local DV = BOBBA.device
	if DV and DV.active and DV.active() then return DV.notify(n) end
	U.notify(n.title, n.text)
end
SO.notify = notify

function SO.friend(key)
	for _, f in ipairs(SO.friends) do if f.key == key then return f end end
end
function SO.unreadMessages()
	local n = 0
	for _, f in ipairs(SO.friends) do n = n + (f.unread or 0) end
	return n
end
function SO.unreadGroups()
	local n = 0
	for _, g in ipairs(SO.groups) do n = n + (g.unread or 0) end
	return n
end

-- --- friends and messages ---------------------------------------------------------------------------
P.receive("friends.list", function(_, data)
	SO.friends = data.friends or {}
	SO.requests = data.requests or {}
	SO.sent = data.sent or {}
	SO.loaded = true
	-- (the conversation being read: nothing unread there)
	if SO.open.thread then
		local f = SO.friend(SO.open.thread)
		if f then f.unread = 0 end
	end
end)
P.receive("friends.update", function(_, data)
	local f = SO.friend(data.key)
	if not f then return end
	local cameOnline = data.online and not f.online
	f.online, f.room, f.roomName = data.online, data.room, data.roomName
	if cameOnline and not (BOBBA.device and BOBBA.device.dnd) then
		notify({ app = "messages", title = f.name, text = T("bobba.phone.friends.online", "is online now"), quiet = true })
	end
end)
P.receive("friends.requested", function(_, data)
	notify({ app = "messages", title = data.name, text = T("bobba.phone.friends.wants", "wants to be your friend"),
		actions = { { T("bobba.phone.friends.accept", "Accept"), function() P.send("friends.accept", { key = data.key }) end },
			{ T("bobba.phone.friends.decline", "Decline"), function() P.send("friends.decline", { key = data.key }) end } } })
end)
P.receive("friends.error", function(_, data)
	SO.lastError = { text = tostring(data.message), at = SysTime() }
	notify({ app = "messages", title = T("bobba.phone.couldnt", "Couldn't do that"), text = tostring(data.message) })
end)
P.receive("messenger.history", function(_, data)
	SO.threads[data.with] = { messages = data.messages or {}, loaded = true }
	local f = SO.friend(data.with)
	if f then f.unread = 0 end
end)
P.receive("messenger.message", function(_, data)
	local th = SO.threads[data.with]
	local have = false
	for _, m in ipairs(th and th.messages or {}) do if m.id == data.id then have = true end end
	if th and not have then th.messages[#th.messages + 1] = { id = data.id, mine = data.mine, text = data.text, at = data.at } end
	local f = SO.friend(data.with)
	if f then
		f.last = { text = data.text, at = data.at, mine = data.mine }
		if not data.mine then
			if SO.open.thread == data.with then P.send("messenger.read", { with = data.with })
			else f.unread = (f.unread or 0) + 1 end
		end
	end
	if not data.mine and SO.open.thread ~= data.with then
		notify({ app = "messages", title = data.name or (f and f.name) or "", text = data.text,
			click = function() if BOBBA.device and BOBBA.device.openThread then BOBBA.device.openThread(data.with) end end })
	end
	BOBBA.events.emit("friendMessage", data)
end)

function SO.openThread(key)
	SO.open.thread = key
	P.send("messenger.history", { with = key })
end
function SO.closeThread() SO.open.thread = nil end

-- --- groups -----------------------------------------------------------------------------------------
P.receive("groups.list", function(_, data) SO.groups = data.groups or {} SO.groupPrice = data.price SO.groupsLoaded = true end)
P.receive("groups.info", function(_, data) SO.groupInfo[data.id] = data end)
P.receive("groups.members", function(_, data) SO.members[data.id] = { members = data.members or {}, requests = data.requests or {} } end)
P.receive("groups.results", function(_, data) SO.results = data end)
P.receive("groups.created", function(_, data) SO.justMade = data.id BOBBA.events.emit("groupCreated", data.id) end)
P.receive("groups.deleted", function(_, data) SO.groupInfo[data.id] = nil end)
P.receive("groups.error", function(_, data)
	SO.groupErrorAt = SysTime()
	SO.lastError = { text = tostring(data.message), at = SysTime() }
	notify({ app = "groups", title = T("bobba.phone.couldnt", "Couldn't do that"), text = tostring(data.message) })
end)
P.receive("groups.asked", function(_, data)
	notify({ app = "groups", title = data.name, text = T("bobba.phone.groups.asks", "asks to join your group"),
		actions = { { T("bobba.phone.friends.accept", "Accept"), function() P.send("groups.accept", { id = data.id, key = data.key }) end } } })
end)
P.receive("groups.history", function(_, data)
	SO.channels[data.channel] = { messages = data.messages or {}, loaded = true, group = data.group }
end)
P.receive("groups.message", function(_, data)
	local ch = SO.channels[data.channel]
	-- (not twice: the history may have it already)
	local have = false
	for _, m in ipairs(ch and ch.messages or {}) do if m.id == data.message.id then have = true end end
	if ch and not have then ch.messages[#ch.messages + 1] = data.message end
	local me = LocalPlayer and IsValid(LocalPlayer()) and LocalPlayer():Nick() or nil
	local mine = me and data.message.name == me
	if SO.open.channel == data.channel then
		P.send("groups.read", { channel = data.channel })
		return
	end
	if mine then return end
	for _, g in ipairs(SO.groups) do if g.id == data.group then g.unread = (g.unread or 0) + 1 end end
	local info = SO.groupInfo[data.group]
	if info then for _, c in ipairs(info.channels or {}) do if c.id == data.channel then c.unread = (c.unread or 0) + 1 end end end
	local gname = ""
	for _, g in ipairs(SO.groups) do if g.id == data.group then gname = g.name end end
	notify({ app = "groups", title = gname, text = data.message.name .. ": " .. data.message.text,
		click = function() if BOBBA.device and BOBBA.device.openChannel then BOBBA.device.openChannel(data.group, data.channel) end end })
end)

function SO.openChannel(id)
	SO.open.channel = id
	P.send("groups.history", { channel = id })
end
function SO.closeChannel() SO.open.channel = nil end

-- --- room events ------------------------------------------------------------------------------------
P.receive("events.list", function(_, data)
	SO.events = data.events or {}
	SO.eventsMax, SO.eventsPrice = data.maxHours or 3, data.price or 0
	SO.eventsLoaded = true
end)
P.receive("events.started", function(_, data)
	notify({ app = "events", title = data.name, text = T("bobba.phone.events.started", "An event started in %room%", { room = data.roomName or "" }),
		click = function()
			local RW = BOBBA.roomWindows
			if RW and RW.visit then RW.visit({ id = data.room, owner = data.owner }) else P.send("room.enter", { id = data.room }) end
		end })
end)
P.receive("events.error", function(_, data)
	SO.lastError = { text = tostring(data.message), at = SysTime() }
	notify({ app = "events", title = T("bobba.phone.couldnt", "Couldn't do that"), text = tostring(data.message) })
end)
