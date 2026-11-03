-- Checks you can run in the console to see that the foundation works:
--   bobba_status      (server console, or an admin in game) what the server loaded
--   bobba_cl_status   (your own console) what your game loaded, and a round trip to the server

local L = BOBBA.L

local function report(print)
	local p = BOBBA.platform
	print(L("status.title", { version = BOBBA.VERSION, platform = p.name .. (p.isServer and " server" or " client") }))
	local ids = BOBBA.util.keys(BOBBA.addons.loaded)
	print(L("status.addons", { count = #ids }))
	for _, id in ipairs(ids) do
		local m = BOBBA.addons.loaded[id]
		print(L("status.addon", { name = m.name, version = m.version, id = id }))
	end
	for _, id in ipairs(BOBBA.util.keys(BOBBA.addons.skipped)) do
		print(L("status.skipped", { id = id, why = BOBBA.addons.skipped[id] }))
	end
	local counts = {}
	for _, t in ipairs(BOBBA.util.keys(BOBBA.registry.types)) do
		counts[#counts + 1] = t .. " " .. BOBBA.registry.count(t)
	end
	print(L("status.registry", { list = table.concat(counts, ", ") }))
	print(L("status.permissions", { backend = p.permissionBackend() }))
	if p.isServer then
		local ok = pcall(function()
			BOBBA.store.setSetting("status_check", "ok")
			assert(BOBBA.store.setting("status_check") == "ok")
		end)
		local n = BOBBA.store.row("SELECT COUNT(*) AS n FROM bobba_migrations").n
		print(L("status.database", { migrations = n, result = ok and L("common.ok") or L("common.failed") }))
	end
	print(L("status.language", { code = BOBBA.lang.current }))
end

if SERVER then
	concommand.Add("bobba_status", function(ply)
		if IsValid(ply) and not BOBBA.perms.has(ply, "bobba.admin.settings") then return end
		report(function(line)
			if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
		end)
	end)

	-- the round trip: a player asks, the server answers with the time it was asked
	BOBBA.platform.receive("status.ping", function(ply, data)
		BOBBA.platform.send("status.pong", { sent = data.sent }, ply)
	end)
else
	concommand.Add("bobba_cl_status", function()
		report(print)
		BOBBA.platform.send("status.ping", { sent = SysTime() })
	end)

	BOBBA.platform.receive("status.pong", function(_, data)
		print(L("status.ping", { ms = math.Round((SysTime() - (data.sent or SysTime())) * 1000) }))
	end)
end
