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

-- Downloads (http.Fetch): ok(body) or fail(reason)
function P.httpGet(url, ok, fail)
	http.Fetch(url, function(body, _, _, code)
		if code == 200 then ok(body) else fail("HTTP " .. tostring(code)) end
	end, function(err) fail(tostring(err)) end)
end

-- Files in garrysmod/data/bobbahotel/ (GMod only allows some endings there: .txt .dat .png .json ...)
function P.writeData(path, bytes)
	local dir = ("bobbahotel/" .. path):match("^(.*)/[^/]*$")
	if dir then file.CreateDir(dir) end
	file.Write("bobbahotel/" .. path, bytes)
end

function P.readData(path)
	return file.Read("bobbahotel/" .. path, "DATA")
end

function P.dataExists(path)
	return file.Exists("bobbahotel/" .. path, "DATA")
end

-- A material from a PNG written with writeData. flags: GMod's material flags (default "noclamp
-- smooth"; pixel art that is scaled up wants "noclamp" so the pixels stay sharp)
-- plays a sound file in garrysmod/data/bobbahotel/ (an MP3): volume 0..1, rate 1 = as it is
-- (higher: faster and higher). onPlay(channel) when it plays (optional)
function P.playSound(path, volume, rate, onPlay)
	if not sound or not sound.PlayFile then return end
	sound.PlayFile("data/bobbahotel/" .. path, "noplay", function(ch)
		if not IsValid(ch) then return end
		ch:SetVolume(math.Clamp(volume or 1, 0, 1))
		if rate and rate ~= 1 then ch:SetPlaybackRate(rate) end
		ch:Play()
		if onPlay then onPlay(ch) end
	end)
end

function P.dataMaterial(path, flags)
	return Material("../data/bobbahotel/" .. path, flags or "noclamp smooth")
end

-- A picture of something drawn (the camera): draw() draws as it would on the screen, and the part of
-- it at x, y, w, h becomes a PNG: cb(pngBytes) (or cb(nil) when it can't). Drawn off the screen, so
-- windows over it aren't in the picture. (The desktop app draws into a canvas; GMod into a render
-- target, read once the frame is drawn.)
function P.renderPNG(x, y, w, h, draw, cb)
	if love and love.graphics then
		local lg = love.graphics
		local canvas = lg.newCanvas(w, h)
		lg.push("all")
		lg.setCanvas(canvas)
		lg.origin()
		lg.setScissor()
		lg.clear(0, 0, 0, 1)
		lg.translate(-x, -y)
		local ok, err = pcall(draw)
		lg.pop()
		if not ok then print("[Bobba] picture: " .. tostring(err)) cb(nil) return end
		cb(canvas:newImageData():encode("png"):getString())
		return
	end
	if not render or not render.Capture then cb(nil) return end
	local rt = GetRenderTargetEx("bobba_picture_" .. w .. "x" .. h, w, h, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGB888)
	local id = "bobba.picture." .. tostring(draw)
	hook.Add("PostRender", id, function()
		hook.Remove("PostRender", id)
		render.PushRenderTarget(rt)
		render.Clear(0, 0, 0, 255, true, true)
		cam.Start2D()
		local m = Matrix()
		m:Translate(Vector(-x, -y, 0))
		cam.PushModelMatrix(m)
		local ok, err = pcall(draw)
		cam.PopModelMatrix()
		cam.End2D()
		local data = ok and render.Capture({ format = "png", x = 0, y = 0, w = w, h = h, alpha = false }) or nil
		render.PopRenderTarget()
		if not ok then print("[Bobba] picture: " .. tostring(err)) end
		cb(data)
	end)
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
