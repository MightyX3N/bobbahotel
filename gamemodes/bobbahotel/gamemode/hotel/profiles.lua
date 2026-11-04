-- Players' profiles (server): Habbo's extended profile - name, look, motto, since when, when last
-- here, friends and relationships, groups - and finding people by name (the friend list's search).
-- The motto shows in the room's infostand too, and is changed there.
--
-- Messages from players: user.profile { key } (or { name })   user.motto { text }   users.search { query }
-- Messages to players:   user.profile { key, name, figure, gender, motto, since, seen, online, friends,
--                          isFriend, requestSent, me, groups = { { id, name, color, rank } },
--                          relationships = { heart = { count, name, figure, gender }, smile = ..., bobba = ... } }
--                        users.results { query, friends = { { key, name, online, figure, gender } }, others = {...} }

BOBBA.profiles = BOBBA.profiles or {}
local PR = BOBBA.profiles
local live = BOBBA.live

PR.MOTTO_MAX = 38
PR.SEARCH_MAX = 50
PR.REL = { [1] = "heart", [2] = "smile", [3] = "bobba" }

local function P() return BOBBA.platform end
local function S() return BOBBA.store end

function PR.migrate()
	S().migrate("core.025_profiles", {
		"ALTER TABLE bobbahotel_users ADD COLUMN since INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_users ADD COLUMN motto TEXT NOT NULL DEFAULT ''",
		"ALTER TABLE bobbahotel_friends ADD COLUMN rel INTEGER NOT NULL DEFAULT 0",
	})
end

function PR.motto(key)
	local r = S().row("SELECT motto FROM bobbahotel_users WHERE key = ?", { tostring(key) })
	return r and r.motto or ""
end

function PR.setMotto(key, text)
	text = tostring(text or ""):gsub("[%z\1-\31]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if (utf8 and utf8.len(text) or #text) > PR.MOTTO_MAX then
		text = utf8 and utf8.offset and text:sub(1, (utf8.offset(text, PR.MOTTO_MAX + 1) or (#text + 1)) - 1) or text:sub(1, PR.MOTTO_MAX)
	end
	S().query("UPDATE bobbahotel_users SET motto = ? WHERE key = ?", { text, tostring(key) })
	-- (whoever sees them in a room sees it at once)
	local p = BOBBA.friends and BOBBA.friends.online[tostring(key)]
	local u = p and live.byPlayer[p]
	if u then
		u.motto = text
		if u.room then for _, other in ipairs(live.players(u.room)) do P().send("room.units", { live.snapshot(u) }, other) end end
	end
	return text
end

-- what a profile shows; viewer: who's looking
function PR.profile(viewer, key)
	key = tostring(key)
	local row = S().row("SELECT key, name, seen, since, motto FROM bobbahotel_users WHERE key = ?", { key })
	if not row then return nil end
	local F, GR = BOBBA.friends, BOBBA.groups
	local figure, gender = BOBBA.looks.get(key)
	local friends = S().row("SELECT COUNT(*) AS n FROM bobbahotel_friends WHERE a = ?", { key })
	local groups = {}
	for _, g in ipairs(GR and GR.listFor(key) or {}) do groups[#groups + 1] = { id = g.id, name = g.name, color = g.color, rank = g.rank } end
	-- the relationships they've set: how many of each, and one of them (Habbo shows one at random)
	local rels = {}
	for n, name in pairs(PR.REL) do
		local rows = S().query("SELECT f.b AS key, u.name AS name FROM bobbahotel_friends f LEFT JOIN bobbahotel_users u ON u.key = f.b WHERE f.a = ? AND f.rel = ?", { key, n })
		if #rows > 0 then
			local pick = rows[math.random(1, #rows)]
			local fig, gen = BOBBA.looks.get(pick.key)
			rels[name] = { count = #rows, key = pick.key, name = pick.name or pick.key, figure = fig, gender = gen }
		end
	end
	viewer = tostring(viewer)
	return {
		key = key, name = row.name, figure = figure, gender = gender, motto = row.motto or "",
		since = tonumber(row.since) or 0, seen = tonumber(row.seen) or 0, online = F and F.online[key] ~= nil or false,
		friends = tonumber(friends and friends.n) or 0, groups = groups, relationships = rels,
		me = viewer == key, isFriend = F and F.areFriends(viewer, key) or false,
		requestSent = S().row("SELECT 1 AS x FROM bobbahotel_friend_requests WHERE sender = ? AND target = ?", { viewer, key }) ~= nil,
		now = P().time(),
	}
end

-- people whose name has the words in it: friends first, then the others
function PR.search(viewer, query)
	query = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
	if query == "" then return {}, {} end
	local like = "%" .. query:gsub("[%%_]", "") .. "%"
	local friends, others = {}, {}
	local F = BOBBA.friends
	for _, r in ipairs(S().query("SELECT key, name FROM bobbahotel_users WHERE lower(name) LIKE ? AND key <> ? ORDER BY seen DESC LIMIT " .. PR.SEARCH_MAX, { like, tostring(viewer) })) do
		local figure, gender = BOBBA.looks.get(r.key)
		local e = { key = r.key, name = r.name, online = F and F.online[r.key] ~= nil or false, figure = figure, gender = gender }
		if F and F.areFriends(viewer, r.key) then friends[#friends + 1] = e else others[#others + 1] = e end
	end
	return friends, others
end

function PR.start()
	PR.migrate()
	local p = P()
	-- (since when: the first time they're seen)
	BOBBA.events.on("playerReady", "bobba.profiles", function(player)
		S().query("UPDATE bobbahotel_users SET since = ? WHERE key = ? AND since = 0", { p.time(), p.playerKey(player) })
	end)
	p.receive("user.profile", function(player, data)
		local key = data.key and tostring(data.key) or nil
		if not key and data.name then key = BOBBA.gifts.findUser(data.name) end
		local prof = key and PR.profile(p.playerKey(player), key)
		if prof then p.send("user.profile", prof, player) end
	end)
	p.receive("user.motto", function(player, data) PR.setMotto(p.playerKey(player), data.text) end)
	local searchedAt = {}
	p.onLeave(function(player) searchedAt[player] = nil end)
	p.receive("users.search", function(player, data)
		local now = p.clock()
		if searchedAt[player] and now - searchedAt[player] < 0.3 then return end
		searchedAt[player] = now
		local friends, others = PR.search(p.playerKey(player), data.query)
		p.send("users.results", { query = tostring(data.query or ""), friends = friends, others = others }, player)
	end)
end
