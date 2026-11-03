-- How everyone looks (server): their figure (Habbo's figure string, "hd-180-1.ch-210-66...") and
-- gender ("M" or "F"), kept per player. A player changes it with the avatar editor; everyone in
-- the room sees the new look at once (Habbo's UserFigureComposer -> figure update).
--
-- The core doesn't know which clothes exist: an addon checks a look (BOBBA.looks.validator, e.g.
-- bobba_habbo with Habbo's figuredata, the way Arcturus' ClothingValidationManager does: clothes
-- that can't be worn are swapped for ones that can); without one only the format is checked. Without a saved look a player has none (nil), and the addon draws its default.
--
--   BOBBA.looks.get(key) -> figure, gender (nil when none saved)
--   BOBBA.looks.set(key, figure, gender) -> true, or false and why
--   BOBBA.looks.validator = function(figure, gender) return cleanedFigure end   -- or nil, why
--   message from players: user.figure { figure, gender }

BOBBA.looks = BOBBA.looks or {}
local looks = BOBBA.looks

looks.MAX_LENGTH = 512

function looks.migrate()
	BOBBA.store.migrate("core.005_looks", {
		[[CREATE TABLE bobbahotel_looks (
			key TEXT PRIMARY KEY,
			figure TEXT NOT NULL,
			gender TEXT NOT NULL
		)]],
	})
end

-- "M" or "F" (Nitro's AvatarEditorUtilities.getGender: anything else is male)
function looks.gender(g)
	g = tostring(g or "")
	if g == "F" or g == "f" then return "F" end
	return "M"
end

-- a figure string's parts: { { type = "hd", id = 180, colors = { 1 } }, ... }, or nil when it isn't one
function looks.parse(figure)
	if type(figure) ~= "string" or figure == "" or #figure > looks.MAX_LENGTH then return nil end
	local out, seen = {}, {}
	for part in (figure .. "."):gmatch("([^%.]*)%.") do
		local t, rest = part:match("^(%l%l)%-(.+)$")
		if not t then return nil end
		local nums = {}
		for n in (rest .. "-"):gmatch("([^%-]*)%-") do
			if not n:match("^%d+$") then return nil end
			nums[#nums + 1] = tonumber(n)
		end
		if seen[t] then return nil end
		seen[t] = true
		local colors = {}
		for i = 2, #nums do colors[#colors + 1] = nums[i] end
		out[#out + 1] = { type = t, id = nums[1], colors = colors }
	end
	return out
end

-- back into a string
function looks.format(parts)
	local out = {}
	for _, p in ipairs(parts) do
		local s = p.type .. "-" .. p.id
		for _, c in ipairs(p.colors or {}) do s = s .. "-" .. c end
		out[#out + 1] = s
	end
	return table.concat(out, ".")
end

function looks.get(key)
	local row = BOBBA.store.row("SELECT figure, gender FROM bobbahotel_looks WHERE key = ?", { tostring(key) })
	if not row then return nil end
	return row.figure, row.gender
end

function looks.set(key, figure, gender)
	gender = looks.gender(gender)
	local parts = looks.parse(figure)
	if not parts then return false, "not a figure" end
	figure = looks.format(parts)
	if looks.validator then
		local cleaned, why = looks.validator(figure, gender, key)
		if not cleaned then return false, why or "not a look you can have" end
		parts = looks.parse(cleaned)
		if not parts then return false, "not a look you can have" end
		figure = looks.format(parts)
	end
	BOBBA.store.query("INSERT OR REPLACE INTO bobbahotel_looks (key, figure, gender) VALUES (?, ?, ?)", { tostring(key), figure, gender })
	BOBBA.events.emit("lookChanged", key, figure, gender)
	return true
end

function looks.start()
	looks.migrate()
	local P = BOBBA.platform
	P.receive("user.figure", function(player, data)
		local key = P.playerKey(player)
		local ok, why = looks.set(key, data and data.figure, data and data.gender)
		if not ok then P.send("room.error", { message = why }, player) return end
		-- everyone in the room sees it (the player's unit there, if any)
		local u = BOBBA.live.byPlayer[player]
		if u then BOBBA.live.setFigure(u, looks.get(key)) end
	end)
end
