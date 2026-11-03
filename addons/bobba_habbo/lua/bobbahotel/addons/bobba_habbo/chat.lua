-- Habbo's chat bubbles (client): the room's chat (the gamemode's client/chat.lua) draws its bubbles
-- with Habbo's own pictures and measurements for each chat style (lib/chatstyles.lua). Until they're
-- here (or if Habbo can't be reached), the gamemode's plain bubbles are drawn.

local H = BOBBA.habbo
BOBBA.room = BOBBA.room or { units = {} }
local R = BOBBA.room

local styles, loading, failed
local skins = {}

local function nums(v)
	local out = {}
	for n in tostring(v or ""):gmatch("-?%d+") do out[#out + 1] = tonumber(n) end
	return out
end

local function load()
	if styles or loading or failed then return end
	loading = true
	H.chatStyles(function(st, err)
		loading = false
		if st then styles = st else failed = err print("[Bobba] Habbo's chat bubbles: " .. tostring(err)) end
	end)
end

local function skinFor(style)
	local st = styles[style] or styles[0]
	if not st or not st.base then return nil end
	local s = skins[st.id]
	if s then return s end
	local reg = st.reg
	local xy, wh = nums(reg["9sliceXY"]), nums(reg["9sliceWH"])
	local m = nums(reg.textFieldMargins)
	local face = nums(reg.faceXY)
	local color = nums(reg.colorXY)
	s = {
		base = st.base, color = st.color, pointer = st.pointer,
		slice = { xy[1] or 0, xy[2] or 0, wh[1] or 1, wh[2] or 1 },
		colorXY = { color[1] or 0, color[2] or 0 },
		faceXY = face[1] and { face[1], face[2] } or nil,
		pointerY = tonumber(reg.pointerY),
		margins = { m[1] or 28, m[2] or 4, m[3] or 12, m[4] or 7 },
		textColor = tonumber(reg.textColorRGB or "") or 0,
		-- the styles with no face (e.g. Habbo's system messages) show no name either
		anonymous = face[1] == nil and st.system,
	}
	skins[st.id] = s
	return s
end

R.chatSkin = function(style)
	if not styles then load() return nil end
	return skinFor(tonumber(style) or 0)
end

-- a few seconds after the game has loaded (so it never holds up the avatars and furni): ready by
-- the first chat. From the cache this is one small file; only a player who already had the avatar
-- data from before the bubbles existed downloads Habbo's client once more for them.
if BOBBA.platform.after then
	BOBBA.platform.after(5, load)
else
	load()
end
