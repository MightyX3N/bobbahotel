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

T["flooding: too many in a row and you have to wait"] = function()
	local mia, bo = start()
	for i = 1, 6 do P.fromPlayer(mia, "room.chat", { text = "spam " .. i }) end
	eq(#P.inbox(bo, "room.chat"), 4, "four get through")
	assert(last(mia, "room.chat.flood"), "told to wait")
	P.now = P.now + 5
	P.fromPlayer(mia, "room.chat", { text = "still waiting" })
	eq(#P.inbox(bo, "room.chat"), 4)
	P.now = P.now + 10
	P.fromPlayer(mia, "room.chat", { text = "back" })
	eq(last(bo, "room.chat").text, "back")
end

return T
