-- Finding Garry's Mod and who's signed in to Steam on this computer: Steam's folder from the
-- registry, its libraries from libraryfolders.vdf, the signed-in account (ActiveUser) and its name
-- from loginusers.vdf.

local ffi = require("ffi")
local FS = require("bobba.fs")
local ST = {}

local advapi
if ffi.os == "Windows" then
	ffi.cdef [[
	int RegGetValueA(void* key, const char* subkey, const char* value, uint32_t flags, uint32_t* type, void* data, uint32_t* size);
	]]
	local ok, lib = pcall(ffi.load, "advapi32")
	if ok then advapi = lib end
end
local HKCU = ffi.cast("void*", ffi.cast("intptr_t", 0x80000001))

local function regString(subkey, value)
	if not advapi then return nil end
	local size = ffi.new("uint32_t[1]", 1024)
	local buf = ffi.new("char[1024]")
	if advapi.RegGetValueA(HKCU, subkey, value, 0x02, nil, buf, size) ~= 0 then return nil end -- RRF_RT_REG_SZ
	return ffi.string(buf)
end
local function regNumber(subkey, value)
	if not advapi then return nil end
	local size = ffi.new("uint32_t[1]", 4)
	local buf = ffi.new("uint32_t[1]")
	if advapi.RegGetValueA(HKCU, subkey, value, 0x10, nil, buf, size) ~= 0 then return nil end -- RRF_RT_REG_DWORD
	return buf[0]
end

function ST.steamFolder()
	local p = regString("Software\\Valve\\Steam", "SteamPath")
	if p and FS.isDir(p) then return FS.clean(p) end
	for _, c in ipairs({ "C:/Program Files (x86)/Steam", "C:/Program Files/Steam", (os.getenv("HOME") or "") .. "/.steam/steam", (os.getenv("HOME") or "") .. "/.local/share/Steam" }) do
		if FS.isDir(c) then return c end
	end
end

-- every Steam library's folder
function ST.libraries()
	local steam = ST.steamFolder()
	local libs = {}
	if not steam then return libs end
	libs[1] = steam
	local vdf = FS.read(steam .. "/steamapps/libraryfolders.vdf") or ""
	for p in vdf:gmatch('"path"%s+"([^"]+)"') do
		p = FS.clean(p:gsub("\\\\", "\\"))
		local dup = false
		for _, l in ipairs(libs) do if l:lower() == p:lower() then dup = true end end
		if not dup then libs[#libs + 1] = p end
	end
	return libs
end

-- a garrysmod folder that has Bobba Hotel in it (gamemodes/bobbahotel), or nil
function ST.isGarrysmod(p)
	p = FS.clean(p)
	if FS.isDir(p .. "/gamemodes/bobbahotel/gamemode") then return p end
	if FS.isDir(p .. "/garrysmod/gamemodes/bobbahotel/gamemode") then return p .. "/garrysmod" end
	if FS.isDir(p .. "/steamapps/common/GarrysMod/garrysmod/gamemodes/bobbahotel") then return p .. "/steamapps/common/GarrysMod/garrysmod" end
	return nil
end
-- whether there's Garry's Mod there at all (without Bobba Hotel)
function ST.hasGarrysmod(p)
	p = FS.clean(p)
	return FS.isDir(p .. "/gamemodes") and FS.isDir(p .. "/addons")
end

function ST.findGarrysmod()
	for _, lib in ipairs(ST.libraries()) do
		local p = lib .. "/steamapps/common/GarrysMod/garrysmod"
		if FS.isDir(p) then return p, ST.isGarrysmod(p) ~= nil end
	end
end

-- the signed-in Steam account: SteamID64, name (or nil)
function ST.account()
	local id = regNumber("Software\\Valve\\Steam\\ActiveProcess", "ActiveUser")
	if not id or id == 0 then return nil end
	-- (76561197960265728 + the account id, as text: too big for a double to hold exactly)
	local base = { 7, 6, 5, 6, 1, 1, 9, 7, 9, 6, 0, 2, 6, 5, 7, 2, 8 }
	local digits = {}
	local n = id
	local i = #base
	local carry = 0
	while i >= 1 do
		local d = base[i] + (n % 10) + carry
		n = math.floor(n / 10)
		carry = math.floor(d / 10)
		digits[i] = d % 10
		i = i - 1
	end
	local key = table.concat(digits)
	local name
	local steam = ST.steamFolder()
	local vdf = steam and FS.read(steam .. "/config/loginusers.vdf") or ""
	local block = vdf:match('"' .. key .. '"%s*(%b{})')
	if block then name = block:match('"PersonaName"%s+"([^"]*)"') end
	return key, name
end

return ST
