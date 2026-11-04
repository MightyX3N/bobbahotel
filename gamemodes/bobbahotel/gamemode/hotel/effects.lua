-- Avatar effects and the wardrobe (server), as Arcturus's EffectsComponent and WardrobeComponent.
--
-- Effects: a player owns effects (Habbo's numbers: 1 Spotlight, 2 Hoverboard, ... the effect map
-- says which picture library each is). One has a time (a day unless said otherwise; 0 = for ever) and
-- a count: wearing it starts its time; when the time is up one is used and the next waits. Wearing
-- one shows it on the avatar to everyone in the room.
--   BOBBA.effects.give(key, effect, seconds)    (seconds: 86400 by default, 0 = for ever)
--   bobba_give <player> effect <id> [days]
-- Messages from players: effects.get {}  effects.enable { id }   (0 = none)
-- Messages to players:   effects.list { effects = { { type, duration, total, secondsLeft, permanent }, ... }, enabled }
--                        effects.expired { type }
--                        room.unit.effect { id, effect }   (units carry effect in their snapshot)
--
-- The wardrobe: ten saved looks per player (nitro-react's avatar.wardrobe.max.slots).
-- Messages from players: wardrobe.get {}  wardrobe.save { slot, figure, gender }
-- Messages to players:   wardrobe.list { looks = { [slot] = { figure, gender } } }

BOBBA.effects = BOBBA.effects or { enabled = {} }
local E = BOBBA.effects
local live = BOBBA.live

E.DEFAULT_DURATION = 86400
E.MAX_TOTAL = 99
E.WARDROBE_SLOTS = 10

local function P() return BOBBA.platform end
local function now() return math.floor(P().time()) end

function E.migrate()
	BOBBA.store.migrate("core.019_effects_wardrobe", {
		[[CREATE TABLE bobbahotel_effects (
			key TEXT NOT NULL,
			effect INTEGER NOT NULL,
			duration INTEGER NOT NULL DEFAULT 86400,
			activated INTEGER NOT NULL DEFAULT -1,
			total INTEGER NOT NULL DEFAULT 1,
			PRIMARY KEY (key, effect)
		)]],
		[[CREATE TABLE bobbahotel_wardrobe (
			key TEXT NOT NULL,
			slot INTEGER NOT NULL,
			figure TEXT NOT NULL,
			gender TEXT NOT NULL,
			PRIMARY KEY (key, slot)
		)]],
	})
end

local function row(key, id)
	local r = BOBBA.store.row("SELECT * FROM bobbahotel_effects WHERE key = ? AND effect = ?", { tostring(key), tonumber(id) or -1 })
	if not r then return nil end
	return { key = r.key, effect = tonumber(r.effect), duration = tonumber(r.duration) or 0, activated = tonumber(r.activated) or -1, total = tonumber(r.total) or 1 }
end

local function save(e)
	BOBBA.store.query("UPDATE bobbahotel_effects SET duration = ?, activated = ?, total = ? WHERE key = ? AND effect = ?", { e.duration, e.activated, e.total, e.key, e.effect })
end

-- HabboEffect.isRemaining: a used-up one counts down; none left, it's gone (false)
local function remaining(e)
	if e.duration <= 0 then return true end
	if e.total > 0 and e.activated >= 0 and now() - e.activated >= e.duration then
		e.activated = -1
		e.total = e.total - 1
		if e.total > 0 then save(e) end
	end
	if e.total <= 0 then
		BOBBA.store.query("DELETE FROM bobbahotel_effects WHERE key = ? AND effect = ?", { e.key, e.effect })
		return false
	end
	return true
end

local function secondsLeft(e)
	if e.duration <= 0 then return -1 end
	if e.activated < 0 then return 0 end
	return math.max(0, e.duration - (now() - e.activated))
end

-- the player's effects (used-up ones are taken away first)
function E.list(key)
	local out = {}
	for _, r in ipairs(BOBBA.store.query("SELECT effect FROM bobbahotel_effects WHERE key = ? ORDER BY effect", { tostring(key) })) do
		local e = row(key, r.effect)
		if e and remaining(e) then
			out[#out + 1] = { type = e.effect, duration = e.duration, total = e.total, secondsLeft = secondsLeft(e), permanent = e.duration <= 0 }
		end
	end
	return out
end

function E.owns(key, id)
	local e = row(key, id)
	return e ~= nil and remaining(e)
end

-- EffectsComponent.createEffect: one more (up to 99), or a new one
function E.give(key, id, seconds)
	id = math.floor(tonumber(id) or 0)
	if id <= 0 or id > 10000 then return false, "no such effect" end
	seconds = math.floor(tonumber(seconds) or E.DEFAULT_DURATION)
	local e = row(key, id)
	if e then
		if e.total < E.MAX_TOTAL then e.total = e.total + 1 end
		save(e)
	else
		BOBBA.store.query("INSERT INTO bobbahotel_effects (key, effect, duration, activated, total) VALUES (?, ?, ?, -1, 1)", { tostring(key), id, seconds })
	end
	local p = E.playerFor(key)
	if p then E.sendList(p) end
	return true
end

function E.playerFor(key)
	for _, u in pairs(live.byPlayer) do
		if u.key == key then return u.player end
	end
	return nil
end

function E.sendList(player)
	local key = P().playerKey(player)
	P().send("effects.list", { effects = E.list(key), enabled = E.enabled[key] or 0 }, player)
end

local function broadcast(r, name, data)
	local list = {}
	for _, id in ipairs(r.order) do
		local u = r.units[id]
		if u.player then list[#list + 1] = u.player end
	end
	if #list > 0 then P().send(name, data, list) end
end

-- what the avatar shows (Room.giveEffect)
function E.show(u, id)
	id = tonumber(id) or 0
	if (u.effect or 0) == id then return end
	u.effect = id
	if u.room then broadcast(u.room, "room.unit.effect", { id = u.id, effect = id }) end
end

-- EnableEffectEvent: wear one (its time starts if it hadn't), or none (0)
function E.enable(player, id)
	local key = P().playerKey(player)
	id = math.floor(tonumber(id) or 0)
	local u = live.byPlayer[player]
	if id <= 0 then
		E.enabled[key] = nil
		if u then E.show(u, 0) end
		E.sendList(player)
		return true
	end
	local e = row(key, id)
	if not e or not remaining(e) then E.sendList(player) return false, "you don't have that effect" end
	if e.duration > 0 and e.activated < 0 then
		e.activated = now()
		save(e)
	end
	E.enabled[key] = id
	if u then E.show(u, id) end
	E.sendList(player)
	return true
end

-- every few seconds: worn effects whose time is up come off
function E.tick()
	for player, u in pairs(live.byPlayer) do
		local id = E.enabled[u.key]
		if id then
			local e = row(u.key, id)
			local stillOn = e and e.duration <= 0
			if e and e.duration > 0 then
				local wasActive = e.activated >= 0 and now() - e.activated < e.duration
				stillOn = wasActive
				if not wasActive then remaining(e) end
			end
			if not stillOn then
				E.enabled[u.key] = nil
				E.show(u, 0)
				P().send("effects.expired", { type = id }, player)
				E.sendList(player)
			end
		end
	end
end

-- --- the wardrobe ---------------------------------------------------------------------------------------
function E.wardrobe(key)
	local out = {}
	for _, r in ipairs(BOBBA.store.query("SELECT slot, figure, gender FROM bobbahotel_wardrobe WHERE key = ? ORDER BY slot", { tostring(key) })) do
		out[tonumber(r.slot)] = { figure = r.figure, gender = r.gender }
	end
	return out
end

function E.saveLook(key, slot, figure, gender)
	slot = math.floor(tonumber(slot) or 0)
	if slot < 1 or slot > E.WARDROBE_SLOTS then return false, "no such wardrobe slot" end
	gender = BOBBA.looks.gender(gender)
	if not BOBBA.looks.parse(figure) then return false, "that isn't a look" end
	-- (cleaned the way a look being worn is: clothes that can't be worn are swapped)
	local v = BOBBA.looks.validator
	if v then
		local clean = v(figure, gender)
		if not clean then return false, "that isn't a look" end
		figure = clean
	end
	BOBBA.store.query("DELETE FROM bobbahotel_wardrobe WHERE key = ? AND slot = ?", { tostring(key), slot })
	BOBBA.store.query("INSERT INTO bobbahotel_wardrobe (key, slot, figure, gender) VALUES (?, ?, ?, ?)", { tostring(key), slot, figure, gender })
	return true
end

function E.start()
	E.migrate()
	local p = P()
	p.receive("effects.get", function(player) E.sendList(player) end)
	p.receive("effects.enable", function(player, data)
		local ok, why = E.enable(player, data.id)
		if not ok and why then p.send("room.error", { message = why }, player) end
	end)
	p.receive("wardrobe.get", function(player)
		local looks = {}
		for slot, l in pairs(E.wardrobe(p.playerKey(player))) do looks[tostring(slot)] = l end
		p.send("wardrobe.list", { looks = looks, slots = E.WARDROBE_SLOTS }, player)
	end)
	p.receive("wardrobe.save", function(player, data)
		local ok, why = E.saveLook(p.playerKey(player), data.slot, data.figure, data.gender)
		if not ok then p.send("room.error", { message = why }, player) return end
		local looks = {}
		for slot, l in pairs(E.wardrobe(p.playerKey(player))) do looks[tostring(slot)] = l end
		p.send("wardrobe.list", { looks = looks, slots = E.WARDROBE_SLOTS }, player)
	end)
	-- coming into a room with an effect on: it's shown
	BOBBA.events.on("roomEntered", "bobba.effects", function(_, u)
		local id = u.key and E.enabled[u.key]
		if id and E.owns(u.key, id) then E.show(u, id) end
	end)
	p.onLeave(function(player) E.enabled[p.playerKey(player)] = nil end)
	p.every("effects.tick", 5, E.tick)
end
