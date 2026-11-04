-- Managing the hotel (hotel/manage.lua)
local T = {}
local function ok(v, what) if not v then error("expected: " .. tostring(what), 2) end end
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	local admin, guest = { key = "3001", name = "Owner" }, { key = "3002", name = "Guest" }
	P.granted[admin] = { ["bobba.admin.hotel"] = true }
	return admin, guest
end
local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end

T["only the owner and admins see and change it"] = function()
	local admin, guest = start()
	P.fromPlayer(guest, "manage.get", {})
	eq(last(guest, "manage.state").denied, true)
	P.fromPlayer(guest, "manage.set", { key = "catalog.price", value = 1 })
	eq(BOBBA.store.setting("catalog.price", "5"), "5")
	P.fromPlayer(admin, "manage.get", {})
	local st = last(admin, "manage.state")
	eq(st.denied, nil)
	eq(st.sections[1].id, "core")
	ok(#st.sections[1].settings > 10, "the core's settings")
end

T["settings: checked by their kind, then kept"] = function()
	local admin = start()
	P.fromPlayer(admin, "manage.set", { key = "catalog.price", value = "12" })
	eq(BOBBA.store.setting("catalog.price"), "12")
	P.fromPlayer(admin, "manage.set", { key = "catalog.price", value = "-3" })
	eq(BOBBA.store.setting("catalog.price"), "12")
	ok(last(admin, "manage.error").message:find("at least"), "too small")
	P.fromPlayer(admin, "manage.set", { key = "videos.enabled", value = false })
	eq(BOBBA.store.setting("videos.enabled"), "0")
	P.fromPlayer(admin, "manage.set", { key = "club.mode", value = "both" })
	eq(BOBBA.store.setting("club.mode"), "both")
	P.fromPlayer(admin, "manage.set", { key = "club.mode", value = "gold" })
	eq(BOBBA.store.setting("club.mode"), "both")
	P.fromPlayer(admin, "manage.set", { key = "nope.nothing", value = "1" })
	eq(last(admin, "manage.error").message, "no such setting")
end

T["the look: name, style, colour, page and news; everyone's told"] = function()
	local admin, guest = start()
	P.fromPlayer(admin, "manage.set", { key = "look.name", value = "Sunset Hotel" })
	eq(BOBBA.access.hotelName(), "Sunset Hotel")
	P.fromPlayer(admin, "manage.set", { key = "look.style", value = "habbo" })
	eq(BOBBA.store.setting("ui.style"), "habbo")
	P.fromPlayer(admin, "manage.set", { key = "look.style", value = "pink" })
	eq(BOBBA.store.setting("ui.style"), "habbo")
	P.fromPlayer(admin, "manage.set", { key = "look.accent", value = "#9db4ff" })
	eq(BOBBA.store.setting("ui.accent"), "9DB4FF")
	P.fromPlayer(admin, "manage.set", { key = "look.news", value = { { title = "Hello\tthere", text = "Line one\nline two", color = "zz" } } })
	local news = BOBBA.manage.news()
	eq(#news, 1)
	eq(news[1].title, "Hello\tthere")
	eq(news[1].text, "Line one\nline two")
	eq(news[1].color, "FFD166")
	P.fromPlayer(guest, "hotel.look", {})
	local look = last(guest, "hotel.look")
	eq(look.style, "habbo")
	eq(look.accent, "9DB4FF")
	eq(look.name, "Sunset Hotel")
end

T["addons: switched off from the next start; their own settings listed"] = function()
	local admin = start()
	BOBBA.addons.all = { extra = { id = "extra", name = "Extra", version = "1", requires = {} } }
	BOBBA.addons.loaded.extra = BOBBA.addons.all.extra
	BOBBA.manage.settings("extra", "Extra", { { key = "extra.words", name = "Words", type = "text", default = "hi", max = 5 } })
	P.fromPlayer(admin, "manage.addon", { id = "extra", on = false })
	eq(P.disabled, "extra")
	local st = last(admin, "manage.state")
	eq(st.restart, true)
	eq(st.addons[1].on, false)
	eq(st.addons[1].loaded, true)
	P.fromPlayer(admin, "manage.addon", { id = "extra", on = true })
	eq(P.disabled, "")
	eq(last(admin, "manage.state").restart, false)
	P.fromPlayer(admin, "manage.set", { key = "extra.words", value = "toolong" })
	eq(BOBBA.store.setting("extra.words", "hi"), "hi")
	P.fromPlayer(admin, "manage.restart", {})
	eq(P.restarted, 1)
	BOBBA.addons.all, BOBBA.addons.loaded.extra = nil, nil
end

return T
