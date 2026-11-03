-- Getting Habbo's files: where they are (Habbo's own settings), downloading with a cache in
-- garrysmod/data/bobbahotel/habbo/, and unpacking a SWF into PNG pictures and its XML.
--
--   BOBBA.habbo.config(function(cfg, err) ... end)       cfg.clientUrl, cfg.furniUrl
--   BOBBA.habbo.library("furni/throne", url, function(lib, err) ... end)
--     lib.images[name] = { path = "habbo/pot/furni/throne/<name>.png", width, height, texWidth, texHeight }
--     (the PNG is padded to a power-of-two size with see-through pixels, so GMod shows it pixel-sharp
--     instead of stretching it to one; the picture is the top-left width x height of it)
--     lib.xml[name] = "<visualizationData ...>"

local H = BOBBA.habbo
local P = BOBBA.platform

H.SETTINGS_URL = "https://www.habbo.com/gamedata/external_variables/1"
H.CACHE = "habbo/"

local function cachePath(key, ending)
	return H.CACHE .. key:gsub("[^%w_%-/%.]", "_") .. ending
end
H.cachePath = cachePath

-- Downloads once; later it comes from the cache. cb(bytes) or cb(nil, why)
function H.download(key, url, cb, canWait)
	local path = cachePath("raw/" .. key, ".dat")
	if P.dataExists(path) then
		cb(P.readData(path))
		return
	end
	return H.httpGet(url, function(body)
		P.writeData(path, body)
		cb(body)
	end, function(why) cb(nil, why .. " (" .. url .. ")") end, canWait)
end

-- A small file Habbo changes now and then (its settings, its client versions): the copy from last
-- time is used at once (so a game start needs nothing from the internet), and a fresh copy is
-- fetched in the background for the next start. The first time it is fetched. cb(text) or cb(nil, why)
local refreshing = {}
function H.remembered(name, url, cb)
	local path = cachePath("remembered/" .. name, ".txt")
	local function fetch(done)
		H.httpGet(url, function(text)
			if text and #text > 0 then P.writeData(path, text) end
			done(text)
		end, function(why) done(nil, why) end)
	end
	local text = P.dataExists(path) and P.readData(path)
	if text and #text > 0 then
		if not refreshing[name] and P.after then
			refreshing[name] = true
			P.after(10, function() fetch(function() end) end)
		end
		cb(text)
		return
	end
	fetch(function(t, why) cb(t, why) end)
end

-- Habbo's settings: where its client files are
local configCache
function H.config(cb)
	if configCache then cb(configCache) return end
	H.remembered("settings", H.SETTINGS_URL, function(text, why)
		if not text then cb(nil, "couldn't reach Habbo: " .. tostring(why)) return end
		local function get(k) return text:match("\n" .. k:gsub("%.", "%%.") .. "=([^\r\n]*)") end
		local client = get("flash.client.url")
		local furni = get("flash.dynamic.download.url")
		if not client or not furni then cb(nil, "Habbo's settings didn't say where its files are") return end
		if furni:sub(1, 2) == "//" then furni = "https:" .. furni end
		configCache = { clientUrl = client, furniUrl = furni, settings = text }
		cb(configCache)
	end)
end

local libraries = {}
local unpacking = {}

-- What a library holds, so the next game start needn't read the SWF again: one line per picture
-- ("I", name, PNG path, width, height, its id in the SWF) and per XML ("X", name, path of the text
-- file), and where the SWF itself is kept ("R", path).
-- Pictures are made into PNG files only when something first draws them (H.image): a library has
-- hundreds (every direction and movement) and only a few get drawn.
H.INDEX_VERSION = "3"
local function indexPath(key) return cachePath("index/" .. key, ".txt") end

-- pictures not made yet: PNG path -> { raw = path of the SWF, id = its picture id }
local pending = {}
H.pendingImages = pending

local function readIndex(key)
	local path = indexPath(key)
	if not P.dataExists(path) then return nil end
	local text = P.readData(path)
	if not text or text:sub(1, #H.INDEX_VERSION + 1) ~= H.INDEX_VERSION .. "\n" then return nil end
	local lib = { key = key, images = {}, xml = {}, problems = {} }
	local raw, rawThere
	local n = 0
	for line in text:gmatch("[^\n]+") do
		n = n + 1
		if n % 100 == 0 then H.yield() end
		local f = {}
		for v in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
		if f[1] == "R" then
			raw = f[2]
			rawThere = P.dataExists(raw)
			lib.raw = raw
		elseif f[1] == "I" then
			local w, h, id = tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
			lib.images[f[2]] = { path = f[3], width = w, height = h, texWidth = H.pow2(w), texHeight = H.pow2(h) }
			-- (with the SWF kept, H.image checks for the PNG when it's first drawn: one check per
			-- picture drawn instead of one per picture in the library)
			if rawThere then
				pending[f[3]] = { raw = raw, id = id }
			elseif not P.dataExists(f[3]) then
				return nil
			end
		elseif f[1] == "X" then
			local xml = P.readData(f[3])
			if not xml then return nil end
			lib.xml[f[2]] = xml
		end
	end
	return lib
end

local function writeIndex(key, lib, raw, ids)
	local lines = { H.INDEX_VERSION, "R\t" .. raw }
	for name, img in pairs(lib.images) do
		lines[#lines + 1] = table.concat({ "I", name, img.path, img.width, img.height, ids[name] or 0 }, "\t")
	end
	for name, xml in pairs(lib.xml) do
		local path = cachePath("xmlcache/" .. key .. "/" .. name, ".txt")
		P.writeData(path, xml)
		lines[#lines + 1] = table.concat({ "X", name, path }, "\t")
	end
	P.writeData(indexPath(key), table.concat(lines, "\n") .. "\n")
end

function H.pow2(n)
	local p = 1
	while p < n do p = p * 2 end
	return p
end

-- the pixels with see-through padding to a power-of-two size
local function padded(img)
	local w, h = img.width, img.height
	local tw, th = H.pow2(w), H.pow2(h)
	if tw == w and th == h then return img.pixels, tw, th end
	local src, out, n = img.pixels, {}, 0
	for y = 0, th - 1 do
		for x = 0, tw - 1 do
			if x < w and y < h then
				local i = (y * w + x) * 4
				out[n + 1], out[n + 2], out[n + 3], out[n + 4] = src[i + 1], src[i + 2], src[i + 3], src[i + 4]
			else
				out[n + 1], out[n + 2], out[n + 3], out[n + 4] = 0, 0, 0, 0
			end
			n = n + 4
		end
	end
	return out, tw, th
end
H.paddedPixels = padded

-- a SWF's packed pictures, read once (the last few kept, for the pictures still to make)
local packedCache, packedOrder = {}, {}
H.PACKED_KEEP = 48
local function keepPacked(raw, p)
	if packedCache[raw] == nil then
		packedOrder[#packedOrder + 1] = raw
		if #packedOrder > H.PACKED_KEEP then packedCache[table.remove(packedOrder, 1)] = nil end
	end
	packedCache[raw] = p
end
local function packedOf(raw)
	local p = packedCache[raw]
	if p then return p end
	local bytes = P.readData(raw)
	local swf = bytes and H.swf.read(bytes, H.inflate, { images = "later", pause = H.yield })
	p = swf and swf.packed or {}
	keepPacked(raw, p)
	return p
end

-- In a job: a library's pictures read into memory ahead of drawing them (so the first draw of a new
-- direction or movement only unpacks its own pictures, never the whole SWF)
function H.warm(lib)
	local raw = lib and lib.raw
	if not raw or packedCache[raw] then return end
	for _, img in pairs(lib.images) do
		if pending[img.path] then packedOf(raw) return end
	end
end

-- Makes sure a library's picture is a PNG file (the first time it's drawn): true, or false when it
-- can't be made. Everything that makes a material from a library's picture calls this first.
function H.image(path)
	local job = pending[path]
	if not job then return true end
	pending[path] = nil
	if P.dataExists(path) then return true end
	local entry = packedOf(job.raw)[job.id]
	if not entry then return false end
	local img = H.swf.unpackImage(entry, H.inflate)
	if not img then return false end
	local px, tw, th = padded(img)
	P.writeData(path, H.png.encode(tw, th, px, H.zlib))
	return true
end

-- a picture's size from its packed data (DefineBitsLossless: id, format, width, height), not unpacking it
local function packedSize(packed)
	local d = packed.data
	return d:byte(4) + d:byte(5) * 256, d:byte(6) + d:byte(7) * 256
end

-- Downloads (or takes from the cache) a SWF and reads it: its XML, and where each picture is (made
-- into a PNG when first drawn, H.image). opts.eager: make every picture now (the room's floors and
-- walls, drawn by the gamemode); opts.canWait: fetched ahead of time (downloaded and read only when
-- nothing else is waiting).
function H.library(key, url, cb, opts)
	if libraries[key] then cb(libraries[key]) return end
	local canWait = opts and opts.canWait or false
	-- the same library asked for again while it is still being read: wait for that (and if that was
	-- only fetching ahead and this can't wait, it's hurried to the front)
	local st = unpacking[key]
	if st then
		table.insert(st.waiting, cb)
		if st.low and not canWait then
			st.low = false
			H.hurryDownload(st.download)
			H.hurryWork(st.job)
		end
		return
	end
	st = { waiting = { cb }, low = canWait }
	unpacking[key] = st
	local function done(lib, err)
		unpacking[key] = nil
		if lib then libraries[key] = lib end
		for _, w in ipairs(st.waiting) do w(lib, err) end
	end
	local function fetch()
		st.download = H.download(key, url, function(bytes, err)
			st.download = nil
			if not bytes then done(nil, err) return end
			local raw = cachePath("raw/" .. key, ".dat")
			st.job = H.work(function()
				local swf, why = H.swf.read(bytes, H.inflate, { images = "later", pause = H.yield })
				if not swf then done(nil, key .. ": " .. tostring(why)) return end
				local lib = { key = key, raw = raw, images = {}, xml = {}, problems = swf.problems }
				local ids = {}
				-- one PNG per picture, named after its first name (Habbo gives some pictures many names)
				local made = {}
				local n = 0
				for name, entry in pairs(swf.byName) do
					n = n + 1
					if n % 50 == 0 then H.yield() end
					if entry.packed then
						local m = made[entry.id]
						if not m then
							local path = cachePath("pot/" .. key .. "/" .. swf.symbols[entry.id], ".png")
							local w, h = packedSize(entry.packed)
							m = { path = path, width = w, height = h, texWidth = H.pow2(w), texHeight = H.pow2(h) }
							-- (whether the PNG is there already is checked when it's first drawn)
							pending[path] = { raw = raw, id = entry.id }
							made[entry.id] = m
						end
						lib.images[name] = m
						ids[name] = entry.id
					elseif entry.binary then
						lib.xml[name] = entry.binary
					end
				end
				-- (the SWF was just read: its pictures are kept for drawing them, unless it was only
				-- fetched ahead, which would push out the ones in use)
				if not st.low then keepPacked(raw, swf.packed) end
				if opts and opts.eager then
					for _, img in pairs(made) do H.image(img.path) H.yield() end
				end
				if #lib.problems == 0 then writeIndex(key, lib, raw, ids) end
				done(lib)
			end, st.low)
		end, st.low)
	end
	-- saved from last time: its index is read a little at a time
	if P.dataExists(indexPath(key)) then
		st.job = H.work(function()
			local cached = readIndex(key)
			if cached then done(cached) else fetch() end
		end, st.low)
		return
	end
	fetch()
end

-- whether a library has been read before (its index is saved): fetching ahead skips these
function H.libraryKnown(key)
	return libraries[key] ~= nil or P.dataExists(indexPath(key))
end
