local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	local mia, bo, cy = { key = "1", name = "Mia" }, { key = "2", name = "Bo" }, { key = "3", name = "Cy" }
	for _, p in ipairs({ mia, bo, cy }) do P.fromPlayer(p, "room.ready") end
	return mia, bo, cy
end

local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end

T["talking: everyone in the room hears it, with who said it"] = function()
	local mia, bo, cy = start()
	P.fromPlayer(mia, "room.chat", { text = "  hello there  " })
	local m = last(bo, "room.chat")
	eq(m.text, "hello there", "trimmed")
	eq(m.kind, "talk")
	eq(m.unit, BOBBA.live.byPlayer[mia].id)
	assert(last(cy, "room.chat") and last(mia, "room.chat"), "Cy and Mia herself too")
end

T["shouting and whispering: a whisper only reaches the two of them"] = function()
	local mia, bo, cy = start()
	P.fromPlayer(mia, "room.chat", { text = "HEY", kind = "shout" })
	eq(last(cy, "room.chat").kind, "shout")
	P.now = P.now + 5
	local before = #P.inbox(cy, "room.chat")
	P.fromPlayer(mia, "room.chat", { text = "psst", kind = "whisper", to = "bo" })
	eq(last(bo, "room.chat").text, "psst", "Bo (any case)")
	eq(last(mia, "room.chat").kind, "whisper", "Mia sees her own whisper")
	eq(#P.inbox(cy, "room.chat"), before, "Cy doesn't")
	P.fromPlayer(mia, "room.chat", { text = "hi", kind = "whisper", to = "nobody" })
	assert(last(mia, "room.error"), "to someone not there: an error")
end

T["at most 100 characters, control characters out, nothing empty"] = function()
	local mia, bo = start()
	P.fromPlayer(mia, "room.chat", { text = string.rep("a", 150) })
	eq(#last(bo, "room.chat").text, 100)
	P.now = P.now + 5
	P.fromPlayer(mia, "room.chat", { text = "a\nb\tc" })
	eq(last(bo, "room.chat").text, "a b c")
	P.now = P.now + 5
	local n = #P.inbox(bo, "room.chat")
	P.fromPlayer(mia, "room.chat", { text = "   " })
	eq(#P.inbox(bo, "room.chat"), n, "nothing sent")
	eq(BOBBA.chat.clean(string.rep("æ", 120)), string.rep("æ", 100), "whole characters")
end

T["flooding (Arcturus): a count of messages that drops by one a second; past the room's limit, muted longer each time"] = function()
	local mia, bo = start()
	-- (the room's chat protection is loose by default: more than 5)
	for i = 1, 6 do P.fromPlayer(mia, "room.chat", { text = "spam " .. i }) end
	eq(#P.inbox(bo, "room.chat"), 5, "five get through")
	eq(last(mia, "room.chat.flood").seconds, 60, "the first time: a minute")
	P.now = P.now + 30
	P.fromPlayer(mia, "room.chat", { text = "still waiting" })
	eq(#P.inbox(bo, "room.chat"), 5)
	P.now = P.now + 31
	P.fromPlayer(mia, "room.chat", { text = "back" })
	eq(last(bo, "room.chat").text, "back")
	-- one a second is never flooding
	for i = 1, 10 do P.now = P.now + 1 P.fromPlayer(mia, "room.chat", { text = "calm " .. i }) end
	eq(last(bo, "room.chat").text, "calm 10")
	-- strict: more than 3; the second time 150 s
	BOBBA.store.query("UPDATE bobbahotel_rooms SET chat_protection = 0")
	BOBBA.live.byPlayer[mia].room.info.chat_protection = 0
	P.now = P.now + 10
	for i = 1, 4 do P.fromPlayer(mia, "room.chat", { text = "fast " .. i }) end
	eq(last(bo, "room.chat").text, "fast 3", "strict: three")
	eq(last(mia, "room.chat.flood").seconds, 150, "the second time")
end

T["hearing distance: talk reaches those near enough; shouts, yourself and those with rights always"] = function()
	local mia, bo, cy = start()
	local r = BOBBA.live.byPlayer[mia].room
	r.info.chat_distance = 2
	local function put(p, x, y)
		local u = BOBBA.live.byPlayer[p]
		BOBBA.pathfinder.removeUnit(r.grid, u.x, u.y)
		u.x, u.y = x, y
		BOBBA.pathfinder.addUnit(r.grid, x, y)
	end
	put(mia, 5, 5) put(bo, 6, 6) put(cy, 9, 9)
	P.fromPlayer(mia, "room.chat", { text = "near" })
	eq(last(bo, "room.chat").text, "near", "Bo, a tile and a half away")
	eq(last(cy, "room.chat"), nil, "Cy, too far")
	eq(last(mia, "room.chat").text, "near", "Mia herself")
	P.now = P.now + 5
	P.fromPlayer(mia, "room.chat", { text = "LOUD", kind = "shout" })
	eq(last(cy, "room.chat").text, "LOUD", "a shout reaches everyone")
end

return T
