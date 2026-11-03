-- Runs on the server and on every player. Registers a language and a permission, the same way
-- furni, clothes and windows will be registered.

BOBBA.lang.add("da", {
	["status.addons"] = "Tilføjelser indlæst: {count}",
	["status.language"] = "Sprog: {code}",
	["common.ok"] = "OK",
}, "Dansk")

BOBBA.perms.define("bobba_example.wave", { default = "user", description = "Example: everyone may wave" })
