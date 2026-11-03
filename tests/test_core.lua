local T = {}

-- util -----------------------------------------------------------------------------------------

T["util: SQL values are quoted, never pasted in raw"] = function()
	local q = BOBBA.platform.db.quote
	eq(BOBBA.util.bindSql("SELECT ? , ?, ?", { "it's", 5, true }, q), "SELECT 'it''s' , 5, 1")
	eq(BOBBA.util.bindSql("x = ?", { BOBBA.util.NULL }, q), "x = NULL")
end

T["util: wrong number of SQL values is an error"] = function()
	local ok = pcall(BOBBA.util.bindSql, "a = ? AND b = ?", { 1 }, BOBBA.platform.db.quote)
	eq(ok, false, "pcall")
end

T["util: text placeholders"] = function()
	eq(BOBBA.util.format("{n} coins for {who}", { n = 5, who = "Mia" }), "5 coins for Mia")
	eq(BOBBA.util.format("{missing} stays", {}), "{missing} stays")
end

T["util: ids"] = function()
	eq(BOBBA.util.validId("bobba_sofa_1"), true)
	eq(BOBBA.util.validId("Sofa"), false)
	eq(BOBBA.util.validId("a b"), false)
	eq(BOBBA.util.validId(5), false)
end

-- events ---------------------------------------------------------------------------------------

T["events: listeners run, a broken one doesn't stop the rest"] = function()
	local got = {}
	BOBBA.events.on("x", "a", function() error("boom") end)
	BOBBA.events.on("x", "b", function(v) got[#got + 1] = v end)
	BOBBA.events.emit("x", 7)
	eq(got[1], 7)
	eq(lastLog():find("boom") ~= nil, true, "error logged")
end

T["events: a listener can answer, and be replaced or removed"] = function()
	BOBBA.events.on("ask", "one", function() return "first" end)
	eq(BOBBA.events.emit("ask"), "first")
	BOBBA.events.on("ask", "one", function() return "replaced" end)
	eq(BOBBA.events.emit("ask"), "replaced")
	BOBBA.events.off("ask", "one")
	eq(BOBBA.events.emit("ask"), nil)
end

-- registry -------------------------------------------------------------------------------------

local function defineThing()
	BOBBA.registry.defineType("thing", {
		fields = { name = "string", size = "number", note = "string?" },
		defaults = { size = 1 },
		validate = function(d) return d.size > 0, "size must be positive" end,
	})
end

T["registry: a valid entry is registered with its addon"] = function()
	defineThing()
	BOBBA.registry.currentAddon = "packa"
	eq(BOBBA.registry.register("thing", "sofa", { name = "Sofa" }), true)
	local e = BOBBA.registry.get("thing", "sofa")
	eq(e.name, "Sofa")
	eq(e.size, 1, "default filled in")
	eq(e.addon, "packa")
end

T["registry: bad entries are left out with a reason"] = function()
	defineThing()
	eq(BOBBA.registry.register("thing", "a", { size = 2 }), false, "missing name")
	eq(BOBBA.registry.register("thing", "b", { name = 5 }), false, "wrong kind")
	eq(BOBBA.registry.register("thing", "c", { name = "C", size = -1 }), false, "validate")
	eq(BOBBA.registry.register("thing", "Bad Id", { name = "D" }), false, "bad id")
	eq(BOBBA.registry.register("nope", "e", { name = "E" }), false, "unknown type")
	eq(BOBBA.registry.count("thing"), 0)
end

T["registry: another addon can't overwrite by accident, only on purpose"] = function()
	defineThing()
	BOBBA.registry.currentAddon = "packa"
	BOBBA.registry.register("thing", "sofa", { name = "Sofa" })
	BOBBA.registry.currentAddon = "packb"
	eq(BOBBA.registry.register("thing", "sofa", { name = "Other" }), false, "accidental clash")
	eq(BOBBA.registry.get("thing", "sofa").name, "Sofa")
	eq(BOBBA.registry.register("thing", "sofa", { name = "Better" }, { replace = true }), true, "on purpose")
	eq(BOBBA.registry.get("thing", "sofa").name, "Better")
	eq(BOBBA.registry.get("thing", "sofa").replaced, "packa")
end

T["registry: the same addon registering again is a reload, not a clash"] = function()
	defineThing()
	BOBBA.registry.currentAddon = "packa"
	BOBBA.registry.register("thing", "sofa", { name = "Sofa" })
	eq(BOBBA.registry.register("thing", "sofa", { name = "Sofa 2" }), true)
	eq(BOBBA.registry.get("thing", "sofa").replaced, nil)
end

T["registry: list is sorted by order, then id"] = function()
	defineThing()
	BOBBA.registry.register("thing", "b", { name = "B" })
	BOBBA.registry.register("thing", "a", { name = "A" })
	BOBBA.registry.register("thing", "z", { name = "Z", order = -1 })
	local l = BOBBA.registry.list("thing")
	eq(l[1].id .. l[2].id .. l[3].id, "zab")
end

-- languages ------------------------------------------------------------------------------------

T["lang: texts, placeholders, and falling back to English, then the key"] = function()
	BOBBA.lang.add("en", { ["hi"] = "Hello {name}", ["only.en"] = "English only" })
	BOBBA.lang.add("da", { ["hi"] = "Hej {name}" }, "Dansk")
	eq(BOBBA.lang.get("hi", { name = "Mia" }), "Hello Mia")
	eq(BOBBA.lang.set("da"), true)
	eq(BOBBA.lang.get("hi", { name = "Mia" }), "Hej Mia")
	eq(BOBBA.lang.get("only.en"), "English only")
	eq(BOBBA.lang.get("never.added"), "never.added")
	eq(BOBBA.lang.set("xx"), false, "unknown language")
	eq(BOBBA.lang.current, "da")
end

T["lang: the core's English texts are there"] = function()
	eq(BOBBA.lang.has("status.title"), true)
	eq(BOBBA.registry.get("language", "en").name, "English")
end

-- permissions ----------------------------------------------------------------------------------

T["perms: the hotel's permissions are handed to the admin system"] = function()
	eq(BOBBA.platform.defined["bobba.staff.deletefurni"], "admin")
	eq(BOBBA.platform.defined["bobba.admin.settings"], "superadmin")
end

T["perms: defaults, granted, unknown"] = function()
	BOBBA.perms.define("test.hug", { default = "user", description = "Hug" })
	eq(BOBBA.perms.has("mia", "test.hug"), true, "user default")
	eq(BOBBA.perms.has("mia", "bobba.staff.kick"), false, "admin default for a normal player")
	BOBBA.platform.granted.mia = { ["bobba.staff.kick"] = true }
	eq(BOBBA.perms.has("mia", "bobba.staff.kick"), true, "granted by the admin mod")
	eq(BOBBA.perms.has("console", "bobba.admin.settings"), true, "console")
	eq(BOBBA.perms.has("mia", "never.defined"), false, "unknown is denied")
end

T["perms: a bad default is refused"] = function()
	eq(BOBBA.perms.define("test.bad", { default = "everyone" }), false)
end

-- saving ---------------------------------------------------------------------------------------

T["store: a migration runs once"] = function()
	eq(BOBBA.store.migrate("test.001", { "CREATE TABLE t (a TEXT)" }), true)
	eq(BOBBA.store.migrate("test.001", { "CREATE TABLE t (a TEXT)" }), false)
	BOBBA.store.query("INSERT INTO t (a) VALUES (?)", { "x" })
	eq(BOBBA.store.row("SELECT COUNT(*) AS n FROM t").n, 1)
end

T["store: a failing migration leaves nothing behind and can run again"] = function()
	local ok = pcall(BOBBA.store.migrate, "test.002", { "CREATE TABLE u (a TEXT)", "THIS IS NOT SQL" })
	eq(ok, false, "failed")
	eq(#BOBBA.store.query("SELECT name FROM sqlite_master WHERE name = 'u'"), 0, "table u rolled back")
	eq(BOBBA.store.migrate("test.002", { "CREATE TABLE u (a TEXT)" }), true, "runs again when fixed")
end

T["store: settings, with quotes in the value"] = function()
	eq(BOBBA.store.setting("lobby", "0"), "0", "default")
	BOBBA.store.setSetting("lobby", "12")
	eq(BOBBA.store.setting("lobby"), "12")
	BOBBA.store.setSetting("name", "Mia's '); DROP TABLE bobba_settings; --")
	eq(BOBBA.store.setting("name"), "Mia's '); DROP TABLE bobba_settings; --")
	eq(BOBBA.store.setting("lobby"), "12", "table still there")
end

-- addons ---------------------------------------------------------------------------------------

local function manifest(id, requires)
	return function() return { id = id, name = id:upper(), version = "1.0", requires = requires } end
end

T["addons: requirements load first; missing, switched-off and looping ones are skipped"] = function()
	local loaded = {}
	local function track(id) return function() loaded[#loaded + 1] = id end end
	local P = BOBBA.platform
	P.fakeAddons = {
		furni = { ["addon.lua"] = manifest("furni", { "base" }), ["shared.lua"] = track("furni") },
		base = { ["addon.lua"] = manifest("base"), ["shared.lua"] = track("base") },
		lonely = { ["addon.lua"] = manifest("lonely", { "ghost" }), ["shared.lua"] = track("lonely") },
		off = { ["addon.lua"] = manifest("off"), ["shared.lua"] = track("off") },
		needsoff = { ["addon.lua"] = manifest("needsoff", { "off" }), ["shared.lua"] = track("needsoff") },
		loopa = { ["addon.lua"] = manifest("loopa", { "loopb" }), ["shared.lua"] = track("loopa") },
		loopb = { ["addon.lua"] = manifest("loopb", { "loopa" }), ["shared.lua"] = track("loopb") },
		wrongid = { ["addon.lua"] = manifest("notthesame") },
	}
	P.disabled = "off"
	BOBBA.addons.loadAll()
	eq(table.concat(loaded, ","), "base,furni")
	local s = BOBBA.addons.skipped
	eq(s.lonely ~= nil, true, "missing requirement")
	eq(s.off, "switched off by the server")
	eq(s.needsoff ~= nil, true, "needs a switched-off addon")
	eq(s.loopa ~= nil and s.loopb ~= nil, true, "loop")
	eq(s.wrongid ~= nil, true, "id must match folder")
end

T["addons: what an addon registers is credited to it, and a broken addon doesn't stop the others"] = function()
	local P = BOBBA.platform
	BOBBA.registry.defineType("thing", { fields = { name = "string" } })
	P.fakeAddons = {
		broken = { ["addon.lua"] = function() error("oops in addon.lua") end },
		good = { ["addon.lua"] = manifest("good"), ["shared.lua"] = function()
			BOBBA.registry.register("thing", "lamp", { name = "Lamp" })
		end },
	}
	P.disabled = ""
	BOBBA.addons.loadAll()
	eq(BOBBA.registry.get("thing", "lamp").addon, "good")
	eq(BOBBA.registry.currentAddon, "core", "reset after loading")
	eq(BOBBA.addons.loaded.good ~= nil, true)
	eq(BOBBA.addons.skipped.broken ~= nil, true)
end

return T
