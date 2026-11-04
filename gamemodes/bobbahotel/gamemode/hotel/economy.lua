-- The economy's log (server): every time money, club days or furni come or go - bought, given by
-- staff, sent as a gift, traded, a tutorial's reward - a line saying who, what, how much, why and
-- with whom, so staff can see where things came from (Arcturus keeps its logs_hc_payday,
-- catalog_items_limited, room_trade_log ... this is one table for all of them).
-- Being paid for being online isn't logged (it's the same for everyone, and would be most of it).
-- Lines older than economy.keep.days (90) go away.
--
-- what: credits / duckets / diamonds / hc / vip (days) / furni (amount: how many, item: the kind)
--
-- Messages from players (managers): manage.log { who, before }  -> manage.log { who, rows, more }
-- bobba_economy [player name or key] [n]: the last lines in the console

BOBBA.economy = BOBBA.economy or {}
local E = BOBBA.economy

E.PAGE = 50

local function S() return BOBBA.store end
local function P() return BOBBA.platform end

function E.migrate()
	S().migrate("core.026_economy", {
		[[CREATE TABLE bobbahotel_economy (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			at INTEGER NOT NULL,
			key TEXT NOT NULL,
			what TEXT NOT NULL,
			amount INTEGER NOT NULL,
			item TEXT NOT NULL DEFAULT '',
			why TEXT NOT NULL DEFAULT '',
			other TEXT NOT NULL DEFAULT ''
		)]],
		"CREATE INDEX bobbahotel_economy_key ON bobbahotel_economy (key, id)",
	})
end

-- one line: key got (or with a minus, lost) amount of what; why: "catalog", "trade", ...;
-- item: a furni's kind; other: whom it was with
function E.log(key, what, amount, why, item, other)
	amount = math.floor(tonumber(amount) or 0)
	if amount == 0 or not S().ready then return end
	if other and tostring(other) == tostring(key) then other = nil end
	local ok = pcall(S().query, "INSERT INTO bobbahotel_economy (at, key, what, amount, item, why, other) VALUES (?, ?, ?, ?, ?, ?, ?)",
		{ math.floor(P().time()), tostring(key), tostring(what), amount, tostring(item or ""), tostring(why or ""), tostring(other or "") })
	return ok
end

-- the lines, newest first: for one player (key) or everyone, before a line's id (the next page)
function E.list(key, before, n)
	n = math.min(200, math.max(1, math.floor(tonumber(n) or E.PAGE)))
	before = math.floor(tonumber(before) or 0)
	local where, args = {}, {}
	if key and key ~= "" then where[#where + 1] = "(e.key = ? OR e.other = ?)" args[#args + 1] = tostring(key) args[#args + 1] = tostring(key) end
	if before > 0 then where[#where + 1] = "e.id < ?" args[#args + 1] = before end
	local rows = S().query("SELECT e.*, u.name AS name, o.name AS other_name FROM bobbahotel_economy e LEFT JOIN bobbahotel_users u ON u.key = e.key LEFT JOIN bobbahotel_users o ON o.key = e.other"
		.. (#where > 0 and (" WHERE " .. table.concat(where, " AND ")) or "") .. " ORDER BY e.id DESC LIMIT " .. (n + 1), args)
	local out = {}
	for i = 1, math.min(n, #rows) do
		local r = rows[i]
		out[i] = { id = tonumber(r.id), at = tonumber(r.at), key = r.key, name = r.name or r.key, what = r.what, amount = tonumber(r.amount),
			item = r.item ~= "" and r.item or nil, why = r.why, other = r.other ~= "" and r.other or nil,
			otherName = r.other ~= "" and (r.other_name or r.other) or nil }
	end
	return out, #rows > n
end

-- someone by name (or their key)
function E.findKey(who)
	who = tostring(who or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if who == "" then return nil end
	if S().row("SELECT key FROM bobbahotel_users WHERE key = ?", { who }) then return who end
	local r = S().row("SELECT key FROM bobbahotel_users WHERE lower(name) = lower(?)", { who })
		or S().row("SELECT key FROM bobbahotel_users WHERE lower(name) LIKE ? ORDER BY seen DESC", { "%" .. who:lower():gsub("[%%_]", "") .. "%" })
	return r and r.key or nil
end

function E.prune()
	local days = tonumber(S().setting("economy.keep.days", "90")) or 90
	if days <= 0 then return end
	pcall(S().query, "DELETE FROM bobbahotel_economy WHERE at < ?", { math.floor(P().time() - days * 86400) })
end

-- a line the way the console shows it
function E.describe(r)
	local thing = r.what == "furni" and ((r.amount > 0 and "+" or "") .. r.amount .. " " .. tostring(r.item))
		or ((r.amount > 0 and "+" or "") .. r.amount .. " " .. r.what .. ((r.what == "hc" or r.what == "vip") and " days" or ""))
	return string.format("#%d %s  %s  %s  (%s%s)", r.id, os.date("%Y-%m-%d %H:%M", r.at), r.name, thing, r.why,
		r.otherName and (", with " .. r.otherName) or "")
end

function E.start()
	E.migrate()
	E.prune()
	local p = P()
	p.receive("manage.log", function(player, data)
		if not (BOBBA.manage and BOBBA.manage.can(player)) then return end
		local key = nil
		if data.who and tostring(data.who) ~= "" then
			key = E.findKey(data.who)
			if not key then p.send("manage.log", { who = tostring(data.who), rows = {}, more = false, missing = true }, player) return end
		end
		local rows, more = E.list(key, data.before)
		p.send("manage.log", { who = tostring(data.who or ""), rows = rows, more = more, before = tonumber(data.before) or 0 }, player)
	end)
end
