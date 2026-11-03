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
function H.download(key, url, cb)
	local path = cachePath("raw/" .. key, ".dat")
	if P.dataExists(path) then
		cb(P.readData(path))
		return
	end
	H.httpGet(url, function(body)
		P.writeData(path, body)
		cb(body)
	end, function(why) cb(nil, why .. " (" .. url .. ")") end)
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

-- What a library holds, so the next game start needn't unpack the SWF again: one line per picture
-- ("I", name, PNG path, width, height) and per XML ("X", name, path of the text file).
H.INDEX_VERSION = "2"
local function indexPath(key) return cachePath("index/" .. key, ".txt") end

local function readIndex(key)
	local path = indexPath(key)
	if not P.dataExists(path) then return nil end
	local text = P.readData(path)
	if not text or text:sub(1, #H.INDEX_VERSION + 1) ~= H.INDEX_VERSION .. "\n" then return nil end
	local lib = { key = key, images = {}, xml = {}, problems = {} }
	for line in text:gmatch("[^\n]+") do
		local kind, a, b, c, d = line:match("^(%a)\t([^\t]*)\t([^\t]*)\t?([^\t]*)\t?([^\t]*)$")
		if kind == "I" then
			if not P.dataExists(b) then return nil end
			local w, h = tonumber(c), tonumber(d)
			lib.images[a] = { path = b, width = w, height = h, texWidth = H.pow2(w), texHeight = H.pow2(h) }
		elseif kind == "X" then
			local xml = P.readData(b)
			if not xml then return nil end
			lib.xml[a] = xml
		end
	end
	return lib
end

local function writeIndex(key, lib)
	local lines = { H.INDEX_VERSION }
	for name, img in pairs(lib.images) do
		lines[#lines + 1] = table.concat({ "I", name, img.path, img.width, img.height }, "\t")
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

-- Downloads (or takes from the cache) a SWF and unpacks it: every picture as a PNG, every XML.
function H.library(key, url, cb)
	if libraries[key] then cb(libraries[key]) return end
	local cached = readIndex(key)
	if cached then
		libraries[key] = cached
		cb(cached)
		return
	end
	-- the same library asked for again while it is still being unpacked: wait for that
	if unpacking[key] then table.insert(unpacking[key], cb) return end
	unpacking[key] = { cb }
	local function done(lib, err)
		local waiting = unpacking[key]
		unpacking[key] = nil
		if lib then libraries[key] = lib end
		for _, w in ipairs(waiting) do w(lib, err) end
	end
	H.download(key, url, function(bytes, err)
		if not bytes then done(nil, err) return end
		-- unpacking is a job: a few milliseconds a frame, so the game doesn't freeze
		H.work(function()
			local swf, why = H.swf.read(bytes, H.inflate, { images = "later" })
			if not swf then done(nil, key .. ": " .. tostring(why)) return end
			local lib = { key = key, images = {}, xml = {}, problems = swf.problems }
			-- one PNG per picture, named after its first name (Habbo gives some pictures many names)
			local made = {}
			for name, entry in pairs(swf.byName) do
				if entry.packed then
					local m = made[entry.id]
					if not m then
						local path = cachePath("pot/" .. key .. "/" .. swf.symbols[entry.id], ".png")
						local img, problem = H.swf.unpackImage(entry.packed, H.inflate)
						if img then
							if not P.dataExists(path) then
								local px, tw, th = padded(img)
								P.writeData(path, H.png.encode(tw, th, px, H.zlib))
							end
							m = { path = path, width = img.width, height = img.height, texWidth = H.pow2(img.width), texHeight = H.pow2(img.height) }
						else
							lib.problems[#lib.problems + 1] = problem
							m = false
						end
						made[entry.id] = m
						H.yield()
					end
					if m then lib.images[name] = m end
				elseif entry.binary then
					lib.xml[name] = entry.binary
				end
			end
			if #lib.problems == 0 then writeIndex(key, lib) end
			done(lib)
		end)
	end)
end
