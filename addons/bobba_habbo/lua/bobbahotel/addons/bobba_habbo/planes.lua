-- Habbo's floors and wallpapers on the room's planes (client): the room view asks how to paint each
-- floor and wall plane (BOBBA.view.planePainter); Habbo's room content and Nitro's plane rasterizers
-- (lib/roomcontent.lua) say which parts of which pictures go where. Until the room content is
-- loaded the room is drawn plain.

local H = BOBBA.habbo
BOBBA.view = BOBBA.view or {}
local V = BOBBA.view

local rc, failed
local cache = {}

local function load()
	H.roomContent(function(r, err)
		if not r then failed = true print("[Bobba] " .. tostring(err)) return end
		rc = r
		cache = {}
		V.dirty = true
	end)
end

V.planePainter = function(kind, id, plane)
	if not rc then return nil end
	local n = plane.normal
	local key = table.concat({ kind, id, plane.textureWidth, plane.textureHeight, plane.textureX, plane.textureY, tostring(plane.texture), n[1], n[2], n[3] }, "|")
	local paint = cache[key]
	if paint == nil then
		paint = H.paintPlane(rc, kind, id, plane, 64) or false
		cache[key] = paint
	end
	return paint or nil
end

-- now: while the game loads (from the files saved last time this needs no internet)
load()

-- the hotel's loading screen waits for the floors and walls
H.loadingCheck("habbo.planes", function() return rc ~= nil or failed == true end)

-- bobba_habbo_floors / bobba_habbo_wallpapers: the ids Habbo has (for bobba_room_floor / _wallpaper)
for cmd, kind in pairs({ bobba_habbo_floors = "floor", bobba_habbo_wallpapers = "wall" }) do
	concommand.Add(cmd, function()
		if not rc then print("[Bobba] Habbo's room content isn't loaded (yet)") return end
		print("[Bobba] " .. table.concat(H.roomIds(rc, kind), " "))
	end)
end
