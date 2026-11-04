-- A stand-in platform for the tests: plain Lua, with the database handed in by the test runner
-- (Python's SQLite, the same SQL as GMod's). Addons are given as a table instead of folders.

local P = {}
P.name = "test"
P.isServer = true
P.isClient = false
P.logs = {}
P.now = 1000000 -- tests move time forward by changing this

function P.log(level, msg)
	P.logs[#P.logs + 1] = { level = level, msg = msg }
end

function P.time() return math.floor(P.now) end
function P.clock() return P.now end

-- players are tables { key = "...", name = "..." }
function P.playerKey(p) return p.key end
function P.playerName(p) return p.name end
P.leaveHandlers = {}
function P.onLeave(fn) P.leaveHandlers[#P.leaveHandlers + 1] = fn end
function P.disconnect(p) for _, fn in ipairs(P.leaveHandlers) do fn(p) end end

-- messages: what was sent (P.sent), and handlers to call as if a player sent something (P.fromPlayer)
P.sent = {}
P.receivers = {}
function P.send(name, data, target)
	local list = target
	if type(target) == "table" and target.key then list = { target } end
	P.sent[#P.sent + 1] = { name = name, data = data, to = list }
end
function P.receive(name, fn) P.receivers[name] = fn end
function P.fromPlayer(p, name, data) return P.receivers[name](p, data or {}) end
-- messages a player got, by name
function P.inbox(p, name)
	local out = {}
	for _, m in ipairs(P.sent) do
		if m.name == name then
			for _, to in ipairs(m.to or {}) do if to == p then out[#out + 1] = m.data end end
		end
	end
	return out
end

-- files (in memory)
P.files = {}
function P.writeData(path, bytes) P.files[path] = bytes end
function P.readData(path) return P.files[path] end
function P.dataExists(path) return P.files[path] ~= nil end

-- timers: P.runTimers() runs every repeating timer once
P.timers = {}
function P.every(id, seconds, fn) P.timers[id] = fn end
function P.after(seconds, fn) fn() end
function P.stop(id) P.timers[id] = nil end
function P.runTimers() for _, fn in pairs(P.timers) do fn() end end

P.db = {
	quote = function(s)
		return "'" .. s:gsub("%z", ""):gsub("'", "''") .. "'"
	end,
	query = function(s)
		local rows, err = TEST_DB_QUERY(s)
		if rows == false then return false, err end
		return rows
	end,
}

P.granted = {}       -- player -> { permission = true }
P.defined = {}
function P.definePermission(name, default) P.defined[name] = default end
function P.hasPermission(player, name, default)
	if player == "console" then return true end
	local g = P.granted[player]
	if g and g[name] ~= nil then return g[name] end
	return default == "user"
end
function P.permissionBackend() return "test" end

-- addons: P.fakeAddons[folder] = { ["addon.lua"] = function() return {...} end, ["shared.lua"] = function() ... end }
P.fakeAddons = {}
P.disabled = ""
function P.addonFolders()
	local out = {}
	for k in pairs(P.fakeAddons) do out[#out + 1] = k end
	table.sort(out)
	return out
end
function P.runAddonFile(folder, name)
	local f = P.fakeAddons[folder][name]
	if f then return f() end
end
function P.loadAddon(folder)
	for _, name in ipairs({ "shared.lua", "server.lua" }) do
		local f = P.fakeAddons[folder][name]
		if f then f() end
	end
end
function P.disabledAddons() return P.disabled end
function P.setDisabledAddons(s) P.disabled = s end
function P.canRestart() return true end
function P.restartHotel() P.restarted = (P.restarted or 0) + 1 end

BOBBA.platform = P
