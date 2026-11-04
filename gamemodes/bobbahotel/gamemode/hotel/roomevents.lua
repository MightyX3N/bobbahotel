-- Room events (server): Habbo's room events (the navigator's "Events"). A room's owner puts on an
-- event (a name, a few words, how long: up to events.max.hours, 3); while it's on, the room is in the
-- navigator's events and everyone online is told it started. One event per room at a time. Putting
-- one on costs events.price.credits (0).
--
-- Messages from players: events.list {}   events.create { room, name, description, hours }   events.end { room }
-- Messages to players:   events.list { events = { { room, roomName, owner, name, description, starts, ends, users, mine } } }
--                        events.started { room, roomName, name, owner }   events.error { message }

BOBBA.roomEvents = BOBBA.roomEvents or {}
local EV = BOBBA.roomEvents
local live = BOBBA.live

local function P() return BOBBA.platform end
local function S() return BOBBA.store end

function EV.migrate()
	BOBBA.store.migrate("core.024_room_events", {
		[[CREATE TABLE bobbahotel_room_events (
			room INTEGER PRIMARY KEY,
			owner TEXT NOT NULL,
			name TEXT NOT NULL,
			description TEXT NOT NULL DEFAULT '',
			starts INTEGER NOT NULL,
			ends INTEGER NOT NULL
		)]],
	})
end

function EV.maxHours() return math.max(1, tonumber(S().setting("events.max.hours", "3")) or 3) end
function EV.price() return math.max(0, tonumber(S().setting("events.price.credits", "0")) or 0) end

-- the events on now (the soonest to end last), and the ones that ended are taken away
function EV.current()
	local now = P().time()
	S().query("DELETE FROM bobbahotel_room_events WHERE ends <= ?", { now })
	local out = {}
	for _, r in ipairs(S().query("SELECT e.*, r.name AS room_name, r.owner_name AS owner_name, r.state AS state FROM bobbahotel_room_events e JOIN bobbahotel_rooms r ON r.id = e.room ORDER BY e.starts DESC")) do
		if tonumber(r.state) ~= 3 then
			local loaded = live.rooms[tonumber(r.room)]
			out[#out + 1] = { room = tonumber(r.room), roomName = r.room_name, owner = r.owner_name, ownerKey = r.owner, name = r.name, description = r.description,
				starts = tonumber(r.starts), ends = tonumber(r.ends), users = loaded and #loaded.order or 0 }
		end
	end
	return out
end

function EV.create(key, data)
	local room = tonumber(data.room) or -1
	local info = live.info(room)
	if not info or info.owner ~= tostring(key) then return false, "you can only put on an event in your own room" end
	local name = tostring(data.name or ""):gsub("[%z\1-\31]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 60)
	if #name < 3 then return false, "an event's name needs 3 letters" end
	local hours = math.Clamp and math.Clamp(math.floor(tonumber(data.hours) or 1), 1, EV.maxHours()) or math.max(1, math.min(EV.maxHours(), math.floor(tonumber(data.hours) or 1)))
	local price = EV.price()
	if price > 0 and not BOBBA.wallet.pay(key, { credits = price }, "room event") then return false, "you need " .. price .. " credits for an event" end
	local now = P().time()
	S().query("INSERT OR REPLACE INTO bobbahotel_room_events (room, owner, name, description, starts, ends) VALUES (?, ?, ?, ?, ?, ?)",
		{ room, tostring(key), name, tostring(data.description or ""):gsub("[%z\1-\9\11-\31]", ""):sub(1, 200), now, now + hours * 3600 })
	return true, { room = room, roomName = info.name, name = name, owner = info.owner_name }
end

function EV.stop(key, room)
	local r = S().row("SELECT owner FROM bobbahotel_room_events WHERE room = ?", { tonumber(room) or -1 })
	if not r then return false, "no event there" end
	if r.owner ~= tostring(key) then return false, "it's not your event" end
	S().query("DELETE FROM bobbahotel_room_events WHERE room = ?", { tonumber(room) })
	return true
end

-- the navigator's events view
function EV.navigatorBlocks(player)
	local rooms = {}
	local NAV = BOBBA.navigator
	for _, e in ipairs(EV.current()) do
		local row = S().row("SELECT * FROM bobbahotel_rooms WHERE id = ?", { e.room })
		if row then
			local d = NAV.roomData(row)
			d.event = { name = e.name, description = e.description, ends = e.ends }
			rooms[#rooms + 1] = d
		end
	end
	table.sort(rooms, function(a, b) return a.users > b.users end)
	return { { code = "top_promotions", rooms = rooms } }
end

function EV.start()
	EV.migrate()
	local p = P()
	local function list(player)
		local key = p.playerKey(player)
		local evs = EV.current()
		for _, e in ipairs(evs) do e.mine = e.ownerKey == key or nil e.ownerKey = nil end
		p.send("events.list", { events = evs, maxHours = EV.maxHours(), price = EV.price() }, player)
	end
	p.receive("events.list", list)
	p.receive("events.create", function(player, data)
		local ok, e = EV.create(p.playerKey(player), data)
		if not ok then p.send("events.error", { message = tostring(e) }, player) return end
		list(player)
		-- everyone here hears of it
		local F = BOBBA.friends
		for _, other in pairs(F and F.online or {}) do p.send("events.started", e, other) end
	end)
	p.receive("events.end", function(player, data)
		local ok, why = EV.stop(p.playerKey(player), data.room)
		if not ok then p.send("events.error", { message = tostring(why) }, player) return end
		list(player)
	end)
end
