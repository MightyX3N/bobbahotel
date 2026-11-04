-- Friends and messages (server): Habbo's friend list and messenger. A friend request (by name) is
-- accepted or declined; friends see each other online and in which room, can follow each other there,
-- and send messages (kept, so they're there when you come back).
--
-- Messages from players: friends.get {}   friends.request { name }   friends.accept { key }
--                        friends.decline { key }   friends.remove { key }   friends.follow { key }
--                        messenger.send { to, text }   messenger.history { with }   messenger.read { with }
-- Messages to players:   friends.list { friends = { { key, name, online, room, roomName, figure, gender,
--                          unread, last = { text, at, mine } } }, requests = { { key, name, figure, gender, at } },
--                          sent = { { key, name } } }
--                        friends.update { key, online, room, roomName }   (a friend came, went or moved)
--                        friends.error { message }
--                        messenger.message { with, id, mine, text, at, name }
--                        messenger.history { with, messages = { { id, mine, text, at } } }

BOBBA.friends = BOBBA.friends or {}
local F = BOBBA.friends
local live = BOBBA.live

F.MAX = 300
F.TEXT_MAX = 500
F.HISTORY = 60
F.online = F.online or {}   -- key -> player (here now)

local function P() return BOBBA.platform end
local function S() return BOBBA.store end

function F.migrate()
	BOBBA.store.migrate("core.022_friends", {
		"CREATE TABLE bobbahotel_friends (a TEXT NOT NULL, b TEXT NOT NULL, since INTEGER NOT NULL, PRIMARY KEY (a, b))",
		"CREATE TABLE bobbahotel_friend_requests (sender TEXT NOT NULL, target TEXT NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (sender, target))",
		[[CREATE TABLE bobbahotel_messages (
			id INTEGER PRIMARY KEY,
			sender TEXT NOT NULL,
			target TEXT NOT NULL,
			text TEXT NOT NULL,
			at INTEGER NOT NULL,
			seen INTEGER NOT NULL DEFAULT 0
		)]],
		"CREATE INDEX bobbahotel_messages_pair ON bobbahotel_messages (sender, target)",
		"CREATE INDEX bobbahotel_messages_unseen ON bobbahotel_messages (target, seen)",
	})
end

function F.max() return tonumber(S().setting("friends.max", tostring(F.MAX))) or F.MAX end

local function nameOf(key)
	local r = S().row("SELECT name FROM bobbahotel_users WHERE key = ?", { tostring(key) })
	return r and r.name or tostring(key)
end
F.nameOf = nameOf

function F.areFriends(a, b)
	return S().row("SELECT 1 AS x FROM bobbahotel_friends WHERE a = ? AND b = ?", { tostring(a), tostring(b) }) ~= nil
end

function F.friendKeys(key)
	local out = {}
	for _, r in ipairs(S().query("SELECT b FROM bobbahotel_friends WHERE a = ?", { tostring(key) })) do out[#out + 1] = r.b end
	return out
end

-- where someone is: the room's id and name (nil when not in one, or one only some may see)
local function whereIs(key)
	local p = F.online[key]
	local u = p and live.byPlayer[p]
	if not u then return nil end
	local info = live.info(u.room.id)
	if info and tonumber(info.state) == 3 then return nil end
	return u.room.id, info and info.name or ""
end

-- the friend list and the requests, for one player
function F.listFor(key)
	key = tostring(key)
	local friends = {}
	local unread = {}
	for _, r in ipairs(S().query("SELECT sender, COUNT(*) AS n FROM bobbahotel_messages WHERE target = ? AND seen = 0 GROUP BY sender", { key })) do
		unread[r.sender] = tonumber(r.n) or 0
	end
	for _, r in ipairs(S().query("SELECT f.b AS key, u.name AS name FROM bobbahotel_friends f LEFT JOIN bobbahotel_users u ON u.key = f.b WHERE f.a = ?", { key })) do
		local room, roomName = whereIs(r.key)
		local figure, gender = BOBBA.looks.get(r.key)
		local last = S().row("SELECT sender, text, at FROM bobbahotel_messages WHERE (sender = ? AND target = ?) OR (sender = ? AND target = ?) ORDER BY id DESC LIMIT 1",
			{ key, r.key, r.key, key })
		friends[#friends + 1] = {
			key = r.key, name = r.name or r.key, online = F.online[r.key] ~= nil, room = room, roomName = roomName,
			figure = figure, gender = gender, unread = unread[r.key] or 0,
			last = last and { text = last.text, at = tonumber(last.at), mine = last.sender == key } or nil,
		}
	end
	local requests = {}
	for _, r in ipairs(S().query("SELECT q.sender AS key, q.at AS at, u.name AS name FROM bobbahotel_friend_requests q LEFT JOIN bobbahotel_users u ON u.key = q.sender WHERE q.target = ? ORDER BY q.at DESC", { key })) do
		local figure, gender = BOBBA.looks.get(r.key)
		requests[#requests + 1] = { key = r.key, name = r.name or r.key, figure = figure, gender = gender, at = tonumber(r.at) }
	end
	local sent = {}
	for _, r in ipairs(S().query("SELECT q.target AS key, u.name AS name FROM bobbahotel_friend_requests q LEFT JOIN bobbahotel_users u ON u.key = q.target WHERE q.sender = ?", { key })) do
		sent[#sent + 1] = { key = r.key, name = r.name or r.key }
	end
	return { friends = friends, requests = requests, sent = sent }
end

function F.sendList(key)
	local p = F.online[tostring(key)]
	if p then P().send("friends.list", F.listFor(key), p) end
end

-- tells someone's online friends where they are now
function F.announce(key)
	local room, roomName = whereIs(key)
	local msg = { key = key, online = F.online[key] ~= nil, room = room, roomName = roomName }
	for _, k in ipairs(F.friendKeys(key)) do
		local p = F.online[k]
		if p then P().send("friends.update", msg, p) end
	end
end

local function makeFriends(a, b)
	local now = P().time()
	S().query("INSERT OR IGNORE INTO bobbahotel_friends (a, b, since) VALUES (?, ?, ?)", { a, b, now })
	S().query("INSERT OR IGNORE INTO bobbahotel_friends (a, b, since) VALUES (?, ?, ?)", { b, a, now })
	S().query("DELETE FROM bobbahotel_friend_requests WHERE (sender = ? AND target = ?) OR (sender = ? AND target = ?)", { a, b, b, a })
	BOBBA.events.emit("friendsMade", a, b)
end

local function count(key)
	local r = S().row("SELECT COUNT(*) AS n FROM bobbahotel_friends WHERE a = ?", { tostring(key) })
	return tonumber(r and r.n) or 0
end

-- asks someone (by name) to be friends: true, or false and why. When they'd asked you already, you're
-- friends at once.
function F.request(key, name)
	key = tostring(key)
	local toKey, toName = BOBBA.gifts.findUser(name)
	if not toKey then return false, "no one called " .. tostring(name) end
	if toKey == key then return false, "that's you" end
	if F.areFriends(key, toKey) then return false, "you're friends with " .. toName .. " already" end
	if count(key) >= F.max() then return false, "your friend list is full" end
	if S().row("SELECT 1 AS x FROM bobbahotel_friend_requests WHERE sender = ? AND target = ?", { toKey, key }) then
		if count(toKey) >= F.max() then return false, toName .. "'s friend list is full" end
		makeFriends(key, toKey)
		return true, toName, toKey, true
	end
	S().query("INSERT OR REPLACE INTO bobbahotel_friend_requests (sender, target, at) VALUES (?, ?, ?)", { key, toKey, P().time() })
	return true, toName, toKey, false
end

function F.accept(key, fromKey)
	key, fromKey = tostring(key), tostring(fromKey)
	if not S().row("SELECT 1 AS x FROM bobbahotel_friend_requests WHERE sender = ? AND target = ?", { fromKey, key }) then return false, "no request" end
	if count(key) >= F.max() then return false, "your friend list is full" end
	makeFriends(key, fromKey)
	return true
end

function F.decline(key, fromKey)
	S().query("DELETE FROM bobbahotel_friend_requests WHERE sender = ? AND target = ?", { tostring(fromKey), tostring(key) })
	return true
end

function F.remove(key, other)
	key, other = tostring(key), tostring(other)
	S().query("DELETE FROM bobbahotel_friends WHERE (a = ? AND b = ?) OR (a = ? AND b = ?)", { key, other, other, key })
	return true
end

-- a message to a friend: the message, or false and why
function F.message(key, to, text)
	key, to = tostring(key), tostring(to)
	text = tostring(text or ""):gsub("[%z\1-\9\11-\31]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return false, "nothing to send" end
	if #text > F.TEXT_MAX then text = text:sub(1, F.TEXT_MAX) end
	if not F.areFriends(key, to) then return false, "you can only message your friends" end
	local now = P().time()
	S().query("INSERT INTO bobbahotel_messages (sender, target, text, at, seen) VALUES (?, ?, ?, ?, 0)", { key, to, text, now })
	local row = S().row("SELECT MAX(id) AS id FROM bobbahotel_messages WHERE sender = ? AND target = ?", { key, to })
	local m = { id = tonumber(row and row.id) or 0, text = text, at = now }
	BOBBA.events.emit("friendMessage", key, to, text)
	return m
end

function F.history(key, with)
	key, with = tostring(key), tostring(with)
	local rows = S().query("SELECT id, sender, text, at FROM bobbahotel_messages WHERE (sender = ? AND target = ?) OR (sender = ? AND target = ?) ORDER BY id DESC LIMIT " .. F.HISTORY,
		{ key, with, with, key })
	local out = {}
	for i = #rows, 1, -1 do
		local r = rows[i]
		out[#out + 1] = { id = tonumber(r.id), mine = r.sender == key, text = r.text, at = tonumber(r.at) }
	end
	return out
end

function F.markRead(key, with)
	S().query("UPDATE bobbahotel_messages SET seen = 1 WHERE target = ? AND sender = ? AND seen = 0", { tostring(key), tostring(with) })
end

-- the player's whole time away: what's unread
function F.unread(key)
	local r = S().row("SELECT COUNT(*) AS n FROM bobbahotel_messages WHERE target = ? AND seen = 0", { tostring(key) })
	return tonumber(r and r.n) or 0
end

function F.start()
	F.migrate()
	local p = P()
	local function err(player, why) p.send("friends.error", { message = tostring(why) }, player) end
	BOBBA.events.on("playerReady", "bobba.friends", function(player)
		local key = p.playerKey(player)
		BOBBA.gifts.remember(key, p.playerName(player))
		local was = F.online[key]
		F.online[key] = player
		F.sendList(key)
		if not was then F.announce(key) end
	end)
	p.onLeave(function(player)
		local key = p.playerKey(player)
		if F.online[key] == player then
			F.online[key] = nil
			F.announce(key)
		end
	end)
	BOBBA.events.on("roomEntered", "bobba.friends", function(_, u) if u.player and F.online[u.key] then F.announce(u.key) end end)
	BOBBA.events.on("roomLeft", "bobba.friends", function(_, u) if u.player and F.online[u.key] then F.announce(u.key) end end)
	BOBBA.events.on("playerReset", "bobba.friends", function(key)
		local others = F.friendKeys(key)
		S().query("DELETE FROM bobbahotel_friends WHERE a = ? OR b = ?", { tostring(key), tostring(key) })
		S().query("DELETE FROM bobbahotel_friend_requests WHERE sender = ? OR target = ?", { tostring(key), tostring(key) })
		S().query("DELETE FROM bobbahotel_messages WHERE sender = ? OR target = ?", { tostring(key), tostring(key) })
		for _, k in ipairs(others) do F.sendList(k) end
	end)
	p.receive("friends.get", function(player) p.send("friends.list", F.listFor(p.playerKey(player)), player) end)
	p.receive("friends.request", function(player, data)
		local key = p.playerKey(player)
		local ok, name, toKey, made = F.request(key, data.name)
		if not ok then return err(player, name) end
		F.sendList(key)
		F.sendList(toKey)
		local other = F.online[toKey]
		if other and not made then p.send("friends.requested", { key = key, name = p.playerName(player) }, other) end
	end)
	p.receive("friends.accept", function(player, data)
		local key = p.playerKey(player)
		local ok, why = F.accept(key, data.key)
		if not ok then return err(player, why) end
		F.sendList(key)
		F.sendList(tostring(data.key))
	end)
	p.receive("friends.decline", function(player, data)
		local key = p.playerKey(player)
		F.decline(key, data.key)
		F.sendList(key)
		F.sendList(tostring(data.key))
	end)
	p.receive("friends.remove", function(player, data)
		local key = p.playerKey(player)
		F.remove(key, data.key)
		F.sendList(key)
		F.sendList(tostring(data.key))
	end)
	-- going to a friend's room (as Habbo's "follow")
	p.receive("friends.follow", function(player, data)
		local key = p.playerKey(player)
		if not F.areFriends(key, tostring(data.key)) then return err(player, "not your friend") end
		local room = whereIs(tostring(data.key))
		if not room then return err(player, "they aren't in a room") end
		local ok, why = live.enter(player, room)
		if not ok and why ~= "doorbell" and why ~= "password" then p.send("room.denied", { id = room, reason = tostring(why) }, player) end
		if why == "password" then
			local info = live.info(room)
			p.send("room.password", { id = room, name = info and info.name or "" }, player)
		end
	end)
	-- (at most a message a second, a little more in a burst)
	local sentAt = {}
	p.onLeave(function(player) sentAt[player] = nil end)
	p.receive("messenger.send", function(player, data)
		local now = p.clock()
		local s = sentAt[player] or { t = now, n = 0 }
		if now - s.t > 5 then s = { t = now, n = 0 } end
		s.n = s.n + 1
		sentAt[player] = s
		if s.n > 8 then return err(player, "slow down a little") end
		local key = p.playerKey(player)
		local to = tostring(data.to or "")
		local m, why = F.message(key, to, data.text)
		if not m then return err(player, why) end
		p.send("messenger.message", { with = to, id = m.id, mine = true, text = m.text, at = m.at }, player)
		local other = F.online[to]
		if other then p.send("messenger.message", { with = key, id = m.id, mine = false, text = m.text, at = m.at, name = p.playerName(player) }, other) end
	end)
	p.receive("messenger.history", function(player, data)
		local key = p.playerKey(player)
		local with = tostring(data.with or "")
		if not F.areFriends(key, with) then return end
		F.markRead(key, with)
		p.send("messenger.history", { with = with, messages = F.history(key, with) }, player)
	end)
	p.receive("messenger.read", function(player, data)
		F.markRead(p.playerKey(player), tostring(data.with or ""))
	end)
end
