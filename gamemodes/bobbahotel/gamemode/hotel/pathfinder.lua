-- Walking: Arcturus's pathfinder (RoomLayout.findPath / getAdjacent / calcPath and RoomTile's
-- costs, github.com/ArcturusEmulator, GPL-3), ported line by line so players walk the way they do on
-- a Habbo retro: diagonals unless both side tiles are closed, steps up of at most 1.1, others in the
-- way unless near the door. tests/pathfinder_java checks it against the original Java.
--
--   local grid = BOBBA.pathfinder.grid(room, layout)          -- from BOBBA.rooms.geometry + the layout
--   local path = BOBBA.pathfinder.find(grid, fromX, fromY, toX, toY)
--   -- nil = no way there, {} = already there or not a tile, else { {x=, y=, z=}, ... } (not the start)

BOBBA.pathfinder = BOBBA.pathfinder or {}
local PF = BOBBA.pathfinder

PF.OPEN, PF.BLOCKED, PF.INVALID, PF.SIT, PF.LAY = "open", "blocked", "invalid", "sit", "lay"
PF.BASICMOVEMENTCOST = 10
PF.DIAGONALMOVEMENTCOST = 14
PF.MAXIMUM_STEP_HEIGHT = 1.1
PF.ALLOW_FALLING = true

-- Java's (short) cast: costs are kept as 16-bit numbers, as in RoomTile
local function short(v)
	v = v % 65536
	if v >= 32768 then v = v - 65536 end
	return v
end

local function newTile(x, y, z, state, allowStack)
	return { x = x, y = y, z = z, state = state, stackHeight = z, allowStack = allowStack, units = { n = 0 }, diagonally = false, g = 0, h = 0, previous = nil }
end

-- new RoomTile(tile): a copy for the search (previous is not copied; units are shared)
local function copy(t)
	local c = { x = t.x, y = t.y, z = t.z, state = t.state, stackHeight = t.stackHeight, allowStack = t.allowStack, units = t.units, diagonally = t.diagonally, g = t.g, h = t.h, previous = nil }
	if c.state == PF.INVALID then c.allowStack = false end
	return c
end

local function same(a, b)
	return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y
end

local function contains(list, t)
	for i = 1, #list do if same(list[i], t) then return true end end
	return false
end

local function remove(list, t)
	for i = 1, #list do
		if same(list[i], t) then table.remove(list, i) return end
	end
end

local function fCosts(t) return t.g + t.h end

local function setG(t, prev)
	t.g = short(prev.g + (t.diagonally and PF.DIAGONALMOVEMENTCOST or PF.BASICMOVEMENTCOST))
end

local function calcG(t, prev)
	if t.diagonally then return prev.g + 14 end
	return prev.g + 10
end

local function setH(t, parent)
	t.h = short((math.abs(t.x - parent.x) + math.abs(t.y - parent.y)) * (parent.diagonally and PF.DIAGONALMOVEMENTCOST or PF.BASICMOVEMENTCOST))
end

local function walkable(t) return t.state == PF.OPEN end

-- The tiles of a room the way Arcturus's RoomLayout.parse makes them: heights from the heightmap,
-- x = invalid, and the door tile open with the height of the tile in front of it.
-- Java's String.split("\r"): empty rows stay (and are skipped below), empty rows at the end go
local function javaSplit(s)
	local rows = {}
	for part in (s .. "\r"):gmatch("(.-)\r") do rows[#rows + 1] = part end
	while #rows > 0 and rows[#rows] == "" do rows[#rows] = nil end
	return rows
end

function PF.grid(heightmap, doorX, doorY, doorDir)
	local rows = javaSplit((heightmap:gsub("\n", "")))
	local g = { sizeX = #(rows[1] or ""), sizeY = #rows, tiles = {}, doorDir = doorDir or 2, allowWalkthrough = false }
	for y = 0, g.sizeY - 1 do
		local row = rows[y + 1]
		if row ~= "" and #row == g.sizeX then
			for x = 0, g.sizeX - 1 do
				local c = row:sub(x + 1, x + 1):lower()
				local state, h = PF.OPEN, 0
				if c == "x" then
					state = PF.INVALID
				elseif c:byte() <= 32 then
					h = 0 -- Java's trim() makes it "" (it removes everything up to the space character)
				elseif c:match("%d") then
					h = tonumber(c)
				else
					h = 10 + (("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):find(c:upper(), 1, true) or 0) - 1
				end
				g.tiles[x * 100000 + y] = newTile(x, y, h, state, true)
			end
		end
	end
	g.doorZ = 0
	local door = PF.tile(g, doorX, doorY)
	g.door = door
	if door then
		door.allowStack = false
		local fx, fy = PF.inFront(doorX, doorY, g.doorDir)
		local front = PF.tile(g, fx, fy)
		if front and front.state ~= PF.INVALID then
			if g.doorZ ~= front.z or door.state ~= front.state then
				g.doorZ = front.z
				door.state = PF.OPEN
			end
		end
	end
	return g
end

-- RoomLayout.getTileInFront (offset 0)
local FRONT = { [0] = { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } }
function PF.inFront(x, y, rotation)
	local o = FRONT[rotation % 8]
	return x + o[1], y + o[2]
end

function PF.exists(g, x, y)
	return not (x < 0 or y < 0 or x >= g.sizeX or y >= g.sizeY)
end

function PF.tile(g, x, y)
	if PF.exists(g, x, y) then return g.tiles[x * 100000 + y] end
	return nil
end

local function findTile(g, list, x, y)
	for i = 1, #list do
		local t = list[i]
		if x == t.x and y == t.y then return t end
	end
	local t = PF.tile(g, x, y)
	if t then return copy(t) end
	return nil
end

local function canOverride(unit, t)
	return unit ~= nil and unit.canOverrideTile ~= nil and unit.canOverrideTile(t) == true
end

local function canWalkOn(t, unit)
	return t ~= nil and (canOverride(unit, t) or (t.state ~= PF.BLOCKED and t.state ~= PF.INVALID))
end

local function distance(a, b)
	local x, y = a.x - b.x, a.y - b.y
	return math.sqrt(x * x + y * y)
end

local function hasUnits(t)
	return t.units.n > 0
end

local function calcPath(g, start, goal)
	local path = {}
	if start == nil then return path end
	local curr = goal
	while curr ~= nil do
		table.insert(path, 1, PF.tile(g, curr.x, curr.y))
		curr = curr.previous
		if curr ~= nil and same(curr, start) then return path end
	end
	return path
end

local function lowestFInOpen(list)
	local cheapest = list[1]
	for i = 1, #list do
		if fCosts(list[i]) < fCosts(cheapest) then cheapest = list[i] end
	end
	return cheapest
end

local function addAdjacent(g, adj, list, node, nextTile, unit, x, y, diagonal)
	local temp = findTile(g, list, x, y)
	if canWalkOn(temp, unit) then
		if temp.state ~= PF.SIT or nextTile.stackHeight - node.stackHeight <= 2.0 then
			temp.diagonally = diagonal
			if not contains(adj, temp) then adj[#adj + 1] = temp end
		end
	end
end

local function getAdjacent(g, list, node, nextTile, unit)
	local x, y = node.x, node.y
	local adj = {}
	if x > 0 then addAdjacent(g, adj, list, node, nextTile, unit, x - 1, y, false) end
	if x < g.sizeX then addAdjacent(g, adj, list, node, nextTile, unit, x + 1, y, false) end
	if y > 0 then addAdjacent(g, adj, list, node, nextTile, unit, x, y - 1, false) end
	if y < g.sizeY then addAdjacent(g, adj, list, node, nextTile, unit, x, y + 1, false) end
	if g.moveDiagonally ~= false then
		local function diag(cond, dx, dy)
			if not cond then return end
			local offX = findTile(g, list, x + dx, y)
			local offY = findTile(g, list, x, y + dy)
			if offX ~= nil and offY ~= nil and (walkable(offX) or walkable(offY)) then
				addAdjacent(g, adj, list, node, nextTile, unit, x + dx, y + dy, true)
			end
		end
		diag(x < g.sizeX and y < g.sizeY, 1, 1)
		diag(x > 0 and y > 0, -1, -1)
		diag(x > 0 and y < g.sizeY, -1, 1)
		diag(x < g.sizeX and y > 0, 1, -1)
	end
	return adj
end

local function findPath(g, oldTile, newTile, goal, unit, retry)
	if oldTile == nil or newTile == nil or same(oldTile, newTile) or newTile.state == PF.INVALID then return {} end
	local open, closed = { copy(oldTile) }, {}
	local door = g.door
	while #open > 0 do
		local current = lowestFInOpen(open)
		if current.x == newTile.x and current.y == newTile.y then
			return calcPath(g, findTile(g, open, oldTile.x, oldTile.y), current)
		end
		closed[#closed + 1] = current
		remove(open, current)
		for _, adj in ipairs(getAdjacent(g, open, current, newTile, unit)) do
			if not contains(closed, adj) then
				local skip = false
				if canOverride(unit, adj) then
					adj.previous = current
					setH(adj, findTile(g, open, newTile.x, newTile.y))
					setG(adj, current)
					open[#open + 1] = adj
					skip = true
				end
				if not skip and (adj.state == PF.BLOCKED or ((adj.state == PF.SIT or adj.state == PF.LAY) and not same(adj, goal))) then
					closed[#closed + 1] = adj
					remove(open, adj)
					skip = true
				end
				if not skip then
					local height = adj.stackHeight - current.stackHeight
					if (not PF.ALLOW_FALLING and height < -PF.MAXIMUM_STEP_HEIGHT) or (adj.state == PF.OPEN and height > PF.MAXIMUM_STEP_HEIGHT) then
						closed[#closed + 1] = adj
						remove(open, adj)
						skip = true
					end
				end
				if not skip and hasUnits(adj) and distance(door, adj) > 2 and (not retry or not g.allowWalkthrough or same(adj, goal)) then
					closed[#closed + 1] = adj
					remove(open, adj)
					skip = true
				end
				if not skip then
					if not contains(open, adj) then
						adj.previous = current
						setH(adj, findTile(g, open, newTile.x, newTile.y))
						setG(adj, current)
						open[#open + 1] = adj
					elseif adj.g > calcG(adj, current) then
						adj.previous = current
						setG(adj, current)
					end
				end
			end
		end
	end
	if g.allowWalkthrough and not retry then
		return findPath(g, oldTile, newTile, goal, unit, true)
	end
	return nil
end

-- A path from one tile to another: nil = no way there, {} = nothing to do, else the tiles to walk
-- (not the start). unit (optional) may have canOverrideTile(tile).
function PF.find(g, fromX, fromY, toX, toY, unit)
	local from, to = PF.tile(g, fromX, fromY), PF.tile(g, toX, toY)
	return findPath(g, from, to, to, unit, false)
end

-- Who is standing where (the pathfinder walks around others, except near the door)
function PF.addUnit(g, x, y)
	local t = PF.tile(g, x, y)
	if t then t.units.n = t.units.n + 1 end
end

function PF.removeUnit(g, x, y)
	local t = PF.tile(g, x, y)
	if t and t.units.n > 0 then t.units.n = t.units.n - 1 end
end
