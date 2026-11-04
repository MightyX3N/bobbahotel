-- The floor plan editor (hotel/floorplan.lua): who may, the checks, saving and coming in again
local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	BOBBA.items.define("table", { width = 2, length = 2, height = 1, directions = { 0, 2 } })
	local mia, bo = { key = "765611980001", name = "Mia" }, { key = "765611980002", name = "Bo" }
	local id = BOBBA.live.create(mia.key, mia.name, "model_a", "Mia's room")
	BOBBA.wallet.addClub(mia.key, 31)
	return mia, bo, id
end

local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end

-- model_a with one row less at the back and the door's tile raised to 1
local function plan(r)
	local rows = BOBBA.util.split(r.layout.heightmap, "\r")
	return rows
end

T["the owner with club gets the plan; others and no club are told why"] = function()
	local mia, bo, id = start()
	BOBBA.live.enter(mia, id)
	P.fromPlayer(mia, "floorplan.get", {})
	local d = last(mia, "floorplan.data")
	assert(d, "data")
	eq(d.heightmap, BOBBA.registry.get("layout", "model_a").heightmap)
	eq(d.door.x .. "," .. d.door.y .. "," .. d.door.dir, "3,5,2")
	eq(d.wallHeight .. " " .. d.wallThickness .. " " .. d.floorThickness .. " " .. d.maxSize, "-1 0 0 64")
	BOBBA.live.enter(bo, id)
	P.fromPlayer(bo, "floorplan.get", {})
	eq(last(bo, "floorplan.data"), nil)
	eq(last(bo, "floorplan.error").errors[1][1], "floor.plan.editor.no.rights")
	-- Bo in his own room, without club
	local boRoom = BOBBA.live.create(bo.key, bo.name, "model_a", "Bo's")
	BOBBA.live.enter(bo, boRoom)
	P.fromPlayer(bo, "floorplan.get", {})
	eq(last(bo, "floorplan.error").errors[1][1], "floor.plan.editor.club.only")
	-- the hotel can let everyone
	BOBBA.store.setSetting("floorplan.club", "0")
	P.fromPlayer(bo, "floorplan.get", {})
	assert(last(bo, "floorplan.data"), "everyone may")
end

T["saving: the room's own shape, door and walls; everyone comes in again at the new door"] = function()
	local mia, bo, id = start()
	BOBBA.live.enter(mia, id)
	BOBBA.live.enter(bo, id)
	local r = BOBBA.live.rooms[id]
	local rows = plan(r)
	-- a raised corner and a new door on the left of row 7
	rows[3] = rows[3]:sub(1, 4) .. "22" .. rows[3]:sub(7)
	rows[8] = "0" .. rows[8]:sub(2)
	P.fromPlayer(mia, "floorplan.save", { heightmap = table.concat(rows, "\r"), doorX = 0, doorY = 7, doorDir = 2, wallThickness = 1, floorThickness = -1, wallHeight = 3 })
	local fe = last(mia, "floorplan.error")
	eq(fe and fe.errors[1][1], nil)
	local info = BOBBA.live.info(id)
	eq(info.layout, "model_a", "made from model_a still")
	eq(info.heightmap, table.concat(rows, "\r"))
	eq(tonumber(info.wall_thickness) .. " " .. tonumber(info.floor_thickness) .. " " .. info.wall_height, "1 -1 3")
	local load = last(bo, "room.load")
	eq(load.heightmap, table.concat(rows, "\r"), "Bo got the new room")
	eq(load.door.x .. "," .. load.door.y, "0,7")
	eq(load.wallHeight, 3)
	local u = BOBBA.live.byPlayer[bo]
	eq(u.x .. "," .. u.y, "0,7", "at the new door")
	-- the raised tiles are 2 high to walk on
	local r2 = BOBBA.live.rooms[id]
	assert(r2 ~= r, "loaded again")
	eq(r2.grid.tiles[5 * 100000 + 2].z, 2)
end

T["the checks: rows, size, door, heights, thickness, wall height"] = function()
	local mia, _, id = start()
	BOBBA.live.enter(mia, id)
	local r = BOBBA.live.rooms[id]
	local FP = BOBBA.floorplan
	local function errs(data)
		local base = { heightmap = r.layout.heightmap, doorX = 3, doorY = 5, doorDir = 2, wallThickness = 0, floorThickness = 0, wallHeight = -1 }
		for k, v in pairs(data) do base[k] = v end
		local ok, e = FP.check(r, base)
		if ok then return "ok" end
		local keys = {}
		for _, x in ipairs(e) do keys[#keys + 1] = x[1]:match("([%w_]+)$") end
		return table.concat(keys, ",")
	end
	eq(errs({}), "ok")
	eq(errs({ heightmap = "x00\r00" }), "rows")
	eq(errs({ heightmap = "xxx\rxxx" }), "effective_height_is_0")
	eq(errs({ heightmap = "x0#" }), "title")
	eq(errs({ heightmap = string.rep(string.rep("0", 10) .. "\r", 65) }), "too_large_height")
	eq(errs({ heightmap = "0r" }), "too_high")
	eq(errs({ doorX = 1, doorY = 1 }), "entry_not_on_tile")
	eq(errs({ doorX = 99 }), "entry_tile_outside_map")
	eq(errs({ doorDir = 8, wallThickness = 2, floorThickness = -3, wallHeight = 17 }), "invalid_entry_tile_direction,invalid_wall_thickness,invalid_floor_thickness,invalid_walls_fixed_height")
	-- (upper case and X are fine; a new line at the end is dropped)
	local ok = FP.check(r, { heightmap = "X00\r0AA\r", doorX = 1, doorY = 0, doorDir = 4, wallThickness = 0, floorThickness = 0, wallHeight = 0.5 })
	eq(ok.heightmap, "x00\r0aa")
	eq(ok.wallHeight, 0.5)
end

T["furni: their tiles can't go or change height; elsewhere is fine"] = function()
	local mia, _, id = start()
	BOBBA.live.enter(mia, id)
	local r = BOBBA.live.rooms[id]
	local placed
	BOBBA.items.place(r, mia, "table", 5, 5, 0, function(it) placed = it end)
	assert(placed, "table placed")
	local rows = plan(r)
	local function set(x, y, c)
		local t = {}
		for i, v in ipairs(rows) do t[i] = v end
		t[y + 1] = t[y + 1]:sub(1, x) .. c .. t[y + 1]:sub(x + 2)
		return table.concat(t, "\r")
	end
	local FP = BOBBA.floorplan
	local base = { doorX = 3, doorY = 5, doorDir = 2, wallThickness = 0, floorThickness = 0, wallHeight = -1 }
	local function try(map)
		local d = { heightmap = map }
		for k, v in pairs(base) do d[k] = v end
		local ok, e = FP.check(r, d)
		return ok and "ok" or e[1][1]:match("([%w_]+)$")
	end
	eq(try(set(6, 6, "x")), "change_blocked_by_room_item", "removed under the table")
	eq(try(set(5, 5, "1")), "change_blocked_by_room_item", "raised under the table")
	eq(try(set(7, 7, "1")), "ok", "next to it")
	local d = FP.data(r)
	eq(table.concat(d.blocked, " "), "5,5 5,6 6,5 6,6")
end

return T
