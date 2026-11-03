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
-- (unpacking a big file in a job gives the frame back now and then)
H.deflate.pause = H.yield

-- something the hotel's loading screen (the gamemode's client/loading.lua) waits for; addons load
-- before it, so the list is started here if it isn't there yet
function H.loadingCheck(id, fn)
	BOBBA.loading = BOBBA.loading or { checks = {}, order = {} }
	local LD = BOBBA.loading
	if not LD.checks[id] then LD.order[#LD.order + 1] = id end
	LD.checks[id] = fn
end

function H.inflate(bytes)
	return (H.deflate:DecompressZlib(bytes))
end

function H.inflateRaw(bytes)
	return (H.deflate:DecompressDeflate(bytes))
end

-- (for the PNG files the addon writes: stored without squeezing, ten times quicker to write, so
-- making a picture the first time it's drawn costs a fraction of a millisecond)
function H.zlib(bytes)
	return (H.deflate:CompressZlib(bytes, { level = 0 }))
end

lib("library.lua")
lib("avatardata.lua")
lib("furnidata.lua")
lib("roomcontent.lua")
lib("chatstyles.lua")
lib("figuredata.lua")

-- client-only file, sent to players by the server
if SERVER then
	AddCSLuaFile("bobbahotel/addons/bobba_habbo/avatars.lua")
	AddCSLuaFile("bobbahotel/addons/bobba_habbo/furni.lua")
	AddCSLuaFile("bobbahotel/addons/bobba_habbo/planes.lua")
	AddCSLuaFile("bobbahotel/addons/bobba_habbo/chat.lua")
	AddCSLuaFile("bobbahotel/addons/bobba_habbo/editor.lua")
end

-- Looks are checked against Habbo's figuredata, the way Arcturus does (server; lib/figuredata.lua).
-- Until it's loaded (a moment after the server starts) a new look waits.
if SERVER and BOBBA.looks then
	local fd
	local function load()
		H.figureData(function(data, err)
			if data then fd = data else print("[Bobba] Habbo's figuredata: " .. tostring(err)) end
		end)
	end
	if BOBBA.platform.after then BOBBA.platform.after(1, load) else load() end
	BOBBA.looks.validator = function(figure, gender)
		if not fd then return nil, "the hotel's clothes are still loading, try again in a moment" end
		return H.validateLook(fd, figure, gender, false, {})
	end
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
