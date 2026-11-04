-- Videos (server): a room's TV. Everyone in a room can add a video (a link from a service the hotel
-- allows: videos.services, "youtube" by default) to the room's queue; it plays for everyone in the room
-- at the same place in it; a vote of half the room skips it; the room's owner (and those with rights)
-- can skip or take one off at once, or turn the TV off for the room. The hotel can turn videos off
-- (videos.enabled 0). How long a video is, and its title, its player tells (the first to play it).
--
-- Messages from players: videos.get {}   videos.add { url }   videos.skip {}   videos.remove { id }
--                        videos.meta { id, title, duration }   videos.ended { id }   videos.room { on }
-- Messages to players:   videos.state { on, playing = { id, service, video, title, duration, startedAt, by, votes, need }
--                          , queue = { { id, service, video, title, by } }, now, watching, canManage }
--                        videos.error { message }

BOBBA.videos = BOBBA.videos or {}
local VI = BOBBA.videos
local live = BOBBA.live

VI.MAX_QUEUE = 30
VI.MAX_PER_PERSON = 3
VI.rooms = VI.rooms or {} -- room id -> { queue, playing, votes, off }
local nextId = 1

local function P() return BOBBA.platform end
local function S() return BOBBA.store end

function VI.enabled() return S().setting("videos.enabled", "1") ~= "0" end
function VI.services()
	local out = {}
	for s in (S().setting("videos.services", "youtube") or ""):gmatch("[%w_]+") do out[s:lower()] = true end
	return out
end

-- a link: the service and the video's id (nil when it's not one the hotel allows)
function VI.parse(url)
	url = tostring(url or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local id = url:match("youtu%.be/([%w_%-]+)") or url:match("youtube%.com/watch%?.-v=([%w_%-]+)") or url:match("youtube%.com/embed/([%w_%-]+)")
		or url:match("youtube%.com/shorts/([%w_%-]+)") or url:match("youtube%.com/live/([%w_%-]+)")
	if not id and url:match("^[%w_%-]+$") and #url == 11 then id = url end
	if id and #id >= 6 and #id <= 20 then return "youtube", id end
end

local function roomOf(player)
	local u = live.byPlayer[player]
	return u and u.room, u
end

local function tv(r)
	local t = VI.rooms[r.id]
	if not t then t = { queue = {}, votes = {} } VI.rooms[r.id] = t end
	return t
end

local function canManage(player, r)
	local info = live.info(r.id)
	return info and BOBBA.access.level(player, info) >= 1
end

local function people(r)
	local n = 0
	for _, id in ipairs(r.order) do if r.units[id].player then n = n + 1 end end
	return n
end

-- the state, as each one in the room sees it
local function stateFor(r, player)
	local t = tv(r)
	local votes = 0
	for _ in pairs(t.votes) do votes = votes + 1 end
	local playing
	if t.playing then
		local p = t.playing
		playing = { id = p.id, service = p.service, video = p.video, title = p.title, duration = p.duration, startedAt = p.startedAt, by = p.by,
			votes = votes, need = math.max(1, math.ceil(people(r) / 2)), voted = t.votes[P().playerKey(player)] or nil }
	end
	local queue = {}
	for _, q in ipairs(t.queue) do queue[#queue + 1] = { id = q.id, service = q.service, video = q.video, title = q.title, by = q.by } end
	return { on = VI.enabled() and not t.off, playing = playing, queue = queue, now = P().time(), watching = people(r), canManage = canManage(player, r) or nil }
end
VI.stateFor = stateFor

local function send(r)
	for _, pl in ipairs(live.players(r)) do P().send("videos.state", stateFor(r, pl), pl) end
end
VI.send = send

-- the next one starts (or nothing)
local function advance(r)
	local t = tv(r)
	t.votes = {}
	t.playing = table.remove(t.queue, 1)
	if t.playing then t.playing.startedAt = P().time() end
	send(r)
end
VI.advance = advance

function VI.add(player, url)
	if not VI.enabled() then return false, "videos are off in this hotel" end
	local r, u = roomOf(player)
	if not r then return false, "go into a room first" end
	local t = tv(r)
	if t.off then return false, "the room's TV is off" end
	local service, video = VI.parse(url)
	if not service then return false, "that isn't a link the TV can play" end
	if not VI.services()[service] then return false, "this hotel doesn't play " .. service end
	if #t.queue >= VI.MAX_QUEUE then return false, "the queue is full" end
	local mine = 0
	for _, q in ipairs(t.queue) do if q.key == u.key then mine = mine + 1 end end
	if mine >= VI.MAX_PER_PERSON and not canManage(player, r) then return false, "you have " .. VI.MAX_PER_PERSON .. " in the queue already" end
	local item = { id = nextId, service = service, video = video, title = nil, duration = nil, by = u.name, key = u.key }
	nextId = nextId + 1
	t.queue[#t.queue + 1] = item
	if not t.playing then advance(r) else send(r) end
	VI.fetchTitle(r, item)
	return true, item
end

-- its title, asked of YouTube (oEmbed) as it's added, so the queue has names before anyone plays it
function VI.fetchTitle(r, item)
	if item.service ~= "youtube" or not (http and http.Fetch) or not (util and util.JSONToTable) then return end
	http.Fetch("https://www.youtube.com/oembed?format=json&url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D" .. item.video, function(body)
		local ok, data = pcall(util.JSONToTable, body or "")
		if not ok or type(data) ~= "table" or type(data.title) ~= "string" or item.title then return end
		item.title = data.title:gsub("[%z\1-\31]", ""):sub(1, 120)
		if VI.rooms[r.id] then send(r) end
	end, function() end)
end

function VI.skip(player)
	local r, u = roomOf(player)
	if not r then return false end
	local t = tv(r)
	if not t.playing then return false, "nothing's playing" end
	-- (the one who added it, and those with rights, skip at once)
	if t.playing.key == u.key or canManage(player, r) then advance(r) return true end
	t.votes[u.key] = true
	local votes = 0
	for k in pairs(t.votes) do votes = votes + 1 end
	if votes >= math.max(1, math.ceil(people(r) / 2)) then advance(r) else send(r) end
	return true
end

function VI.remove(player, id)
	local r, u = roomOf(player)
	if not r then return false end
	local t = tv(r)
	for i, q in ipairs(t.queue) do
		if q.id == tonumber(id) then
			if q.key ~= u.key and not canManage(player, r) then return false, "only the one who added it, or the room's owner" end
			table.remove(t.queue, i)
			send(r)
			return true
		end
	end
	return false, "not in the queue"
end

-- a player's video player says how long it is and what it's called (the first one counts)
function VI.meta(player, data)
	local r = roomOf(player)
	if not r then return end
	local t = tv(r)
	local function set(item)
		if not item or item.id ~= tonumber(data.id) then return false end
		if not item.title and type(data.title) == "string" then item.title = data.title:gsub("[%z\1-\31]", ""):sub(1, 120) end
		local d = tonumber(data.duration)
		if not item.duration and d and d > 0 and d < 24 * 3600 then item.duration = math.floor(d) end
		return true
	end
	if set(t.playing) then send(r) return end
	for _, q in ipairs(t.queue) do if set(q) then send(r) return end end
end

-- one has ended (a player says so, or its time is up)
function VI.ended(player, id)
	local r = roomOf(player)
	if not r then return end
	local t = tv(r)
	local p = t.playing
	if not p or p.id ~= tonumber(id) then return end
	local played = P().time() - (p.startedAt or 0)
	-- (only when it really has had its time: a player can't skip it for everyone by saying so early)
	if p.duration and played < p.duration - 5 then return end
	if not p.duration and played < 10 then return end
	advance(r)
end

function VI.tick()
	local now = P().time()
	for id, t in pairs(VI.rooms) do
		local r = live.rooms[id]
		if not r then
			VI.rooms[id] = nil
		elseif t.playing and t.playing.duration and now - t.playing.startedAt > t.playing.duration + 3 then
			advance(r)
		end
	end
end

function VI.setRoom(player, on)
	local r = roomOf(player)
	if not r then return false end
	local info = live.info(r.id)
	if not info or BOBBA.access.level(player, info) < 4 then return false, "only the room's owner can turn the TV off or on" end
	local t = tv(r)
	t.off = not on or nil
	if t.off then t.queue, t.playing, t.votes = {}, nil, {} end
	send(r)
	return true
end

function VI.start()
	local p = P()
	local function err(player, why) if why then p.send("videos.error", { message = tostring(why) }, player) end end
	p.receive("videos.get", function(player)
		local r = roomOf(player)
		if r then p.send("videos.state", stateFor(r, player), player) end
	end)
	p.receive("videos.add", function(player, data) local ok, why = VI.add(player, data.url) if not ok then err(player, why) end end)
	p.receive("videos.skip", function(player) local ok, why = VI.skip(player) if not ok then err(player, why) end end)
	p.receive("videos.remove", function(player, data) local ok, why = VI.remove(player, data.id) if not ok then err(player, why) end end)
	p.receive("videos.meta", function(player, data) VI.meta(player, data) end)
	p.receive("videos.ended", function(player, data) VI.ended(player, data.id) end)
	p.receive("videos.room", function(player, data) local ok, why = VI.setRoom(player, data.on) if not ok then err(player, why) end end)
	-- coming into a room: what's on its TV
	BOBBA.events.on("roomEntered", "bobba.videos", function(r, u)
		if u.player and VI.rooms[r.id] then p.send("videos.state", stateFor(r, u.player), u.player) end
	end)
	-- leaving: their vote goes
	BOBBA.events.on("roomLeft", "bobba.videos", function(r, u)
		local t = VI.rooms[r.id]
		if t and t.votes[u.key] then t.votes[u.key] = nil send(r) end
	end)
	p.every("bobba.videos", 1, VI.tick)
end
