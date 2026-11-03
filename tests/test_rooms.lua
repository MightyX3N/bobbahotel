local T = {}

local function door(room)
	-- Nitro's door: x + 0.5 for a door in the left wall (dir 90), y + 0.5 in the right wall (dir 180)
	return math.floor(room.door.x), math.floor(room.door.y)
end

-- Guest rooms have their door as a gap in the wall, which Nitro finds from the heightmap; it has to
-- be the tile players come in on. (Public rooms come in elsewhere, as in Habbo.)
T["every Habbo layout builds, and guest rooms' doors are where Nitro draws them"] = function()
	local layouts = BOBBA.registry.list("layout")
	eq(#layouts, 59, "layouts")
	local wrong = {}
	for _, l in ipairs(layouts) do
		local room = assert(BOBBA.rooms.geometry(l.id))
		assert(#room.planes > 0, l.id .. " has planes")
		local v = BOBBA.rooms.view(room, 64)
		assert(#v > 0, l.id .. " has planes on screen")
		local x, y = door(room)
		local guest = l.id:match("^model_[a-z0-9]$") ~= nil
		if guest and (x ~= l.door.x or y ~= l.door.y) then wrong[#wrong + 1] = string.format("%s nitro %d,%d layout %d,%d", l.id, x, y, l.door.x, l.door.y) end
	end
	if #wrong > 0 then error("doors differ: " .. table.concat(wrong, "; ")) end
	local x, y = door(BOBBA.rooms.geometry("model_a"))
	eq(x .. "," .. y, "3,5", "model_a's door")
end

T["the mouse on a tile's middle picks that tile"] = function()
	local room = BOBBA.rooms.geometry("model_a")
	local cam = BOBBA.nitro.create(64)
	local view = BOBBA.rooms.view(room, 64)
	for _, t in ipairs({ { 3, 5 }, { 5, 5 }, { 10, 10 }, { 4, 12 } }) do
		local h = BOBBA.rooms.tileHeight(room, t[1], t[2])
		assert(h, "tile exists")
		local s = cam.screen(t[1], t[2], h)
		local hit = BOBBA.rooms.pick(room, view, 64, s[1], s[2])
		assert(hit, "something under the mouse at " .. t[1] .. "," .. t[2])
		eq(hit.floor, true, "floor")
		eq(hit.tileX, t[1], "x")
		eq(hit.tileY, t[2], "y")
	end
	eq(BOBBA.rooms.pick(room, view, 64, 5000, 5000), nil, "nothing far away")
end

T["raised tiles and stairs: picks the height"] = function()
	local room = BOBBA.rooms.geometry("model_4") -- 0 at the front, 9 at the back
	local cam = BOBBA.nitro.create(64)
	local view = BOBBA.rooms.view(room, 64)
	local s = cam.screen(18, 5, 9)
	local hit = BOBBA.rooms.pick(room, view, 64, s[1], s[2])
	eq(hit.tileX .. "," .. hit.tileY .. "," .. hit.tileZ, "18,5,9")
end

T["layouts: checked when registered"] = function()
	local ok = BOBBA.registry.register("layout", "t_bad_chars", { heightmap = "xx\rx#", door = { x = 0, y = 0 } })
	eq(ok, false, "bad characters")
	eq(BOBBA.registry.register("layout", "t_empty", { heightmap = "xxx\rxxx", door = { x = 0, y = 0 } }), false, "no tiles")
	eq(BOBBA.registry.register("layout", "t_door", { heightmap = "x0", door = {} }), false, "door without x, y")
	eq(BOBBA.registry.register("layout", "t_ok", { heightmap = "xxxx\nx00x\n000x\nxxxx", door = { x = 0, y = 2 } }), true)
	local l = BOBBA.registry.get("layout", "t_ok")
	eq(l.heightmap, "xxxx\rx00x\r000x\rxxxx", "new lines become \\r")
	eq(l.door.dir, 2, "default direction")
	local room = BOBBA.rooms.geometry("t_ok")
	local x, y = door(room)
	eq(x .. "," .. y, "0,2", "door")
end

T["a layout an addon changes gets new geometry"] = function()
	BOBBA.registry.register("layout", "t_change", { heightmap = "xxx\rx0x\r00x\rxxx", door = { x = 0, y = 2 } })
	local a = BOBBA.rooms.geometry("t_change")
	BOBBA.registry.register("layout", "t_change", { heightmap = "xxxx\rx00x\r000x\rxxxx", door = { x = 0, y = 2 } })
	local b = BOBBA.rooms.geometry("t_change")
	eq(a == b, false, "not the old cached one")
	eq(#b.tiles[2], 4, "new width")
end

T["plane colours: style colour times Nitro's shade"] = function()
	local floor = BOBBA.registry.get("plane_style", "default_floor")
	local r, g, b = BOBBA.rooms.planeColor(floor, 0xFFFFFF)
	eq(r .. "," .. g .. "," .. b, "161,99,55", "top")
	r, g, b = BOBBA.rooms.planeColor(floor, 0xBBBBBB)
	eq(r .. "," .. g .. "," .. b, "118,72,40", "right edge")
	eq(BOBBA.registry.register("plane_style", "t_bad", { kind = "roof", color = { r = 1, g = 1, b = 1 } }), false, "bad kind")
	eq(BOBBA.registry.register("plane_style", "t_bad2", { kind = "wall", color = { r = 300, g = 1, b = 1 } }), false, "bad colour")
end

return T
