-- Habbo content, downloaded from Habbo's own servers on each player's PC (nothing of Habbo's is in
-- this addon). Kept apart from the gamemode so it can be switched off or replaced.

BOBBA.habbo = BOBBA.habbo or {}
local H = BOBBA.habbo
local P = BOBBA.platform

local function lib(name) return P.runAddonFile("bobba_habbo", "lib/" .. name) end
H.deflate = H.deflate or lib("libdeflate.lua")
H.swf = lib("swf.lua")
H.png = lib("png.lua")
H.xml = lib("xml.lua")
H.zip = lib("zip.lua")
lib("work.lua")

function H.inflate(bytes)
	return (H.deflate:DecompressZlib(bytes))
end

function H.inflateRaw(bytes)
	return (H.deflate:DecompressDeflate(bytes))
end

function H.zlib(bytes)
	return (H.deflate:CompressZlib(bytes, { level = 1 }))
end

lib("library.lua")
lib("avatardata.lua")

-- client-only file, sent to players by the server
if SERVER then AddCSLuaFile("bobbahotel/addons/bobba_habbo/avatars.lua") end
