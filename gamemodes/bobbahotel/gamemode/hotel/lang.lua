-- Texts: every word the hotel shows comes from a language file, so anyone can add a language.
--
--   BOBBA.lang.add("en", { ["catalogue.title"] = "Catalogue", ["coins.amount"] = "{n} coins" })
--   BOBBA.lang.get("coins.amount", { n = 5 })   --> "5 coins"
--
-- Several addons may add to the same language; a missing text falls back to English, then to the key.

BOBBA.lang = BOBBA.lang or { strings = {}, current = "en" }
local lang = BOBBA.lang

BOBBA.registry.defineType("language", { fields = { name = "string" } })

function lang.add(code, strings, name)
	assert(BOBBA.util.validId(code), "language code must be an id like 'en' or 'da'")
	assert(type(strings) == "table", "lang.add(code, strings)")
	if not BOBBA.registry.get("language", code) then
		BOBBA.registry.register("language", code, { name = name or code })
	end
	local into = lang.strings[code]
	if not into then
		into = {}
		lang.strings[code] = into
	end
	for k, v in pairs(strings) do
		if type(k) == "string" and type(v) == "string" then into[k] = v end
	end
end

function lang.set(code)
	if not lang.strings[code] then return false end
	lang.current = code
	BOBBA.events.emit("languageChanged", code)
	return true
end

function lang.has(key)
	local cur = lang.strings[lang.current]
	local en = lang.strings.en
	return (cur and cur[key] ~= nil) or (en and en[key] ~= nil) or false
end

function lang.get(key, vars)
	local cur = lang.strings[lang.current]
	local text = cur and cur[key]
	if text == nil then
		local en = lang.strings.en
		text = en and en[key]
	end
	if text == nil then return key end
	return BOBBA.util.format(text, vars)
end

BOBBA.L = lang.get
