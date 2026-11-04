-- Rooms: layouts (the shape of a room), and the room's planes worked out the way Nitro does it
-- (BOBBA.nitro, generated from Nitro's own code in tools/nitro-port).
--
--   BOBBA.registry.register("layout", "my_layout", { heightmap = "xxxx\rx00x\r000x\rxxxx", door = { x = 0, y = 2, dir = 2 } })
--   local room = BOBBA.rooms.geometry("model_a")         -- planes, tile heights, door (cached)
--   local planes = BOBBA.rooms.view(room, 64)            -- planes on screen, deepest first
--   local hit = BOBBA.rooms.pick(room, planes, 64, x, y)  -- tile/wall under a screen point

BOBBA.rooms = BOBBA.rooms or {}
local rooms = BOBBA.rooms

rooms.PLANE_FLOOR, rooms.PLANE_WALL, rooms.PLANE_LANDSCAPE = 1, 2, 3
rooms.MAX_SIZE = 128 -- rows and columns a layout may have

-- Layout heightmaps: one row per line, a character per tile: x = no tile, 0-9 then a-z = height
-- 0-35. Rows are separated by "\r" like Habbo's (a "\n" is turned into "\r").
local function normalise(heightmap)
	return (heightmap:gsub("\r\n", "\r"):gsub("\n", "\r"))
end

BOBBA.registry.defineType("layout", {
	fields = { heightmap = "string", door = "table", name = "string?", club = "boolean?", order = "number?" },
	validate = function(def)
		def.heightmap = normalise(def.heightmap)
		local rows = BOBBA.util.split(def.heightmap, "\r")
		if #rows == 0 then return false, "heightmap is empty" end
		if #rows > rooms.MAX_SIZE then return false, "more than " .. rooms.MAX_SIZE .. " rows" end
		local tiles = 0
		for _, row in ipairs(rows) do
			if #row > rooms.MAX_SIZE then return false, "a row is longer than " .. rooms.MAX_SIZE end
			if row:find("[^xX0-9a-zA-Z]") then return false, "heightmap may only have x, 0-9 and a-z" end
			local _, n = row:gsub("[^xX]", "")
			tiles = tiles + n
		end
		if tiles == 0 then return false, "no tiles" end
		local d = def.door
		if type(d.x) ~= "number" or type(d.y) ~= "number" then return false, "door needs x and y" end
		d.dir = d.dir or 2
		return true
	end,
})

-- height of one heightmap character (nil for no tile)
function rooms.charHeight(c)
	if c == "x" or c == "X" or c == "" then return nil end
	return tonumber(c, 36)
end

local cache = {}

-- The room's geometry for a layout, as Nitro builds it from the server's message. Cached per
-- layout and wall height. opts: wallHeight (-1 = automatic, Habbo's default), floorThickness,
-- wallThickness (multipliers, 1 = normal).
function rooms.geometry(layoutId, opts)
	local layout = BOBBA.registry.get("layout", layoutId)
	if not layout then return nil, "unknown layout " .. tostring(layoutId) end
	opts = opts or {}
	if not opts.door then
		local o = {}
		for k, v in pairs(opts) do o[k] = v end
		o.door = layout.door
		opts = o
	end
	local room = rooms.geometryFor(layout.heightmap, opts)
	room.layout = layoutId
	return room
end

-- The same for a heightmap as it is (what the server sends with a room).
function rooms.geometryFor(heightmap, opts)
	opts = opts or {}
	-- numbers only: Nitro's code compares with numbers (text "-1" would count as a fixed height)
	local wh, ft, wt = tonumber(opts.wallHeight) or -1, tonumber(opts.floorThickness) or 1, tonumber(opts.wallThickness) or 1
	-- the door tile, as Habbo's server tells Nitro (RoomEntryTile): without it Nitro guesses one from the
	-- heightmap, and in a public room (whose door isn't in a wall) it cut a door into some other wall
	local dx, dy = -1, -1
	if opts.door and tonumber(opts.door.x) and tonumber(opts.door.y) then dx, dy = tonumber(opts.door.x), tonumber(opts.door.y) end
	local key = wh .. "|" .. ft .. "|" .. wt .. "|" .. dx .. "," .. dy .. "|" .. heightmap
	if not cache[key] then
		local room = BOBBA.nitro.build(heightmap, wh, true, dx, dy, ft, wt)
		room.views = {}
		cache[key] = room
	end
	return cache[key]
end

function rooms.clearCache()
	cache = {}
end

-- The planes on screen at a scale (64 = zoomed in, 32 = zoomed out), deepest first. Corners are
-- in pixels from the room's origin on screen.
function rooms.view(room, scale)
	local v = room.views[scale]
	if not v then
		v = BOBBA.nitro.planes(room, scale)
		room.views[scale] = v
	end
	return v
end

-- What is at screen point (x, y) (pixels from the room's origin): nil, or a table with floor
-- (true/false), tileX, tileY, tileZ, plane, and for walls wallX, wallY, direction.
function rooms.pick(room, view, scale, x, y)
	return BOBBA.nitro.pick(room, view, scale, x, y)
end

-- Height of a tile in the layout (nil = no tile). x and y start at 0, like Habbo's.
function rooms.tileHeight(room, x, y)
	local row = room.tiles[y + 1]
	local h = row and row[x + 1]
	if h == nil or h < 0 then return nil end
	return h
end

-- How floors, walls and the outside (landscape) look. Addons register more (with a texture later);
-- the core's defaults are Habbo's plain room: measured from a Habbo screenshot, and the same as
-- Nitro's default floor (#989862). Nitro then shades each side (floor edges, left and right walls,
-- wall tops) the way RoomVisualization does: Habbo's left wall is exactly 0.8 of its right wall.
-- grid (optional): the thin lines on each tile's back edges, as a share of the floor's colour.
BOBBA.registry.defineType("plane_style", {
	fields = { kind = "string", color = "table", material = "string?", name = "string?", grid = "number?" },
	validate = function(def)
		if def.kind ~= "floor" and def.kind ~= "wall" and def.kind ~= "landscape" then return false, "kind must be floor, wall or landscape" end
		local c = def.color
		for _, k in ipairs({ "r", "g", "b" }) do
			if type(c[k]) ~= "number" or c[k] < 0 or c[k] > 255 then return false, "color needs r, g, b from 0 to 255" end
		end
		return true
	end,
})

BOBBA.registry.register("plane_style", "default_floor", { kind = "floor", color = { r = 152, g = 152, b = 98 }, grid = 0.93 })
BOBBA.registry.register("plane_style", "default_wall", { kind = "wall", color = { r = 181, g = 185, b = 197 } })
BOBBA.registry.register("plane_style", "default_landscape", { kind = "landscape", color = { r = 134, g = 182, b = 217 } })

-- A plane's colour on screen: its style's colour times Nitro's shade for that side (0xRRGGBB).
function rooms.planeColor(style, shade)
	local c = style.color
	local r = math.floor(c.r * math.floor(shade / 65536) / 255)
	local g = math.floor(c.g * (math.floor(shade / 256) % 256) / 255)
	local b = math.floor(c.b * (shade % 256) / 255)
	return r, g, b
end

-- The door hole. Nitro cuts its "door" mask (room.nitro door_64: 32 x 104 px with its foot in the
-- middle, i.e. 1 tile wide and 3.25 units high at 32 px a unit) out of every wall and landscape
-- plane the door lies on (RoomEngine adds it at the door, RoomVisualization.updatePlaneMasks finds
-- the planes, RoomPlane.updateMask places it).
rooms.DOOR_HOLE = { width = 1, height = 3.25 }

local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function len(a) return math.sqrt(dot(a, a)) end
local function scalarProjection(a, b)
	local l = len(b)
	if l > 0 then return dot(a, b) / l end
	return -1
end

-- holes per plane: holes[planeIndex] = { { u0, u1, v0, v1 }, ... } in units along the plane's left
-- side (u) and right side (v); planeIndex counts from 0 like the planes on screen (p.index)
function rooms.holes(room)
	if room.holeList then return room.holeList end
	local holes = {}
	local d = room.door
	if d and (d.dir == 90 or d.dir == 180) then
		local mask = { d.x, d.y, d.z }
		for i, p in ipairs(room.planes) do
			if p.type == rooms.PLANE_WALL or p.type == rooms.PLANE_LANDSCAPE then
				local diff = { mask[1] - p.loc[1], mask[2] - p.loc[2], mask[3] - p.loc[3] }
				if math.abs(scalarProjection(diff, p.normal)) < 0.01 then
					local u = scalarProjection(diff, p.left)
					local v = scalarProjection(diff, p.right)
					local L, H = len(p.left), len(p.right)
					local u0, u1 = math.max(0, u - rooms.DOOR_HOLE.width / 2), math.min(L, u + rooms.DOOR_HOLE.width / 2)
					local v0, v1 = math.max(0, v), math.min(H, v + rooms.DOOR_HOLE.height)
					if u1 > u0 and v1 > v0 then
						holes[i - 1] = holes[i - 1] or {}
						table.insert(holes[i - 1], { u0, u1, v0, v1 })
					end
				end
			end
		end
	end
	room.holeList = holes
	return holes
end

-- A plane as rectangles (u0, u1, v0, v1 in units) that leave its holes out
function rooms.planePieces(room, index)
	local p = room.planes[index + 1]
	local L, H = len(p.left), len(p.right)
	local pieces = { { 0, L, 0, H } }
	for _, h in ipairs(rooms.holes(room)[index] or {}) do
		local out = {}
		for _, r in ipairs(pieces) do
			local a, b = math.max(r[1], h[1]), math.min(r[2], h[2])
			local c, e = math.max(r[3], h[3]), math.min(r[4], h[4])
			if a >= b or c >= e then
				out[#out + 1] = r -- the hole misses this piece
			else
				if r[1] < a then out[#out + 1] = { r[1], a, r[3], r[4] } end
				if b < r[2] then out[#out + 1] = { b, r[2], r[3], r[4] } end
				if c > r[3] then out[#out + 1] = { a, b, r[3], c } end
				if e < r[4] then out[#out + 1] = { a, b, e, r[4] } end
			end
		end
		pieces = out
	end
	return pieces
end

-- a point on a plane, from units along its sides
-- the lengths of a plane's two sides (left, right)
function rooms.planeSize(room, index)
	local p = room.planes[index + 1]
	return len(p.left), len(p.right)
end

function rooms.planePoint(room, index, u, v)
	local p = room.planes[index + 1]
	local L, H = len(p.left), len(p.right)
	local fu, fv = (L > 0) and u / L or 0, (H > 0) and v / H or 0
	return p.loc[1] + p.left[1] * fu + p.right[1] * fv, p.loc[2] + p.left[2] * fu + p.right[2] * fv, p.loc[3] + p.left[3] * fu + p.right[3] * fv
end

-- Nitro pushes whatever stands exactly on the door far back (RoomEngine setDisplacement), so it is
-- drawn behind the walls and seen through the door hole: half hidden, outside the room.
-- [bobba] Nitro does that only while standing exactly on the door, so halfway through a step into or
-- out of the door the avatar was drawn over the wall beside the hole. Here whoever is past the wall's
-- line (between it and the door) counts as behind the wall too.
function rooms.atDoor(room, x, y, z)
	local d = room.door
	if not d then return false end
	if d.dir == 90 then
		-- the left wall: its line is x = d.x, the door tile half a tile outside it
		return x < d.x and math.abs(y - d.y) < 1 and math.abs(z - d.z) < 1
	elseif d.dir == 180 then
		return y < d.y and math.abs(x - d.x) < 1 and math.abs(z - d.z) < 1
	end
	return false
end

-- The floor of the door tile (Nitro adds it last, as its own small plane). In Habbo it lies behind
-- the wall and is only seen through the door hole, so it is drawn before the walls. Returns its
-- plane index (from 0) or nil.
function rooms.doorFloor(room)
	if room.doorFloorIndex ~= nil then return room.doorFloorIndex or nil end
	room.doorFloorIndex = false
	local d = room.door
	if d and (d.dir == 90 or d.dir == 180) then
		local tx, ty = d.x, d.y
		if d.dir == 90 then tx = d.x - 0.5 else ty = d.y - 0.5 end
		for i, p in ipairs(room.planes) do
			if p.type == rooms.PLANE_FLOOR and p.loc[1] == tx + 0.5 and p.loc[2] == ty + 0.5 and p.loc[3] == d.z
				and p.left[1] == -1 and p.right[2] == -1 then
				room.doorFloorIndex = i - 1
			end
		end
	end
	return room.doorFloorIndex or nil
end

-- The thin lines of a floor's tiles (Habbo's plain floor has a line on each tile's back edges, one
-- texture pixel wide: 1/32 of a tile). For a flat floor plane (index from 0): a list of strips,
-- each { x0, x1, y0, y1, z } in room coordinates.
rooms.GRID_WIDTH = 1 / 32
function rooms.gridLines(room, index)
	local p = room.planes[index + 1]
	if p.type ~= rooms.PLANE_FLOOR or p.left[3] ~= 0 or p.right[3] ~= 0 then return {} end
	local xs = { p.loc[1], p.loc[1] + p.left[1] + p.right[1] }
	local ys = { p.loc[2], p.loc[2] + p.left[2] + p.right[2] }
	local x0, x1 = math.min(xs[1], xs[2]), math.max(xs[1], xs[2])
	local y0, y1 = math.min(ys[1], ys[2]), math.max(ys[1], ys[2])
	local z, w, out = p.loc[3], rooms.GRID_WIDTH, {}
	-- tile edges lie on .5; a line runs along the back (smaller x / y) edge of each tile
	local bx = math.ceil(x0 - 0.5 - 1e-9) + 0.5
	while bx < x1 - 1e-9 do
		out[#out + 1] = { bx, math.min(bx + w, x1), y0, y1, z }
		bx = bx + 1
	end
	local by = math.ceil(y0 - 0.5 - 1e-9) + 0.5
	while by < y1 - 1e-9 do
		out[#out + 1] = { x0, x1, by, math.min(by + w, y1), z }
		by = by + 1
	end
	return out
end
