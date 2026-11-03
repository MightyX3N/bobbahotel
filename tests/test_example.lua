local T = {}

T["the example addon loads and does what the guide says"] = function()
	local dir = TEST_ROOT .. "/../examples/bobba_example/lua/bobbahotel/addons/bobba_example/"
	local function file(name)
		return function() return assert(loadfile(dir .. name))() end
	end
	BOBBA.platform.fakeAddons = {
		bobba_example = { ["addon.lua"] = file("addon.lua"), ["shared.lua"] = file("shared.lua"), ["server.lua"] = file("server.lua") },
	}
	BOBBA.addons.loadAll()
	eq(BOBBA.addons.loaded.bobba_example ~= nil, true, "loaded")
	eq(BOBBA.registry.get("language", "da").name, "Dansk")
	eq(BOBBA.registry.get("permission", "bobba_example.wave").addon, "bobba_example")
	eq(BOBBA.perms.has("anyone", "bobba_example.wave"), true)
	BOBBA.store.query("INSERT INTO bobba_example_visits (steamid, visits) VALUES (?, ?)", { "STEAM_0:1:2", 1 })
	eq(BOBBA.store.row("SELECT visits FROM bobba_example_visits").visits, 1)
	BOBBA.lang.set("da")
	eq(BOBBA.L("status.addons", { count = 1 }), "Tilføjelser indlæst: 1")
	eq(BOBBA.L("status.ping", { ms = 3 }), "Server answered in 3 ms", "falls back to English")
end

return T
