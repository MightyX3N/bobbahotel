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
	AddCSLuaFile("bobbahotel/addons/bobba_habbo/ui.lua")
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
	BOBBA.looks.validator = function(figure, gender, key)
		if not fd then return nil, "the hotel's clothes are still loading, try again in a moment" end
		local level = (key ~= nil and BOBBA.wallet ~= nil) and BOBBA.wallet.clubLevel(key) or 0
		return H.validateLook(fd, figure, gender, level, {})
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

-- The catalogue's furni (server): Habbo's floor furni that Habbo sells (an offerid), a page for each
-- furni line ("pura", "iced", ...) under "Furni". Left out for now: wall furni, and what needs
-- something the hotel doesn't have yet (wired, pets, music, teleports, clothing, groups, effects).
-- Every furni costs the hotel's catalog.price credits (bobba_wallet_setting catalog.price <n>).
H.CATALOG_SKIP_CATEGORIES = { pets = true, sound_fx = true, leaderboards = true, music = true, credit = true, teleport = true }
H.CATALOG_SKIP_LINES = { horse = true, nests = true, pet_food = true, pet_accessories = true, clothing = true, guilds = true,
	sfx = true, wired = true, fxbox = true }

function H.catalogLineName(line)
	if line == "" then return "Other" end
	local s = line:gsub("_", " ")
	return s:sub(1, 1):upper() .. s:sub(2)
end

if SERVER and BOBBA.catalog then
	BOBBA.catalog.provider = function(cb)
		H.furnidata(function(fd, err)
			if not fd then print("[Bobba] the catalogue: " .. tostring(err)) cb({}) return end
			local price = tonumber(BOBBA.store.setting("catalog.price", "5")) or 5
			local lines = {}
			for class, f in pairs(fd.byClass) do
				if not f.wall and (f.offer or -1) ~= -1 and f.special == 1 and not H.CATALOG_SKIP_CATEGORIES[f.category]
					and not f.category:find("^wired") and not H.CATALOG_SKIP_LINES[f.line] then
					local list = lines[f.line]
					if not list then list = {} lines[f.line] = list end
					list[#list + 1] = { kind = class, name = f.name ~= "" and f.name or class, price = { credits = price }, order = f.id or 0 }
				end
			end
			local pages = {}
			for line, offers in pairs(lines) do
				table.sort(offers, function(a, b) return a.order < b.order end)
				pages[#pages + 1] = { name = H.catalogLineName(line), line = line, offers = offers }
			end
			table.sort(pages, function(a, b)
				if (a.line == "") ~= (b.line == "") then return b.line == "" end
				return a.name:lower() < b.name:lower()
			end)
			cb({ { name = "Furni", nameKey = "catalog.furni", children = pages } })
		end)
	end
end
