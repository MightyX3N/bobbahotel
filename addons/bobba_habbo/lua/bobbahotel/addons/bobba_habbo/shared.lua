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

-- the rooms new players pick from (Habbo's six classic ones)
P.runAddonFile("bobba_habbo", "starterrooms.lua")

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
-- furni's own file say (server; lib/furnidata.lua).
if SERVER and BOBBA.items then
	BOBBA.items.resolver = function(kind, cb)
		H.furnidata(function(fd, err)
			if not fd then cb(nil, err) return end
			local entry = H.furniEntry(fd, kind)
			if not entry then cb(nil, "Habbo has no furni called " .. kind) return end
			-- (Habbo's wallpapers, floors and landscapes are put on the room, not placed: nothing more
			-- to know, their file isn't needed)
			local paint = (entry.special == 2 and "wallpaper") or (entry.special == 3 and "floor") or (entry.special == 4 and "landscape") or nil
			if paint then
				cb({ width = 1, length = 1, height = 0, directions = { 2, 4 }, states = 1, category = entry.category, wall = true, paint = paint })
				return
			end
			local function got(info, err2)
				if not info then cb(nil, err2) return end
				cb({ width = info.width, length = info.length, height = info.height, walk = info.walk, sit = info.sit, lay = info.lay,
					directions = info.directions, states = info.states, logic = info.logic, category = entry.category, wall = entry.wall or nil })
			end
			-- (a poster without a file of its own is Habbo's "poster")
			H.furniInfo(kind, function(info, err2)
				if not info and H.posterNumber(kind) then H.furniInfo("poster", got) return end
				got(info, err2)
			end)
		end)
	end
end

-- The catalogue's furni (server): every floor furni in Habbo's furnidata, sold by Habbo now or not,
-- on a page for its furni line ("pura", "iced", ...) under "Furni". Lines of the same kind over the
-- years (Habboween 2009 ... 2026, Christmas, Easter, ...) are pages under one; a line with very many
-- furni is cut into parts. Left out:
--   rares and limited editions (H.CATALOG_RARE_LINES, and furni called LTD): staff give those
--   what needs something the hotel doesn't have yet (wired, pets, music, games, vending machines,
--     clothing, groups, effects)
--   Habbo's test furni
-- Posters (one furni in Habbo, a number each) get a page; so do stickies. Wallpapers, floors and
-- landscapes (Habbo's room content) are on a tab of their own, "Spaces".
-- Every furni costs the hotel's catalog.price credits (bobba_wallet_setting catalog.price <n>).
H.CATALOG_SKIP_CATEGORIES = { pets = true, leaderboards = true, music = true, credit = true,
	vending_machine = true, games = true }
H.CATALOG_SKIP_LINES = { horse = true, nests = true, pet_food = true, pet_accessories = true, clothing = true, guilds = true,
	wired = true, fxbox = true, trax = true, credit_furni = true, testing = true }
H.CATALOG_RARE_LINES = { rare = true, bonusrare = true, nft = true, nftmint = true, collectibles = true, pixel_collectible = true,
	gacha = true }
H.CATALOG_PAGE_SIZE = 150
H.STICKIES_PER_PAD = 20

-- lines over the years: what they're called together (the rest are their own name, made readable)
H.CATALOG_FAMILY_NAMES = { xmas = "Christmas", habboween = "Habboween", easter = "Easter", valentine = "Valentine's",
	newyear = "New Year", garden = "Garden", nft = "NFT", buildersclub = "Builders Club", habbopalooza = "Habbopalooza",
	university = "University", summer = "Summer", cyberpunk = "Cyberpunk", cny = "Lunar New Year", st_patricks = "St. Patrick's Day" }

-- seasonal lines (by their family's name): only sold in their season (the hotel's catalogue.lua says
-- when each is, and whether that's switched on)
H.CATALOG_SEASONS = { xmas = "christmas", habboween = "halloween", easter = "easter", valentine = "valentine",
	newyear = "newyear", summer = "summer", winter = "winter", wintercabin = "winter", winterhorizon = "winter",
	st_patricks = "stpatricks", cny = "lunarnewyear", xmas2010_quest_items = "christmas", summer2011_quest_items = "summer" }

function H.catalogLineName(line)
	if line == "" then return "Other" end
	local s = line:gsub("_", " "):gsub("(%a)(%d+)$", "%1 %2")
	return s:sub(1, 1):upper() .. s:sub(2)
end

function H.catalogRare(class, f)
	if H.CATALOG_RARE_LINES[f.line] or f.line:find("^nft") then return true end
	local base = H.furniBase(class):lower()
	return base:find("_ltd") ~= nil or base:find("^ltd") ~= nil or (f.name or ""):find("%f[%w]LTD%f[%W]") ~= nil
end

-- a line's family and year: "habboween_2015" -> habboween, 2015; "xmas2010" -> xmas, 2010;
-- "garden16" -> garden, 2016 (Habbo's anniversaries habbo15/20/25 are their own lines)
local function family(line)
	if line:find("^habbo%d+$") then return nil end
	-- (Builders Club's lines go together: buildersclub_alpha1, buildersclub_recolorable, ...)
	if line:find("^buildersclub_") then return "buildersclub", line:sub(14) end
	local base, year = line:match("^(.-)_?(%d%d%d%d)$")
	if not base then base, year = line:match("^(%a[%a_]-)_?(%d%d)$") if year then year = "20" .. year end end
	if not base or base == "" then return nil end
	return base, year
end

-- extra: { posters = { { n, name }, ... }, spaces = { floor = ids, wall = ids, landscape = ids } }
function H.catalogPages(fd, price, extra)
	extra = extra or {}
	-- the furni, by line; trophies (specialtype 11, engraved when bought) on a page of their own
	local lines = {}
	local trophies = {}
	-- rares and limited editions: on a staff-only tab, free (staff give them)
	local rareLines = {}
	for class, f in pairs(fd.byClass) do
		if f.special == 1 and H.catalogRare(class, f) and f.name ~= "" and not f.name:find(" name$") then
			local list = rareLines[f.line]
			if not list then list = {} rareLines[f.line] = list end
			list[#list + 1] = { kind = class, name = f.name, price = {}, order = f.id or 0 }
		end
		if not f.wall and f.special == 11 and (f.offer or -1) ~= -1 then
			trophies[#trophies + 1] = { kind = class, name = f.name, price = { credits = price }, order = f.id or 0, trophy = true }
		end
		if f.special == 1 and not H.CATALOG_SKIP_CATEGORIES[f.category] and not f.category:find("^wired")
			and not H.CATALOG_SKIP_LINES[f.line] and not f.line:find("^pet_") and not H.catalogRare(class, f)
			and f.name ~= "" and not f.name:find(" name$")
			-- (random teleports and step-on switches look like teleports but work differently: later)
			and not (f.category == "teleport" and (class:find("rnd") or class:find("random") or class:find("change_state"))) then
			local list = lines[f.line]
			if not list then list = {} lines[f.line] = list end
			-- (teleports are sold in linked pairs, like Habbo's)
			list[#list + 1] = { kind = class, name = f.name, price = { credits = price }, order = f.id or 0, pair = f.category == "teleport" or nil }
		end
	end
	-- a page for a line (cut into parts when it's big)
	local function page(name, offers)
		table.sort(offers, function(a, b) return a.order < b.order end)
		if #offers <= H.CATALOG_PAGE_SIZE then return { name = name, offers = offers, iconKind = offers[1].kind } end
		local parts = {}
		for i = 1, #offers, H.CATALOG_PAGE_SIZE do
			local part = {}
			for j = i, math.min(#offers, i + H.CATALOG_PAGE_SIZE - 1) do part[#part + 1] = offers[j] end
			parts[#parts + 1] = { name = name .. " " .. #parts + 1, offers = part, iconKind = part[1].kind }
		end
		return { name = name, children = parts, iconKind = offers[1].kind }
	end
	-- the pages for some lines: families over the years together, the rest one each
	local function group(lines)
		-- families: lines with the same name and a year
		local families, single = {}, {}
		for line, offers in pairs(lines) do
			local base, year = family(line)
			if base then
				families[base] = families[base] or {}
				families[base][#families[base] + 1] = { line = line, year = year, offers = offers }
			else
				single[#single + 1] = { line = line, offers = offers }
			end
		end
		-- (a line with the family's own name, "xmas" or "habboween", joins it too)
		for base, list in pairs(families) do
			if lines[base] then
				for i = #single, 1, -1 do if single[i].line == base then table.remove(single, i) end end
				list[#list + 1] = { line = base, year = nil, offers = lines[base] }
			end
		end
		local top = {}
		for base, list in pairs(families) do
			if #list == 1 then
				local l = list[1]
				local p = page(H.catalogLineName(l.line), l.offers)
				p.season = H.CATALOG_SEASONS[base]
				top[#top + 1] = p
			else
				table.sort(list, function(a, b) return (a.year or "0") < (b.year or "0") end)
				local name = H.CATALOG_FAMILY_NAMES[base] or H.catalogLineName(base)
				local children = {}
				for _, l in ipairs(list) do
					local label = l.year and (l.year:find("^%d+$") and l.year or H.catalogLineName(l.year)) or name
					children[#children + 1] = page(label, l.offers)
				end
				top[#top + 1] = { name = name, children = children, iconKind = children[#children].iconKind, season = H.CATALOG_SEASONS[base] }
			end
		end
		for _, l in ipairs(single) do
			local p = page(H.CATALOG_FAMILY_NAMES[l.line] or H.catalogLineName(l.line), l.offers)
			p.season = H.CATALOG_SEASONS[l.line]
			top[#top + 1] = p
		end
		return top
	end
	local top = group(lines)
	if #trophies > 0 then
		-- (with the "trophies" line's own furni when there is one: one Trophies page)
		local p
		for _, t in ipairs(top) do if t.name == "Trophies" and t.offers then p = t end end
		if p then
			for _, o2 in ipairs(trophies) do p.offers[#p.offers + 1] = o2 end
			table.sort(p.offers, function(a, b) return a.order < b.order end)
		else
			p = page("Trophies", trophies)
			top[#top + 1] = p
		end
		p.layout = "trophies"
	end
	table.sort(top, function(a, b)
		if (a.name == "Other") ~= (b.name == "Other") then return b.name == "Other" end
		return a.name:lower() < b.name:lower()
	end)
	-- posters: each of Habbo's numbers; stickies: a pad is 20
	if extra.posters and #extra.posters > 0 then
		local offers = {}
		for _, p in ipairs(extra.posters) do
			offers[#offers + 1] = { kind = "poster" .. p.n, name = p.name, price = { credits = price }, order = p.n }
		end
		local pg = page("Posters", offers)
		table.insert(top, 1, pg)
	end
	local stickies = {}
	for class, f in pairs(fd.byClass) do
		if f.special == 5 and f.wall then
			stickies[#stickies + 1] = { kind = class, name = f.name, price = { credits = price }, order = f.id or 0, count = H.STICKIES_PER_PAD }
		end
	end
	if #stickies > 0 then table.insert(top, 1, page("Stickies", stickies)) end
	table.sort(top, function(a, b)
		if (a.name == "Other") ~= (b.name == "Other") then return b.name == "Other" end
		return a.name:lower() < b.name:lower()
	end)
	local out = { { name = "Furni", children = top } }
	-- Habbo's "Spaces": a wallpaper, floor or landscape each (the furni "wallpaper", "floor" or
	-- "landscape" with its id as its data)
	if extra.spaces then
		local tab = { name = "Spaces", children = {} }
		for _, part in ipairs({ { "wall", "wallpaper", "Wallpaper", "Wallpaper" }, { "floor", "floor", "Floors", "Floor" }, { "landscape", "landscape", "Landscapes", "Landscape" } }) do
			local ids = extra.spaces[part[1]] or {}
			local f = fd.byClass[part[2]]
			if f and #ids > 0 then
				local offers = {}
				for i, id in ipairs(ids) do
					offers[#offers + 1] = { kind = part[2], data = id, name = part[4] .. " " .. id, price = { credits = price }, order = i }
				end
				local pg = page(part[3], offers)
				pg.iconKind = part[2]
				tab.children[#tab.children + 1] = pg
			end
		end
		if #tab.children > 0 then out[#out + 1] = tab end
	end
	local rareTop = group(rareLines)
	table.sort(rareTop, function(a, b) return a.name:lower() < b.name:lower() end)
	out[#out + 1] = { name = "Rares", staff = true, children = rareTop }
	return out
end

-- Habbo's posters: the numbers its texts have a name for (poster_<n>_name). cb({ { n, name }, ... })
function H.posters(cb)
	H.config(function(cfg)
		if not cfg then cb({}) return end
		local url
		for u in cfg.settings:gmatch("\nexternal%.texts%.txt=([^\r\n]*)") do url = u end
		if not url or url:find("${", 1, true) then cb({}) return end
		H.remembered("texts", (url:gsub("^http:", "https:")), function(text)
			local out = {}
			for n, name in (text or ""):gmatch("\nposter_(%d+)_name=([^\r\n]*)") do
				out[#out + 1] = { n = tonumber(n), name = name }
			end
			table.sort(out, function(a, b) return a.n < b.n end)
			cb(out)
		end)
	end)
end

if SERVER and BOBBA.catalog then
	BOBBA.catalog.provider = function(cb)
		H.furnidata(function(fd, err)
			if not fd then print("[Bobba] the catalogue: " .. tostring(err)) cb({}) return end
			H.posters(function(posters)
				H.roomContentIds(function(spaces, why)
					if not spaces then print("[Bobba] the catalogue's spaces: " .. tostring(why)) end
					cb(H.catalogPages(fd, tonumber(BOBBA.store.setting("catalog.price", "5")) or 5, { posters = posters, spaces = spaces }))
				end)
			end)
		end)
	end
end
