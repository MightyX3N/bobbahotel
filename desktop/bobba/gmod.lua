-- Garry's Mod's Lua functions, made from Love2D and LuaJIT, so the gamemode and its addons run
-- here as they are. This file is what the game and its server both have (hooks, timers, files,
-- include, net messages, convars, SQLite, HTTP, players); gmod_client.lua adds drawing, panels and
-- input for the game.
--
--   require("bobba.gmod")(cfg)
--   cfg.server        true on the server's thread
--   cfg.garrysmod     the garrysmod folder (gamemodes/, addons/, data/)
--   cfg.save          the desktop's own folder (its database, settings)
--   cfg.transport(s)  sends a message to the other side (a string)
--   cfg.console(text, color)  a line for the console
--   cfg.player        { key = SteamID64, name = ... } (the one playing)

local FS = require("bobba.fs")
local JSON = require("bobba.json")
local HTTP = require("bobba.http")
require("love.data")
require("love.timer")

return function(cfg)
	local G = {} -- what the desktop itself needs from here (G.tick, G.incoming, ...)
	local isServer = cfg.server and true or false
	SERVER, CLIENT = isServer, not isServer
	G.cfg = cfg
	local GMOD = FS.clean(cfg.garrysmod)

	-- --- printing ------------------------------------------------------------------------------
	local function out(text, color) cfg.console(text, color) end
	G.out = out
	print = function(...)
		local t = {}
		for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
		out(table.concat(t, "\t") .. "\n")
	end
	Msg = function(...)
		local t = {}
		for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
		out(table.concat(t))
	end
	MsgN = function(...) Msg(...) out("\n") end
	MsgC = function(...)
		local color
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if type(v) == "table" and v.r then color = v else out(tostring(v), color) end
		end
	end
	ErrorNoHalt = function(...)
		local t = {}
		for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
		out(table.concat(t), { r = 255, g = 90, b = 90 })
	end
	ErrorNoHaltWithStack = ErrorNoHalt

	-- --- small things --------------------------------------------------------------------------
	local colorMeta = {}
	colorMeta.__index = colorMeta
	function colorMeta:Unpack() return self.r, self.g, self.b, self.a end
	function colorMeta:ToTable() return { self.r, self.g, self.b, self.a } end
	colorMeta.__tostring = function(c) return string.format("%d %d %d %d", c.r, c.g, c.b, c.a) end
	colorMeta.__eq = function(a, b) return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a end
	Color = function(r, g, b, a)
		return setmetatable({ r = math.min(tonumber(r) or 255, 255), g = math.min(tonumber(g) or 255, 255), b = math.min(tonumber(b) or 255, 255), a = math.min(tonumber(a) or 255, 255) }, colorMeta)
	end
	IsColor = function(c) return getmetatable(c) == colorMeta end
	color_white, color_black, color_transparent = Color(255, 255, 255), Color(0, 0, 0), Color(255, 255, 255, 0)
	HSVToColor = function(h, s, v)
		h = h % 360
		local c = v * s
		local x = c * (1 - math.abs((h / 60) % 2 - 1))
		local m = v - c
		local r, g, b
		if h < 60 then r, g, b = c, x, 0 elseif h < 120 then r, g, b = x, c, 0 elseif h < 180 then r, g, b = 0, c, x
		elseif h < 240 then r, g, b = 0, x, c elseif h < 300 then r, g, b = x, 0, c else r, g, b = c, 0, x end
		return Color(math.floor((r + m) * 255), math.floor((g + m) * 255), math.floor((b + m) * 255))
	end
	ColorToHSV = function(c)
		local r, g, b = c.r / 255, c.g / 255, c.b / 255
		local max, min = math.max(r, g, b), math.min(r, g, b)
		local d = max - min
		local h = 0
		if d > 0 then
			if max == r then h = 60 * (((g - b) / d) % 6) elseif max == g then h = 60 * ((b - r) / d + 2) else h = 60 * ((r - g) / d + 4) end
		end
		return h, max == 0 and 0 or d / max, max
	end

	math.Clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end
	math.Round = function(v, d)
		local m = 10 ^ (d or 0)
		return math.floor(v * m + 0.5) / m
	end
	math.Approach = function(cur, target, inc)
		inc = math.abs(inc)
		if cur < target then return math.min(cur + inc, target) end
		if cur > target then return math.max(cur - inc, target) end
		return target
	end
	math.Remap = function(v, a, b, c, d) return c + (d - c) * ((v - a) / (b - a)) end
	string.Trim = function(s, ch)
		if ch then ch = ch:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") else ch = "%s" end
		return (s:gsub("^" .. ch .. "*(.-)" .. ch .. "*$", "%1"))
	end
	string.StartWith = function(s, p) return s:sub(1, #p) == p end
	string.StartsWith = string.StartWith
	string.EndsWith = function(s, p) return p == "" or s:sub(-#p) == p end
	string.Explode = function(sep, s, pattern)
		local t = {}
		if sep == "" then for i = 1, #s do t[i] = s:sub(i, i) end return t end
		local at = 1
		while true do
			local a, b = s:find(sep, at, not pattern)
			if not a then t[#t + 1] = s:sub(at) break end
			t[#t + 1] = s:sub(at, a - 1)
			at = b + 1
		end
		return t
	end
	string.Split = function(s, sep) return string.Explode(sep, s) end
	string.Replace = function(s, a, b) return (s:gsub(a:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"), (b:gsub("%%", "%%%%")))) end
	string.Left = function(s, n) return s:sub(1, n) end
	string.Right = function(s, n) return s:sub(-n) end
	table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
	table.HasValue = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
	table.GetKeys = function(t) local k = {} for x in pairs(t) do k[#k + 1] = x end return k end
	table.IsEmpty = function(t) return next(t) == nil end
	table.Copy = function(t, seen)
		seen = seen or {}
		if seen[t] then return seen[t] end
		local c = {}
		seen[t] = c
		for k, v in pairs(t) do c[k] = type(v) == "table" and table.Copy(v, seen) or v end
		return setmetatable(c, getmetatable(t))
	end
	table.Merge = function(a, b) for k, v in pairs(b) do if type(v) == "table" and type(a[k]) == "table" then table.Merge(a[k], v) else a[k] = v end end return a end
	table.Add = function(a, b) for _, v in ipairs(b) do a[#a + 1] = v end return a end
	table.Empty = function(t) for k in pairs(t) do t[k] = nil end end
	SortedPairs = function(t, desc)
		local keys = {}
		for k in pairs(t) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			if type(a) ~= type(b) then return tostring(a) < tostring(b) end
			if desc then return a > b end
			return a < b
		end)
		local i = 0
		return function()
			i = i + 1
			local k = keys[i]
			if k ~= nil then return k, t[k] end
		end
	end
	isstring = function(v) return type(v) == "string" end
	isnumber = function(v) return type(v) == "number" end
	istable = function(v) return type(v) == "table" end
	isfunction = function(v) return type(v) == "function" end
	isbool = function(v) return type(v) == "boolean" end
	tobool = function(v) return v ~= nil and v ~= false and v ~= 0 and v ~= "0" and v ~= "false" end
	bit = bit or require("bit")
	utf8 = utf8 or require("utf8")
	unpack = unpack or table.unpack

	IsValid = function(o)
		if not o then return false end
		local t = type(o)
		if t ~= "table" and t ~= "userdata" then return false end
		local fn = o.IsValid
		if type(fn) ~= "function" then return false end
		return fn(o) and true or false
	end
	NULL = setmetatable({}, { __index = function() return function() end end })
	rawset(NULL, "IsValid", function() return false end)

	-- --- time -----------------------------------------------------------------------------------
	local started = love.timer.getTime()
	SysTime = function() return love.timer.getTime() end
	CurTime = function() return love.timer.getTime() - started end
	RealTime = CurTime
	UnPredictedCurTime = CurTime
	G.frameTime, G.frame = 1 / 60, 0
	FrameTime = function() return G.frameTime end
	RealFrameTime = FrameTime
	FrameNumber = function() return G.frame end
	engine = { TickInterval = function() return 1 / 66 end, ActiveGamemode = function() return "bobbahotel" end }
	game = { SinglePlayer = function() return true end, MaxPlayers = function() return 1 end, GetMap = function() return "bobba_desktop" end, IsDedicated = function() return false end }
	system = { IsWindows = function() return FS.windows end, IsLinux = function() return not FS.windows end, IsOSX = function() return false end, SteamTime = os.time, AppTime = SysTime }

	-- --- hooks ----------------------------------------------------------------------------------
	local hooks = {}
	hook = {}
	function hook.Add(name, id, fn)
		if type(fn) ~= "function" then return end
		hooks[name] = hooks[name] or {}
		hooks[name][id] = fn
	end
	function hook.Remove(name, id) if hooks[name] then hooks[name][id] = nil end end
	function hook.GetTable() return hooks end
	function hook.Call(name, gm, ...)
		local list = hooks[name]
		if list then
			for id, fn in pairs(list) do
				local ok, a, b, c, d = pcall(fn, ...)
				if not ok then
					ErrorNoHalt("[hook " .. name .. " " .. tostring(id) .. "] " .. tostring(a) .. "\n")
				elseif a ~= nil then
					return a, b, c, d
				end
			end
		end
		if gm and type(gm[name]) == "function" then
			local ok, a, b, c, d = pcall(gm[name], gm, ...)
			if ok then return a, b, c, d end
			ErrorNoHalt("[GM:" .. name .. "] " .. tostring(a) .. "\n")
		end
	end
	function hook.Run(name, ...) return hook.Call(name, GAMEMODE, ...) end

	-- --- timers ---------------------------------------------------------------------------------
	local timers, simple = {}, {}
	timer = {}
	function timer.Simple(delay, fn) simple[#simple + 1] = { at = SysTime() + (tonumber(delay) or 0), fn = fn } end
	function timer.Create(id, delay, reps, fn)
		timers[id] = { delay = tonumber(delay) or 0, reps = tonumber(reps) or 1, fn = fn, at = SysTime() + (tonumber(delay) or 0), done = 0 }
	end
	function timer.Remove(id) timers[id] = nil end
	function timer.Exists(id) return timers[id] ~= nil end
	function timer.Adjust(id, delay, reps, fn)
		local t = timers[id]
		if not t then return false end
		t.delay = delay or t.delay
		if reps then t.reps = reps end
		if fn then t.fn = fn end
		return true
	end
	function timer.Start(id) local t = timers[id] if t then t.at = SysTime() + t.delay end end
	function timer.Stop(id) local t = timers[id] if t then t.at = math.huge end end
	local function runTimers()
		local now = SysTime()
		if #simple > 0 then
			local due, keep = {}, {}
			for _, s in ipairs(simple) do if s.at <= now then due[#due + 1] = s else keep[#keep + 1] = s end end
			simple = keep
			for _, s in ipairs(due) do
				local ok, err = pcall(s.fn)
				if not ok then ErrorNoHalt("[timer] " .. tostring(err) .. "\n") end
			end
		end
		for id, t in pairs(timers) do
			if t.at <= now and timers[id] == t then
				t.at = now + t.delay
				t.done = t.done + 1
				if t.reps > 0 and t.done >= t.reps then timers[id] = nil end
				local ok, err = pcall(t.fn)
				if not ok then ErrorNoHalt("[timer " .. tostring(id) .. "] " .. tostring(err) .. "\n") end
			end
		end
	end

	-- --- convars and console commands -----------------------------------------------------------
	FCVAR_NONE, FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY, FCVAR_USERINFO, FCVAR_PROTECTED, FCVAR_CHEAT = 0, 128, 8192, 256, 512, 32, 16384
	local convars, commands, changeCallbacks = {}, {}, {}
	local cfgFile = FS.join(cfg.save, isServer and "server.cfg" or "client.cfg")
	local saved = {}
	do
		local text = FS.read(cfgFile)
		for name, value in (text or ""):gmatch('([%w_]+)%s+"([^"\n]*)"') do saved[name] = value end
	end
	local function saveConvars()
		local lines = {}
		for name, cv in pairs(convars) do if cv.archive then lines[#lines + 1] = name .. ' "' .. cv.value:gsub('"', "") .. '"' end end
		table.sort(lines)
		FS.write(cfgFile, table.concat(lines, "\n") .. "\n")
	end
	local cvMeta = {}
	cvMeta.__index = cvMeta
	function cvMeta:GetString() return self.value end
	function cvMeta:GetInt() return math.floor(tonumber(self.value) or 0) end
	function cvMeta:GetFloat() return tonumber(self.value) or 0 end
	function cvMeta:GetBool() return (tonumber(self.value) or 0) ~= 0 end
	function cvMeta:GetName() return self.name end
	function cvMeta:GetDefault() return self.default end
	function cvMeta:GetHelpText() return self.help or "" end
	function cvMeta:SetString(v) G.setConvar(self.name, tostring(v)) end
	function cvMeta:SetInt(v) G.setConvar(self.name, tostring(math.floor(tonumber(v) or 0))) end
	function cvMeta:SetFloat(v) G.setConvar(self.name, tostring(v)) end
	function cvMeta:SetBool(v) G.setConvar(self.name, v and "1" or "0") end

	local function makeConvar(name, default, archive, help)
		if convars[name] then return convars[name] end
		local cv = setmetatable({ name = name, default = tostring(default or ""), archive = archive, help = help }, cvMeta)
		cv.value = (archive and saved[name]) or cv.default
		convars[name] = cv
		return cv
	end
	CreateConVar = function(name, default, flags, help)
		if type(flags) == "table" then local f = 0 for _, x in ipairs(flags) do f = bit.bor(f, x) end flags = f end
		return makeConvar(name, default, bit.band(tonumber(flags) or 0, FCVAR_ARCHIVE) ~= 0, help)
	end
	CreateClientConVar = function(name, default, archive, userinfo, help)
		return makeConvar(name, default, archive ~= false, help)
	end
	GetConVar = function(name) return convars[name] end
	GetConVarNumber = function(name) local c = convars[name] return c and c:GetFloat() or 0 end
	GetConVarString = function(name) local c = convars[name] return c and c:GetString() or "" end
	ConVarExists = function(name) return convars[name] ~= nil end
	makeConvar("gmod_language", "en", false)

	function G.setConvar(name, value)
		local cv = convars[name]
		if not cv then return false end
		local old = cv.value
		if old == value then return true end
		cv.value = value
		if cv.archive then saveConvars() end
		for id, fn in pairs(changeCallbacks[name] or {}) do
			local ok, err = pcall(fn, name, old, value)
			if not ok then ErrorNoHalt("[cvars " .. tostring(id) .. "] " .. tostring(err) .. "\n") end
		end
		return true
	end
	cvars = {
		AddChangeCallback = function(name, fn, id)
			changeCallbacks[name] = changeCallbacks[name] or {}
			changeCallbacks[name][id or (#changeCallbacks[name] + 1)] = fn
		end,
		RemoveChangeCallback = function(name, id) if changeCallbacks[name] then changeCallbacks[name][id] = nil end end,
		String = function(name, def) local c = convars[name] return c and c.value or def end,
		Number = function(name, def) local c = convars[name] return c and tonumber(c.value) or def end,
		Bool = function(name, def) local c = convars[name] if not c then return def end return (tonumber(c.value) or 0) ~= 0 end,
	}
	concommand = {
		Add = function(name, fn, complete, help) commands[name:lower()] = fn end,
		Remove = function(name) commands[name:lower()] = nil end,
		GetTable = function() return commands end,
	}
	-- splits a console line like GMod: words, "quoted words"
	local function words(line)
		local t = {}
		local i = 1
		while i <= #line do
			local c = line:sub(i, i)
			if c:match("%s") then i = i + 1
			elseif c == '"' then
				local j = line:find('"', i + 1, true) or (#line + 1)
				t[#t + 1] = line:sub(i + 1, j - 1)
				i = j + 1
			else
				local j = line:find("%s", i) or (#line + 1)
				t[#t + 1] = line:sub(i, j - 1)
				i = j
			end
		end
		return t
	end
	-- runs a console line here; false when nothing here knows it
	function G.runCommand(line, ply)
		local args = words(line)
		local name = args[1] and args[1]:lower()
		if not name then return true end
		table.remove(args, 1)
		local fn = commands[name]
		if fn then
			local ok, err = pcall(fn, ply or (CLIENT and LocalPlayer and LocalPlayer()) or NULL, name, args, table.concat(args, " "))
			if not ok then ErrorNoHalt("[" .. name .. "] " .. tostring(err) .. "\n") end
			return true
		end
		local cv = convars[name]
		if cv then
			if #args == 0 then out(name .. ' = "' .. cv.value .. '" (default "' .. cv.default .. '")' .. (cv.help and ("\n " .. cv.help) or "") .. "\n")
			else G.setConvar(name, table.concat(args, " ")) end
			return true
		end
		return false
	end
	RunConsoleCommand = function(name, ...)
		local parts = { name }
		for i = 1, select("#", ...) do parts[#parts + 1] = '"' .. tostring((select(i, ...))) .. '"' end
		G.console(table.concat(parts, " "))
	end
	-- a line typed in the console (or from RunConsoleCommand): here, or the server's
	function G.console(line)
		if G.runCommand(line) then return end
		if CLIENT then cfg.transport("C" .. line) else out("Unknown command: " .. line .. "\n") end
	end
	function G.commandNames()
		local t = {}
		for n in pairs(commands) do t[#t + 1] = n end
		for n in pairs(convars) do t[#t + 1] = n end
		table.sort(t)
		return t
	end

	-- --- files ----------------------------------------------------------------------------------
	-- GMod's "LUA" path: lua/ and every addon's lua/, and the gamemodes
	local luaRoots = {}
	local function addRoot(p) if FS.isDir(p) then luaRoots[#luaRoots + 1] = p end end
	addRoot(GMOD .. "/lua")
	addRoot(GMOD .. "/gamemodes")
	local _, addonDirs = FS.list(GMOD .. "/addons")
	for _, a in ipairs(addonDirs) do
		addRoot(GMOD .. "/addons/" .. a .. "/lua")
		addRoot(GMOD .. "/addons/" .. a .. "/gamemodes")
	end
	G.luaRoots = luaRoots
	-- "GAME" is garrysmod/ and every addon (fonts, sounds, materials)
	local gameRoots = { GMOD }
	for _, a in ipairs(addonDirs) do gameRoots[#gameRoots + 1] = GMOD .. "/addons/" .. a end
	G.gameRoots = gameRoots

	local DATA = GMOD .. "/data"
	-- a name the game gives: no going up (".."), no drive or root, as GMod allows
	local function safeName(p)
		p = tostring(p or ""):gsub("\\", "/"):gsub("^%a:", ""):gsub("^/+", "")
		for part in p:gmatch("[^/]+") do if part == ".." then return "_invalid_" end end
		return p
	end
	G.safeName = safeName
	-- (Windows doesn't mind the case of names; elsewhere a name GMod wrote in lower case is found too)
	local function dataPath(p)
		p = DATA .. "/" .. safeName(p)
		if not FS.windows and not FS.exists(p) then
			local low = DATA .. "/" .. p:sub(#DATA + 2):lower()
			if FS.exists(low) then return low end
		end
		return p
	end
	G.dataPath = dataPath

	local function rootsFor(where)
		where = (where or "GAME"):upper()
		if where == "DATA" then return { DATA }, true end
		if where == "LUA" or where == "LSV" or where == "LCL" then return luaRoots end
		if where == "MOD" then return { GMOD } end
		return gameRoots
	end
	-- the file's real path on the computer (the first root that has it)
	function G.findPath(name, where)
		local roots, data = rootsFor(where)
		name = safeName(name)
		if data then
			local p = dataPath(name)
			return FS.exists(p) and p or nil
		end
		for _, r in ipairs(roots) do
			local p = r .. "/" .. name
			if FS.exists(p) then return p end
		end
	end

	file = {}
	function file.Read(name, where)
		if where == true then where = "GAME" end
		local p = G.findPath(name, where or "DATA")
		if not p or FS.isDir(p) then return nil end
		return FS.read(p)
	end
	function file.Write(name, data)
		local p = dataPath(name)
		FS.mkdirs(FS.parent(p))
		FS.write(p, tostring(data))
	end
	function file.Append(name, data)
		local p = dataPath(name)
		FS.mkdirs(FS.parent(p))
		FS.write(p, tostring(data), true)
	end
	function file.Exists(name, where) return G.findPath(name, where or "GAME") ~= nil end
	function file.IsDir(name, where) local p = G.findPath(name, where or "GAME") return p ~= nil and FS.isDir(p) end
	function file.CreateDir(name) FS.mkdirs(dataPath(name)) end
	function file.Delete(name) os.remove(dataPath(name)) end
	function file.Size(name, where)
		local d = file.Read(name, where)
		return d and #d or -1
	end
	function file.Time(name, where) return 0 end
	-- file.Find("folder/*.lua", "LUA") -> files, folders (from every root, each once, sorted)
	function file.Find(pattern, where)
		local roots, data = rootsFor(where)
		pattern = pattern:gsub("\\", "/")
		local dir, glob = pattern:match("^(.*)/([^/]*)$")
		if not dir then dir, glob = "", pattern end
		local lp = FS.globPattern(glob)
		local files, dirs, seenF, seenD = {}, {}, {}, {}
		for _, r in ipairs(roots) do
			local full = dir == "" and r or (r .. "/" .. dir)
			local fs, ds = FS.list(full)
			for _, f in ipairs(fs) do if not seenF[f] and f:match(lp) then seenF[f] = true files[#files + 1] = f end end
			for _, d in ipairs(ds) do if not seenD[d] and d:match(lp) then seenD[d] = true dirs[#dirs + 1] = d end end
		end
		table.sort(files)
		table.sort(dirs)
		return files, dirs
	end

	-- --- include --------------------------------------------------------------------------------
	local stack = {}
	G.includeStack = stack
	-- a Lua file by GMod's rules: next to the file including it, then from the roots
	local function resolve(name)
		name = name:gsub("\\", "/")
		local cur = stack[#stack]
		if cur then
			local dir = cur.rel:match("^(.*)/[^/]*$")
			if dir then
				local rel = dir .. "/" .. name
				for _, r in ipairs(luaRoots) do
					local p = r .. "/" .. rel
					if FS.kind(p) == "file" then return p, rel end
				end
			end
		end
		for _, r in ipairs(luaRoots) do
			local p = r .. "/" .. name
			if FS.kind(p) == "file" then return p, name end
		end
	end
	-- --- the sandbox: the hotel's Lua (the gamemode, its addons; one day a server's) has what GMod
	-- gives, not more: no io, no running programs, no FFI or LuaJIT's insides, no love, files only
	-- through file.* (written only in data/), no loading bytecode. Its globals are the real ones
	-- (the desktop reads BOBBA from them), but what it can see of them is filtered.
	local realLoad = loadstring
	local ENV = {}
	G.env = ENV
	local function sandboxed(fn) if type(fn) == "function" then setfenv(fn, ENV) end return fn end
	local function compile(code, name)
		code = tostring(code or "")
		if code:byte(1) == 27 then return nil, "bytecode isn't allowed" end
		local fn, err = realLoad(code, name)
		return sandboxed(fn), err
	end
	G.compile = compile
	local safeOS = { time = os.time, date = os.date, clock = os.clock, difftime = os.difftime }
	local safeDebug = {
		traceback = debug.traceback,
		getinfo = function(f, what)
			local i = debug.getinfo(type(f) == "number" and f + 1 or f, what)
			if i then i.func = nil end
			return i
		end,
	}
	local SAFE = {
		os = safeOS, debug = safeDebug, _G = ENV,
		loadstring = function(code, name) return compile(code, name) end,
		getfenv = function(f)
			local ok, e = pcall(getfenv, type(f) == "number" and f + 1 or f or 2)
			if ok and e ~= _G then return e end
			return ENV
		end,
		setfenv = function(f, t)
			if type(f) == "function" and getfenv(f) ~= ENV then error("setfenv: that function isn't the game's", 2) end
			return setfenv(f, t)
		end,
	}
	local BLOCKED = { io = true, os = true, require = true, ffi = true, jit = true, debug = true, package = true, loadfile = true,
		dofile = true, load = true, loadstring = true, getfenv = true, setfenv = true, love = true, module = true, _G = true, arg = true,
		TEST = true, TEST_API = true }
	setmetatable(ENV, {
		__index = function(_, k) if BLOCKED[k] then return SAFE[k] end return _G[k] end,
		__newindex = function(_, k, v) if BLOCKED[k] then return end _G[k] = v end,
		__metatable = false,
	})
	function G.runFile(path, rel)
		local src = FS.read(path)
		if not src then ErrorNoHalt("Couldn't read " .. path .. "\n") return end
		local fn, err = compile(src, "@" .. rel)
		if not fn then ErrorNoHalt(tostring(err) .. "\n") return end
		stack[#stack + 1] = { path = path, rel = rel }
		local res = { pcall(fn) }
		stack[#stack] = nil
		if not res[1] then ErrorNoHalt(tostring(res[2]) .. "\n") return end
		return unpack(res, 2, table.maxn(res))
	end
	include = function(name)
		local p, rel = resolve(name)
		if not p then ErrorNoHalt("Couldn't include file '" .. tostring(name) .. "' (File not found)\n") return end
		return G.runFile(p, rel)
	end
	CompileFile = function(name)
		local p, rel = resolve(name)
		if not p then return nil end
		return (compile(FS.read(p), "@" .. rel))
	end
	CompileString = function(code, id, handle)
		local fn, err = compile(code, "@" .. tostring(id))
		if not fn and handle ~= false then ErrorNoHalt(tostring(err) .. "\n") end
		if not fn and handle == false then return err end
		return fn
	end
	RunString = function(code, id) local fn = CompileString(code, id or "RunString") if type(fn) == "function" then fn() end end
	AddCSLuaFile = function() end
	resource = { AddFile = function() end, AddSingleFile = function() end, AddWorkshop = function() end }
	DeriveGamemode = function() end
	GM = { Name = "", Folder = "gamemodes/bobbahotel" }
	GAMEMODE = GM

	-- --- util -----------------------------------------------------------------------------------
	util = util or {}
	util.TableToJSON = function(t, pretty) return JSON.encode(t) end
	util.JSONToTable = function(s) local v = JSON.decode(s) if type(v) == "table" then return v end return nil end
	-- (zlib: both ends are this program; GMod's own LZMA comes with the custom server)
	util.Compress = function(s)
		if s == nil or s == "" then return "" end
		return love.data.compress("string", "zlib", s)
	end
	util.Decompress = function(s)
		if s == nil or s == "" then return nil end
		local ok, r = pcall(love.data.decompress, "string", "zlib", s)
		if ok then return r end
	end
	util.AddNetworkString = function() return 1 end
	util.NetworkStringToID = function() return 1 end
	util.CRC = function(s)
		local crc = 0xFFFFFFFF
		for i = 1, #s do
			crc = bit.bxor(crc, s:byte(i))
			for _ = 1, 8 do crc = bit.bxor(bit.rshift(crc, 1), bit.band(0xEDB88320, -bit.band(crc, 1))) end
		end
		crc = bit.bnot(crc)
		if crc < 0 then crc = crc + 2 ^ 32 end
		return tostring(crc)
	end
	util.Base64Encode = function(s) return love.data.encode("string", "base64", s) end
	util.Base64Decode = function(s) local ok, r = pcall(love.data.decode, "string", "base64", s) return ok and r or nil end
	util.SHA256 = function(s) return love.data.encode("string", "hex", love.data.hash("sha256", s)) end
	util.MD5 = function(s) return love.data.encode("string", "hex", love.data.hash("md5", s)) end

	-- --- SQLite (the server's) ------------------------------------------------------------------
	if isServer then
		local SQ = require("bobba.sqlite")
		local db, why = SQ.open(FS.join(cfg.save, cfg.database or "hotel.db"))
		if not db then out("[Desktop] " .. tostring(why) .. "\n", { r = 255, g = 90, b = 90 }) end
		local last = ""
		sql = {
			Query = function(s)
				if not db then last = "no database" return false end
				local r = db:query(s)
				if r == false then last = db.lastError end
				return r
			end,
			QueryRow = function(s, row) local r = sql.Query(s) return r and r[row or 1] end,
			QueryValue = function(s) local r = sql.Query(s) if r and r[1] then for _, v in pairs(r[1]) do return v end end end,
			SQLStr = function(s, noQuotes) return SQ.quote(s, noQuotes) end,
			LastError = function() return last end,
			TableExists = function(t) return sql.Query("SELECT name FROM sqlite_master WHERE name = " .. SQ.quote(t) .. " AND type = 'table'") ~= nil end,
			Begin = function() sql.Query("BEGIN") end,
			Commit = function() sql.Query("COMMIT") end,
		}
		SQLStr = sql.SQLStr
		G.db = db
	end

	-- --- HTTP -------------------------------------------------------------------------------------
	HTTP.init(isServer and "server" or "client")
	http = {
		Fetch = function(url, ok, fail, headers)
			HTTP.get(url, function(code, body)
				if code and code > 0 then
					if ok then ok(body, #body, {}, code) end
				elseif fail then
					fail(body ~= "" and body or "unsuccessful")
				end
			end)
		end,
	}
	HTTP_FETCH = http.Fetch

	-- --- players ----------------------------------------------------------------------------------
	local playerMeta = {}
	playerMeta.__index = playerMeta
	function playerMeta:IsValid() return self.valid end
	function playerMeta:SteamID64() return self.key end
	function playerMeta:SteamID()
		local n = tonumber(self.key)
		if not n then return "STEAM_0:0:0" end
		local id = n - 76561197960265728
		return "STEAM_0:" .. (id % 2) .. ":" .. math.floor(id / 2)
	end
	function playerMeta:AccountID() return (tonumber(self.key) or 0) - 76561197960265728 end
	function playerMeta:Nick() return self.name end
	playerMeta.Name, playerMeta.GetName = playerMeta.Nick, playerMeta.Nick
	function playerMeta:IsBot() return false end
	function playerMeta:IsPlayer() return true end
	function playerMeta:IsAdmin() return true end -- (the one playing owns this hotel)
	function playerMeta:IsSuperAdmin() return true end
	function playerMeta:IsListenServerHost() return true end
	function playerMeta:GetUserGroup() return "superadmin" end
	function playerMeta:UserID() return 1 end
	function playerMeta:EntIndex() return 1 end
	function playerMeta:Ping() return 0 end
	function playerMeta:PrintMessage(kind, text)
		if isServer then cfg.transport("P" .. tostring(text) .. "\n") else out(tostring(text) .. "\n") end
	end
	function playerMeta:ChatPrint(text) self:PrintMessage(3, text) end
	function playerMeta:Kick(reason) out("Kicked: " .. tostring(reason) .. "\n") end
	setmetatable(playerMeta, { __index = function() return function() end end })
	G.player = setmetatable({ key = cfg.player.key, name = cfg.player.name, valid = false }, playerMeta)
	player = {
		GetAll = function() return G.player.valid and { G.player } or {} end,
		GetHumans = function() return G.player.valid and { G.player } or {} end,
		GetBots = function() return {} end,
		GetCount = function() return G.player.valid and 1 or 0 end,
		GetBySteamID64 = function(id) if G.player.valid and G.player.key == id then return G.player end return false end,
	}
	HUD_PRINTNOTIFY, HUD_PRINTCONSOLE, HUD_PRINTTALK, HUD_PRINTCENTER = 1, 2, 3, 4
	MOVETYPE_NONE, MOVETYPE_WALK, MOVETYPE_NOCLIP = 0, 2, 8

	-- --- net messages ---------------------------------------------------------------------------
	local receivers = {}
	local outgoing
	local reading, readAt = "", 1
	local function u32(n)
		n = math.floor(tonumber(n) or 0) % 4294967296
		return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
	end
	net = {}
	function net.Start(name) outgoing = { name = name, parts = {} } end
	function net.WriteString(s) local p = outgoing.parts p[#p + 1] = tostring(s):gsub("%z", "") .. "\0" end
	function net.WriteUInt(n, bits) local p = outgoing.parts p[#p + 1] = u32(n) end
	function net.WriteInt(n, bits) local p = outgoing.parts p[#p + 1] = u32(n) end
	function net.WriteBool(b) local p = outgoing.parts p[#p + 1] = b and "\1" or "\0" end
	function net.WriteFloat(f) net.WriteString(tostring(f)) end
	net.WriteDouble = net.WriteFloat
	function net.WriteData(d, len) local p = outgoing.parts p[#p + 1] = u32(len or #d) .. d:sub(1, len or #d) end
	function net.WriteTable(t) net.WriteString(JSON.encode(t)) end
	function net.ReadString()
		local j = reading:find("\0", readAt, true) or (#reading + 1)
		local s = reading:sub(readAt, j - 1)
		readAt = j + 1
		return s
	end
	function net.ReadUInt()
		local a, b, c, d = reading:byte(readAt, readAt + 3)
		readAt = readAt + 4
		return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216
	end
	function net.ReadInt(bits)
		local n = net.ReadUInt()
		if n >= 2147483648 then n = n - 4294967296 end
		return n
	end
	function net.ReadBool() local b = reading:byte(readAt) readAt = readAt + 1 return b == 1 end
	function net.ReadFloat() return tonumber(net.ReadString()) or 0 end
	net.ReadDouble = net.ReadFloat
	function net.ReadData(len)
		local n = net.ReadUInt()
		local d = reading:sub(readAt, readAt + n - 1)
		readAt = readAt + n
		return d
	end
	function net.ReadTable() return JSON.decode(net.ReadString()) or {} end
	function net.Receive(name, fn) receivers[name:lower()] = fn end
	local function send()
		if not outgoing then return end
		cfg.transport("N" .. outgoing.name .. "\0" .. table.concat(outgoing.parts))
		outgoing = nil
	end
	net.Send = send
	net.Broadcast = send
	net.SendToServer = send
	net.SendOmit = function() outgoing = nil end
	net.BytesWritten = function() return outgoing and #table.concat(outgoing.parts) or 0 end

	-- a message from the other side
	function G.incoming(msg)
		local kind = msg:sub(1, 1)
		if kind == "N" then
			local j = msg:find("\0", 2, true)
			local name = msg:sub(2, j - 1)
			local fn = receivers[name:lower()]
			if not fn then return end
			reading, readAt = msg:sub(j + 1), 1
			local ok, err = pcall(fn, #reading * 8, isServer and G.player or nil)
			if not ok then ErrorNoHalt("[net " .. name .. "] " .. tostring(err) .. "\n") end
			reading = ""
		elseif kind == "C" and isServer then
			-- a console line from the player
			if not G.runCommand(msg:sub(2), G.player) then G.player:PrintMessage(2, "Unknown command: " .. msg:sub(2)) end
		elseif kind == "P" and not isServer then
			out(msg:sub(2))
		end
	end

	-- --- every frame / tick ---------------------------------------------------------------------
	function G.tick(dt)
		G.frame = G.frame + 1
		G.frameTime = dt or G.frameTime
		HTTP.poll()
		runTimers()
		hook.Run("Think")
		if isServer then hook.Run("Tick") end
	end

	return G
end
