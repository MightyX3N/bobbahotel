-- hotel/looks.lua: saving a look, checking it, everyone in the room seeing it
local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.looks.validator = nil
	BOBBA.live.start()
	local mia, bo = { key = "1", name = "Mia" }, { key = "2", name = "Bo" }
	for _, p in ipairs({ mia, bo }) do P.fromPlayer(p, "room.ready") end
	return mia, bo
end

local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end

T["figure strings: read and written back the same, nonsense refused"] = function()
	local L = BOBBA.looks
	local parts = L.parse("hd-180-1.ch-210-66.lg-716-66-62.wa-2007")
	eq(#parts, 4)
	eq(parts[3].type, "lg") eq(parts[3].id, 716) eq(parts[3].colors[2], 62)
	eq(#parts[4].colors, 0, "a part without colours")
	eq(L.format(parts), "hd-180-1.ch-210-66.lg-716-66-62.wa-2007")
	for _, bad in ipairs({ "", "hd", "hd-x-1", "HD-180-1", "hd-180-1..ch-210", "hd-180-1.hd-185-1", "hd-180-1;DROP", string.rep("hd-180-1.", 100) }) do
		eq(L.parse(bad), nil, "refused: " .. bad:sub(1, 20))
	end
	eq(L.gender("f"), "F") eq(L.gender("x"), "M")
end

T["a new look: saved, and everyone in the room sees it"] = function()
	local mia, bo = start()
	eq(BOBBA.looks.get("1"), nil, "nothing saved yet")
	local u = BOBBA.live.byPlayer[mia]
	eq(u.figure, nil)
	P.fromPlayer(mia, "user.figure", { figure = "hd-600-1.ch-635-70.lg-716-66-62", gender = "F" })
	local f, g = BOBBA.looks.get("1")
	eq(f, "hd-600-1.ch-635-70.lg-716-66-62") eq(g, "F")
	local seen = last(bo, "room.units")
	eq(seen[1].id, u.id) eq(seen[1].figure, f) eq(seen[1].gender, "F")
	assert(last(mia, "room.units"), "Mia sees it too")
end

T["the look comes along into the next room and the next visit"] = function()
	local mia = start()
	P.fromPlayer(mia, "user.figure", { figure = "hd-180-1.ch-210-66", gender = "M" })
	BOBBA.live.leave(mia)
	BOBBA.live.enter(mia, BOBBA.live.homeRoom())
	local load = last(mia, "room.load")
	local me
	for _, s in ipairs(load.units) do if s.id == load.you then me = s end end
	eq(me.figure, "hd-180-1.ch-210-66", "in room.load")
end

T["the addon's check: what it refuses isn't saved, what it cleans is saved clean"] = function()
	local mia = start()
	BOBBA.looks.validator = function(figure, gender)
		if figure:find("xx%-") then return nil, "no such clothes" end
		return (figure:gsub("%.?ha%-%d+[%-%d]*", ""))   -- (cleans: no hats)
	end
	P.fromPlayer(mia, "user.figure", { figure = "hd-180-1.xx-1", gender = "M" })
	eq(BOBBA.looks.get("1"), nil)
	eq(last(mia, "room.error").message, "no such clothes")
	P.fromPlayer(mia, "user.figure", { figure = "hd-180-1.ha-1002-70.ch-210-66", gender = "M" })
	eq(BOBBA.looks.get("1"), "hd-180-1.ch-210-66", "saved the way the check cleaned it")
	P.fromPlayer(mia, "user.figure", { figure = "garbage" })
	eq(last(mia, "room.error").message, "not a figure")
	BOBBA.looks.validator = nil
end

return T
