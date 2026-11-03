-- bobba_habbo_test: downloads a piece of furniture (the throne) and an avatar part (the body) from
-- Habbo, unpacks them into garrysmod/data/bobbahotel/habbo/ and says what it found.

local H = BOBBA.habbo

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
