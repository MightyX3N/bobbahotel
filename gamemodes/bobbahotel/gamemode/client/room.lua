-- The room you're in (client): shows it with the room view, sends your clicks as walking, and
-- draws everyone in it. Until avatars come in, people are a simple stand-in figure.
--   bobba_room <id>   go to a room          (server: bobba_rooms lists them, bobba_room_create makes one)

BOBBA.room = BOBBA.room or { units = {} }
local R = BOBBA.room
local V = BOBBA.view
local P = BOBBA.platform

surface.CreateFont("BobbaName", { font = "Verdana", size = 11, weight = 700 })

function R.show()
	local c = R.current
	if not c then return end
	V.mode = "room"
	V.show(BOBBA.rooms.geometryFor(c.heightmap, { wallHeight = c.wallHeight }), c.name .. "  (room " .. c.id .. ", by " .. c.owner .. ")   click = walk   scroll = zoom   drag = move")
end

local function setUnit(s)
	local u = R.units[s.id] or { id = s.id }
	R.units[s.id] = u
	u.name, u.dir = s.name, s.dir
	u.from = { x = s.x, y = s.y, z = s.z }
	u.to = s.to
	u.started = SysTime()
	return u
end

P.receive("room.load", function(_, data)
	R.current = data
	R.units = {}
	R.you = data.you
	for _, s in ipairs(data.units or {}) do setUnit(s) end
	R.show()
end)

P.receive("room.units", function(_, list)
	for _, s in ipairs(list) do setUnit(s) end
end)

P.receive("room.unit.remove", function(_, data)
	R.units[data.id] = nil
end)

P.receive("room.error", function(_, data)
	chat.AddText(Color(255, 120, 120), "[Bobba] ", color_white, tostring(data.message))
end)

BOBBA.events.on("roomClick", "bobba.room.walk", function(hit)
	if V.mode == "room" and hit.floor then
		P.send("room.walk", { x = hit.tileX, y = hit.tileY })
	end
end)

-- where a unit is now: sliding from its tile to the next over one step (0.5 s), like Habbo
local STEP = 0.5
local function position(u)
	if not u.to then return u.from.x, u.from.y, u.from.z end
	local f = math.min((SysTime() - u.started) / STEP, 1)
	local a, b = u.from, u.to
	return a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.z + (b.z - a.z) * f
end

local function colorFor(name)
	local h = 0
	for i = 1, #name do h = (h * 31 + name:byte(i)) % 360 end
	return HSVToColor(h, 0.55, 0.85)
end

local function ellipse(cx, cy, rx, ry, n)
	local pts = {}
	for i = 0, n - 1 do
		local t = i / n * math.pi * 2
		pts[#pts + 1] = { x = cx + math.cos(t) * rx, y = cy + math.sin(t) * ry }
	end
	return V.clockwise(pts)
end

-- the stand-in figure: shadow, legs, body, head, a nose showing which way it faces, and the name
local function drawUnit(u)
	local x, y, z = position(u)
	local sx, sy, k = V.project(x, y, z)
	if not sx then return end
	draw.NoTexture()
	surface.SetDrawColor(0, 0, 0, 70)
	surface.DrawPoly(ellipse(sx, sy, 15 * k, 7 * k, 16))
	local c = colorFor(u.name or "?")
	surface.SetDrawColor(60, 60, 80, 255)
	surface.DrawRect(sx - 8 * k, sy - 30 * k, 7 * k, 30 * k)
	surface.DrawRect(sx + 1 * k, sy - 30 * k, 7 * k, 30 * k)
	surface.SetDrawColor(c.r, c.g, c.b, 255)
	surface.DrawRect(sx - 11 * k, sy - 62 * k, 22 * k, 34 * k)
	surface.SetDrawColor(240, 200, 160, 255)
	surface.DrawPoly(ellipse(sx, sy - 74 * k, 11 * k, 12 * k, 16))
	-- the nose: towards the next tile in the facing direction
	local d = ({ [0] = { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } })[u.dir or 2]
	local nx, ny = V.project(x + d[1], y + d[2], z)
	if nx then
		local dx, dy = nx - sx, ny - sy
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 0 then
			surface.SetDrawColor(200, 120, 90, 255)
			surface.DrawRect(sx + dx / len * 9 * k - 2 * k, sy - 74 * k + dy / len * 4 * k - 2 * k, 4 * k, 4 * k)
		end
	end
end

-- names go over everything (also over the wall when someone stands in the door)
local function drawName(u)
	local x, y, z = position(u)
	local sx, sy, k = V.project(x, y, z)
	if not sx then return end
	draw.SimpleTextOutlined(u.name or "?", "BobbaName", sx, sy - 92 * k, u.id == R.you and Color(255, 230, 120) or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 200))
end

-- phase "behind": whoever stands exactly in the door (drawn before the walls, so the wall hides
-- them except through the door hole); "front": everyone else
V.drawUnits = function(phase)
	if V.mode ~= "room" then return end
	-- deepest first (Nitro sorts by the screen depth of where each one stands)
	local list = {}
	for _, u in pairs(R.units) do
		local x, y, z = position(u)
		local behind = BOBBA.rooms.atDoor(V.room, x, y, z)
		if (phase == "behind") == behind then
			local _, _, _, depth = V.project(x, y, z)
			list[#list + 1] = { u = u, depth = depth or 0 }
		end
	end
	table.sort(list, function(a, b) return a.depth > b.depth end)
	for _, e in ipairs(list) do drawUnit(e.u) end
	if phase == "front" then
		for _, u in pairs(R.units) do drawName(u) end
	end
end

concommand.Add("bobba_room", function(_, _, args)
	local id = tonumber(args[1])
	if not id then print("bobba_room <id>   (bobba_rooms lists them)") return end
	P.send("room.enter", { id = id })
end)

-- tell the server we're ready for the room (also after a Lua reload)
local function ready() P.send("room.ready", {}) end
hook.Add("InitPostEntity", "bobba.room", ready)
if IsValid(LocalPlayer()) then ready() end
