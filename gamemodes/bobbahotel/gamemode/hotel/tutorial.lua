-- The new player's tutorial (server): after picking a starter room, four small steps in it, each
-- done by doing it: walk somewhere, open the gift, move or turn a furni, say something. Done, a
-- small reward (tutorial.reward.credits, 50 by default; 0 for none). It can be skipped.
--
-- Messages to players:   tutorial.step { step, steps, done, reward }   (step 1..4; done: finished)
--                        tutorial.done { reward }
-- Messages from players: tutorial.skip {}

BOBBA.tutorial = BOBBA.tutorial or {}
local TU = BOBBA.tutorial
local live = BOBBA.live

TU.STEPS = { "walk", "gift", "move", "chat" }

local function P() return BOBBA.platform end

function TU.migrate()
	BOBBA.store.migrate("core.021_tutorial", {
		[[CREATE TABLE bobbahotel_tutorial (
			key TEXT PRIMARY KEY,
			step INTEGER NOT NULL DEFAULT 1,
			done INTEGER NOT NULL DEFAULT 0
		)]],
	})
end

function TU.reward()
	return math.max(0, tonumber(BOBBA.store.setting("tutorial.reward.credits", "50")) or 50)
end

-- where someone is: nil (no tutorial), or { step, done }
function TU.state(key)
	local r = BOBBA.store.row("SELECT step, done FROM bobbahotel_tutorial WHERE key = ?", { tostring(key) })
	if not r then return nil end
	return { step = tonumber(r.step) or 1, done = tonumber(r.done) == 1 }
end

local function send(player, st)
	P().send("tutorial.step", { step = st.step, steps = #TU.STEPS, name = TU.STEPS[st.step], done = st.done, reward = TU.reward() }, player)
end

function TU.begin(key)
	BOBBA.store.query("DELETE FROM bobbahotel_tutorial WHERE key = ?", { tostring(key) })
	BOBBA.store.query("INSERT INTO bobbahotel_tutorial (key, step, done) VALUES (?, 1, 0)", { tostring(key) })
end

local function finish(player, key, rewarded)
	BOBBA.store.query("UPDATE bobbahotel_tutorial SET done = 1 WHERE key = ?", { tostring(key) })
	local reward = rewarded and TU.reward() or 0
	if reward > 0 then BOBBA.wallet.add(key, "credits", reward, "tutorial") end
	if player then P().send("tutorial.done", { reward = reward }, player) end
end

-- something done: the step it is moves on (only in the step's order)
function TU.did(player, what)
	if not player then return end
	local key = P().playerKey(player)
	local st = TU.state(key)
	if not st or st.done or TU.STEPS[st.step] ~= what then return end
	st.step = st.step + 1
	if st.step > #TU.STEPS then
		finish(player, key, true)
		return
	end
	BOBBA.store.query("UPDATE bobbahotel_tutorial SET step = ? WHERE key = ?", { st.step, tostring(key) })
	send(player, st)
end

function TU.start()
	TU.migrate()
	local p = P()
	-- a starter room chosen: the tutorial starts (shown once they're in it)
	BOBBA.events.on("starterRoomCreated", "bobba.tutorial", function(key) TU.begin(key) end)
	BOBBA.events.on("roomEntered", "bobba.tutorial", function(_, u)
		if not u.player then return end
		local st = TU.state(u.key)
		if st and not st.done then send(u.player, st) end
	end)
	BOBBA.events.on("unitStepped", "bobba.tutorial", function(_, u) TU.did(u.player, "walk") end)
	BOBBA.events.on("giftOpened", "bobba.tutorial", function(_, player) TU.did(player, "gift") end)
	BOBBA.events.on("itemMoved", "bobba.tutorial", function(_, _, player) TU.did(player, "move") end)
	BOBBA.events.on("roomChat", "bobba.tutorial", function(_, u) TU.did(u.player, "chat") end)
	p.receive("tutorial.skip", function(player)
		local key = p.playerKey(player)
		local st = TU.state(key)
		if st and not st.done then finish(player, key, false) end
	end)
end
