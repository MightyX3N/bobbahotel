-- Everyone's money and Habbo Club (server), as Habbo has them: credits, duckets (Habbo's activity
-- points type 0) and diamonds (type 5). Never bought with real money: players start with some, are
-- paid for being online (Arcturus's CreditsScheduler / PixelScheduler / PointsScheduler), and staff
-- can give it. Habbo Club is bought with diamonds in the catalogue (catalog.lua) and lasts days.
--
-- What the numbers are is the hotel's settings (BOBBA.store.setting), changed with bobba_wallet_setting:
--   wallet.start.credits / .duckets / .diamonds      what a new player has
--   wallet.pay.every                                 seconds online between pays
--   wallet.pay.credits / .duckets / .diamonds        each pay
--
-- Messages to players: user.purse { credits, duckets, diamonds, clubDays, clubMinutes, clubLevel }
-- Messages from players: user.purse.get {}

BOBBA.wallet = BOBBA.wallet or { online = {} }
local W = BOBBA.wallet

W.CURRENCIES = { credits = true, duckets = true, diamonds = true }
W.DEFAULTS = {
	["wallet.start.credits"] = 5000, ["wallet.start.duckets"] = 0, ["wallet.start.diamonds"] = 0,
	["wallet.pay.every"] = 900, ["wallet.pay.credits"] = 25, ["wallet.pay.duckets"] = 50, ["wallet.pay.diamonds"] = 2,
}

BOBBA.perms.define("bobba.staff.currency", { default = "admin", description = "Give players credits, duckets, diamonds and Habbo Club" })

function W.setting(name)
	return tonumber(BOBBA.store.setting(name, tostring(W.DEFAULTS[name] or 0))) or W.DEFAULTS[name] or 0
end

function W.migrate()
	BOBBA.store.migrate("core.007_wallets", {
		[[CREATE TABLE bobbahotel_wallets (
			key TEXT PRIMARY KEY,
			credits INTEGER NOT NULL DEFAULT 0,
			duckets INTEGER NOT NULL DEFAULT 0,
			diamonds INTEGER NOT NULL DEFAULT 0,
			club_until INTEGER NOT NULL DEFAULT 0
		)]],
	})
end

-- a player's wallet (made with the start amounts the first time)
function W.get(key)
	key = tostring(key)
	local row = BOBBA.store.row("SELECT * FROM bobbahotel_wallets WHERE key = ?", { key })
	if not row then
		BOBBA.store.query("INSERT INTO bobbahotel_wallets (key, credits, duckets, diamonds, club_until) VALUES (?, ?, ?, ?, 0)",
			{ key, W.setting("wallet.start.credits"), W.setting("wallet.start.duckets"), W.setting("wallet.start.diamonds") })
		row = BOBBA.store.row("SELECT * FROM bobbahotel_wallets WHERE key = ?", { key })
	end
	return {
		key = key, credits = tonumber(row.credits) or 0, duckets = tonumber(row.duckets) or 0,
		diamonds = tonumber(row.diamonds) or 0, clubUntil = tonumber(row.club_until) or 0,
	}
end

-- Habbo Club: 1 while it lasts (HabboClubLevelEnum.CLUB), else 0
function W.clubLevel(key)
	return (W.get(key).clubUntil > BOBBA.platform.time()) and 1 or 0
end

local function playerFor(key)
	for player, k in pairs(W.online) do if k == key then return player end end
end

-- the purse as Nitro shows it (PurseView: credits, activity points, days of club left)
function W.purse(key)
	local w = W.get(key)
	local left = math.max(0, w.clubUntil - BOBBA.platform.time())
	return { credits = w.credits, duckets = w.duckets, diamonds = w.diamonds,
		clubDays = math.floor(left / 86400), clubMinutes = math.floor(left / 60), clubLevel = left > 0 and 1 or 0 }
end

function W.send(key)
	local player = playerFor(key)
	if player then BOBBA.platform.send("user.purse", W.purse(key), player) end
end

-- adds (or with a minus, takes) an amount; false when there isn't enough
function W.add(key, currency, amount)
	if not W.CURRENCIES[currency] then return false end
	amount = math.floor(tonumber(amount) or 0)
	local w = W.get(key)
	if w[currency] + amount < 0 then return false end
	BOBBA.store.query("UPDATE bobbahotel_wallets SET " .. currency .. " = " .. currency .. " + ? WHERE key = ?", { amount, tostring(key) })
	W.send(key)
	BOBBA.events.emit("walletChanged", key, currency, amount)
	return true
end

-- pays a price { credits = n, duckets = n, diamonds = n } (all of it or none)
function W.pay(key, price)
	local w = W.get(key)
	for c, n in pairs(price) do
		if not W.CURRENCIES[c] or (w[c] or 0) < n then return false end
	end
	for c, n in pairs(price) do
		if n ~= 0 then BOBBA.store.query("UPDATE bobbahotel_wallets SET " .. c .. " = " .. c .. " - ? WHERE key = ?", { n, tostring(key) }) end
	end
	W.send(key)
	return true
end

-- more days of Habbo Club (from now, or from when it ends if it still runs)
function W.addClub(key, days)
	local w = W.get(key)
	local now = BOBBA.platform.time()
	local untilT = math.max(w.clubUntil, now) + math.floor(days * 86400)
	BOBBA.store.query("UPDATE bobbahotel_wallets SET club_until = ? WHERE key = ?", { untilT, tostring(key) })
	W.send(key)
	BOBBA.events.emit("clubChanged", key)
end

-- everyone online gets paid now and then
function W.payOnline()
	for _, key in pairs(W.online) do
		for _, c in ipairs({ "credits", "duckets", "diamonds" }) do
			local n = W.setting("wallet.pay." .. c)
			if n > 0 then BOBBA.store.query("UPDATE bobbahotel_wallets SET " .. c .. " = " .. c .. " + ? WHERE key = ?", { n, key }) end
		end
		W.send(key)
	end
end

function W.start()
	W.migrate()
	local P = BOBBA.platform
	P.receive("user.purse.get", function(player)
		local key = P.playerKey(player)
		W.online[player] = key
		P.send("user.purse", W.purse(key), player)
	end)
	P.onLeave(function(player) W.online[player] = nil end)
	BOBBA.events.on("roomEntered", "bobba.wallet", function(_, u)
		if u.player and not W.online[u.player] then
			W.online[u.player] = u.key
			P.send("user.purse", W.purse(u.key), u.player)
		end
	end)
	local last = P.clock and P.clock() or 0
	P.every("wallet.pay", 30, function()
		local now = P.clock and P.clock() or 0
		if now - last >= W.setting("wallet.pay.every") then
			last = now
			W.payOnline()
		end
	end)
end
