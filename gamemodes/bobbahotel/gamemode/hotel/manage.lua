-- Managing the hotel (server): what its owner and admins change from the start screen's "Manage
-- hotel" (client/manage.lua) - the hotel's addons (on or off; that takes a restart), their settings and
-- the hotel's own, and its look: its name, what it's about and its news (its page), the UI it starts
-- in, its colour and which page it shows. Needs bobba.admin.hotel (admins and up by default).
--
-- Settings are described so the screen can show them. The core's are below; an addon has its own in
-- its addon.lua (settings = { ... }) or from its code:
--
--   BOBBA.manage.settings("my_addon", "My addon", {
--       { key = "my_addon.price", name = "Price", type = "number", default = 10, min = 0, max = 1000, description = "..." },
--       { key = "my_addon.on", name = "On", type = "bool", default = true },
--       { key = "my_addon.mode", name = "Mode", type = "choice", default = "a", choices = { { "a", "First" }, { "b", "Second" } } },
--       { key = "my_addon.word", name = "Word", type = "text", default = "", max = 60 },
--   })
--
-- Messages from players: manage.get {}   manage.set { key, value }   manage.addon { id, on }   manage.restart {}
-- Messages to players:   manage.state { addons, sections, look, restart, platform }   manage.saved { key }
--                        manage.error { message }   manage.restarting {}
--                        hotel.look { style, accent, website, name } (to everyone, when it changes; and asked: hotel.look {})

BOBBA.manage = BOBBA.manage or {}
local M = BOBBA.manage
local function P() return BOBBA.platform end
local function S() return BOBBA.store end

M.PERM = "bobba.admin.hotel"
BOBBA.perms.define(M.PERM, { default = "admin", description = "Manage the hotel: its addons, their settings and its look" })

M.sections = M.sections or {}     -- id -> { id, name, order, settings = { def, ... } }
M.byKey = M.byKey or {}           -- setting key -> def
M.sectionOrder = M.sectionOrder or 0

-- describes some settings (a section: the core's, or an addon's)
function M.settings(id, name, list)
	local sec = M.sections[id]
	if not sec then
		M.sectionOrder = M.sectionOrder + 1
		sec = { id = id, name = name or id, order = M.sectionOrder, settings = {} }
		M.sections[id] = sec
	end
	sec.name = name or sec.name
	for _, d in ipairs(list or {}) do
		if type(d) == "table" and type(d.key) == "string" and d.key ~= "" then
			d.type = (d.type == "bool" or d.type == "number" or d.type == "choice" or d.type == "text") and d.type or "text"
			d.name = d.name or d.key
			d.section = id
			if not M.byKey[d.key] then sec.settings[#sec.settings + 1] = d end
			M.byKey[d.key] = d
		end
	end
	return sec
end

-- a setting's value now (as its type: true/false, a number, a string)
local function toStored(d, v)
	if d.type == "bool" then return (v == true or v == 1 or v == "1" or v == "true") and "1" or "0" end
	return tostring(v)
end
function M.value(d)
	local default = d.default
	if default == nil then default = (d.type == "bool" and false) or (d.type == "number" and 0) or "" end
	local raw = S().setting(d.key, nil)
	if raw == nil then return default end
	if d.type == "bool" then return raw ~= "0" and raw ~= "" end
	if d.type == "number" then return tonumber(raw) or default end
	return raw
end

-- is v right for d? the value to keep, or nil and why
function M.check(d, v)
	if d.type == "bool" then return toStored(d, v) end
	if d.type == "number" then
		local n = tonumber(v)
		if not n or n ~= n then return nil, "that isn't a number" end
		if d.whole ~= false then n = math.floor(n + 0.5) end
		if d.min and n < d.min then return nil, "at least " .. d.min end
		if d.max and n > d.max then return nil, "at most " .. d.max end
		return tostring(n)
	end
	if d.type == "choice" then
		for _, c in ipairs(d.choices or {}) do if tostring(c[1]) == tostring(v) then return tostring(c[1]) end end
		return nil, "that isn't one of the choices"
	end
	local t = tostring(v or ""):gsub("[%z\1-\8\11-\31]", "")
	if #t > (d.max or 200) then return nil, "at most " .. (d.max or 200) .. " letters" end
	return t
end

-- --- the core's settings ------------------------------------------------------------------------------
local function n(key, name, default, min, max, description, group) return { key = key, name = name, type = "number", default = default, min = min, max = max, description = description, group = group } end
local function b(key, name, default, description, group) return { key = key, name = name, type = "bool", default = default, description = description, group = group } end
M.settings("core", "The hotel", {
	n("wallet.start.credits", "Credits to start with", 5000, 0, 1000000, "What a new player has", "Money"),
	n("wallet.start.duckets", "Duckets to start with", 0, 0, 1000000, nil, "Money"),
	n("wallet.start.diamonds", "Diamonds to start with", 0, 0, 1000000, nil, "Money"),
	n("wallet.pay.every", "Pay every (seconds)", 900, 60, 86400, "Everyone online is paid this often", "Money"),
	n("wallet.pay.credits", "Credits each time", 25, 0, 100000, nil, "Money"),
	n("wallet.pay.duckets", "Duckets each time", 50, 0, 100000, nil, "Money"),
	n("wallet.pay.diamonds", "Diamonds each time", 2, 0, 100000, nil, "Money"),
	b("trading.enabled", "Trading", true, "Players swap furni in rooms that allow it", "Money"),
	n("economy.keep.days", "Keep the money log (days)", 90, 0, 3650, "0: for ever", "Money"),
	n("catalog.price", "Furni price (credits)", 5, 0, 100000, "What each furni in the shop costs", "Shops"),
	b("catalog.seasons", "Seasonal furni only in season", true, "Christmas furni at Christmas, and so on", "Shops"),
	{ key = "club.mode", name = "Clubs", type = "choice", default = "hc", choices = { { "hc", "Habbo Club" }, { "vip", "VIP" }, { "both", "Both" } }, group = "Shops" },
	n("hc.price.31", "Club, 1 month (diamonds)", 250, 0, 1000000, nil, "Shops"),
	n("hc.price.93", "Club, 3 months (diamonds)", 700, 0, 1000000, nil, "Shops"),
	n("vip.price.31", "VIP, 1 month (diamonds)", 400, 0, 1000000, nil, "Shops"),
	n("vip.price.93", "VIP, 3 months (diamonds)", 1100, 0, 1000000, nil, "Shops"),
	n("camera.price.credits", "A photo (credits)", 2, 0, 100000, nil, "Shops"),
	n("groups.price.credits", "Making a group (credits)", 100, 0, 1000000, nil, "People"),
	n("groups.max.owned", "Groups one can own", 5, 0, 100, nil, "People"),
	n("friends.max", "Most friends", 300, 1, 5000, nil, "People"),
	n("events.price.credits", "Putting on an event (credits)", 0, 0, 100000, nil, "People"),
	n("events.max.hours", "Longest event (hours)", 3, 1, 48, nil, "People"),
	n("tutorial.reward.credits", "Tutorial reward (credits)", 50, 0, 100000, "For finishing the first steps", "People"),
	b("videos.enabled", "Videos", true, "The rooms' TVs", "Rooms"),
	b("wired.scripts", "Wired scripts", true, "The script boxes: a little Lua in a room's wired", "Rooms"),
	{ key = "videos.services", name = "Video services", type = "text", default = "youtube", max = 80, description = "Which ones play (youtube)", group = "Rooms" },
	b("floorplan.club", "Floor plans for club members only", true, nil, "Rooms"),
	n("rooms.idle.seconds", "Asleep after (seconds)", 120, 10, 3600, "Avatars that do nothing fall asleep", "Rooms"),
})

-- addons' own settings, from their addon.lua (settings = { ... })
function M.fromManifests()
	for id, m in pairs(BOBBA.addons.all or {}) do
		if type(m.settings) == "table" and #m.settings > 0 then M.settings(id, m.name, m.settings) end
	end
end

-- --- the look ------------------------------------------------------------------------------------------
M.LOOK = {
	name = { key = "hotel_name", max = 32 },
	description = { key = "hotel.description", max = 400 },
	style = { key = "ui.style", choices = { [""] = true, phone = true, habbo = true } },
	accent = { key = "ui.accent" },
	website = { key = "website.page", max = 40 },
	news = { key = "website.news" },
}
-- the news: kept as lines of title, text, date, colour (tabs between; older hotels: JSON)
local function esc(s) return (tostring(s or ""):gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\n", "\\n")) end
local function unesc(s) return (s:gsub("\\(.)", function(c) return c == "t" and "\t" or c == "n" and "\n" or c end)) end
function M.news()
	local raw = S().setting("website.news", "") or ""
	if raw:sub(1, 1) == "[" then
		local t = util and util.JSONToTable and util.JSONToTable(raw) or nil
		return type(t) == "table" and t or {}
	end
	local out = {}
	for line in (raw .. "\n"):gmatch("(.-)\n") do
		if line ~= "" then
			local f = {}
			for part in (line .. "\t"):gmatch("(.-)\t") do f[#f + 1] = unesc(part) end
			out[#out + 1] = { title = f[1] or "", text = f[2] or "", date = f[3] ~= "" and f[3] or nil, color = f[4] ~= "" and f[4] or nil }
		end
	end
	return out
end
local function packNews(list)
	local lines = {}
	for _, it in ipairs(list) do lines[#lines + 1] = esc(it.title) .. "\t" .. esc(it.text) .. "\t" .. esc(it.date) .. "\t" .. esc(it.color) end
	return table.concat(lines, "\n")
end

function M.look()
	local news = M.news()
	return {
		name = BOBBA.access.hotelName(), description = S().setting("hotel.description", ""),
		style = S().setting("ui.style", ""), accent = S().setting("ui.accent", ""), website = S().setting("website.page", ""),
		news = type(news) == "table" and news or {},
	}
end
-- what every player's game needs of it
function M.lookForPlayers()
	local l = M.look()
	return { name = l.name, style = l.style, accent = l.accent, website = l.website }
end

local function cleanNews(list)
	local out = {}
	if type(list) ~= "table" then return out end
	for i, it in ipairs(list) do
		if i > 10 then break end
		if type(it) == "table" then
			local function c(v, m) return tostring(v or ""):gsub("[%z\1-\8\11-\31]", ""):sub(1, m) end
			local color = c(it.color, 6):gsub("[^%x]", "")
			out[#out + 1] = { title = c(it.title, 80), text = c(it.text, 400), date = c(it.date, 20), color = #color == 6 and color:upper() or "FFD166" }
		end
	end
	return out
end

function M.setLook(field, v)
	local L = M.LOOK[field]
	if not L then return false, "no such part of the look" end
	if field == "name" then BOBBA.access.setHotelName(v)
	elseif field == "style" then
		v = tostring(v or "")
		if not L.choices[v] then return false, "phone, habbo or the pack's" end
		S().setSetting(L.key, v)
	elseif field == "accent" then
		v = tostring(v or ""):gsub("[^%x]", "")
		if v ~= "" and #v ~= 6 then return false, "a colour like FF9F5A" end
		S().setSetting(L.key, v:upper())
	elseif field == "news" then
		S().setSetting(L.key, packNews(cleanNews(v)))
	else
		v = tostring(v or ""):gsub("[%z\1-\8\11-\31]", "")
		if #v > L.max then return false, "at most " .. L.max .. " letters" end
		S().setSetting(L.key, v)
	end
	P().send("hotel.look", M.lookForPlayers())
	return true
end

-- --- addons ------------------------------------------------------------------------------------------
local function disabledSet()
	local set = {}
	for id in tostring(P().disabledAddons and P().disabledAddons() or ""):gmatch("[^,%s]+") do set[id] = true end
	return set
end
-- every addon the hotel has: { id, name, version, description, author, on, loaded, why, requires, settings }
function M.addonList()
	local off = disabledSet()
	local out = {}
	for id, m in pairs(BOBBA.addons.all or {}) do
		out[#out + 1] = { id = id, name = m.name, version = m.version, description = type(m.description) == "string" and m.description or nil,
			author = type(m.author) == "string" and m.author or nil, requires = m.requires, on = not off[id],
			loaded = BOBBA.addons.loaded[id] ~= nil, why = BOBBA.addons.skipped[id], hasSettings = M.sections[id] ~= nil }
	end
	for id, why in pairs(BOBBA.addons.skipped or {}) do
		if not (BOBBA.addons.all or {})[id] then out[#out + 1] = { id = id, name = id, version = "?", on = false, loaded = false, why = why, broken = true } end
	end
	table.sort(out, function(a, b2) return tostring(a.name):lower() < tostring(b2.name):lower() end)
	return out
end

-- switches an addon on or off (from the next start); and whatever needs it, or it needs, is said
function M.setAddon(id, on)
	if not (BOBBA.addons.all or {})[id] then return false, "no such addon" end
	local off = disabledSet()
	off[id] = (not on) or nil
	local list = {}
	for k in pairs(off) do list[#list + 1] = k end
	table.sort(list)
	P().setDisabledAddons(table.concat(list, ","))
	return true
end

-- does what's switched on differ from what's running?
function M.restartNeeded()
	local off = disabledSet()
	for id in pairs(BOBBA.addons.all or {}) do
		local wanted = not off[id]
		local running = BOBBA.addons.loaded[id] ~= nil
		local skippedForOther = BOBBA.addons.skipped[id] and BOBBA.addons.skipped[id] ~= "switched off by the server"
		if wanted ~= running and not (wanted and skippedForOther) then return true end
	end
	return false
end

-- --- what the screen shows ------------------------------------------------------------------------------
function M.state()
	local sections = {}
	for _, sec in pairs(M.sections) do
		local list = {}
		for _, d in ipairs(sec.settings) do
			list[#list + 1] = { key = d.key, name = d.name, type = d.type, description = d.description, group = d.group, min = d.min, max = d.max,
				choices = d.choices, value = M.value(d), default = d.default }
		end
		sections[#sections + 1] = { id = sec.id, name = sec.name, order = sec.order, settings = list }
	end
	table.sort(sections, function(a, b2) return a.order < b2.order end)
	return { addons = M.addonList(), sections = sections, look = M.look(), restart = M.restartNeeded(),
		canRestart = P().canRestart and P().canRestart() or false }
end

function M.can(player) return player == "console" or BOBBA.perms.has(player, M.PERM) end

function M.start()
	M.fromManifests()
	local p = P()
	local function err(player, why) p.send("manage.error", { message = tostring(why) }, player) end
	p.receive("hotel.look", function(player) p.send("hotel.look", M.lookForPlayers(), player) end)
	p.receive("manage.get", function(player)
		if not M.can(player) then return p.send("manage.state", { denied = true }, player) end
		p.send("manage.state", M.state(), player)
	end)
	p.receive("manage.set", function(player, data)
		if not M.can(player) then return err(player, "only the hotel's owner and admins can change that") end
		local key = tostring(data.key or "")
		local field = key:match("^look%.(.+)$")
		local ok, why
		if field then ok, why = M.setLook(field, data.value)
		else
			local d = M.byKey[key]
			if not d then return err(player, "no such setting") end
			local v
			v, why = M.check(d, data.value)
			if v then S().setSetting(key, v) ok = true end
		end
		if not ok then return err(player, why) end
		p.send("manage.saved", { key = key }, player)
		p.send("manage.state", M.state(), player)
	end)
	p.receive("manage.addon", function(player, data)
		if not M.can(player) then return err(player, "only the hotel's owner and admins can change that") end
		local ok, why = M.setAddon(tostring(data.id or ""), data.on and true or false)
		if not ok then return err(player, why) end
		p.send("manage.state", M.state(), player)
	end)
	p.receive("manage.restart", function(player)
		if not M.can(player) then return err(player, "only the hotel's owner and admins can restart it") end
		p.send("manage.restarting", {})
		if p.restartHotel then p.restartHotel() end
	end)
end
