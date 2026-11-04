-- What avatars do besides walking and talking (server), as Arcturus does it: dancing, waving and the
-- other expressions, holding up a sign, sitting down on the floor and standing up, and falling asleep
-- (idle) after a while of doing nothing.
--
-- Messages from players: room.dance { style }       0 stop, 1 the dance, 2-4 Habbo Club's dances
--                        room.expression { id }     1 wave, 2 blow a kiss, 3 laugh (2 and 3: VIP), 5 idle
--                        room.sign { id }           0-17 (Nitro's sign menu)
--                        room.posture { sit }       sit on the floor / stand up
-- Messages to players:   room.unit.dance { id, dance }   room.unit.expression { id, expression }
--                        room.unit.sign { id, sign }     room.unit.idle { id, idle }
--                        (and room.units for sitting, with posture "sit", height 0.5)
-- Units carry dance and idle in their snapshot (roomlive.lua).

BOBBA.actions = BOBBA.actions or {}
local AC = BOBBA.actions
local live = BOBBA.live

AC.EXPRESSIONS = { [1] = "wave", [2] = "blow", [3] = "laugh", [5] = "idle" }
AC.VIP_EXPRESSIONS = { [2] = true, [3] = true }
AC.MAX_SIGN = 17
AC.FLOOR_SIT = 0.5 -- Arcturus's "sit 0.5" on the floor

local function P() return BOBBA.platform end

local function players(r)
	local out = {}
	for _, id in ipairs(r.order) do
		local u = r.units[id]
		if u.player then out[#out + 1] = u.player end
	end
	return out
end
local function broadcast(r, name, data)
	local list = players(r)
	if #list > 0 then P().send(name, data, list) end
end

local function clubLevel(u)
	return (u.key and BOBBA.wallet and BOBBA.wallet.clubLevel(u.key)) or 0
end

-- seconds of doing nothing before an avatar falls asleep (Arcturus: 240 room cycles, 2 minutes); 0 = never
function AC.idleAfter()
	return tonumber(BOBBA.store.setting("rooms.idle.seconds", "120")) or 120
end

-- awake (Room.unIdle): on any action
function AC.active(u)
	u.lastActive = P().clock()
	if u.idle then
		u.idle = false
		if u.room then broadcast(u.room, "room.unit.idle", { id = u.id, idle = false }) end
	end
end

function AC.setIdle(u)
	if u.idle then return end
	u.idle = true
	-- (asleep: no more dancing)
	if (u.dance or 0) > 0 then AC.dance(u, 0) end
	if u.room then broadcast(u.room, "room.unit.idle", { id = u.id, idle = true }) end
end

-- Room.dance: everyone sees it (and only if it changed)
function AC.dance(u, style)
	style = math.floor(tonumber(style) or 0)
	if style < 0 or style > 4 then return false end
	if (u.dance or 0) == style then return true end
	u.dance = style
	if u.room then broadcast(u.room, "room.unit.dance", { id = u.id, dance = style }) end
	return true
end

-- a player's dance: Habbo Club's dances (2-4) for members (Nitro only offers them to members)
function AC.playerDance(u, style)
	style = math.floor(tonumber(style) or -1)
	if style < 0 or style > 4 then return false, "no such dance" end
	if style > 1 and clubLevel(u) < 1 then return false, "that dance is for Habbo Club members" end
	-- (dancing on a seat: no; Habbo stands you up only by walking)
	if style > 0 and (u.posture == "sit" or u.posture == "lay") then return false, "sit or lie down first" end
	AC.active(u)
	return AC.dance(u, style)
end

function AC.expression(u, id)
	id = math.floor(tonumber(id) or 0)
	if not AC.EXPRESSIONS[id] then return false, "no such expression" end
	if id == 5 then AC.setIdle(u) return true end
	if AC.VIP_EXPRESSIONS[id] and clubLevel(u) < 2 then return false, "that's for VIP members" end
	-- (lying down: no waving; Nitro's GetCanUseExpression)
	if u.posture == "lay" then return false, "not while lying down" end
	AC.active(u)
	broadcast(u.room, "room.unit.expression", { id = u.id, expression = id })
	return true
end

function AC.sign(u, id)
	id = math.floor(tonumber(id) or -1)
	if id < 0 or id > AC.MAX_SIGN then return false, "no such sign" end
	AC.active(u)
	broadcast(u.room, "room.unit.sign", { id = u.id, sign = id })
	BOBBA.events.emit("unitSign", u.room, u, id)
	return true
end

-- Room.makeSit / makeStand: on the floor, turned to a straight direction; walking stands you up
function AC.sit(u)
	if u.posture == "sit" or u.posture == "lay" or u.teleporting then return false end
	if u.px then live.freeStop(u) end
	u.path, u.goal, u.useOnArrive = nil, nil, nil
	if (u.dance or 0) > 0 then AC.dance(u, 0) end
	u.cmdSit = true
	u.posture, u.height = "sit", AC.FLOOR_SIT
	u.dir = u.dir - u.dir % 2
	AC.active(u)
	broadcast(u.room, "room.units", { live.snapshot(u) })
	return true
end

function AC.stand(u)
	if not u.cmdSit then return false end
	u.cmdSit = nil
	u.dir = u.dir - u.dir % 2
	if not BOBBA.items.settle(u.room, u) then u.posture, u.height = nil, nil end
	AC.active(u)
	broadcast(u.room, "room.units", { live.snapshot(u) })
	return true
end

-- every room tick: who has been doing nothing long enough falls asleep
function AC.tick()
	local after = AC.idleAfter()
	if after <= 0 then return end
	local now = P().clock()
	for _, r in pairs(live.rooms) do
		for _, id in ipairs(r.order) do
			local u = r.units[id]
			if u.player and not u.idle and (u.dance or 0) == 0 then
				u.lastActive = u.lastActive or now
				if now - u.lastActive >= after then AC.setIdle(u) end
			end
		end
	end
end

function AC.start()
	local p = P()
	local function unit(player) return live.byPlayer[player] end
	local function err(player, why) if why then p.send("room.error", { message = tostring(why) }, player) end end
	-- (at most 10 a second each)
	local rate = {}
	p.onLeave(function(player) rate[player] = nil end)
	local function limited(player)
		local now = p.clock()
		local r = rate[player]
		if not r or now - r.t >= 1 then r = { t = now, n = 0 } rate[player] = r end
		r.n = r.n + 1
		return r.n > 10
	end
	p.receive("room.dance", function(player, data)
		local u = unit(player)
		if not u or limited(player) then return end
		local ok, why = AC.playerDance(u, data.style)
		if not ok then err(player, why) end
	end)
	p.receive("room.expression", function(player, data)
		local u = unit(player)
		if not u or limited(player) then return end
		local ok, why = AC.expression(u, data.id)
		if not ok then err(player, why) end
	end)
	p.receive("room.sign", function(player, data)
		local u = unit(player)
		if not u or limited(player) then return end
		AC.sign(u, data.id)
	end)
	p.receive("room.posture", function(player, data)
		local u = unit(player)
		if not u or limited(player) then return end
		if data.sit then AC.sit(u) else AC.stand(u) end
	end)
	-- awake: walking, talking
	BOBBA.events.on("unitStepped", "bobba.actions", function(_, u) AC.active(u) end)
	BOBBA.events.on("roomChat", "bobba.actions", function(_, u) AC.active(u) end)
	BOBBA.events.on("roomEntered", "bobba.actions", function(_, u) u.lastActive = p.clock() end)
	p.every("rooms.idle", 1, AC.tick)
end
