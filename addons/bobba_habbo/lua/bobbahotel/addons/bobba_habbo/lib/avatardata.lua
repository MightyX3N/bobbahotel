-- The data Habbo draws avatars with, from Habbo's own servers:
--   from Habbo's desktop client (a ZIP with HabboAir.swf inside): HabboAvatarGeometry, -PartSets,
--     -Animation, -Figure and the lay/swim offsets. Downloaded once per client version (about 19 MB),
--     then only the XML is kept.
--   from the client folder: HabboAvatarActions.xml, figuremap.xml, effectmap.xml
--   from gamedata: figuredata (all clothes and colours)
--
--   BOBBA.habbo.avatarData(function(data, err) ... end)
--     data.geometry, data.partSets, data.animation, data.figure, data.actions, data.figuremap,
--     data.effectmap, data.figuredata (XML text), data.offsets.lay, data.offsets.swim

local H = BOBBA.habbo
local P = BOBBA.platform

H.CLIENT_URLS = "https://www.habbo.com/gamedata/clienturls"

-- name in HabboAir.swf (before the "$") -> our name
H.CLIENT_XML = {
	HabboAvatarGeometry_xml = "geometry",
	HabboAvatarPartSets_xml = "partSets",
	HabboAvatarAnimation_xml = "animation",
	HabboAvatarFigure_xml = "figure",
	action_offset_lay_xml = "offset_lay",
	action_offset_swim_xml = "offset_swim",
}

local function textPath(folder, name)
	return H.cachePath("avatar/" .. folder .. "/" .. name, ".txt")
end

-- The XML inside Habbo's desktop client, cached per client version. cb(files) or cb(nil, why)
function H.clientXml(cb)
	P.httpGet(H.CLIENT_URLS, function(json)
		local url = json:match('"flash%-windows"%s*:%s*"([^"]+)"')
		local version = json:match('"flash%-windows%-version"%s*:%s*"([^"]+)"') or "0"
		if not url then cb(nil, "Habbo didn't say where its desktop client is") return end
		url = url:gsub("\\/", "/")
		local folder = "client_" .. version
		local files, have = {}, true
		for _, ours in pairs(H.CLIENT_XML) do
			local p = textPath(folder, ours)
			if P.dataExists(p) then files[ours] = P.readData(p) else have = false end
		end
		if have then cb(files) return end
		P.httpGet(url, function(zipBytes)
			local zip, why = H.zip.open(zipBytes)
			if not zip then cb(nil, why) return end
			local swfBytes, why2 = zip.read("HabboAir.swf", H.inflateRaw)
			zipBytes = nil
			if not swfBytes then cb(nil, why2) return end
			local swf, why3 = H.swf.read(swfBytes, H.inflate, { images = false })
			swfBytes = nil
			if not swf then cb(nil, "HabboAir.swf: " .. tostring(why3)) return end
			for name, entry in pairs(swf.byName) do
				local ours = H.CLIENT_XML[name:match("^([^%$]+)%$") or name]
				if ours and entry.binary then files[ours] = entry.binary end
			end
			for _, ours in pairs(H.CLIENT_XML) do
				if not files[ours] then cb(nil, "Habbo's client has no " .. ours .. " any more") return end
			end
			for ours, text in pairs(files) do P.writeData(textPath(folder, ours), text) end
			collectgarbage()
			cb(files)
		end, function(why) cb(nil, "couldn't download Habbo's client: " .. why) end)
	end, function(why) cb(nil, "couldn't reach Habbo: " .. why) end)
end

-- A text file, cached under a key that changes when Habbo changes it
local function cachedText(key, url, cb)
	H.download(key, url, function(text, err) cb(text, err) end)
end

local avatarCache
function H.avatarData(cb)
	if avatarCache then cb(avatarCache) return end
	H.config(function(cfg, err)
		if not cfg then cb(nil, err) return end
		local rev = cfg.clientUrl:match("([^/]+)/?$") or "client"
		-- the setting is there twice; the last one (with Habbo's revision in it) counts
		local figuredataUrl = "https://www.habbo.com/gamedata/figuredata/1"
		for u in cfg.settings:gmatch("\nexternal%.figurepartlist%.txt=([^\r\n]*)") do figuredataUrl = u end
		figuredataUrl = figuredataUrl:gsub("^http:", "https:")
		local data = { offsets = {} }
		local steps = {
			function(nxt) H.clientXml(function(files, e)
				if not files then cb(nil, e) return end
				for k, v in pairs(files) do data[k] = v end
				nxt()
			end) end,
		}
		local function text(field, key, url)
			steps[#steps + 1] = function(nxt) cachedText(key, url, function(t, e)
				if not t then cb(nil, e) return end
				data[field] = t
				nxt()
			end) end
		end
		text("actions", "avatar/" .. rev .. "/HabboAvatarActions", cfg.clientUrl .. "HabboAvatarActions.xml")
		text("figuremap", "avatar/" .. rev .. "/figuremap", cfg.clientUrl .. "figuremap.xml")
		text("effectmap", "avatar/" .. rev .. "/effectmap", cfg.clientUrl .. "effectmap.xml")
		text("figuredata", "avatar/figuredata_" .. (figuredataUrl:match("([%w]+)$") or "1"), figuredataUrl)
		local i = 0
		local function nxt()
			i = i + 1
			if steps[i] then steps[i](nxt) return end
			data.offsets.lay, data.offsets.swim = data.offset_lay, data.offset_swim
			avatarCache = data
			cb(data)
		end
		nxt()
	end)
end
