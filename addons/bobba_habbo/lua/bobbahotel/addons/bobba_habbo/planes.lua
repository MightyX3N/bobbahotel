-- Habbo's floors, wallpapers and landscapes on the room's planes (client): the room view asks how to paint each
-- floor and wall plane (BOBBA.view.planePainter); Habbo's room content and Nitro's plane rasterizers
-- (lib/roomcontent.lua) say which parts of which pictures go where. Until the room content is
-- loaded the room is drawn plain.

local H = BOBBA.habbo
local P = BOBBA.platform
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

-- a room with no floor or wallpaper chosen gets Nitro's (RoomEngine.createRoomInstance: floor 111,
-- wallpaper 201; Arcturus only sends a room's paint when it isn't "0.0")
H.DEFAULT_PLANES = { floor = "111", wall = "201", landscape = "1" }

V.planePainter = function(kind, id, plane)
	if not rc then return nil end
	if id == nil or id == "" or id == "0.0" or id == "0" then id = H.DEFAULT_PLANES[kind] or id end
	local n = plane.normal
	local key = table.concat({ kind, id, plane.textureWidth, plane.textureHeight, plane.textureX, plane.textureY, tostring(plane.texture), n[1], n[2], n[3] }, "|")
	local paint = cache[key]
	if paint == nil then
		paint = H.paintPlane(rc, kind, id, plane, 64) or false
		cache[key] = paint
	end
	return paint or nil
end

-- windows: the holes Habbo's masks cut (lib/roomcontent.lua)
V.maskShape = function(maskType, scale, normal)
	if not rc then return nil end
	return H.maskShape(rc, maskType, scale, normal)
end

-- a wallpaper's, floor's or landscape's pattern, flat in a box (the catalogue's and inventory's
-- preview): BOBBA.room.paintSwatch(paint, id, x, y, w, h, s) -> drawn?   paint: "wallpaper",
-- "floor" or "landscape"; s: screen pixels a Habbo pixel
local SECTION = { wallpaper = "wall", floor = "floor", landscape = "landscape" }
-- (the normals the room's planes have: a right wall, the floor)
local NORMAL = { wall = { 0.70710678118655, -0.35355339059327, -0.61237243569579 }, floor = { 0, 0.86602540378444, -0.5 },
	landscape = { 0.70710678118655, -0.35355339059327, -0.61237243569579 } }
local swatchMaterials = {}
BOBBA.room = BOBBA.room or { units = {} }
BOBBA.room.paintSwatch = function(paint, id, x, y, w, h, s)
	local sec = SECTION[paint]
	if not rc or not sec or not rc[sec] then return false end
	local tw, th = math.max(1, math.ceil(w / s)), math.max(1, math.ceil(h / s))
	local key = table.concat({ "swatch", sec, tostring(id), tw, th }, "|")
	local out = cache[key]
	if out == nil then
		out = H.paintPlane(rc, sec, id, { textureWidth = tw, textureHeight = th, textureX = 0, textureY = 0, texture = true, normal = NORMAL[sec] }, 64) or false
		cache[key] = out
	end
	if not out then return false end
	render.PushFilterMag(TEXFILTER.POINT)
	render.PushFilterMin(TEXFILTER.POINT)
	for _, layer in ipairs(out.layers) do
		local c = layer.color or 0xFFFFFF
		local r, g, b = math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256
		if layer.fill then
			draw.NoTexture()
			surface.SetDrawColor(r, g, b, 255)
			surface.DrawRect(x, y, w, h)
		else
			for _, q in ipairs(layer.quads) do
				local img = q.image
				local m = swatchMaterials[img.path]
				if not m then
					H.image(img.path)
					m = P.dataMaterial(img.path, "noclamp")
					swatchMaterials[img.path] = m
				end
				surface.SetMaterial(m)
				surface.SetDrawColor(r, g, b, 255)
				local X0, Y0 = x + math.floor(q.x * s + 0.5), y + math.floor(q.y * s + 0.5)
				local X1, Y1 = x + math.floor((q.x + q.w) * s + 0.5), y + math.floor((q.y + q.h) * s + 0.5)
				surface.DrawTexturedRectUV(X0, Y0, X1 - X0, Y1 - Y0, q.u0 / img.texWidth, q.v0 / img.texHeight, q.u1 / img.texWidth, q.v1 / img.texHeight)
			end
		end
	end
	render.PopFilterMin()
	render.PopFilterMag()
	return true
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
