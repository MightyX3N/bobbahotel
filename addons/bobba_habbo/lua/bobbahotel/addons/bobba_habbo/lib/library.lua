-- Getting Habbo's files: where they are (Habbo's own settings), downloading with a cache in
-- garrysmod/data/bobbahotel/habbo/, and unpacking a SWF into PNG pictures and its XML.
--
--   BOBBA.habbo.config(function(cfg, err) ... end)       cfg.clientUrl, cfg.furniUrl
--   BOBBA.habbo.library("furni/throne", url, function(lib, err) ... end)
--     lib.images[name] = { path = "habbo/png/furni/throne/<name>.png", width, height }
--     lib.xml[name] = "<visualizationData ...>"

local H = BOBBA.habbo
local P = BOBBA.platform

H.SETTINGS_URL = "https://www.habbo.com/gamedata/external_variables/1"
H.CACHE = "habbo/"

local function cachePath(key, ending)
	return H.CACHE .. key:gsub("[^%w_%-/%.]", "_") .. ending
end

-- Downloads once; later it comes from the cache. cb(bytes) or cb(nil, why)
function H.download(key, url, cb)
	local path = cachePath("raw/" .. key, ".dat")
	if P.dataExists(path) then
		cb(P.readData(path))
		return
	end
	P.httpGet(url, function(body)
		P.writeData(path, body)
		cb(body)
	end, function(why) cb(nil, why .. " (" .. url .. ")") end)
end

-- Habbo's settings: where its client files are
local configCache
function H.config(cb)
	if configCache then cb(configCache) return end
	P.httpGet(H.SETTINGS_URL, function(text)
		local function get(k) return text:match("\n" .. k:gsub("%.", "%%.") .. "=([^\r\n]*)") end
		local client = get("flash.client.url")
		local furni = get("flash.dynamic.download.url")
		if not client or not furni then cb(nil, "Habbo's settings didn't say where its files are") return end
		if furni:sub(1, 2) == "//" then furni = "https:" .. furni end
		configCache = { clientUrl = client, furniUrl = furni, settings = text }
		cb(configCache)
	end, function(why) cb(nil, "couldn't reach Habbo: " .. why) end)
end

local libraries = {}

-- Downloads (or takes from the cache) a SWF and unpacks it: every picture as a PNG, every XML.
function H.library(key, url, cb)
	if libraries[key] then cb(libraries[key]) return end
	H.download(key, url, function(bytes, err)
		if not bytes then cb(nil, err) return end
		local swf, why = H.swf.read(bytes, H.inflate)
		if not swf then cb(nil, key .. ": " .. tostring(why)) return end
		local lib = { key = key, images = {}, xml = {}, problems = swf.problems }
		for name, entry in pairs(swf.byName) do
			if entry.image then
				local path = cachePath("png/" .. key .. "/" .. name, ".png")
				if not P.dataExists(path) then
					P.writeData(path, H.png.encode(entry.image.width, entry.image.height, entry.image.pixels, H.zlib))
				end
				lib.images[name] = { path = path, width = entry.image.width, height = entry.image.height }
			elseif entry.binary then
				lib.xml[name] = entry.binary
			end
		end
		libraries[key] = lib
		cb(lib)
	end)
end
