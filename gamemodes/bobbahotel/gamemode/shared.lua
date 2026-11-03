-- Bobba Hotel: loads the core (plain Lua, see hotel/), the GMod platform layer, then the hotel addons.

GM.Name = "Bobba Hotel"
GM.Author = "Bobba Hotel"
DeriveGamemode("base")

local files = include("hotel/files.lua")
if SERVER then AddCSLuaFile("hotel/files.lua") end

for _, f in ipairs(files) do
	if f == "PLATFORM" then f = "platform/gmod.lua" end
	if SERVER then AddCSLuaFile(f) end
	include(f)
end

if SERVER then BOBBA.store.init() end

-- GMod's own language setting picks the hotel's language (English when there's no translation).
local gl = GetConVar("gmod_language")
BOBBA.lang.set(gl and gl:GetString() or "en")

BOBBA.addons.loadAll()

if SERVER then AddCSLuaFile("status.lua") end
include("status.lua")

-- client-only files (drawing, windows, input)
local CLIENT_FILES = { "client/view.lua" }
for _, f in ipairs(CLIENT_FILES) do
	if SERVER then AddCSLuaFile(f) else include(f) end
end
