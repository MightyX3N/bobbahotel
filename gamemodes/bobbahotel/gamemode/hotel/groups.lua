-- Groups (server): Habbo's groups, with a Discord-like inside. A group has a name, a colour, a
-- description, a room of its own, members (owner, admins, members) and channels: text channels with
-- their messages (kept), and voice channels (a place to talk; the talking comes with voice chat).
-- Making one costs groups.price.credits (100); one can own groups.max.owned (5). A group is open (anyone joins) or closed (asks first).
--
-- Messages from players: groups.mine {}   groups.get { id }   groups.search { query }
--                        groups.create { name, description, color, room }   groups.edit { id, name, description, color, room, open }
--                        groups.join { id }   groups.leave { id }   groups.delete { id }
--                        groups.members { id }   groups.rank { id, key, rank }   groups.kick { id, key }
--                        groups.accept { id, key }   groups.channel.add { id, name, kind }   groups.channel.remove { channel }
--                        groups.history { channel }   groups.send { channel, text }   groups.read { channel }
-- Messages to players:   groups.list { groups = { { id, name, color, rank, unread, members, online } } }
--                        groups.info { id, name, description, color, room, roomName, owner, ownerName, open, members,
--                          online, rank, requested, channels = { { id, name, kind, unread } } }
--                        groups.members { id, members = { { key, name, rank, online, figure, gender } }, requests = {...} }
--                        groups.results { query, groups = { { id, name, color, members, open, description } } }
--                        groups.history { channel, messages = { { id, key, name, text, at, figure, gender } } }
--                        groups.message { group, channel, message = { id, key, name, text, at } }
--                        groups.created { id }   groups.error { message }

BOBBA.groups = BOBBA.groups or {}
local GR = BOBBA.groups
local live = BOBBA.live

GR.RANK = { member = 0, admin = 1, owner = 2 }
GR.COLORS = { "B98CFF", "FFD166", "FF9F5A", "3FC6A0", "6E8BFF", "F26B8A", "9DB4FF", "E8C26A", "C9D2E5" }
GR.TEXT_MAX = 500
GR.HISTORY = 80
GR.MAX_OWNED = 5
GR.MAX_CHANNELS = 20

local function P() return BOBBA.platform end
local function S() return BOBBA.store end

function GR.migrate()
	BOBBA.store.migrate("core.023_groups", {
		[[CREATE TABLE bobbahotel_groups (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL,
			description TEXT NOT NULL DEFAULT '',
			color TEXT NOT NULL DEFAULT 'B98CFF',
			owner TEXT NOT NULL,
			room INTEGER NOT NULL DEFAULT 0,
			open INTEGER NOT NULL DEFAULT 1,
			created INTEGER NOT NULL
		)]],
		"CREATE TABLE bobbahotel_group_members (grp INTEGER NOT NULL, key TEXT NOT NULL, rank INTEGER NOT NULL DEFAULT 0, joined INTEGER NOT NULL, PRIMARY KEY (grp, key))",
		"CREATE TABLE bobbahotel_group_requests (grp INTEGER NOT NULL, key TEXT NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (grp, key))",
		"CREATE TABLE bobbahotel_group_channels (id INTEGER PRIMARY KEY, grp INTEGER NOT NULL, name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'text', pos INTEGER NOT NULL DEFAULT 0)",
		[[CREATE TABLE bobbahotel_group_messages (
			id INTEGER PRIMARY KEY,
			channel INTEGER NOT NULL,
			key TEXT NOT NULL,
			name TEXT NOT NULL,
			text TEXT NOT NULL,
			at INTEGER NOT NULL
		)]],
		"CREATE INDEX bobbahotel_group_messages_channel ON bobbahotel_group_messages (channel, id)",
		"CREATE TABLE bobbahotel_group_reads (channel INTEGER NOT NULL, key TEXT NOT NULL, last INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (channel, key))",
	})
end

function GR.price() return math.max(0, tonumber(S().setting("groups.price.credits", "100")) or 100) end

function GR.get(id)
	local r = S().row("SELECT * FROM bobbahotel_groups WHERE id = ?", { tonumber(id) or -1 })
	if not r then return nil end
	r.id, r.room, r.open = tonumber(r.id), tonumber(r.room) or 0, tonumber(r.open) == 1
	return r
end

-- someone's rank in a group: 0 member, 1 admin, 2 owner; nil when not in it
function GR.rank(id, key)
	local r = S().row("SELECT rank FROM bobbahotel_group_members WHERE grp = ? AND key = ?", { tonumber(id) or -1, tostring(key) })
	return r and tonumber(r.rank) or nil
end

local function memberKeys(id)
	local out = {}
	for _, r in ipairs(S().query("SELECT key FROM bobbahotel_group_members WHERE grp = ?", { tonumber(id) })) do out[#out + 1] = r.key end
	return out
end
GR.memberKeys = memberKeys

local function online(key) return BOBBA.friends and BOBBA.friends.online[tostring(key)] end

local function cleanText(t, max)
	t = tostring(t or ""):gsub("[%z\1-\9\11-\31]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #t > max then t = t:sub(1, max) end
	return t
end
local function cleanColor(c)
	c = tostring(c or ""):gsub("[^%x]", ""):upper()
	if #c ~= 6 then return GR.COLORS[1] end
	return c
end

local function channels(id)
	local out = {}
	for _, r in ipairs(S().query("SELECT id, name, kind, pos FROM bobbahotel_group_channels WHERE grp = ? ORDER BY pos, id", { tonumber(id) })) do
		out[#out + 1] = { id = tonumber(r.id), name = r.name, kind = r.kind }
	end
	return out
end

local function unread(channel, key)
	local last = S().row("SELECT last FROM bobbahotel_group_reads WHERE channel = ? AND key = ?", { channel, tostring(key) })
	local r = S().row("SELECT COUNT(*) AS n FROM bobbahotel_group_messages WHERE channel = ? AND id > ? AND key <> ?", { channel, tonumber(last and last.last) or 0, tostring(key) })
	return tonumber(r and r.n) or 0
end

function GR.listFor(key)
	local out = {}
	for _, r in ipairs(S().query("SELECT g.id AS id, g.name AS name, g.color AS color, m.rank AS rank FROM bobbahotel_group_members m JOIN bobbahotel_groups g ON g.id = m.grp WHERE m.key = ? ORDER BY m.joined", { tostring(key) })) do
		local n = 0
		for _, c in ipairs(channels(r.id)) do if c.kind == "text" then n = n + unread(c.id, key) end end
		local members = memberKeys(r.id)
		local on = 0
		for _, k in ipairs(members) do if online(k) then on = on + 1 end end
		out[#out + 1] = { id = tonumber(r.id), name = r.name, color = r.color, rank = tonumber(r.rank), unread = n, members = #members, online = on }
	end
	return out
end

function GR.info(id, key)
	local g = GR.get(id)
	if not g then return nil end
	local rank = GR.rank(id, key)
	local members = memberKeys(id)
	local on = 0
	for _, k in ipairs(members) do if online(k) then on = on + 1 end end
	local chans = {}
	for _, c in ipairs(channels(id)) do
		chans[#chans + 1] = { id = c.id, name = c.name, kind = c.kind, unread = (rank and c.kind == "text") and unread(c.id, key) or 0 }
	end
	local info = g.room > 0 and live.info(g.room)
	return {
		id = g.id, name = g.name, description = g.description, color = g.color, room = g.room > 0 and g.room or nil,
		roomName = info and info.name or nil, owner = g.owner, ownerName = BOBBA.friends.nameOf(g.owner), open = g.open,
		members = #members, online = on, rank = rank, channels = rank and chans or {},
		requested = S().row("SELECT 1 AS x FROM bobbahotel_group_requests WHERE grp = ? AND key = ?", { g.id, tostring(key) }) ~= nil,
	}
end

local function sendList(key)
	local p = online(key)
	if p then P().send("groups.list", { groups = GR.listFor(key), price = GR.price() }, p) end
end
local function sendInfo(id, key)
	local p = online(key)
	local info = GR.info(id, key)
	if p and info then P().send("groups.info", info, p) end
end
-- everyone in the group hears of a change (their lists, and the group's page)
local function changed(id, extra)
	for _, k in ipairs(memberKeys(id)) do sendList(k) sendInfo(id, k) end
	for _, k in ipairs(extra or {}) do sendList(k) sendInfo(id, k) end
end

-- a new group: its id, or false and why
function GR.create(key, data)
	local name = cleanText(data.name, 40)
	if (utf8 and utf8.len(name) or #name) < 3 then return false, "a group's name needs 3 letters" end
	local owned = S().row("SELECT COUNT(*) AS n FROM bobbahotel_groups WHERE owner = ?", { tostring(key) })
	if (tonumber(owned and owned.n) or 0) >= (tonumber(S().setting("groups.max.owned", tostring(GR.MAX_OWNED))) or GR.MAX_OWNED) then return false, "you have as many groups as you can" end
	local room = tonumber(data.room) or 0
	if room > 0 then
		local info = live.info(room)
		if not info or info.owner ~= tostring(key) then return false, "the group's room must be one of yours" end
	end
	local price = GR.price()
	if price > 0 and not BOBBA.wallet.pay(key, { credits = price }) then return false, "you need " .. price .. " credits to make a group" end
	local now = P().time()
	S().query("INSERT INTO bobbahotel_groups (name, description, color, owner, room, open, created) VALUES (?, ?, ?, ?, ?, ?, ?)",
		{ name, cleanText(data.description, 255), cleanColor(data.color), tostring(key), room, data.open == false and 0 or 1, now })
	local r = S().row("SELECT MAX(id) AS id FROM bobbahotel_groups WHERE owner = ?", { tostring(key) })
	local id = tonumber(r.id)
	S().query("INSERT INTO bobbahotel_group_members (grp, key, rank, joined) VALUES (?, ?, 2, ?)", { id, tostring(key), now })
	S().query("INSERT INTO bobbahotel_group_channels (grp, name, kind, pos) VALUES (?, 'general', 'text', 0)", { id })
	S().query("INSERT INTO bobbahotel_group_channels (grp, name, kind, pos) VALUES (?, 'Lounge', 'voice', 1)", { id })
	BOBBA.events.emit("groupCreated", id, key)
	return id
end

function GR.edit(key, data)
	local g = GR.get(data.id)
	if not g then return false, "no such group" end
	if (GR.rank(g.id, key) or -1) < 1 then return false, "only the group's admins can change it" end
	local name = data.name and cleanText(data.name, 40) or g.name
	if (utf8 and utf8.len(name) or #name) < 3 then return false, "a group's name needs 3 letters" end
	local room = data.room ~= nil and (tonumber(data.room) or 0) or g.room
	if room > 0 and room ~= g.room then
		local info = live.info(room)
		if not info or info.owner ~= g.owner then return false, "the group's room must be the owner's" end
	end
	local open = g.open
	if data.open ~= nil then open = data.open and true or false end
	S().query("UPDATE bobbahotel_groups SET name = ?, description = ?, color = ?, room = ?, open = ? WHERE id = ?",
		{ name, data.description and cleanText(data.description, 255) or g.description, data.color and cleanColor(data.color) or g.color, room, open and 1 or 0, g.id })
	return true
end

function GR.join(key, id)
	local g = GR.get(id)
	if not g then return false, "no such group" end
	if GR.rank(id, key) then return false, "you're in it already" end
	if not g.open then
		S().query("INSERT OR REPLACE INTO bobbahotel_group_requests (grp, key, at) VALUES (?, ?, ?)", { g.id, tostring(key), P().time() })
		return true, "asked"
	end
	S().query("INSERT INTO bobbahotel_group_members (grp, key, rank, joined) VALUES (?, ?, 0, ?)", { g.id, tostring(key), P().time() })
	return true, "joined"
end

function GR.accept(key, id, who)
	if (GR.rank(id, key) or -1) < 1 then return false, "only the group's admins can let people in" end
	if not S().row("SELECT 1 AS x FROM bobbahotel_group_requests WHERE grp = ? AND key = ?", { tonumber(id), tostring(who) }) then return false, "no request" end
	S().query("DELETE FROM bobbahotel_group_requests WHERE grp = ? AND key = ?", { tonumber(id), tostring(who) })
	S().query("INSERT OR IGNORE INTO bobbahotel_group_members (grp, key, rank, joined) VALUES (?, ?, 0, ?)", { tonumber(id), tostring(who), P().time() })
	return true
end

function GR.leave(key, id)
	local rank = GR.rank(id, key)
	if not rank then return false, "you're not in it" end
	if rank == 2 then return false, "the owner can't leave: delete the group instead" end
	S().query("DELETE FROM bobbahotel_group_members WHERE grp = ? AND key = ?", { tonumber(id), tostring(key) })
	return true
end

function GR.delete(key, id)
	local g = GR.get(id)
	if not g then return false, "no such group" end
	local pl = online(key)
	if g.owner ~= tostring(key) and not (pl and BOBBA.perms.has(pl, "bobba.staff.groups")) then return false, "only the owner can delete it" end
	local members = memberKeys(g.id)
	for _, c in ipairs(channels(g.id)) do
		S().query("DELETE FROM bobbahotel_group_messages WHERE channel = ?", { c.id })
		S().query("DELETE FROM bobbahotel_group_reads WHERE channel = ?", { c.id })
	end
	S().query("DELETE FROM bobbahotel_group_channels WHERE grp = ?", { g.id })
	S().query("DELETE FROM bobbahotel_group_members WHERE grp = ?", { g.id })
	S().query("DELETE FROM bobbahotel_group_requests WHERE grp = ?", { g.id })
	S().query("DELETE FROM bobbahotel_groups WHERE id = ?", { g.id })
	return true, members
end

-- the owner sets someone's rank (member or admin); an admin can remove members
function GR.setRank(key, id, who, rank)
	if GR.rank(id, key) ~= 2 then return false, "only the owner can do that" end
	local cur = GR.rank(id, who)
	if not cur or cur == 2 then return false, "they can't be changed" end
	S().query("UPDATE bobbahotel_group_members SET rank = ? WHERE grp = ? AND key = ?", { (tonumber(rank) or 0) >= 1 and 1 or 0, tonumber(id), tostring(who) })
	return true
end
function GR.kick(key, id, who)
	local mine, theirs = GR.rank(id, key) or -1, GR.rank(id, who)
	if mine < 1 or not theirs or theirs >= mine then return false, "you can't remove them" end
	S().query("DELETE FROM bobbahotel_group_members WHERE grp = ? AND key = ?", { tonumber(id), tostring(who) })
	return true
end

function GR.addChannel(key, id, name, kind)
	if (GR.rank(id, key) or -1) < 1 then return false, "only the group's admins can add channels" end
	name = cleanText(name, 30):gsub("%s+", "-")
	if kind ~= "voice" then name = name:lower() kind = "text" end
	if name == "" then return false, "a channel needs a name" end
	local n = S().row("SELECT COUNT(*) AS n, MAX(pos) AS pos FROM bobbahotel_group_channels WHERE grp = ?", { tonumber(id) })
	if (tonumber(n and n.n) or 0) >= GR.MAX_CHANNELS then return false, "that's as many channels as a group can have" end
	S().query("INSERT INTO bobbahotel_group_channels (grp, name, kind, pos) VALUES (?, ?, ?, ?)", { tonumber(id), name, kind, (tonumber(n and n.pos) or 0) + 1 })
	return true
end

local function channelOf(channel)
	local c = S().row("SELECT id, grp, name, kind FROM bobbahotel_group_channels WHERE id = ?", { tonumber(channel) or -1 })
	if c then c.id, c.grp = tonumber(c.id), tonumber(c.grp) end
	return c
end
GR.channelOf = channelOf

function GR.removeChannel(key, channel)
	local c = channelOf(channel)
	if not c then return false, "no such channel" end
	if (GR.rank(c.grp, key) or -1) < 1 then return false, "only the group's admins can remove channels" end
	local left = S().row("SELECT COUNT(*) AS n FROM bobbahotel_group_channels WHERE grp = ? AND kind = 'text'", { c.grp })
	if c.kind == "text" and (tonumber(left and left.n) or 0) <= 1 then return false, "a group keeps one text channel" end
	S().query("DELETE FROM bobbahotel_group_messages WHERE channel = ?", { c.id })
	S().query("DELETE FROM bobbahotel_group_reads WHERE channel = ?", { c.id })
	S().query("DELETE FROM bobbahotel_group_channels WHERE id = ?", { c.id })
	return true, c.grp
end

function GR.history(key, channel)
	local c = channelOf(channel)
	if not c or not GR.rank(c.grp, key) then return nil end
	local rows = S().query("SELECT id, key, name, text, at FROM bobbahotel_group_messages WHERE channel = ? ORDER BY id DESC LIMIT " .. GR.HISTORY, { c.id })
	local out = {}
	for i = #rows, 1, -1 do
		local r = rows[i]
		out[#out + 1] = { id = tonumber(r.id), key = r.key, name = r.name, text = r.text, at = tonumber(r.at) }
	end
	-- (their faces: one look each)
	local looks = {}
	for _, m in ipairs(out) do
		if not looks[m.key] then local f, g = BOBBA.looks.get(m.key) looks[m.key] = { f, g } end
		m.figure, m.gender = looks[m.key][1], looks[m.key][2]
	end
	return out, c
end

function GR.markRead(key, channel)
	local r = S().row("SELECT MAX(id) AS id FROM bobbahotel_group_messages WHERE channel = ?", { tonumber(channel) or -1 })
	S().query("INSERT OR REPLACE INTO bobbahotel_group_reads (channel, key, last) VALUES (?, ?, ?)", { tonumber(channel) or -1, tostring(key), tonumber(r and r.id) or 0 })
end

-- a message in a text channel: the message, the channel; or false and why
function GR.send(key, name, channel, text)
	local c = channelOf(channel)
	if not c then return false, "no such channel" end
	if c.kind ~= "text" then return false, "that's a voice channel" end
	if not GR.rank(c.grp, key) then return false, "you're not in the group" end
	text = cleanText(text, GR.TEXT_MAX)
	if text == "" then return false, "nothing to send" end
	local now = P().time()
	S().query("INSERT INTO bobbahotel_group_messages (channel, key, name, text, at) VALUES (?, ?, ?, ?, ?)", { c.id, tostring(key), tostring(name), text, now })
	local r = S().row("SELECT MAX(id) AS id FROM bobbahotel_group_messages WHERE channel = ?", { c.id })
	return { id = tonumber(r and r.id) or 0, key = tostring(key), name = tostring(name), text = text, at = now }, c
end

function GR.search(query)
	query = cleanText(query, 40):lower()
	local out = {}
	for _, r in ipairs(S().query("SELECT id, name, color, description, open FROM bobbahotel_groups ORDER BY id DESC LIMIT 500")) do
		if query == "" or r.name:lower():find(query, 1, true) then
			out[#out + 1] = { id = tonumber(r.id), name = r.name, color = r.color, description = r.description, open = tonumber(r.open) == 1, members = #memberKeys(r.id) }
			if #out >= 50 then break end
		end
	end
	table.sort(out, function(a, b) return a.members > b.members end)
	return out
end

-- the groups a room belongs to (the navigator's "group:" search)
function GR.roomsNamed(text)
	local out = {}
	for _, r in ipairs(S().query("SELECT room, name FROM bobbahotel_groups WHERE room > 0")) do
		if r.name:lower():find(tostring(text):lower(), 1, true) then out[tonumber(r.room)] = true end
	end
	return out
end

function GR.start()
	GR.migrate()
	BOBBA.perms.define("bobba.staff.groups", { default = "admin", description = "Delete any group" })
	local p = P()
	local function err(player, why) p.send("groups.error", { message = tostring(why) }, player) end
	BOBBA.events.on("playerReady", "bobba.groups", function(player) sendList(p.playerKey(player)) end)
	BOBBA.events.on("playerReset", "bobba.groups", function(key)
		for _, r in ipairs(S().query("SELECT id FROM bobbahotel_groups WHERE owner = ?", { tostring(key) })) do GR.delete(key, r.id) end
		S().query("DELETE FROM bobbahotel_group_members WHERE key = ?", { tostring(key) })
		S().query("DELETE FROM bobbahotel_group_requests WHERE key = ?", { tostring(key) })
	end)
	p.receive("groups.mine", function(player) p.send("groups.list", { groups = GR.listFor(p.playerKey(player)), price = GR.price() }, player) end)
	p.receive("groups.get", function(player, data)
		local info = GR.info(data.id, p.playerKey(player))
		if info then p.send("groups.info", info, player) else err(player, "no such group") end
	end)
	p.receive("groups.search", function(player, data)
		p.send("groups.results", { query = tostring(data.query or ""), groups = GR.search(data.query) }, player)
	end)
	p.receive("groups.create", function(player, data)
		local key = p.playerKey(player)
		local id, why = GR.create(key, data)
		if not id then return err(player, why) end
		p.send("groups.created", { id = id }, player)
		sendList(key)
		sendInfo(id, key)
	end)
	p.receive("groups.edit", function(player, data)
		local ok, why = GR.edit(p.playerKey(player), data)
		if not ok then return err(player, why) end
		changed(tonumber(data.id))
	end)
	p.receive("groups.join", function(player, data)
		local key = p.playerKey(player)
		local ok, how = GR.join(key, data.id)
		if not ok then return err(player, how) end
		if how == "asked" then
			-- (the admins see who's asking)
			for _, k in ipairs(memberKeys(data.id)) do
				if (GR.rank(data.id, k) or 0) >= 1 and online(k) then p.send("groups.asked", { id = tonumber(data.id), key = key, name = p.playerName(player) }, online(k)) end
			end
			sendInfo(tonumber(data.id), key)
			return
		end
		changed(tonumber(data.id))
	end)
	p.receive("groups.accept", function(player, data)
		local ok, why = GR.accept(p.playerKey(player), data.id, data.key)
		if not ok then return err(player, why) end
		changed(tonumber(data.id))
	end)
	p.receive("groups.leave", function(player, data)
		local key = p.playerKey(player)
		local ok, why = GR.leave(key, data.id)
		if not ok then return err(player, why) end
		changed(tonumber(data.id), { key })
	end)
	p.receive("groups.delete", function(player, data)
		local ok, members = GR.delete(p.playerKey(player), data.id)
		if not ok then return err(player, members) end
		for _, k in ipairs(members) do
			sendList(k)
			if online(k) then p.send("groups.deleted", { id = tonumber(data.id) }, online(k)) end
		end
	end)
	p.receive("groups.members", function(player, data)
		local key = p.playerKey(player)
		local id = tonumber(data.id) or -1
		if not GR.rank(id, key) then return err(player, "you're not in the group") end
		local list = {}
		for _, r in ipairs(S().query("SELECT m.key AS key, m.rank AS rank, u.name AS name FROM bobbahotel_group_members m LEFT JOIN bobbahotel_users u ON u.key = m.key WHERE m.grp = ? ORDER BY m.rank DESC, m.joined", { id })) do
			local figure, gender = BOBBA.looks.get(r.key)
			list[#list + 1] = { key = r.key, name = r.name or r.key, rank = tonumber(r.rank), online = online(r.key) ~= nil, figure = figure, gender = gender }
		end
		local requests = {}
		if (GR.rank(id, key) or 0) >= 1 then
			for _, r in ipairs(S().query("SELECT q.key AS key, u.name AS name FROM bobbahotel_group_requests q LEFT JOIN bobbahotel_users u ON u.key = q.key WHERE q.grp = ?", { id })) do
				requests[#requests + 1] = { key = r.key, name = r.name or r.key }
			end
		end
		p.send("groups.members", { id = id, members = list, requests = requests }, player)
	end)
	p.receive("groups.rank", function(player, data)
		local ok, why = GR.setRank(p.playerKey(player), data.id, data.key, data.rank)
		if not ok then return err(player, why) end
		changed(tonumber(data.id))
	end)
	p.receive("groups.kick", function(player, data)
		local ok, why = GR.kick(p.playerKey(player), data.id, data.key)
		if not ok then return err(player, why) end
		changed(tonumber(data.id), { tostring(data.key) })
	end)
	p.receive("groups.channel.add", function(player, data)
		local ok, why = GR.addChannel(p.playerKey(player), data.id, data.name, data.kind)
		if not ok then return err(player, why) end
		changed(tonumber(data.id))
	end)
	p.receive("groups.channel.remove", function(player, data)
		local ok, grp = GR.removeChannel(p.playerKey(player), data.channel)
		if not ok then return err(player, grp) end
		changed(grp)
	end)
	p.receive("groups.history", function(player, data)
		local key = p.playerKey(player)
		local list, c = GR.history(key, data.channel)
		if not list then return err(player, "you can't read that channel") end
		GR.markRead(key, c.id)
		p.send("groups.history", { channel = c.id, group = c.grp, messages = list }, player)
	end)
	p.receive("groups.read", function(player, data)
		local c = channelOf(data.channel)
		if c and GR.rank(c.grp, p.playerKey(player)) then GR.markRead(p.playerKey(player), c.id) end
	end)
	local sentAt = {}
	p.onLeave(function(player) sentAt[player] = nil end)
	p.receive("groups.send", function(player, data)
		local now = p.clock()
		local s = sentAt[player] or { t = now, n = 0 }
		if now - s.t > 5 then s = { t = now, n = 0 } end
		s.n = s.n + 1
		sentAt[player] = s
		if s.n > 8 then return err(player, "slow down a little") end
		local key = p.playerKey(player)
		local m, c = GR.send(key, p.playerName(player), data.channel, data.text)
		if not m then return err(player, c) end
		local figure, gender = BOBBA.looks.get(key)
		m.figure, m.gender = figure, gender
		for _, k in ipairs(memberKeys(c.grp)) do
			local o = online(k)
			if o then p.send("groups.message", { group = c.grp, channel = c.id, message = m }, o) end
		end
	end)
end
