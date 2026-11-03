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
lib("furnidata.lua")
lib("roomcontent.lua")

-- client-only file, sent to players by the server
if SERVER then
	AddCSLuaFile("bobbahotel/addons/bobba_habbo/avatars.lua")
	AddCSLuaFile("bobbahotel/addons/bobba_habbo/furni.lua")
	AddCSLuaFile("bobbahotel/addons/bobba_habbo/planes.lua")
end

-- The hotel asks what a kind of furni is (its size, height, sitting...): Habbo's furnidata and the
-- furni's own file say (server; lib/furnidata.lua). Wall furni come later.
if SERVER and BOBBA.items then
	BOBBA.items.resolver = function(kind, cb)
		H.furnidata(function(fd, err)
			if not fd then cb(nil, err) return end
			local entry = fd.byClass[kind] or fd.byClass[H.furniBase(kind)]
			if not entry then cb(nil, "Habbo has no furni called " .. kind) return end
			if entry.wall then cb(nil, kind .. " goes on a wall (wall furni come later)") return end
			H.furniInfo(kind, function(info, err2)
				if not info then cb(nil, err2) return end
				cb({ width = info.width, length = info.length, height = info.height, walk = info.walk, sit = info.sit, lay = info.lay,
					directions = info.directions, states = info.states })
			end)
		end)
	end
end
