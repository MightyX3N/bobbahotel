-- Sounds (client), like Nitro's SoundManager: Habbo's few UI sounds (money coming in, messages,
-- respect, the camera) at the "UI" volume, and furni samples (sound blocks) at the "Furni" volume,
-- both from the settings window. The sounds themselves come from an addon (bobba_habbo: Habbo's).
--
--   BOBBA.sounds.find = function(name) return path end   a sound's file in garrysmod/data/bobbahotel/
--     (names: nitro-react's SoundNames, credits, duckets, messenger_message_received, ...)
--   BOBBA.sounds.play(name)                              plays one of those
--   BOBBA.sounds.playFile(path, kind, rate)              kind "ui" / "furni" / "trax"; rate 1 = as it is

BOBBA.sounds = BOBBA.sounds or {}
local S = BOBBA.sounds
local P = BOBBA.platform

local function volume(kind)
	local cv = GetConVar("bobba_setting_volume_" .. (kind or "ui"))
	return math.Clamp((cv and cv:GetFloat() or 100) / 100, 0, 1)
end

function S.playFile(path, kind, rate)
	if not path or not P.playSound then return end
	local v = volume(kind)
	if v <= 0 then return end
	P.playSound(path, v, rate)
end

function S.play(name)
	local path = S.find and S.find(name)
	if path then S.playFile(path, "ui") end
end

-- money in (usePurse: credits changed; duckets came) and a purchase (useCatalog: PURCHASE_SUCCESS),
-- the same sound once when both happen together
local last = {}
local lastCash = 0
local function cash()
	if SysTime() - lastCash < 1 then return end
	lastCash = SysTime()
	S.play("credits")
end
BOBBA.events.on("purseChanged", "bobba.sounds", function(p)
	local credits, duckets = p.credits or 0, (p.points and p.points[0]) or 0
	if last.credits ~= nil then
		if credits ~= last.credits then cash() end
		if duckets > last.duckets then S.play("duckets") end
	end
	last.credits, last.duckets = credits, duckets
end)
BOBBA.events.on("catalogBought", "bobba.sounds", function() cash() end)
