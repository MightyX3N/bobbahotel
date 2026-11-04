-- Wired's script boxes (server): an effect (wired.lua's "script") and a condition ("scriptcondition")
-- that run a short Lua script someone with rights wrote, instead of fixed settings. The script only
-- sees what's made for it (WS.env): the room, its people and furni, the one who set it off, a little
-- memory of its own, and Lua's safe parts. It can change the room the way wired can - move and switch
-- furni, whisper, teleport people - and nothing else: no money, no furni made or given away, no files,
-- no network, nothing of the server.
--
-- So no script can slow the hotel down: each run may do at most WS.MAX_STEPS steps of Lua and use at
-- most WS.MAX_MEMORY KB more memory, a room's scripts at most WS.ROOM_STEPS steps a second, and a
-- script that breaks those is stopped (its box shows why). The steps are counted with a debug hook,
-- with the JIT off for the script (LuaJIT doesn't count steps in compiled code).
--
-- A script sees:
--   user        who set it off (nil when no one did, e.g. a repeating trigger): see "a user" below
--   trigger     { kind = "says" | "walkson" | ..., text = what was said, furni = the furni it was about }
--   selected    the furni chosen in the box's window, as a list
--   room        room.users() room.furni() room.get(id) room.count() room.elapsed() room.reset()
--               room.owner (name) room.id room.name
--               room.call(furni): runs the wired stack the furni is on (like "Execute wired stacks")
--   memory      a table kept between runs while the room is loaded (numbers, strings, true/false)
--   say(text)   whispers to the user (only they see it); print(...) the same, for testing
--   random(a, b), wait(seconds, fn): fn after a while (at most 30 s, 10 waiting at once)
--   a user:     .name .x .y .dir .effect .isOwner  :whisper(text) :teleport(x, y) :teleportTo(furni) :kick()
--   a furni:    .id .kind .x .y .z .dir .state  :setState(n) :toggle() :move(x, y [, dir]) :turn(dir) :usersOn()
-- A condition script returns true or false.

BOBBA.wiredScript = BOBBA.wiredScript or {}
local WS = BOBBA.wiredScript
local W = BOBBA.wired
local live = BOBBA.live

WS.MAX_CODE = 4000
WS.MAX_STEPS = 200000         -- Lua steps (instructions) a run
WS.ROOM_STEPS = 2000000       -- a room's scripts, a second
WS.HOOK_EVERY = 1000
WS.MAX_MEMORY = 2048          -- KB more than when it started
WS.MAX_STRING = 10000
WS.MAX_WAITS = 10
WS.MAX_MEMORY_KEYS = 200

local function P() return BOBBA.platform end
local function I() return BOBBA.items end

-- --- compiling ---------------------------------------------------------------------------------------
-- (GMod has CompileString; plain Lua load / loadstring. Never bytecode.)
local function compile(code, name)
	if code:byte(1) == 27 then return nil, "that isn't a script" end
	if load and not setfenv then
		local f, err = load(code, "=" .. name, "t", {})
		return f, err
	end
	if CompileString then
		local f = CompileString(code, name, false)
		if type(f) == "string" then return nil, f end
		return f
	end
	return loadstring(code, "=" .. name)
end

-- does it compile? true, or false and why
function WS.check(code)
	if code == "" then return true end
	local f, err = compile(code, "script")
	if not f then return false, "the script has a mistake: " .. tostring(err):gsub("^.-:(%d+):", "line %1:") end
	return true
end

local ABORT = {}  -- (thrown to stop a script; pcall inside the script can't catch it)

-- --- what a script sees ---------------------------------------------------------------------------------
local function safeString()
	local s = {}
	for _, k in ipairs({ "byte", "char", "format", "len", "lower", "reverse", "sub", "upper" }) do s[k] = string[k] end
	-- (patterns run in C, where steps aren't counted: only on strings of a sensible length)
	for _, k in ipairs({ "find", "gmatch", "gsub", "match" }) do
		local f = string[k]
		s[k] = function(str, ...)
			if #tostring(str) > WS.MAX_STRING then error("that string is too long", 2) end
			return f(str, ...)
		end
	end
	s.rep = function(str, n, sep)
		n = math.floor(tonumber(n) or 0)
		if #tostring(str) * n > WS.MAX_STRING then error("that string would be too long", 2) end
		return string.rep(str, n, sep)
	end
	return s
end
local function copyLib(lib, names)
	local t = {}
	for _, k in ipairs(names) do t[k] = lib[k] end
	return t
end
local MATH = { "abs", "ceil", "floor", "max", "min", "sqrt", "huge", "pi", "fmod", "sin", "cos", "tan", "atan", "exp", "log", "modf" }
local TABLE = { "insert", "remove", "sort", "concat" }

-- a furni as a script sees it
local function furniObject(r, it, run)
	if not it then return nil end
	local f = { id = it.id, kind = it.kind, x = it.x, y = it.y, z = it.z, dir = it.dir, state = it.state or 0 }
	local function live_() local o = r.items[it.id] if o ~= it then error("that furni isn't in the room any more", 3) end return o end
	function f:setState(n)
		local o = live_()
		n = math.floor(tonumber(n) or 0)
		if W.typeOf(o) then return false end
		if n < 0 or n >= math.max(1, o.def.states or 1) then return false end
		I().setState(r, o, n)
		self.state = n
		return true
	end
	function f:toggle()
		local o = live_()
		if W.typeOf(o) then return false end
		local ok = I().toggle(r, o)
		self.state = o.state
		return ok
	end
	function f:move(x, y, dir)
		local o = live_()
		local ok = W.move(r, o, math.floor(tonumber(x) or o.x), math.floor(tonumber(y) or o.y), dir and math.floor(tonumber(dir) or o.dir) or o.dir)
		self.x, self.y, self.z, self.dir = o.x, o.y, o.z, o.dir
		return ok
	end
	function f:turn(dir)
		local o = live_()
		local ok = W.move(r, o, o.x, o.y, math.floor(tonumber(dir) or o.dir) % 8)
		self.dir = o.dir
		return ok
	end
	function f:usersOn()
		local o = live_()
		local out = {}
		for _, u in ipairs(W.unitsOn(r, o)) do out[#out + 1] = run.user(u) end
		return out
	end
	return f
end

-- a person as a script sees it
local function userObject(r, u, run)
	if not u then return nil end
	local o = { name = u.name, x = u.x, y = u.y, dir = u.dir, effect = u.effect or 0, isOwner = u.key == r.info.owner }
	local function live_() if r.units[u.id] ~= u then error("they aren't in the room any more", 3) end return u end
	function o:whisper(text) W.whisper(live_(), tostring(text)) end
	function o:teleport(x, y)
		local x2, y2 = math.floor(tonumber(x) or -1), math.floor(tonumber(y) or -1)
		local me = live_()
		local PF = BOBBA.pathfinder
		local t = PF and PF.tile(r.grid, x2, y2)
		if not t or t.state == PF.INVALID or t.state == PF.BLOCKED or (r.layout.door.x == x2 and r.layout.door.y == y2) then return false end
		if me.teleporting then return false end
		live.warp(r, me, x2, y2)
		self.x, self.y = x2, y2
		return true
	end
	function o:teleportTo(f)
		local it = f and r.items[tonumber(f.id) or -1]
		if not it or it.def.wall then return false end
		return self:teleport(it.x, it.y)
	end
	function o:kick()
		local me = live_()
		if not me.player or me.key == r.info.owner or BOBBA.perms.has(me.player, "bobba.staff.anyroom") then return false end
		local player = me.player
		P().after(0, function()
			if live.byPlayer[player] == me and me.room == r then
				P().send("room.denied", { id = r.id, reason = "kicked" }, player)
				BOBBA.access.toHotelView(player)
			end
		end)
		return true
	end
	return o
end

-- memory kept between runs: only plain values, a limited number of them
local function memoryOf(r, box)
	local st = W.state(r)
	st.vars = st.vars or {}
	local raw = st.vars[box.id] or {}
	st.vars[box.id] = raw
	return setmetatable({}, {
		__index = raw,
		__newindex = function(_, k, v)
			local tk, tv = type(k), type(v)
			if tk ~= "string" and tk ~= "number" then error("memory's names are words or numbers", 2) end
			if v ~= nil and tv ~= "string" and tv ~= "number" and tv ~= "boolean" then error("memory keeps words, numbers and true/false", 2) end
			if tv == "string" and #v > 1000 then error("that's too long to keep", 2) end
			if raw[k] == nil and v ~= nil then
				local n = 0
				for _ in pairs(raw) do n = n + 1 end
				if n >= WS.MAX_MEMORY_KEYS then error("memory is full", 2) end
			end
			raw[k] = v
		end,
		__pairs = function() return next, raw, nil end,
	})
end

-- the environment for one run
function WS.env(r, box, ctx, depth)
	local run = {}
	run.user = function(u) return userObject(r, u, run) end
	run.furni = function(it) return furniObject(r, it, run) end
	local env = {
		assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs, select = select,
		tonumber = tonumber, tostring = tostring, type = type, unpack = unpack or table.unpack,
		string = safeString(), math = copyLib(math, MATH), table = copyLib(table, TABLE),
		os = { time = os.time, date = function(f, t) return os.date(f == nil and "%c" or tostring(f):gsub("^!", ""), t) end },
	}
	-- (pcall inside the script: never catches being stopped)
	env.pcall = function(fn, ...)
		local res = { pcall(fn, ...) }
		if not res[1] and res[2] == ABORT then error(ABORT, 0) end
		return (unpack or table.unpack)(res)
	end
	env.random = function(a, b)
		if a == nil then return math.random() end
		a = math.floor(tonumber(a) or 1)
		if b == nil then return math.random(1, math.max(1, a)) end
		b = math.floor(tonumber(b) or a)
		if b < a then a, b = b, a end
		return math.random(a, b)
	end
	env.user = run.user(ctx.unit)
	env.trigger = { kind = ctx.kind, text = ctx.text, furni = ctx.item and run.furni(ctx.item) or nil }
	local selected = {}
	for _, it in ipairs(W.chosen(r, W.cfg(box))) do selected[#selected + 1] = run.furni(it) end
	env.selected = selected
	env.memory = memoryOf(r, box)
	env.say = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
		if ctx.unit then W.whisper(ctx.unit, table.concat(parts, " ")) end
	end
	env.print = env.say
	env.room = {
		id = r.id, name = r.info.name, owner = r.info.owner_name,
		users = function()
			local out = {}
			for _, id in ipairs(r.order) do out[#out + 1] = run.user(r.units[id]) end
			return out
		end,
		count = function() return #r.order end,
		furni = function(kind)
			local out = {}
			local ids = {}
			for id, it in pairs(r.items) do if it.def and (kind == nil or it.kind == kind) then ids[#ids + 1] = id end end
			table.sort(ids)
			for _, id in ipairs(ids) do out[#out + 1] = run.furni(r.items[id]) end
			return out
		end,
		get = function(id) return run.furni(r.items[tonumber(id) or -1]) end,
		elapsed = function() return W.elapsed(r) end,
		reset = function() local st = W.state(r) st.timer, st.fired = P().clock(), {} end,
		call = function(f)
			local it = f and r.items[tonumber(f.id) or -1]
			if not it then return false end
			local tiles = W.boxes(r)
			for _, t in ipairs(tiles[it.x .. "," .. it.y] or {}) do
				local ty = W.typeOf(t)
				if ty and ty.kind == "trigger" then
					local c = { unit = ctx.unit, item = ctx.item, text = ctx.text, kind = ctx.kind }
					P().after(0, function() W.runStack(r, t, c, (depth or 0) + 1) end)
					return true
				end
			end
			return false
		end,
	}
	env.wait = function(seconds, fn)
		if type(fn) ~= "function" then error("wait(seconds, function)", 2) end
		local st = W.state(r)
		st.waits = st.waits or {}
		local n = st.waits[box.id] or 0
		if n >= WS.MAX_WAITS then error("too many waits at once", 2) end
		st.waits[box.id] = n + 1
		seconds = math.max(0, math.min(30, tonumber(seconds) or 0))
		P().after(seconds, function()
			st.waits[box.id] = math.max(0, (st.waits[box.id] or 1) - 1)
			if r.items[box.id] ~= box or not live.rooms[r.id] then return end
			-- (the script's names are this run's again while it runs)
			local c = WS.compiled(r, box)
			local prev = c.env
			c.env = env
			local ok, err = WS.call(r, box, fn, {})
			c.env = prev
			if not ok then W.boxError(r, box, err) end
		end)
	end
	env._G = env
	return env
end

-- --- running ------------------------------------------------------------------------------------------
-- runs fn under the limits; true and what it returned, or false and why
-- can scripts be held to their limits here? (steps counted, the JIT switched off for them)
function WS.canLimit()
	if not (debug and debug.sethook) then return false end
	if jit and not jit.off then return false end
	return true
end

function WS.call(r, box, fn, args)
	if not WS.canLimit() then return false, "scripts can't run on this server (its Lua can't count their steps)" end
	local st = W.state(r)
	local sec = math.floor(P().clock())
	if st.scriptSecond ~= sec then st.scriptSecond, st.scriptSteps = sec, 0 end
	if (st.scriptSteps or 0) >= WS.ROOM_STEPS then return false, "this room's scripts did too much this second" end
	local steps = 0
	local memStart = collectgarbage("count")
	local why
	local co = coroutine.create(function(...) return fn(...) end)
	if jit and jit.off then jit.off(fn, true) end
	-- (LuaJIT has one hook for every coroutine: whatever was there before is put back after)
	local oldF, oldM, oldC
	if debug.gethook then oldF, oldM, oldC = debug.gethook() end
	debug.sethook(co, function()
		steps = steps + WS.HOOK_EVERY
		if steps > WS.MAX_STEPS then why = "it took too long (an endless loop?)" error(ABORT, 0) end
		if (st.scriptSteps or 0) + steps > WS.ROOM_STEPS then why = "this room's scripts did too much this second" error(ABORT, 0) end
		if collectgarbage("count") - memStart > WS.MAX_MEMORY then why = "it used too much memory" error(ABORT, 0) end
	end, "", WS.HOOK_EVERY)
	local res = { coroutine.resume(co, (unpack or table.unpack)(args or {})) }
	debug.sethook(co)
	if oldF then debug.sethook(oldF, oldM, oldC) else debug.sethook() end
	st.scriptSteps = (st.scriptSteps or 0) + steps
	if not res[1] then
		local err = res[2]
		if err == ABORT then return false, "stopped: " .. (why or "too much") end
		return false, tostring(err):gsub("^%[?[^:]*%]?:(%d+):", "line %1:")
	end
	if coroutine.status(co) ~= "dead" then return false, "scripts can't pause (use wait)" end
	return true, res[2]
end

-- a box's script, compiled once. Its environment is set once, to a stand-in that reads from (and
-- writes to) the run's own environment (some hosts let a function's environment be set only once).
function WS.compiled(r, box)
	local st = W.state(r)
	st.compiled = st.compiled or {}
	local c = st.compiled[box.id]
	local code = W.cfg(box).code or ""
	if c and c.code == code then return c end
	local fn, err = compile(code, "script")
	c = { code = code, fn = fn, err = err }
	if fn then
		c.proxy = setmetatable({}, {
			__index = function(_, k) return c.env and c.env[k] end,
			__newindex = function(_, k, v) if c.env then c.env[k] = v end end,
		})
		if setfenv then setfenv(fn, c.proxy)
		elseif debug.setupvalue then
			-- (Lua 5.2+: the script's _ENV is its first upvalue)
			if debug.getupvalue(fn, 1) == "_ENV" then debug.setupvalue(fn, 1, c.proxy) end
		end
	end
	st.compiled[box.id] = c
	return c
end

-- one run of a box's script with this context; true and what it returned, or false and why
function WS.run(r, box, ctx, depth)
	if not W.scriptsOn() then return false, "scripts are switched off in this hotel" end
	local c = WS.compiled(r, box)
	if not c.fn then return false, tostring(c.err) end
	local before = c.env
	c.env = WS.env(r, box, ctx, depth)
	local ok, res = WS.call(r, box, c.fn, {})
	-- (a run inside another, e.g. a wired teleport setting off the same box: back to the outer one's)
	c.env = before
	return ok, res
end

-- the boxes
W.define("script", { kind = "effect", furni = W.MAX_FURNI, script = true,
	run = function(r, box, cfg, ctx, depth)
		if (cfg.code or "") == "" then return end
		local ok, err = WS.run(r, box, ctx, depth)
		if not ok then W.boxError(r, box, err) end
	end })
W.define("scriptcondition", { kind = "condition", furni = W.MAX_FURNI, script = true,
	test = function(r, box, cfg, ctx)
		if (cfg.code or "") == "" then return true end
		local ok, res = WS.run(r, box, ctx)
		if not ok then W.boxError(r, box, res) return false end
		return res and true or false
	end })
