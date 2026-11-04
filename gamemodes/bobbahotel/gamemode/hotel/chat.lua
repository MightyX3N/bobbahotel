-- Talking in rooms (server): what someone says goes to everyone in the room, a shout too, a
-- whisper only to the one it's for (and back to who whispered). Like Habbo (Arcturus): at most
-- 100 characters, and too many messages in a row is flooding.
--
-- Messages from players: room.chat { text, kind = "talk" | "shout" | "whisper", to = name, style }
-- Messages to players:   room.chat { unit, text, kind, style }

BOBBA.chat = BOBBA.chat or {}
local chat = BOBBA.chat

chat.MAX_LENGTH = 100
-- flood control (Arcturus Room.talk): each message adds 1 to a count that goes down by 1 a second;
-- past the room's limit (its chat protection: 0 strict 3, 1 normal 4, 2 loose 5) you're muted for
-- FLOOD_BASE + FLOOD_BASE x mutes so far squared (60 s, then 150, 300, ...). Those with rights in the
-- room aren't (Arcturus's flood.with.rights off). The count and the mutes are the player's, in every room.
chat.FLOOD_LIMITS = { [0] = 3, [1] = 4, [2] = 5 }
chat.FLOOD_BASE = 30
chat.flood = chat.flood or {}
BOBBA.perms.define("bobba.staff.noflood", { default = "admin", description = "Never muted for flooding the chat" })

local KINDS = { talk = true, shout = true, whisper = true }

-- cleans what someone typed: no control characters, no leading or trailing spaces, cut to 100
-- characters (whole UTF-8 characters)
function chat.clean(text)
	text = tostring(text or ""):gsub("[%c]", " ")
	text = text:match("^%s*(.-)%s*$")
	if #text > chat.MAX_LENGTH * 4 then text = text:sub(1, chat.MAX_LENGTH * 4) end
	local out, n = {}, 0
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		n = n + 1
		if n > chat.MAX_LENGTH then break end
		out[#out + 1] = ch
	end
	return table.concat(out)
end

-- (Arcturus: within the room's hearing distance, in tiles, of whoever talks; yourself, and those with
-- rights, always hear it; a shout reaches everyone)
local function hears(r, u, o)
	if o == u then return true end
	if o.player and BOBBA.access and BOBBA.access.hasRights(o.player, r.info) then return true end
	local d = math.abs(tonumber(r.info.chat_distance) or 50)
	local ax, ay = u.px or u.x, u.py or u.y
	local bx, by = o.px or o.x, o.py or o.y
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) <= d
end

local function recipients(r, u, kind, toName)
	local list = {}
	if kind == "whisper" then
		local target
		for _, uid in ipairs(r.order) do
			local o = r.units[uid]
			if o.name and toName and o.name:lower() == toName:lower() then target = o break end
		end
		if not target or target == u then return nil, "nobody called " .. tostring(toName) .. " is in the room" end
		if u.player then list[#list + 1] = u.player end
		if target.player then list[#list + 1] = target.player end
		return list
	end
	for _, uid in ipairs(r.order) do
		local o = r.units[uid]
		if o.player and (kind == "shout" or hears(r, u, o)) then list[#list + 1] = o.player end
	end
	return list
end

-- Someone in a room says something. Returns true, or false and why.
function chat.say(u, text, kind, toName, style)
	if not u or not u.room then return false, "not in a room" end
	kind = KINDS[kind] and kind or "talk"
	text = chat.clean(text)
	if text == "" then return false, "nothing to say" end
	local P = BOBBA.platform
	local now = P.clock()
	local f = chat.flood[u.key or u] or { count = 0, at = now, mutes = 0, untilT = 0 }
	chat.flood[u.key or u] = f
	if now < f.untilT then
		if u.player then P.send("room.chat.flood", { seconds = math.ceil(f.untilT - now) }, u.player) end
		return false, "flood"
	end
	local exempt = u.player and (BOBBA.perms.has(u.player, "bobba.staff.noflood") or (BOBBA.access and BOBBA.access.hasRights(u.player, u.room.info)))
	if not exempt then
		-- (down by one a second)
		local gone = math.floor(now - f.at)
		if gone > 0 then f.count = math.max(0, f.count - gone) f.at = f.at + gone end
		f.count = f.count + 1
		local limit = chat.FLOOD_LIMITS[math.floor(tonumber(u.room.info.chat_protection) or 2)] or 5
		if f.count > limit then
			f.mutes = f.mutes + 1
			local seconds = chat.FLOOD_BASE + chat.FLOOD_BASE * f.mutes * f.mutes
			f.untilT, f.count = now + seconds, 0
			if u.player then P.send("room.chat.flood", { seconds = seconds }, u.player) end
			return false, "flood"
		end
	end
	local list, why = recipients(u.room, u, kind, toName)
	if not list then return false, why end
	local allowed = BOBBA.events.emit("roomChat", u.room, u, text, kind)
	if allowed == false then return false, "not allowed" end
	-- (taken by something else, e.g. a wired keyword: nothing more to do)
	if allowed == "handled" then return true end
	style = math.floor(tonumber(style) or 0)
	if style < 0 or style > 1000 then style = 0 end
	if #list > 0 then P.send("room.chat", { unit = u.id, text = text, kind = kind, style = style }, list) end
	return true
end

function chat.start()
	local P = BOBBA.platform
	P.receive("room.chat", function(player, data)
		local u = BOBBA.live.byPlayer[player]
		if not u then return end
		local ok, why = chat.say(u, data.text, data.kind, data.to, data.style)
		if not ok and why ~= "flood" and why ~= "nothing to say" then P.send("room.error", { message = why }, player) end
	end)
end
