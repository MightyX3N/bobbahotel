-- Wired (server): Habbo's room logic, the way Arcturus runs it (WiredHandler). Boxes are furni:
-- triggers (something happened), conditions (is it so?) and effects (do this), plus add-ons
-- (random effect, unseen effect). Boxes on the same tile are a stack: when a stack's trigger
-- fires, its conditions are checked and, if they all hold, its effects run (each after its delay).
-- The script boxes (Habbo's "Custom Wired" furni) run a short Lua script instead: hotel/wiredscript.lua.
--
-- What kind of box a furni is: def.wired = a type's id (W.TYPES), set from the furni's kind for
-- Habbo's (wf_trg_says_something ...); an addon's own furni can say it itself.
-- A box's settings are kept in its furni's data (W.encode): text, numbers, chosen furni, delay,
-- a snapshot (match furni), a script. Whoever may change the room opens a box (using it), changes
-- it and saves; the window is drawn from the fields the server sends (W.TYPES[...].fields).
--
-- So that no room can slow the hotel down: at most W.RUNS_PER_SECOND stacks a second in a room,
-- stacks calling stacks at most W.MAX_DEPTH deep, and scripts have their own limits.
--
-- Messages from players: wired.save { id, text, ints, items, delay, code }
-- Messages to players:   wired.open { id, kind, type, name, fields, furni, delay, cfg, error }
--                        wired.saved { id }   wired.error { message }

BOBBA.wired = BOBBA.wired or {}
local W = BOBBA.wired
local live = BOBBA.live

W.MAX_FURNI = 20
W.MAX_TEXT = 100
W.RUNS_PER_SECOND = 200
W.MAX_DEPTH = 8
W.HALF = 0.5          -- Habbo's wired time step: half a second

local function P() return BOBBA.platform end
local function S() return BOBBA.store end
local function I() return BOBBA.items end

-- --- settings kept in a furni's data ------------------------------------------------------------------
local function esc(s) return (tostring(s or ""):gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "")) end
local function unesc(s) return (s:gsub("\\(.)", function(c) return c == "n" and "\n" or c end)) end
local function nums(s)
	local out = {}
	for n in tostring(s or ""):gmatch("[^,]+") do out[#out + 1] = tonumber(n) end
	return out
end

function W.encode(cfg)
	local lines = {}
	if cfg.text and cfg.text ~= "" then lines[#lines + 1] = "t=" .. esc(cfg.text) end
	if cfg.ints and #cfg.ints > 0 then lines[#lines + 1] = "i=" .. table.concat(cfg.ints, ",") end
	if cfg.items and #cfg.items > 0 then lines[#lines + 1] = "f=" .. table.concat(cfg.items, ",") end
	if (cfg.delay or 0) > 0 then lines[#lines + 1] = "d=" .. cfg.delay end
	if cfg.snap then
		local parts = {}
		for id, s in pairs(cfg.snap) do parts[#parts + 1] = table.concat({ id, s.x, s.y, s.z, s.dir, s.state }, ":") end
		table.sort(parts)
		if #parts > 0 then lines[#lines + 1] = "s=" .. table.concat(parts, ";") end
	end
	if cfg.code and cfg.code ~= "" then lines[#lines + 1] = "c=" .. esc(cfg.code) end
	return table.concat(lines, "\n")
end

function W.decode(data)
	local cfg = { text = "", ints = {}, items = {}, delay = 0, code = "" }
	for line in tostring(data or ""):gmatch("[^\n]+") do
		local k, v = line:match("^(%a)=(.*)$")
		if k == "t" then cfg.text = unesc(v)
		elseif k == "i" then cfg.ints = nums(v)
		elseif k == "f" then cfg.items = nums(v)
		elseif k == "d" then cfg.delay = tonumber(v) or 0
		elseif k == "c" then cfg.code = unesc(v)
		elseif k == "s" then
			cfg.snap = {}
			for part in v:gmatch("[^;]+") do
				local n = nums(part:gsub(":", ","))
				if n[1] then cfg.snap[n[1]] = { x = n[2], y = n[3], z = n[4], dir = n[5], state = n[6] } end
			end
		end
	end
	return cfg
end

-- a box's settings (kept decoded on the furni until its data changes)
function W.cfg(it)
	if it.wiredData ~= it.data then it.wiredCfg, it.wiredData = W.decode(it.data), it.data end
	return it.wiredCfg
end

-- --- the boxes' fields (what their windows show) ------------------------------------------------------
-- text { key, max }; radio { int, options = { { value, text } } }; slider { int, min, max, unit
-- (seconds a step) }; check { int }; number { int, min, max }; date { int }; code
local function text(label, fallback, max) return { type = "text", label = label, fallback = fallback, max = max or W.MAX_TEXT } end
local function slider(int, label, fallback, min, max, unit, default) return { type = "slider", int = int, label = label, fallback = fallback, min = min, max = max, unit = unit, default = default or min } end
local function radio(int, label, fallback, options) return { type = "radio", int = int, label = label, fallback = fallback, options = options } end
local function check(int, label, fallback, default) return { type = "check", int = int, label = label, fallback = fallback, default = default or 0 } end
local SNAP_CHECKS = {
	{ type = "title", label = "wiredfurni.params.conditions", fallback = "Match these:" },
	check(1, "wiredfurni.params.condition.state", "Furni state", 1),
	check(2, "wiredfurni.params.condition.direction", "Direction", 1),
	check(3, "wiredfurni.params.condition.position", "Position", 1),
}
local MOVES = {}
for i, t in ipairs({ "No movement", "Move to a random direction", "Move randomly left or right", "Move randomly up or down",
	"Move up", "Move right", "Move down", "Move left" }) do MOVES[i] = { i - 1, "wiredfurni.params.movefurni." .. (i - 1), t } end
local TURNS = {}
for i, t in ipairs({ "No rotation", "Rotate clockwise", "Rotate counterclockwise", "Rotate randomly" }) do TURNS[i] = { i - 1, "wiredfurni.params.rotatefurni." .. (i - 1), t } end
local DIRS = {}
for i, t in ipairs({ "North-east", "East", "South-east", "South", "South-west", "West", "North-west", "North" }) do DIRS[i] = { (i - 1), "wiredfurni.params.startdir." .. (i - 1), t } end

-- W.TYPES[id] = { kind = "trigger" | "effect" | "condition" | "extra", furni = how many may be
-- chosen (0: none), fields = {...}, test / run / matches functions (below) }
W.TYPES = W.TYPES or {}
-- which Habbo furni is which
W.HABBO = {
	wf_trg_says_something = "says", wf_trg_walks_on_furni = "walkson", wf_trg_walks_off_furni = "walksoff",
	wf_trg_enter_room = "enter", wf_trg_state_changed = "used", wf_trg_periodically = "repeat",
	wf_trg_period_long = "repeatlong", wf_trg_at_given_time = "attime", wf_trg_at_time_long = "attimelong",
	wf_trg_collision = "collision", wf_trg_click_furni = "click",
	wf_act_toggle_state = "toggle", wf_act_toggle_to_rnd = "togglerandom", wf_act_reset_timers = "reset",
	wf_act_show_message = "message", wf_act_teleport_to = "teleport", wf_act_kick_user = "kick",
	wf_act_mute_triggerer = "mute", wf_act_move_rotate = "moverotate", wf_act_match_to_sshot = "matchset",
	wf_act_chase = "chase", wf_act_flee = "flee", wf_act_call_stacks = "callstacks", wf_act_move_to_dir = "movedir",
	wf_cnd_trggrer_on_frn = "onfurni", wf_cnd_not_trggrer_on = "notonfurni", wf_cnd_furnis_hv_avtrs = "hasusers",
	wf_cnd_not_hv_avtrs = "nousers", wf_cnd_has_furni_on = "hasfurni", wf_cnd_not_furni_on = "nofurni",
	wf_cnd_match_snapshot = "matches", wf_cnd_not_match_snap = "notmatches", wf_cnd_stuff_is = "stuffis",
	wf_cnd_not_stuff_is = "notstuffis", wf_cnd_time_more_than = "timemore", wf_cnd_time_less_than = "timeless",
	wf_cnd_user_count_in = "usercount", wf_cnd_not_user_count = "notusercount", wf_cnd_actor_in_group = "ingroup",
	wf_cnd_not_in_group = "notingroup", wf_cnd_wearing_effect = "effect", wf_cnd_not_wearing_fx = "noteffect",
	wf_cnd_date_rng_active = "daterange",
	wf_xtra_random = "random", wf_xtra_unseen = "unseen",
	-- (Habbo's "Custom Wired" furni: the script boxes)
	wf_test_act = "script", wf_test_cnd = "scriptcondition",
}

function W.define(id, def)
	def.id = id
	def.furni = def.furni or 0
	def.fields = def.fields or {}
	W.TYPES[id] = def
	return def
end

-- the type of a furni (nil: not wired)
function W.typeOf(it)
	local d = it.def
	if not d then return nil end
	local id = d.wired
	if id == nil then id = W.HABBO[it.kind] end
	return id and W.TYPES[id] or nil
end

-- --- the room's state ---------------------------------------------------------------------------------
local function state(r)
	if not r.wired then r.wired = { timer = P().clock(), fired = {}, unseen = {}, vars = {}, errors = {}, runs = 0, second = 0 } end
	return r.wired
end
W.state = state

-- the boxes in a room, by tile ("x,y" -> list), and the triggers of a type
function W.boxes(r)
	local st = state(r)
	if st.boxes and st.boxesFor == r.items then return st.boxes, st.triggers end
	local tiles, triggers = {}, {}
	for _, it in pairs(r.items) do
		local t = W.typeOf(it)
		if t then
			local key = it.x .. "," .. it.y
			tiles[key] = tiles[key] or {}
			table.insert(tiles[key], it)
			if t.kind == "trigger" then
				triggers[t.id] = triggers[t.id] or {}
				table.insert(triggers[t.id], it)
			end
		end
	end
	for _, list in pairs(tiles) do table.sort(list, function(a, b) return a.z < b.z or (a.z == b.z and a.id < b.id) end) end
	for _, list in pairs(triggers) do table.sort(list, function(a, b) return a.id < b.id end) end
	st.boxes, st.triggers, st.boxesFor = tiles, triggers, r.items
	return tiles, triggers
end
function W.dirty(r) if r.wired then r.wired.boxes = nil end end

function W.elapsed(r) return P().clock() - state(r).timer end

-- a box lights up for a moment (Arcturus activateBox)
function W.flash(r, it)
	if it.flashing then return end
	it.flashing = true
	local was = it.state
	it.state = 1
	I().broadcastItem(r, it)
	P().after(W.HALF, function()
		it.flashing = nil
		if r.items[it.id] ~= it then return end
		it.state = was or 0
		I().broadcastItem(r, it)
	end)
end

-- the chosen furni that are still in the room
function W.chosen(r, cfg)
	local out = {}
	for _, id in ipairs(cfg.items or {}) do
		local it = r.items[id]
		if it and it.def then out[#out + 1] = it end
	end
	return out
end

-- is a unit on a furni (one of its tiles)?
function W.unitOn(u, it)
	if not u or not it.def or it.def.wall then return false end
	for _, t in ipairs(I().footprint(it.def, it.x, it.y, it.dir)) do
		if t.x == u.x and t.y == u.y then return true end
	end
	return false
end
function W.unitsOn(r, it)
	local out = {}
	for _, id in ipairs(r.order) do local u = r.units[id] if W.unitOn(u, it) then out[#out + 1] = u end end
	return out
end

-- --- running stacks -----------------------------------------------------------------------------------
-- something happened: every trigger of this type that matches runs its stack.
-- ctx = { unit, item, text, ... }; returns whether any stack ran
function W.fire(r, typeId, ctx)
	if not r or not r.items then return false end
	local _, triggers = W.boxes(r)
	local list = triggers[typeId]
	if not list then return false end
	ctx = ctx or {}
	ctx.kind = ctx.kind or typeId
	local ran = false
	for _, box in ipairs(list) do
		local t = W.TYPES[typeId]
		if r.items[box.id] == box and (not t.matches or t.matches(r, box, W.cfg(box), ctx or {})) then
			if W.runStack(r, box, ctx or {}) then ran = true end
		end
	end
	return ran
end

-- the stack on a trigger's tile: conditions, then its effects
function W.runStack(r, trigger, ctx, depth)
	depth = depth or 0
	if depth > W.MAX_DEPTH then return false end
	local st = state(r)
	-- (too much at once: the room waits)
	local sec = math.floor(P().clock())
	if st.second ~= sec then st.second, st.runs = sec, 0 end
	st.runs = st.runs + 1
	if st.runs > W.RUNS_PER_SECOND then
		if not st.warned then st.warned = true W.warn(r, "Wired is running too often in this room; some of it was skipped.") end
		return false
	end
	local tiles = W.boxes(r)
	local stack = tiles[trigger.x .. "," .. trigger.y] or {}
	local effects, extras = {}, {}
	for _, it in ipairs(stack) do
		local t = W.typeOf(it)
		if t and t.kind == "condition" then
			local ok, res = pcall(t.test, r, it, W.cfg(it), ctx)
			if not ok then W.boxError(r, it, res) return false end
			if not res then return false end
		elseif t and t.kind == "effect" then effects[#effects + 1] = it
		elseif t and t.kind == "extra" then extras[t.id] = it end
	end
	W.flash(r, trigger)
	for _, x in pairs(extras) do W.flash(r, x) end
	-- the add-ons: one at random, or the next one not yet run
	if extras.unseen and #effects > 0 then
		local key = trigger.x .. "," .. trigger.y
		local i = ((st.unseen[key] or 0) % #effects) + 1
		st.unseen[key] = i
		effects = { effects[i] }
	elseif extras.random and #effects > 0 then
		effects = { effects[math.random(1, #effects)] }
	end
	for _, eff in ipairs(effects) do
		local t = W.typeOf(eff)
		local cfg = W.cfg(eff)
		local function go()
			if r.items[eff.id] ~= eff or not live.rooms[r.id] then return end
			W.flash(r, eff)
			local ok, err = pcall(t.run, r, eff, cfg, ctx, depth)
			if not ok then W.boxError(r, eff, err) end
		end
		local delay = (tonumber(cfg.delay) or 0) * W.HALF
		if delay > 0 then P().after(delay, go) else go() end
	end
	return true
end

-- something went wrong in a box: kept to show in its window, and the room's owner is told (once
-- a while)
function W.boxError(r, it, err)
	local st = state(r)
	local msg = tostring(err or "error"):gsub("^.-:%d+: ", "")
	st.errors[it.id] = msg
	local now = P().clock()
	if (st.toldAt or 0) + 10 < now then
		st.toldAt = now
		W.warn(r, "A wired box had a problem: " .. msg)
	end
end

-- tells whoever may change the room (in it now)
function W.warn(r, text)
	for _, id in ipairs(r.order) do
		local u = r.units[id]
		if u.player and I().canEdit(u.player, r) then P().send("room.error", { message = text }, u.player) end
	end
end

-- a whisper only one person sees (Habbo's wired bubble)
W.BUBBLE = 34
function W.whisper(u, text)
	if not u or not u.player then return end
	text = tostring(text or ""):sub(1, 200)
	if text == "" then return end
	P().send("room.chat", { unit = u.id, text = text, kind = "whisper", style = W.BUBBLE }, u.player)
end

-- --- moving furni (effects) ----------------------------------------------------------------------------
local AHEAD = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 },
	[1] = { 1, -1 }, [3] = { 1, 1 }, [5] = { -1, 1 }, [7] = { -1, -1 } }
W.AHEAD = AHEAD

-- a furni to x, y (dir) if it fits there; slides like Habbo's. true when it moved
function W.move(r, it, x, y, dir)
	if not it.def or it.def.wall then return false end
	dir = dir or it.dir
	if x == it.x and y == it.y and dir == it.dir then return false end
	return I().moveBy(r, it, x, y, dir) == true
end

-- the user nearest a furni
local function nearest(r, it)
	local best, bd
	for _, id in ipairs(r.order) do
		local u = r.units[id]
		local d = math.abs(u.x - it.x) + math.abs(u.y - it.y)
		if not bd or d < bd then best, bd = u, d end
	end
	return best, bd
end
W.nearest = nearest

-- one step towards (1) or away from (-1) someone: the tile to go to
local function stepFor(it, u, sign)
	local dx, dy = u.x - it.x, u.y - it.y
	local sx = dx == 0 and 0 or (dx > 0 and 1 or -1)
	local sy = dy == 0 and 0 or (dy > 0 and 1 or -1)
	if sign < 0 then sx, sy = -sx, -sy end
	if math.abs(dx) >= math.abs(dy) then return { { sx, 0 }, { 0, sy } } end
	return { { 0, sy }, { sx, 0 } }
end

-- --- the types ------------------------------------------------------------------------------------------
local ANY_OR_OWNER = { { 0, "wiredfurni.params.anyavatar", "Any avatar" }, { 1, "wiredfurni.params.owneronly", "The room's owner" } }

-- triggers
W.define("says", { kind = "trigger", fields = { text("wiredfurni.params.whatissaid", "What is said:"),
	radio(1, "wiredfurni.params.picktriggerer", "Who says it:", ANY_OR_OWNER) },
	matches = function(r, box, cfg, ctx)
		if not ctx.text or cfg.text == "" then return false end
		if (cfg.ints[1] or 0) == 1 and (not ctx.unit or ctx.unit.key ~= r.info.owner) then return false end
		return ctx.text:lower():find(cfg.text:lower(), 1, true) ~= nil
	end })
W.define("walkson", { kind = "trigger", furni = W.MAX_FURNI,
	matches = function(r, box, cfg, ctx) for _, id in ipairs(cfg.items) do if ctx.item and ctx.item.id == id then return true end end return false end })
W.define("walksoff", { kind = "trigger", furni = W.MAX_FURNI, matches = W.TYPES.walkson.matches })
W.define("used", { kind = "trigger", furni = W.MAX_FURNI, matches = W.TYPES.walkson.matches })
W.define("click", { kind = "trigger", furni = W.MAX_FURNI, matches = W.TYPES.walkson.matches })
W.define("enter", { kind = "trigger", fields = { radio(1, "wiredfurni.params.picktriggerer", "Who comes in:",
	{ { 0, "wiredfurni.params.anyavatar", "Any avatar" }, { 1, "wiredfurni.params.certainavatar", "A certain avatar" } }),
	text("wiredfurni.params.username", "Their name:", 40) },
	matches = function(r, box, cfg, ctx)
		if (cfg.ints[1] or 0) == 1 and cfg.text ~= "" then return ctx.unit ~= nil and (ctx.unit.name or ""):lower() == cfg.text:lower() end
		return true
	end })
W.define("repeat", { kind = "trigger", fields = { slider(1, "wiredfurni.params.settime", "Every %seconds% seconds", 1, 60, W.HALF, 2) } })
W.define("repeatlong", { kind = "trigger", fields = { slider(1, "wiredfurni.params.setlongtime", "Every %seconds% seconds", 1, 120, 5, 1) } })
W.define("attime", { kind = "trigger", fields = { slider(1, "wiredfurni.params.settime", "After %seconds% seconds", 1, 1200, W.HALF, 2) } })
W.define("attimelong", { kind = "trigger", fields = { slider(1, "wiredfurni.params.setlongtime", "After %seconds% seconds", 1, 120, 5, 1) } })
W.define("collision", { kind = "trigger" })

-- effects
local function each(r, cfg, fn) for _, it in ipairs(W.chosen(r, cfg)) do fn(it) end end
W.define("toggle", { kind = "effect", furni = W.MAX_FURNI, run = function(r, box, cfg)
	each(r, cfg, function(it) if not W.typeOf(it) then I().toggle(r, it) end end)
end })
W.define("togglerandom", { kind = "effect", furni = W.MAX_FURNI, run = function(r, box, cfg)
	each(r, cfg, function(it)
		local n = it.def.states or 1
		if n > 1 and not W.typeOf(it) then I().setState(r, it, math.random(0, n - 1)) end
	end)
end })
W.define("reset", { kind = "effect", run = function(r) local st = state(r) st.timer, st.fired = P().clock(), {} end })
W.define("message", { kind = "effect", fields = { text("wiredfurni.params.message", "Message:", 100) },
	run = function(r, box, cfg, ctx) W.whisper(ctx.unit, cfg.text) end })
W.define("teleport", { kind = "effect", furni = W.MAX_FURNI, run = function(r, box, cfg, ctx)
	local u = ctx.unit
	local list = W.chosen(r, cfg)
	if not u or #list == 0 or u.teleporting then return end
	local to = list[math.random(1, #list)]
	if to.def.wall then return end
	live.warp(r, u, to.x, to.y)
end })
W.define("kick", { kind = "effect", fields = { text("wiredfurni.params.message", "Message:", 100) },
	run = function(r, box, cfg, ctx)
		local u = ctx.unit
		-- (never the room's owner or staff: Arcturus)
		if not u or not u.player or u.key == r.info.owner or BOBBA.perms.has(u.player, "bobba.staff.anyroom") then return end
		W.whisper(u, cfg.text)
		local player = u.player
		P().after(1, function()
			if live.byPlayer[player] == u and u.room == r then
				P().send("room.denied", { id = r.id, reason = "kicked" }, player)
				BOBBA.access.toHotelView(player)
			end
		end)
	end })
W.define("mute", { kind = "effect", fields = { slider(1, "wiredfurni.params.length.minutes", "Minutes: %value%", 1, 10, nil, 1),
	text("wiredfurni.params.message", "Message:", 100) },
	run = function(r, box, cfg, ctx)
		local u = ctx.unit
		if not u or not u.player or u.key == r.info.owner then return end
		local minutes = math.max(1, math.min(10, cfg.ints[1] or 1))
		r.mutes = r.mutes or {}
		r.mutes[u.key] = P().clock() + minutes * 60
		P().send("room.muted", { seconds = minutes * 60 }, u.player)
		W.whisper(u, cfg.text)
	end })
local function turn(dir, how)
	if how == 1 then return (dir + 2) % 8 end
	if how == 2 then return (dir + 6) % 8 end
	if how == 3 then return ({ 0, 2, 4, 6 })[math.random(1, 4)] end
	return dir
end
W.define("moverotate", { kind = "effect", furni = W.MAX_FURNI,
	fields = { radio(1, "wiredfurni.params.movefurni", "Move:", MOVES), radio(2, "wiredfurni.params.rotatefurni", "Rotate:", TURNS) },
	run = function(r, box, cfg)
		local how, rot = cfg.ints[1] or 0, cfg.ints[2] or 0
		each(r, cfg, function(it)
			local dx, dy = 0, 0
			if how == 1 then local v = AHEAD[({ 0, 2, 4, 6 })[math.random(1, 4)]] dx, dy = v[1], v[2]
			elseif how == 2 then dx = math.random(0, 1) == 0 and -1 or 1
			elseif how == 3 then dy = math.random(0, 1) == 0 and -1 or 1
			elseif how == 4 then dy = -1 elseif how == 5 then dx = 1 elseif how == 6 then dy = 1 elseif how == 7 then dx = -1 end
			local dir = rot > 0 and turn(it.dir, rot) or it.dir
			-- (a direction it can't face: as it was)
			local okDir = false
			for _, d in ipairs(it.def.directions or { 0, 2, 4, 6 }) do if d == dir then okDir = true end end
			if not okDir then dir = it.dir end
			W.move(r, it, it.x + dx, it.y + dy, dir)
		end)
	end })
W.define("movedir", { kind = "effect", furni = W.MAX_FURNI,
	fields = { radio(1, "wiredfurni.params.startdir", "Start direction:", DIRS) },
	-- each one moves a tile the way it's going; blocked, it turns around (Habbo's "Move furni to direction")
	run = function(r, box, cfg)
		local st = state(r)
		st.dirs = st.dirs or {}
		each(r, cfg, function(it)
			local d = st.dirs[it.id] or ((cfg.ints[1] or 0) % 8)
			local v = AHEAD[d]
			if not W.move(r, it, it.x + v[1], it.y + v[2], it.dir) then
				d = (d + 4) % 8
				v = AHEAD[d]
				W.move(r, it, it.x + v[1], it.y + v[2], it.dir)
			end
			st.dirs[it.id] = d
		end)
	end })
W.define("matchset", { kind = "effect", furni = W.MAX_FURNI, snapshot = true, fields = SNAP_CHECKS,
	run = function(r, box, cfg)
		local snap = cfg.snap or {}
		local sState, sDir, sPos = (cfg.ints[1] or 1) == 1, (cfg.ints[2] or 1) == 1, (cfg.ints[3] or 1) == 1
		each(r, cfg, function(it)
			local s = snap[it.id]
			if not s then return end
			if sState and s.state and it.state ~= s.state and not W.typeOf(it) then I().setState(r, it, s.state) end
			if sPos or sDir then
				W.move(r, it, sPos and s.x or it.x, sPos and s.y or it.y, sDir and s.dir or it.dir)
			end
		end)
	end })
local function chaseOrFlee(sign)
	return function(r, box, cfg)
		each(r, cfg, function(it)
			local u = nearest(r, it)
			if not u then return end
			for _, v in ipairs(stepFor(it, u, sign)) do
				if v[1] ~= 0 or v[2] ~= 0 then
					local x, y = it.x + v[1], it.y + v[2]
					-- (chasing into someone: they've collided)
					if sign > 0 and u.x == x and u.y == y then W.fire(r, "collision", { unit = u, item = it }) return end
					if W.move(r, it, x, y, it.dir) then return end
				end
			end
		end)
	end
end
W.define("chase", { kind = "effect", furni = W.MAX_FURNI, run = chaseOrFlee(1) })
W.define("flee", { kind = "effect", furni = W.MAX_FURNI, run = chaseOrFlee(-1) })
W.define("callstacks", { kind = "effect", furni = W.MAX_FURNI, run = function(r, box, cfg, ctx, depth)
	local seen = {}
	each(r, cfg, function(it)
		local key = it.x .. "," .. it.y
		if seen[key] or (it.x == box.x and it.y == box.y) then return end
		seen[key] = true
		local tiles = W.boxes(r)
		for _, t in ipairs(tiles[key] or {}) do
			local ty = W.typeOf(t)
			if ty and ty.kind == "trigger" then W.runStack(r, t, ctx, (depth or 0) + 1) return end
		end
	end)
end })

-- conditions
local function onAny(r, cfg, u)
	for _, it in ipairs(W.chosen(r, cfg)) do if W.unitOn(u, it) then return true end end
	return false
end
W.define("onfurni", { kind = "condition", furni = W.MAX_FURNI, test = function(r, box, cfg, ctx) return ctx.unit ~= nil and onAny(r, cfg, ctx.unit) end })
W.define("notonfurni", { kind = "condition", furni = W.MAX_FURNI, test = function(r, box, cfg, ctx) return not (ctx.unit and onAny(r, cfg, ctx.unit)) end })
W.define("hasusers", { kind = "condition", furni = W.MAX_FURNI, test = function(r, box, cfg)
	for _, it in ipairs(W.chosen(r, cfg)) do if #W.unitsOn(r, it) == 0 then return false end end
	return true
end })
W.define("nousers", { kind = "condition", furni = W.MAX_FURNI, test = function(r, box, cfg)
	for _, it in ipairs(W.chosen(r, cfg)) do if #W.unitsOn(r, it) > 0 then return false end end
	return true
end })
local function hasOnTop(r, it)
	for _, o in pairs(r.items) do
		if o ~= it and o.def and not o.def.wall and o.z >= it.z + (it.def.height or 0) - 0.01 then
			for _, t in ipairs(I().footprint(o.def, o.x, o.y, o.dir)) do
				if W.unitOn({ x = t.x, y = t.y }, it) then return true end
			end
		end
	end
	return false
end
W.hasOnTop = hasOnTop
local ALL_OR_ANY = { { 0, "wiredfurni.params.requireall.0", "Any of the furni" }, { 1, "wiredfurni.params.requireall.1", "All of the furni" } }
W.define("hasfurni", { kind = "condition", furni = W.MAX_FURNI, fields = { radio(1, "wiredfurni.params.requireall", "Which:", ALL_OR_ANY) },
	test = function(r, box, cfg)
		local list = W.chosen(r, cfg)
		local all = (cfg.ints[1] or 0) == 1
		for _, it in ipairs(list) do
			local has = hasOnTop(r, it)
			if all and not has then return false end
			if not all and has then return true end
		end
		return all and #list > 0
	end })
W.define("nofurni", { kind = "condition", furni = W.MAX_FURNI,
	fields = { radio(1, "wiredfurni.params.not_requireall", "Which:", { { 0, "wiredfurni.params.not_requireall.0", "Any of the furni" }, { 1, "wiredfurni.params.not_requireall.1", "All of the furni" } }) },
	test = function(r, box, cfg)
		local list = W.chosen(r, cfg)
		local all = (cfg.ints[1] or 0) == 1
		for _, it in ipairs(list) do
			local has = hasOnTop(r, it)
			if all and has then return false end
			if not all and not has then return true end
		end
		return all or #list == 0
	end })
local function matchesSnap(r, cfg)
	local snap = cfg.snap or {}
	local sState, sDir, sPos = (cfg.ints[1] or 1) == 1, (cfg.ints[2] or 1) == 1, (cfg.ints[3] or 1) == 1
	for _, it in ipairs(W.chosen(r, cfg)) do
		local s = snap[it.id]
		if s then
			if sState and s.state ~= (it.state or 0) then return false end
			if sDir and s.dir ~= it.dir then return false end
			if sPos and (s.x ~= it.x or s.y ~= it.y) then return false end
		end
	end
	return true
end
W.define("matches", { kind = "condition", furni = W.MAX_FURNI, snapshot = true, fields = SNAP_CHECKS, test = function(r, box, cfg) return matchesSnap(r, cfg) end })
W.define("notmatches", { kind = "condition", furni = W.MAX_FURNI, snapshot = true, fields = SNAP_CHECKS, test = function(r, box, cfg) return not matchesSnap(r, cfg) end })
local function stuffIs(r, cfg, ctx)
	if not ctx.item then return false end
	for _, it in ipairs(W.chosen(r, cfg)) do if it == ctx.item or it.kind == ctx.item.kind then return true end end
	return false
end
W.define("stuffis", { kind = "condition", furni = W.MAX_FURNI, test = function(r, box, cfg, ctx) return stuffIs(r, cfg, ctx) end })
W.define("notstuffis", { kind = "condition", furni = W.MAX_FURNI, test = function(r, box, cfg, ctx) return not stuffIs(r, cfg, ctx) end })
W.define("timemore", { kind = "condition", fields = { slider(1, "wiredfurni.params.allowafter", "After %seconds% seconds", 1, 1200, W.HALF, 2) },
	test = function(r, box, cfg) return W.elapsed(r) > (cfg.ints[1] or 1) * W.HALF end })
W.define("timeless", { kind = "condition", fields = { slider(1, "wiredfurni.params.allowbefore", "Before %seconds% seconds", 1, 1200, W.HALF, 2) },
	test = function(r, box, cfg) return W.elapsed(r) < (cfg.ints[1] or 1) * W.HALF end })
local COUNT_FIELDS = { slider(1, "wiredfurni.params.usercountmin", "At least: %value%", 1, 50, nil, 1), slider(2, "wiredfurni.params.usercountmax", "At most: %value%", 1, 50, nil, 50) }
local function countIn(r, cfg) local n = #r.order return n >= (cfg.ints[1] or 1) and n <= (cfg.ints[2] or 50) end
W.define("usercount", { kind = "condition", fields = COUNT_FIELDS, test = function(r, box, cfg) return countIn(r, cfg) end })
W.define("notusercount", { kind = "condition", fields = COUNT_FIELDS, test = function(r, box, cfg) return not countIn(r, cfg) end })
local function inGroup(r, u)
	if not u or not BOBBA.groups then return false end
	local g = S().row("SELECT id FROM bobbahotel_groups WHERE room = ?", { r.id })
	return g ~= nil and BOBBA.groups.rank(tonumber(g.id), u.key) ~= nil
end
W.define("ingroup", { kind = "condition", test = function(r, box, cfg, ctx) return inGroup(r, ctx.unit) end })
W.define("notingroup", { kind = "condition", test = function(r, box, cfg, ctx) return ctx.unit ~= nil and not inGroup(r, ctx.unit) end })
local EFFECT_FIELD = { { type = "number", int = 1, label = "wiredfurni.tooltip.effectid", fallback = "Effect number:", min = 0, max = 10000, default = 0 } }
W.define("effect", { kind = "condition", fields = EFFECT_FIELD, test = function(r, box, cfg, ctx) return ctx.unit ~= nil and (ctx.unit.effect or 0) == (cfg.ints[1] or 0) end })
W.define("noteffect", { kind = "condition", fields = EFFECT_FIELD, test = function(r, box, cfg, ctx) return ctx.unit ~= nil and (ctx.unit.effect or 0) ~= (cfg.ints[1] or 0) end })
W.define("daterange", { kind = "condition", fields = { { type = "date", int = 1, label = "wiredfurni.params.startdate", fallback = "From:" },
	{ type = "date", int = 2, label = "wiredfurni.params.enddate", fallback = "Until:" } },
	test = function(r, box, cfg)
		local now = P().time()
		return now >= (cfg.ints[1] or 0) and (cfg.ints[2] or 0) > 0 and now <= cfg.ints[2]
	end })

-- add-ons
W.define("random", { kind = "extra" })
W.define("unseen", { kind = "extra" })

-- what each does (shown in its window, under its name)
W.DESC = {
	says = "Fires when someone says something with these words in it. Only they see it.",
	walkson = "Fires when someone walks onto one of the chosen furni.",
	walksoff = "Fires when someone walks off one of the chosen furni.",
	enter = "Fires when someone comes into the room.",
	used = "Fires when one of the chosen furni is used (switched, rolled, opened).",
	click = "Fires when someone clicks one of the chosen furni.",
	["repeat"] = "Fires again and again, every so often.",
	repeatlong = "Fires again and again, every so often (long times).",
	attime = "Fires once, this long after the timers were reset.",
	attimelong = "Fires once, this long after the timers were reset (long times).",
	collision = "Fires when furni moved by wired runs into someone.",
	toggle = "Switches the chosen furni to their next state, as if used.",
	togglerandom = "Switches the chosen furni to a random state.",
	reset = "Resets the room's timers (for the timed triggers and conditions).",
	message = "Whispers a message to whoever set it off. Only they see it.",
	teleport = "Teleports whoever set it off onto one of the chosen furni.",
	kick = "Sends whoever set it off out of the room (never its owner).",
	mute = "Mutes whoever set it off in this room for a while.",
	moverotate = "Moves and turns the chosen furni.",
	movedir = "Moves the chosen furni one tile at a time; blocked, they turn back.",
	matchset = "Puts the chosen furni back as they were when this was saved.",
	chase = "Moves the chosen furni one tile towards the nearest person.",
	flee = "Moves the chosen furni one tile away from the nearest person.",
	callstacks = "Runs the wired stacks the chosen furni are on.",
	onfurni = "Only if whoever set it off is on one of the chosen furni.",
	notonfurni = "Only if whoever set it off is not on any of the chosen furni.",
	hasusers = "Only if someone is on each of the chosen furni.",
	nousers = "Only if no one is on any of the chosen furni.",
	hasfurni = "Only if there's furni on top of the chosen furni.",
	nofurni = "Only if there's no furni on top of the chosen furni.",
	matches = "Only if the chosen furni are as they were when this was saved.",
	notmatches = "Only if the chosen furni aren't as they were when this was saved.",
	stuffis = "Only if the furni that set it off is one of the chosen (or the same kind).",
	notstuffis = "Only if the furni that set it off isn't one of the chosen.",
	timemore = "Only if more than this long has gone since the timers were reset.",
	timeless = "Only if less than this long has gone since the timers were reset.",
	usercount = "Only if this many people are in the room.",
	notusercount = "Only if not this many people are in the room.",
	ingroup = "Only if whoever set it off is in the room's group.",
	notingroup = "Only if whoever set it off isn't in the room's group.",
	effect = "Only if whoever set it off has this effect on.",
	noteffect = "Only if whoever set it off doesn't have this effect on.",
	daterange = "Only between these two dates.",
	script = "Runs your own Lua script: move and switch furni, whisper, teleport, count, remember.",
	scriptcondition = "Your own Lua script decides: return true to let the stack go on.",
}

-- --- opening and saving a box -----------------------------------------------------------------------------
function W.open(r, player, it)
	if not I().canEdit(player, r) then return false, "only those with rights can change wired" end
	local t = W.typeOf(it)
	if not t then return false end
	local cfg = W.cfg(it)
	if t.kind == "extra" then return true end
	P().send("wired.open", {
		id = it.id, kind = t.kind, type = t.id, furni = t.furni, fields = t.fields, delay = t.kind == "effect", desc = t.desc or W.DESC[t.id],
		script = t.script, cfg = { text = cfg.text, ints = cfg.ints, items = cfg.items, delay = cfg.delay, code = cfg.code },
		error = state(r).errors[it.id], scriptsOff = t.script and not W.scriptsOn() or nil,
	}, player)
	return true
end

function W.scriptsOn() return S().setting("wired.scripts", "1") ~= "0" end

local function clampInt(v, lo, hi, d)
	v = math.floor(tonumber(v) or d)
	if v ~= v then v = d end
	return math.max(lo, math.min(hi, v))
end

-- checks what was sent against the box's fields; the settings to keep, or nil and why
function W.clean(r, it, t, data)
	local cfg = { text = "", ints = {}, items = {}, delay = 0, code = "" }
	local ints = type(data.ints) == "table" and data.ints or {}
	for _, f in ipairs(t.fields) do
		if f.type == "text" then
			cfg.text = tostring(data.text or ""):gsub("[%z\1-\31]", ""):sub(1, f.max or W.MAX_TEXT)
		elseif f.type == "slider" or f.type == "number" then
			cfg.ints[f.int] = clampInt(ints[f.int], f.min or 0, f.max or 1000000, f.default or f.min or 0)
		elseif f.type == "radio" then
			local v, okv = math.floor(tonumber(ints[f.int]) or f.options[1][1]), false
			for _, o in ipairs(f.options) do if o[1] == v then okv = true end end
			cfg.ints[f.int] = okv and v or f.options[1][1]
		elseif f.type == "check" then
			cfg.ints[f.int] = (tonumber(ints[f.int]) or 0) ~= 0 and 1 or 0
		elseif f.type == "date" then
			cfg.ints[f.int] = clampInt(ints[f.int], 0, 4102444800, 0)
		end
	end
	-- (no gaps: the list is saved as it is)
	local n = 0
	for k in pairs(cfg.ints) do if k > n then n = k end end
	for i = 1, n do cfg.ints[i] = cfg.ints[i] or 0 end
	if t.furni > 0 and type(data.items) == "table" then
		local seen = {}
		for _, id in ipairs(data.items) do
			id = tonumber(id)
			local o = id and r.items[id]
			if o and not seen[id] and #cfg.items < t.furni then seen[id] = true cfg.items[#cfg.items + 1] = id end
		end
	end
	if t.kind == "effect" then cfg.delay = clampInt(data.delay, 0, 20, 0) end
	if t.snapshot then
		cfg.snap = {}
		for _, id in ipairs(cfg.items) do
			local o = r.items[id]
			cfg.snap[id] = { x = o.x, y = o.y, z = o.z, dir = o.dir, state = o.state or 0 }
		end
	end
	if t.script then
		if not W.scriptsOn() then return nil, "scripts are switched off in this hotel" end
		local code = tostring(data.code or "")
		if #code > BOBBA.wiredScript.MAX_CODE then return nil, "a script can be at most " .. BOBBA.wiredScript.MAX_CODE .. " letters" end
		local ok, why = BOBBA.wiredScript.check(code)
		if not ok then return nil, why end
		cfg.code = code
	end
	return cfg
end

function W.save(r, player, data)
	local it = r.items[tonumber(data.id) or -1]
	local t = it and W.typeOf(it)
	if not t then return false, "that isn't wired" end
	if not I().canEdit(player, r) then return false, "only those with rights can change wired" end
	local cfg, why = W.clean(r, it, t, data)
	if not cfg then return false, why end
	it.data = W.encode(cfg)
	S().query("UPDATE bobbahotel_items SET data = ? WHERE id = ?", { it.data, it.id })
	local st = state(r)
	st.errors[it.id] = nil
	st.fired[it.id] = nil
	if st.vars then st.vars[it.id] = nil end
	if st.compiled then st.compiled[it.id] = nil end
	return true
end

-- --- what happens in rooms -------------------------------------------------------------------------------
-- the timed triggers (every half second)
function W.tick()
	local now = P().clock()
	for _, r in pairs(live.rooms) do
		if r.wired or next(r.items or {}) then
			local _, triggers = W.boxes(r)
			if next(triggers) then
				local st = state(r)
				local elapsed = now - st.timer
				for _, id in ipairs({ "repeat", "repeatlong" }) do
					for _, box in ipairs(triggers[id] or {}) do
						local every = (W.cfg(box).ints[1] or 1) * (id == "repeat" and W.HALF or 5)
						st.next = st.next or {}
						-- (seen first now: it was there since the last tick)
						if not st.next[box.id] then st.next[box.id] = now - W.HALF + every end
						if now >= st.next[box.id] - 1e-6 then
							st.next[box.id] = now + every
							W.runStack(r, box, {})
						end
					end
				end
				for _, id in ipairs({ "attime", "attimelong" }) do
					for _, box in ipairs(triggers[id] or {}) do
						local at = (W.cfg(box).ints[1] or 1) * (id == "attime" and W.HALF or 5)
						if not st.fired[box.id] and elapsed >= at - 1e-6 then
							st.fired[box.id] = true
							W.runStack(r, box, {})
						end
					end
				end
			end
		end
	end
end

-- where everyone stood: walking off and on furni
local function tilesItems(r, x, y)
	local out = {}
	for _, it in pairs(r.items) do
		if it.def and not it.def.wall and W.unitOn({ x = x, y = y }, it) then out[#out + 1] = it end
	end
	return out
end

function W.start()
	local p = P()
	p.receive("wired.save", function(player, data)
		local u = live.byPlayer[player]
		if not u or not u.room then return end
		local ok, why = W.save(u.room, player, data)
		if ok then p.send("wired.saved", { id = tonumber(data.id) }, player)
		else p.send("wired.error", { message = tostring(why or "couldn't save that") }, player) end
	end)
	p.every("wired.tick", W.HALF, W.tick)
	local E = BOBBA.events
	E.on("itemPlaced", "bobba.wired", function(r) W.dirty(r) end)
	E.on("itemRemoved", "bobba.wired", function(r, it) W.dirty(r) if r.wired then r.wired.errors[it.id] = nil end end)
	E.on("itemMoved", "bobba.wired", function(r) W.dirty(r) end)
	E.on("roomLoaded", "bobba.wired", function(r) r.wired = nil end)
	-- someone said something: a keyword said (Arcturus: then only they see it, as a whisper)
	E.on("roomChat", "bobba.wired", function(r, u, text, kind)
		if kind == "whisper" then return nil end
		local ctx = { unit = u, text = text }
		local _, triggers = W.boxes(r)
		local heard = false
		for _, box in ipairs(triggers.says or {}) do
			if W.TYPES.says.matches(r, box, W.cfg(box), ctx) then heard = true end
		end
		if not heard then return nil end
		if u.player then p.send("room.chat", { unit = u.id, text = text, kind = "whisper", style = 0 }, u.player) end
		W.fire(r, "says", ctx)
		return "handled"
	end)
	E.on("roomEntered", "bobba.wired", function(r, u)
		u.wiredTile = u.x .. "," .. u.y
		W.fire(r, "enter", { unit = u })
	end)
	E.on("roomLeft", "bobba.wired", function(r, u)
		if r.wired and r.wired.vars then r.wired.users = nil end
	end)
	E.on("unitStepped", "bobba.wired", function(r, u)
		local key = u.x .. "," .. u.y
		local was = u.wiredTile
		if was == key then return end
		u.wiredTile = key
		local _, triggers = W.boxes(r)
		if not triggers.walkson and not triggers.walksoff then return end
		if was and triggers.walksoff then
			local wx, wy = was:match("^(%-?%d+),(%-?%d+)$")
			for _, it in ipairs(tilesItems(r, tonumber(wx), tonumber(wy))) do
				if not W.unitOn(u, it) then W.fire(r, "walksoff", { unit = u, item = it }) end
			end
		end
		if triggers.walkson then
			for _, it in ipairs(tilesItems(r, u.x, u.y)) do W.fire(r, "walkson", { unit = u, item = it }) end
		end
	end)
	E.on("itemUsed", "bobba.wired", function(r, it, player)
		W.fire(r, "used", { unit = player and live.byPlayer[player], item = it })
	end)
end
