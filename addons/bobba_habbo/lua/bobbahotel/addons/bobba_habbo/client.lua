-- bobba_habbo_test: downloads a piece of furniture (the throne) and an avatar part (the body) from
-- Habbo, unpacks them into garrysmod/data/bobbahotel/habbo/ and says what it found.

local H = BOBBA.habbo

-- Habbo avatars in rooms
BOBBA.platform.runAddonFile("bobba_habbo", "avatars.lua")
-- Habbo furni in rooms
BOBBA.platform.runAddonFile("bobba_habbo", "furni.lua")

concommand.Add("bobba_habbo_test", function()
	print("[Bobba] asking Habbo where its files are...")
	H.config(function(cfg, err)
		if not cfg then print("[Bobba] " .. err) return end
		print("[Bobba] client files: " .. cfg.clientUrl)
		local function report(lib, err2)
			if not lib then print("[Bobba] failed: " .. tostring(err2)) return end
			local n, x = 0, 0
			for _ in pairs(lib.images) do n = n + 1 end
			for _ in pairs(lib.xml) do x = x + 1 end
			print(string.format("[Bobba] %s: %d pictures, %d XML files, %d problems", lib.key, n, x, #lib.problems))
			for _, p in ipairs(lib.problems) do print("[Bobba]   " .. p) end
			for name, text in pairs(lib.xml) do
				BOBBA.platform.writeData("habbo/xml/" .. lib.key .. "/" .. name .. ".txt", text)
			end
		end
		local t0 = SysTime()
		H.library("furni/throne", cfg.furniUrl .. "45512/throne.swf", function(lib, e)
			report(lib, e)
			H.library("figure/hh_human_body", cfg.clientUrl .. "hh_human_body.swf", function(lib2, e2)
				report(lib2, e2)
				print(string.format("[Bobba] done in %.2f s", SysTime() - t0))
			end)
		end)
	end)
end)

-- bobba_habbo_avatardata: gets everything Habbo draws avatars with (the first time this downloads
-- Habbo's desktop client, about 19 MB, and takes the avatar data out of it).
concommand.Add("bobba_habbo_avatardata", function()
	print("[Bobba] getting Habbo's avatar data (the first time takes a while)...")
	local t0 = SysTime()
	H.avatarData(function(data, err)
		if not data then print("[Bobba] failed: " .. tostring(err)) return end
		local names = {}
		for k, v in pairs(data) do
			if type(v) == "string" then names[#names + 1] = k end
		end
		table.sort(names)
		for _, k in ipairs(names) do
			print(string.format("[Bobba]   %-12s %8d bytes", k, #data[k]))
		end
		print(string.format("[Bobba] done in %.2f s", SysTime() - t0))
	end)
end)

-- bobba_habbo_figure <figure>: downloads the clothes of a figure, e.g.
--   bobba_habbo_figure hr-100-61.hd-180-1.ch-210-66.lg-270-82.sh-290-80
concommand.Add("bobba_habbo_figure", function(_, _, args)
	local figure = args[1] or "hr-100-61.hd-180-1.ch-210-66.lg-270-82.sh-290-80"
	print("[Bobba] getting the clothes for " .. figure .. "...")
	local t0 = SysTime()
	H.figureLibraries(figure, function(libs, err)
		if not libs then print("[Bobba] failed: " .. tostring(err)) return end
		for _, lib in ipairs(libs) do
			local n = 0
			for _ in pairs(lib.images) do n = n + 1 end
			print(string.format("[Bobba]   %-32s %4d pictures, %d problems", lib.key, n, #lib.problems))
			for name, text in pairs(lib.xml) do
				BOBBA.platform.writeData("habbo/xml/" .. lib.key .. "/" .. name .. ".txt", text)
			end
		end
		print(string.format("[Bobba] done in %.2f s", SysTime() - t0))
	end)
end)

-- bobba_habbo_imaging: saves Habbo's own pictures of a figure (habbo-imaging) to
-- garrysmod/data/bobbahotel/habbo/imaging/, to check our avatars against. For testing.
concommand.Add("bobba_habbo_imaging", function(_, _, args)
	local figure = args[1] or "hr-100-61.hd-180-1.ch-210-66.lg-270-82.sh-290-80"
	local list = {}
	for d = 0, 7 do
		list[#list + 1] = { "std_" .. d, "direction=" .. d .. "&head_direction=" .. d .. "&action=std&gesture=std" }
		list[#list + 1] = { "sit_" .. d, "direction=" .. d .. "&head_direction=" .. d .. "&action=sit" }
		list[#list + 1] = { "lay_" .. d, "direction=" .. d .. "&head_direction=" .. d .. "&action=lay" }
		list[#list + 1] = { "head_" .. d, "direction=" .. d .. "&head_direction=" .. ((d + 1) % 8) .. "&action=std" }
		list[#list + 1] = { "crr_" .. d, "direction=" .. d .. "&head_direction=" .. d .. "&action=crr=2" }
		list[#list + 1] = { "sml_" .. d, "direction=" .. d .. "&head_direction=" .. d .. "&action=std&gesture=sml" }
	end
	local done = 0
	for _, item in ipairs(list) do
		local url = "https://www.habbo.com/habbo-imaging/avatarimage?figure=" .. figure .. "&" .. item[2] .. "&img_format=png"
		BOBBA.platform.httpGet(url, function(body)
			BOBBA.platform.writeData("habbo/imaging/" .. item[1] .. ".png", body)
			done = done + 1
			if done == #list then print("[Bobba] saved " .. done .. " pictures from Habbo") end
		end, function(why) print("[Bobba] " .. item[1] .. ": " .. tostring(why)) end)
	end
end)

-- bobba_habbo_furni <classname>: downloads and unpacks one furni (e.g. throne, rare_dragonlamp*1)
concommand.Add("bobba_habbo_furni", function(_, _, args)
	local class = args[1] or "throne"
	local t0 = SysTime()
	H.furniLibrary(class, function(lib, err)
		if not lib then print("[Bobba] " .. class .. ": " .. tostring(err)) return end
		local n = 0
		for _ in pairs(lib.images) do n = n + 1 end
		print(string.format("[Bobba] %s: %d pictures, %d problems, %.2f s", lib.key, n, #lib.problems, SysTime() - t0))
	end)
end)

-- bobba_habbo_furni_sample [count]: downloads (without unpacking) a set of furni to check the
-- furniture code with: some chosen ones and [count] (default 60) picked at random from furnidata.
-- They land in garrysmod/data/bobbahotel/habbo/raw/furni/. For testing.
H.FURNI_SAMPLE = {
	"throne", "chair_polyfon", "sofa_polyfon", "bed_polyfon", "bed_budget", "bed_budget_one", "table_polyfon_small",
	"rare_dragonlamp", "rare_fan", "lamp_basic", "scifiport", "edice", "pillow", "chair_norja", "sofachair_norja",
	"rare_icecream", "hc_lmp", "habbowheel", "doorD", "rare_parasol", "carpet_standard", "pura_mdl1", "teleport_door",
}
concommand.Add("bobba_habbo_furni_sample", function(_, _, args)
	local count = tonumber(args[1]) or 60
	H.furnidata(function(fd, err)
		if not fd then print("[Bobba] " .. tostring(err)) return end
		local classes, seen = {}, {}
		local function add(c)
			local base = H.furniBase(c)
			if seen[base] or not fd.byClass[c] then return end
			seen[base] = true
			classes[#classes + 1] = c
		end
		for _, c in ipairs(H.FURNI_SAMPLE) do add(c) end
		local all = {}
		for c, f in pairs(fd.byClass) do if not f.wall then all[#all + 1] = c end end
		table.sort(all)
		math.randomseed(12345)
		for _ = 1, count * 3 do
			if #classes >= #H.FURNI_SAMPLE + count then break end
			add(all[math.random(#all)])
		end
		print("[Bobba] downloading " .. #classes .. " furni...")
		local left, failed = #classes, 0
		for _, c in ipairs(classes) do
			H.furniUrl(c, function(url, base)
				if not url then failed = failed + 1 left = left - 1 return end
				H.download("furni/" .. base, url, function(bytes, e)
					if not bytes then failed = failed + 1 print("[Bobba]   " .. c .. ": " .. tostring(e)) end
					left = left - 1
					if left == 0 then print("[Bobba] done: " .. (#classes - failed) .. " furni, " .. failed .. " failed") end
				end)
			end)
		end
	end)
end)
