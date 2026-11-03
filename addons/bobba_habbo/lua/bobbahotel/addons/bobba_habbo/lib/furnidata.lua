-- Habbo's furni, from Habbo's own servers (client and server):
--   furnidata: every furni's class name, file version, size on the floor, and whether it can be
--     walked, sat or laid on. Read once into a small index (garrysmod/data/bobbahotel/habbo/
--     furnidata/index.txt); the furnidata itself is refreshed in the background (H.remembered).
--   a furni's SWF: its pictures and XML (H.library), or on the server just what the room needs to
--     know (H.furniInfo: size, height, directions, how many states).
--
--   H.furnidata(function(fd, err) ... end)      fd.byClass["throne"] = { id, rev, x, y, walk, sit, lay, wall, name,
--                                                 line, offer, category, special }  (furniline, offerid (-1: not sold),
--                                                 category, specialtype (1: an ordinary furni))
--   H.furniLibrary("throne", function(lib, err) ... end)
--   H.furniInfo("throne", function(info, err) ... end)
--     info = { width, length, height, walk, sit, lay, directions = { 0, 2, 4, 6 }, states, logic }

local H = BOBBA.habbo
local P = BOBBA.platform

H.FURNIDATA_INDEX_VERSION = "2"

-- A Habbo setting with its ${...} filled in (Habbo's settings refer to each other). Some settings
-- are in the file more than once: the last one counts (it's the one that is filled in).
function H.setting(cfg, key, depth)
	local v
	for found in ("\n" .. cfg.settings):gmatch("\n" .. key:gsub("[%.%-]", "%%%0") .. "=([^\r\n]*)") do v = found end
	if not v then return nil end
	depth = (depth or 0) + 1
	if depth > 5 then return v end
	v = v:gsub("%${([^}]+)}", function(k) return H.setting(cfg, k, depth) or "" end)
	if v:sub(1, 2) == "//" then v = "https:" .. v end
	return v
end

-- the class name without the colour ("bed_budget*3" -> "bed_budget", 3)
function H.furniBase(classname)
	local base, color = classname:match("^([^%*]+)%*(%d+)$")
	if base then return base, tonumber(color) end
	return classname, 0
end

local function tag(body, name)
	return body:match("<" .. name .. ">([^<]*)</" .. name .. ">")
end

local function unescape(s)
	return (s or ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&")
end

-- the furnidata XML (about 12 MB) read with patterns, a piece at a time
local function parse(text)
	local byClass, n = {}, 0
	local function each(section, wall)
		local s, e = text:find("<" .. section .. ">", 1, true)
		local stop = text:find("</" .. section .. ">", e or 1, true)
		if not s or not stop then return end
		local pos = e + 1
		while true do
			local a, b, attrs = text:find("<furnitype([^>]*)>", pos)
			if not a or a > stop then break end
			local c, d = text:find("</furnitype>", b + 1, true)
			if not c then break end
			local body = text:sub(b + 1, c - 1)
			local class = attrs:match('classname="([^"]*)"')
			if class and class ~= "" then
				byClass[class] = {
					id = tonumber(attrs:match('id="(%-?%d+)"')) or 0,
					rev = tonumber(tag(body, "revision")) or 0,
					x = tonumber(tag(body, "xdim")) or 1, y = tonumber(tag(body, "ydim")) or 1,
					walk = tag(body, "canstandon") == "1", sit = tag(body, "cansiton") == "1", lay = tag(body, "canlayon") == "1",
					wall = wall, name = unescape(tag(body, "name")),
					line = tag(body, "furniline") or "", offer = tonumber(tag(body, "offerid")) or -1,
					category = tag(body, "category") or "", special = tonumber(tag(body, "specialtype")) or 1,
				}
			end
			pos = d + 1
			n = n + 1
			if n % 100 == 0 then H.yield() end
		end
	end
	each("roomitemtypes", false)
	each("wallitemtypes", true)
	return byClass
end

local INDEX = "furnidata/index"
local FIELDS = { "id", "rev", "x", "y", "walk", "sit", "lay", "wall", "name", "line", "offer", "category", "special" }

local function writeIndex(byClass, length)
	local lines = { H.FURNIDATA_INDEX_VERSION .. "\t" .. length }
	for class, f in pairs(byClass) do
		local row = { class }
		for _, k in ipairs(FIELDS) do
			local v = f[k]
			if type(v) == "boolean" then v = v and "1" or "0" end
			row[#row + 1] = tostring(v):gsub("[\t\n\r]", " ")
		end
		lines[#lines + 1] = table.concat(row, "\t")
	end
	P.writeData(H.cachePath(INDEX, ".txt"), table.concat(lines, "\n") .. "\n")
end

local function readIndex(length)
	local path = H.cachePath(INDEX, ".txt")
	if not P.dataExists(path) then return nil end
	local text = P.readData(path)
	if not text then return nil end
	local head = text:match("^([^\n]*)\n")
	if head ~= H.FURNIDATA_INDEX_VERSION .. "\t" .. length then return nil end
	local byClass = {}
	for line in text:gmatch("[^\n]+") do
		local c = {}
		for v in (line .. "\t"):gmatch("([^\t]*)\t") do c[#c + 1] = v end
		if #c == 14 then
			byClass[c[1]] = {
				id = tonumber(c[2]), rev = tonumber(c[3]), x = tonumber(c[4]), y = tonumber(c[5]),
				walk = c[6] == "1", sit = c[7] == "1", lay = c[8] == "1", wall = c[9] == "1", name = c[10],
				line = c[11], offer = tonumber(c[12]) or -1, category = c[13], special = tonumber(c[14]) or 1,
			}
		end
	end
	return byClass
end

local furnidata, waiting
function H.furnidata(cb)
	if furnidata then cb(furnidata) return end
	if waiting then waiting[#waiting + 1] = cb return end
	waiting = { cb }
	local function done(fd, err)
		local list = waiting
		waiting = nil
		furnidata = fd
		for _, w in ipairs(list) do w(fd, err) end
	end
	H.config(function(cfg, err)
		if not cfg then done(nil, err) return end
		local url = H.setting(cfg, "furnidata.load.url")
		if not url then done(nil, "Habbo's settings didn't say where its furnidata is") return end
		H.remembered("furnidata", url, function(text, why)
			if not text then done(nil, "couldn't get Habbo's furnidata: " .. tostring(why)) return end
			local byClass = readIndex(#text)
			if byClass then done({ byClass = byClass }) return end
			H.work(function()
				local parsed = parse(text)
				if next(parsed) == nil then done(nil, "Habbo's furnidata had no furni in it") return end
				writeIndex(parsed, #text)
				done({ byClass = parsed })
			end)
		end)
	end)
end

-- Habbo's posters are one furni ("poster", its number in its data); Nitro makes each its own kind,
-- "poster" and the number ("poster5"), and so does the hotel. The poster's number, or nil.
function H.posterNumber(classname)
	return tonumber(tostring(classname):match("^poster(%d+)$"))
end

-- the furnidata entry for a kind (a poster's is the poster's)
function H.furniEntry(fd, classname)
	local entry = fd.byClass[classname] or fd.byClass[H.furniBase(classname)]
	if not entry and H.posterNumber(classname) then entry = fd.byClass.poster end
	return entry
end

-- where a furni's SWF is (cb(url, base, entry) or cb(nil, why))
function H.furniUrl(classname, cb)
	H.config(function(cfg, err)
		if not cfg then cb(nil, err) return end
		H.furnidata(function(fd, err2)
			if not fd then cb(nil, err2) return end
			local base = H.furniBase(classname)
			local entry = H.furniEntry(fd, classname)
			if not entry then cb(nil, "Habbo has no furni called " .. classname) return end
			cb(cfg.furniUrl .. entry.rev .. "/" .. base .. ".swf", base, entry)
		end)
	end)
end

-- A sound sample (sound blocks, Habbo's flash.dynamic.download.samples.template): its MP3 in the cache.
-- cb(path) or cb(nil, why)
local sampleWaiting = {}
function H.furniSample(id, cb)
	id = tonumber(id)
	if not id then cb(nil, "no sample") return end
	local path = H.cachePath("samples/" .. id, ".mp3")
	if P.dataExists(path) then cb(path) return end
	if sampleWaiting[id] then table.insert(sampleWaiting[id], cb) return end
	sampleWaiting[id] = { cb }
	local function done(p, why)
		local list = sampleWaiting[id]
		sampleWaiting[id] = nil
		for _, w in ipairs(list) do w(p, why) end
	end
	H.config(function(cfg, err)
		if not cfg then done(nil, err) return end
		local template = H.setting(cfg, "flash.dynamic.download.samples.template") or "mp3/sound_machine_sample_%typeid%.mp3"
		local url = cfg.furniUrl .. template:gsub("%%typeid%%", tostring(id))
		H.httpGet(url, function(body)
			if not body or #body == 0 then done(nil, "empty sample") return end
			P.writeData(path, body)
			done(path)
		end, function(why) done(nil, why) end)
	end)
end

-- the furni's SWF, unpacked (pictures and XML; for drawing it)
function H.furniLibrary(classname, cb)
	H.furniUrl(classname, function(url, base)
		if not url then cb(nil, base) return end
		H.library("furni/" .. base, url, cb)
	end)
end

-- What the room needs to know about a furni (server). From furnidata and the furni's own logic and
-- visualization XML (only the XML is taken from its SWF), kept in furni/info/<name>.txt.
local infos = {}
local infoWaiting = {}

-- how many states a furni has: one per animation (Habbo's states are its animations 0, 1, 2, ...)
local function countStates(visualization)
	local top = -1
	for attrs in visualization:gmatch("<animation(%s[^>]*)>") do
		local id = tonumber(attrs:match('%sid="(%d+)"'))
		-- (the animations between two states don't count)
		-- (and Habbo's special ones from 100 up aren't states you switch to)
		if id and not attrs:find("transition", 1, true) and id < 100 and id > top then top = id end
	end
	return math.max(1, top + 1)
end

local function readInfo(text)
	local f = {}
	for k, v in text:gmatch("([%w]+)=([^\n]*)") do f[k] = v end
	if not f.height then return nil end
	local dirs = {}
	for d in (f.directions or "0"):gmatch("%d+") do dirs[#dirs + 1] = tonumber(d) end
	return {
		width = tonumber(f.width) or 1, length = tonumber(f.length) or 1, height = tonumber(f.height) or 0,
		walk = f.walk == "1", sit = f.sit == "1", lay = f.lay == "1", directions = dirs, states = tonumber(f.states) or 1,
		logic = f.logic ~= "" and f.logic or nil,
	}
end

H.FURNI_INFO_VERSION = "2"

function H.furniInfo(classname, cb)
	if infos[classname] then cb(infos[classname]) return end
	if infoWaiting[classname] then table.insert(infoWaiting[classname], cb) return end
	infoWaiting[classname] = { cb }
	local function done(info, err)
		local list = infoWaiting[classname]
		infoWaiting[classname] = nil
		if info then infos[classname] = info end
		for _, w in ipairs(list) do w(info, err) end
	end
	local base = H.furniBase(classname)
	local path = H.cachePath("furni/info/" .. base, ".txt")
	if P.dataExists(path) then
		local text = P.readData(path) or ""
		if text:match("^v=([^\n]*)") == H.FURNI_INFO_VERSION then
			local info = readInfo(text)
			if info then done(info) return end
		end
	end
	H.furniUrl(classname, function(url, base2, entry)
		if not url then done(nil, base2) return end
		H.download("furni/" .. base2, url, function(bytes, err)
			if not bytes then done(nil, err) return end
			H.work(function()
				local swf, why = H.swf.read(bytes, H.inflate, { images = false })
				if not swf then done(nil, classname .. ": " .. tostring(why)) return end
				local logic, vis, index
				for name, e in pairs(swf.byName) do
					if e.binary then
						if name:match("_logic$") then logic = e.binary end
						if name:match("_visualization$") then vis = e.binary end
						if name:match("_index$") then index = e.binary end
					end
				end
				-- what kind of furni it is to use (Nitro's logic type: furniture_dice, furniture_multistate, ...)
				local logicType = index and index:match('logic="([^"]*)"') or ""
				if not logic or not vis then done(nil, classname .. ": no logic or visualization in its file") return end
				local d = logic:match("<dimensions([^>]*)>") or ""
				local height = tonumber(d:match('z="([%d%.%-]+)"')) or 0
				local dirs = {}
				local inDirs = logic:match("<directions>(.-)</directions>") or ""
				for deg in inDirs:gmatch('id="(%d+)"') do dirs[#dirs + 1] = math.floor(tonumber(deg) / 45) end
				if #dirs == 0 then dirs = { 0 } end
				local text = table.concat({
					"v=" .. H.FURNI_INFO_VERSION,
					"width=" .. entry.x, "length=" .. entry.y, "height=" .. height,
					"walk=" .. (entry.walk and 1 or 0), "sit=" .. (entry.sit and 1 or 0), "lay=" .. (entry.lay and 1 or 0),
					"directions=" .. table.concat(dirs, ","), "states=" .. countStates(vis), "logic=" .. logicType,
				}, "\n") .. "\n"
				P.writeData(path, text)
				done(readInfo(text))
			end)
		end)
	end)
end
