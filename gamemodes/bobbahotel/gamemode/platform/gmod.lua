-- The platform layer on Garry's Mod: the only core file that calls GMod functions.

local P = {}
P.name = "gmod"
P.isServer = SERVER
P.isClient = CLIENT

local COLORS = { info = Color(120, 200, 255), warn = Color(255, 200, 80), error = Color(255, 90, 90) }

function P.log(level, msg)
	MsgC(COLORS[level] or color_white, "[Bobba] ", color_white, msg, "\n")
end

function P.time()
	return os.time()
end

-- seconds, precise (for timing between things, not dates)
function P.clock()
	return SysTime()
end

-- players: a key that stays the same (SteamID64; bots get one from their name) and the name shown
function P.playerKey(ply)
	if ply:IsBot() then return "bot_" .. ply:Nick() end
	return ply:SteamID64()
end

function P.playerName(ply)
	return ply:Nick()
end

function P.onLeave(fn)
	if SERVER then hook.Add("PlayerDisconnected", "bobba.leave." .. tostring(fn), fn) end
end

function P.after(seconds, fn)
	timer.Simple(seconds, fn)
end

function P.every(id, seconds, fn)
	timer.Create("bobba." .. id, seconds, 0, fn)
end

function P.stop(id)
	timer.Remove("bobba." .. id)
end

-- Saving: GMod's own SQLite (garrysmod/sv.db), server only.
if SERVER then
	P.db = {
		quote = function(s) return sql.SQLStr(s) end,
		query = function(s)
			local res = sql.Query(s)
			if res == false then return false, sql.LastError() end
			return res or {}
		end,
	}
end

-- Permissions: CAMI when an admin mod provides it (ULX, SAM, sAdmin, ...), otherwise GMod's
-- admin and superadmin.
P.permissionBackend = function()
	if CAMI then return "CAMI (" .. (ULib and "ULX" or sam and "SAM" or "admin mod") .. ")" end
	return "GMod admin/superadmin"
end

function P.definePermission(name, default, description)
	if CAMI and CAMI.RegisterPrivilege then
		CAMI.RegisterPrivilege({ Name = name, MinAccess = default, Description = description })
	end
end

local function fallback(ply, default)
	if default == "user" then return true end
	if default == "admin" then return ply:IsAdmin() end
	return ply:IsSuperAdmin()
end

function P.hasPermission(ply, name, default)
	if not IsValid(ply) then return true end -- the server console may do anything
	if CAMI and CAMI.PlayerHasAccess then
		local has = CAMI.PlayerHasAccess(ply, name, nil)
		if has ~= nil then return has == true end
	end
	return fallback(ply, default)
end

-- Hotel addons live in lua/bobbahotel/addons/<id>/ (a Workshop addon or a folder in garrysmod/addons).
local ADDONS = "bobbahotel/addons/"

function P.addonFolders()
	local _, dirs = file.Find(ADDONS .. "*", "LUA")
	table.sort(dirs)
	return dirs
end

function P.runAddonFile(folder, name)
	local path = ADDONS .. folder .. "/" .. name
	if SERVER then AddCSLuaFile(path) end
	return include(path)
end

function P.loadAddon(folder)
	local base = ADDONS .. folder .. "/"
	if file.Exists(base .. "shared.lua", "LUA") then
		if SERVER then AddCSLuaFile(base .. "shared.lua") end
		include(base .. "shared.lua")
	end
	if SERVER and file.Exists(base .. "server.lua", "LUA") then include(base .. "server.lua") end
	if file.Exists(base .. "client.lua", "LUA") then
		if SERVER then AddCSLuaFile(base .. "client.lua") else include(base .. "client.lua") end
	end
end

-- Addons the server switched off (ids separated by commas). Replicated, so players skip them too.
local disabledVar = CreateConVar("bobba_disabled_addons", "", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), "Hotel addons to switch off, ids separated by commas")
function P.disabledAddons()
	return disabledVar:GetString()
end
if SERVER then
	cvars.AddChangeCallback("bobba_disabled_addons", function(_, _, new)
		P.log("info", BOBBA.L("addons.changed", { list = new == "" and "-" or new }))
	end, "bobba")
end

-- Messages between server and players: a name and a table. For the foundation this sends JSON;
-- busy messages (room updates) get their own compact formats later.
if SERVER then util.AddNetworkString("bobba.msg") end
local receivers = {}

function P.receive(name, fn)
	receivers[name] = fn
end

local function write(name, data)
	local json = util.Compress(util.TableToJSON(data or {}))
	net.Start("bobba.msg")
	net.WriteString(name)
	net.WriteUInt(#json, 32)
	net.WriteData(json, #json)
end

function P.send(name, data, target)
	write(name, data)
	if SERVER then
		if target then net.Send(target) else net.Broadcast() end
	else
		net.SendToServer()
	end
end

net.Receive("bobba.msg", function(_, ply)
	local name = net.ReadString()
	local len = net.ReadUInt(32)
	if len > 65000 then return end
	local data = util.JSONToTable(util.Decompress(net.ReadData(len)) or "") or {}
	local fn = receivers[name]
	if fn then BOBBA.safe("message " .. name, fn, ply, data) end
end)

BOBBA.platform = P
