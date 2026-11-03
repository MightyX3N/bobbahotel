-- Talking in rooms (server): what someone says goes to everyone in the room, a shout too, a
-- whisper only to the one it's for (and back to who whispered). Like Habbo (Arcturus): at most
-- 100 characters, and too many messages in a row is flooding.
--
-- Messages from players: room.chat { text, kind = "talk" | "shout" | "whisper", to = name, style }
-- Messages to players:   room.chat { unit, text, kind, style }

BOBBA.chat = BOBBA.chat or {}
local chat = BOBBA.chat

chat.MAX_LENGTH = 100
-- flood control: more than FLOOD_COUNT messages within FLOOD_SECONDS and you wait FLOOD_WAIT
chat.FLOOD_COUNT = 4
chat.FLOOD_SECONDS = 3
chat.FLOOD_WAIT = 10

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
		if o.player then list[#list + 1] = o.player end
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
	if u.floodUntil and now < u.floodUntil then return false, "flood" end
	u.chatTimes = u.chatTimes or {}
	local recent = {}
	for _, t in ipairs(u.chatTimes) do if now - t < chat.FLOOD_SECONDS then recent[#recent + 1] = t end end
	recent[#recent + 1] = now
	u.chatTimes = recent
	if #recent > chat.FLOOD_COUNT then
		u.floodUntil = now + chat.FLOOD_WAIT
		u.chatTimes = {}
		if u.player then P.send("room.chat.flood", { seconds = chat.FLOOD_WAIT }, u.player) end
		return false, "flood"
	end
	local list, why = recipients(u.room, u, kind, toName)
	if not list then return false, why end
	local allowed = BOBBA.events.emit("roomChat", u.room, u, text, kind)
	if allowed == false then return false, "not allowed" end
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
