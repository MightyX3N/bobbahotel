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
	opts = opts or {}
	local layout = BOBBA.registry.get("layout", layoutId)
	if not layout then return nil, "unknown layout " .. tostring(layoutId) end
	local wh, ft, wt = opts.wallHeight or -1, opts.floorThickness or 1, opts.wallThickness or 1
	local key = layoutId .. "|" .. wh .. "|" .. ft .. "|" .. wt .. "|" .. layout.heightmap
	if not cache[key] then
		-- Arcturus sends no separate door tile, so Nitro finds the door from the heightmap (-1, -1)
		local room = BOBBA.nitro.build(layout.heightmap, wh, true, -1, -1, ft, wt)
		room.layout = layoutId
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
-- the core's defaults are flat colours taken from Habbo's default floor and wallpaper. Nitro then
-- shades each side (floor edges, left and right walls) the way RoomVisualization does.
BOBBA.registry.defineType("plane_style", {
	fields = { kind = "string", color = "table", material = "string?", name = "string?" },
	validate = function(def)
		if def.kind ~= "floor" and def.kind ~= "wall" and def.kind ~= "landscape" then return false, "kind must be floor, wall or landscape" end
		local c = def.color
		for _, k in ipairs({ "r", "g", "b" }) do
			if type(c[k]) ~= "number" or c[k] < 0 or c[k] > 255 then return false, "color needs r, g, b from 0 to 255" end
		end
		return true
	end,
})

BOBBA.registry.register("plane_style", "default_floor", { kind = "floor", color = { r = 161, g = 99, b = 55 } })
BOBBA.registry.register("plane_style", "default_wall", { kind = "wall", color = { r = 193, g = 173, b = 112 } })
BOBBA.registry.register("plane_style", "default_landscape", { kind = "landscape", color = { r = 134, g = 182, b = 217 } })

-- A plane's colour on screen: its style's colour times Nitro's shade for that side (0xRRGGBB).
function rooms.planeColor(style, shade)
	local c = style.color
	local r = math.floor(c.r * math.floor(shade / 65536) / 255)
	local g = math.floor(c.g * (math.floor(shade / 256) % 256) / 255)
	local b = math.floor(c.b * (shade % 256) / 255)
	return r, g, b
end
