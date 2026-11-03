-- A stand-in platform for the tests: plain Lua, with the database handed in by the test runner
-- (Python's SQLite, the same SQL as GMod's). Addons are given as a table instead of folders.

local P = {}
P.name = "test"
P.isServer = true
P.isClient = false
P.logs = {}
P.clock = 1000000

function P.log(level, msg)
	P.logs[#P.logs + 1] = { level = level, msg = msg }
end

function P.time() return P.clock end

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

BOBBA.platform = P
