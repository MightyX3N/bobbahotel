-- Habbo's figuredata as tables: every colour palette and every kind of clothing (set type) with its
-- sets, for the avatar editor (client) and for checking looks (server, the way Arcturus'
-- ClothingValidationManager does).
--
--   local fd = H.parseFigureData(xmlText)
--   fd.palettes[id] = { id, colors = { { id, index, club, selectable, rgb }, ... } (figuredata's order), byId }
--   fd.setTypes[type] = { type, paletteId, mand = { M = { [0] = bool, [1] = bool }, F = ... },
--                         sets = { { id, gender, club, colorable, selectable, preselectable, sellable,
--                                    parts = { { id, type, colorable, index, colorIndex }, ... } }, ... },
--                         byId }
--   fd.order = { "hr", "hd", ... }   the set types in figuredata's order
--   H.validateLook(fd, figure, gender, clubLevel, owned) -> the cleaned figure
--   H.figureData(cb)   -- downloaded (or cached) and read: cb(fd) or cb(nil, why)

local H = BOBBA.habbo

local function bool(v) return v == "1" or v == "true" end

function H.parseFigureData(text)
	local X = H.xml
	local root = X.find(X.parse(text, H.yield), "figuredata")
	if not root then return nil, "not Habbo's figuredata" end
	local fd = { palettes = {}, setTypes = {}, order = {} }
	for _, pal in ipairs(X.all(root, "palette")) do
		local p = { id = tonumber(pal.attrs.id), colors = {}, byId = {} }
		for _, c in ipairs(X.children(pal, "color")) do
			local hex = (c.text or ""):match("%x+") or "FFFFFF"
			local color = {
				id = tonumber(c.attrs.id), index = tonumber(c.attrs.index) or 0, club = tonumber(c.attrs.club) or 0,
				selectable = bool(c.attrs.selectable), rgb = tonumber(hex, 16) or 0xFFFFFF,
			}
			p.colors[#p.colors + 1] = color
			p.byId[color.id] = color
		end
		fd.palettes[p.id] = p
	end
	for _, st in ipairs(X.all(root, "settype")) do
		local t = {
			type = st.attrs.type, paletteId = tonumber(st.attrs.paletteid), sets = {}, byId = {},
			mand = {
				M = { [0] = bool(st.attrs.mand_m_0), [1] = bool(st.attrs.mand_m_1) },
				F = { [0] = bool(st.attrs.mand_f_0), [1] = bool(st.attrs.mand_f_1) },
			},
		}
		for _, se in ipairs(X.children(st, "set")) do
			local set = {
				id = tonumber(se.attrs.id), gender = (se.attrs.gender or "U"):upper(), club = tonumber(se.attrs.club) or 0,
				colorable = bool(se.attrs.colorable), selectable = bool(se.attrs.selectable),
				preselectable = bool(se.attrs.preselectable), sellable = bool(se.attrs.sellable), parts = {},
			}
			for _, pa in ipairs(X.children(se, "part")) do
				set.parts[#set.parts + 1] = {
					id = tonumber(pa.attrs.id), type = pa.attrs.type, colorable = bool(pa.attrs.colorable),
					index = tonumber(pa.attrs.index) or 0, colorIndex = tonumber(pa.attrs.colorindex) or 0,
				}
			end
			t.sets[#t.sets + 1] = set
			t.byId[set.id] = set
		end
		fd.setTypes[t.type] = t
		fd.order[#fd.order + 1] = t.type
		H.yield()
	end
	return fd
end

-- Arcturus FiguredataSettype.getFirstSetForGender / getFirstNonHCSetForGender: from the highest id down
local function sortedIds(t)
	local ids = {}
	for id in pairs(t.byId) do ids[#ids + 1] = id end
	table.sort(ids, function(a, b) return a > b end)
	return ids
end

local function firstSet(t, gender, nonClub)
	for _, id in ipairs(sortedIds(t)) do
		local set = t.byId[id]
		if (set.gender == gender or set.gender == "U") and not set.sellable and set.selectable and not (nonClub and set.club > 0) then return set end
	end
	if nonClub then return firstSet(t, gender, false) end
	local ids = sortedIds(t)
	return ids[1] and t.byId[ids[1]] or nil
end

-- Arcturus FiguredataPalette.getFirstNonHCColor: the lowest id that isn't club
local function firstNonClubColor(p)
	local best
	for _, c in ipairs(p.colors) do
		if c.club == 0 and (not best or c.id < best.id) then best = c end
	end
	return best or p.colors[1]
end

-- Arcturus ClothingValidationManager.validateLook: the look as it may be worn. Clothes that don't
-- exist, aren't for this gender, can't be chosen, are club (without club) or sellable (and not
-- owned) are swapped for the first that can be worn when that kind of clothing is mandatory, else
-- left out; mandatory kinds missing are added; colours that don't exist (or are club) become the
-- palette's first. clubLevel: 0 none, 1 HC, 2 VIP (figuredata's club="2" is VIP's; true = all).
function H.validateLook(fd, figure, gender, clubLevel, owned)
	gender = (gender == "F" or gender == "f") and "F" or "M"
	local level = type(clubLevel) == "number" and clubLevel or (clubLevel and 2 or 0)
	local club = level > 0 and 1 or 0
	owned = owned or {}
	local parts, order = {}, {}
	for part in (tostring(figure or "") .. "."):gmatch("([^%.]*)%.") do
		if part:find("-", 1, true) then
			local data = {}
			for v in (part .. "-"):gmatch("([^%-]*)%-") do data[#data + 1] = v end
			if fd.setTypes[data[1]] and not parts[data[1]] then
				parts[data[1]] = data
				order[#order + 1] = data[1]
			end
		end
	end
	for _, t in ipairs(fd.order) do
		if not parts[t] and fd.setTypes[t].mand[gender][club] then
			parts[t] = { t }
			order[#order + 1] = t
		end
	end
	local out = {}
	for _, name in ipairs(order) do
		local data = parts[name]
		local t = fd.setTypes[name]
		local palette = fd.palettes[t.paletteId]
		repeat
			if not palette then break end
			local setId = tonumber(data[2] or "-1") or -1
			local set = t.byId[setId]
			if not set or set.club > level or not set.selectable or (set.sellable and not owned[set.id])
				or (set.gender ~= "U" and set.gender ~= gender) then
				if not t.mand[gender][club] then break end
				set = firstSet(t, gender, true)
				if not set then break end
				setId = set.id
			end
			local s = name .. "-" .. setId
			if set.colorable then
				local c1 = tonumber(data[3] or "-1") or -1
				local c = palette.byId[c1]
				if not c or c.club > level then c1 = firstNonClubColor(palette).id end
				s = s .. "-" .. c1
				if data[4] then
					local c2 = tonumber(data[4]) or -1
					c = palette.byId[c2]
					if not c or c.club > level then c2 = firstNonClubColor(palette).id end
					s = s .. "-" .. c2
				end
			end
			out[#out + 1] = s
		until true
	end
	return table.concat(out, ".")
end

local cache, waiting
function H.figureData(cb)
	if cache then cb(cache) return end
	if waiting then waiting[#waiting + 1] = cb return end
	waiting = { cb }
	local function done(fd, err)
		local list = waiting
		waiting = nil
		cache = fd
		for _, w in ipairs(list) do w(fd, err) end
	end
	H.figureDataXml(function(text, err)
		if not text then done(nil, err) return end
		H.work(function()
			local fd, why = H.parseFigureData(text)
			done(fd, why)
		end, true)
	end)
end
