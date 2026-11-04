-- The camera's pictures (server): photos bought from the camera (a photo furni to hang on a wall, as
-- Habbo's external_image_wallitem_poster_small) and room thumbnails (the navigator's pictures).
-- Pictures come from the player's game as PNGs (320 x 320 photos, 110 x 110 thumbnails, as Nitro's
-- camera makes them), in pieces of Base64, and are kept in garrysmod/data/bobbahotel/photos/.
--
-- Messages from players: camera.upload { up, i, n, data, purpose = "photo" | "thumbnail" }   (piece i of n)
--                        photo.get { id }
-- Messages to players:   camera.purchased { id }   camera.thumbnail { room, id }   camera.error { message }
--                        photo.data { id, i, n, data }   (piece i of n)
-- Settings: camera.price.credits (2, Arcturus's), camera.price.duckets (0)

BOBBA.photos = BOBBA.photos or { uploads = {} }
local PH = BOBBA.photos
local live = BOBBA.live

PH.SIZES = { photo = 320, thumbnail = 110 }
PH.MAX_BYTES = 400 * 1024
PH.PIECE = 12000          -- Base64 characters a message
PH.KIND = "photo"         -- the furni a bought photo is

BOBBA.perms.define("bobba.camera.use", { default = "user", description = "Buy photos from the camera" })

local function P() return BOBBA.platform end

function PH.migrate()
	BOBBA.store.migrate("core.020_photos", {
		[[CREATE TABLE bobbahotel_photos (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			owner TEXT NOT NULL,
			room INTEGER NOT NULL DEFAULT 0,
			kind TEXT NOT NULL DEFAULT 'photo',
			created INTEGER NOT NULL
		)]],
		"ALTER TABLE bobbahotel_rooms ADD COLUMN thumbnail INTEGER NOT NULL DEFAULT 0",
	})
end

function PH.path(id) return "photos/" .. math.floor(tonumber(id) or 0) .. ".png" end

-- a PNG's width and height (from its IHDR), or nil when it isn't a PNG
function PH.pngSize(bytes)
	if type(bytes) ~= "string" or #bytes < 24 or bytes:sub(1, 8) ~= "\137PNG\r\n\26\n" or bytes:sub(13, 16) ~= "IHDR" then return nil end
	local function u32(i) local a, b, c, d = bytes:byte(i, i + 3) return ((a * 256 + b) * 256 + c) * 256 + d end
	return u32(17), u32(21)
end

local function price()
	return { credits = tonumber(BOBBA.store.setting("camera.price.credits", "2")) or 2,
		duckets = tonumber(BOBBA.store.setting("camera.price.duckets", "0")) or 0 }
end
PH.price = price

local function store(key, room, kind, bytes)
	BOBBA.store.query("INSERT INTO bobbahotel_photos (owner, room, kind, created) VALUES (?, ?, ?, ?)", { tostring(key), tonumber(room) or 0, kind, math.floor(P().time()) })
	local id = tonumber(BOBBA.store.row("SELECT last_insert_rowid() AS id").id)
	P().writeData(PH.path(id), bytes)
	return id
end

-- a finished picture: bought as a photo, or made the room's thumbnail. true, or false and why
function PH.finish(player, purpose, bytes)
	local w, h = PH.pngSize(bytes)
	local size = PH.SIZES[purpose]
	if not size then return false, "no such picture" end
	if not w or w ~= size or h ~= size then return false, "that isn't a picture from the camera" end
	local key = P().playerKey(player)
	local u = live.byPlayer[player]
	if purpose == "photo" then
		if not BOBBA.perms.has(player, "bobba.camera.use") then return false, "you may not buy photos" end
		if not BOBBA.wallet.pay(key, price()) then return false, "you don't have enough to buy the photo" end
		local id = store(key, u and u.room and u.room.id or 0, "photo", bytes)
		BOBBA.inventory.give(key, PH.KIND, 1, tostring(id))
		P().send("camera.purchased", { id = id }, player)
		return true
	end
	-- the room's thumbnail: its owner (or staff), in the room
	local r = u and u.room
	if not r then return false, "you're not in a room" end
	if not BOBBA.access.ownerLevel(player, r.info) then return false, "only the room's owner can change its picture" end
	local id = store(key, r.id, "thumbnail", bytes)
	BOBBA.store.query("UPDATE bobbahotel_rooms SET thumbnail = ? WHERE id = ?", { id, r.id })
	r.info = live.info(r.id)
	P().send("camera.thumbnail", { room = r.id, id = id }, player)
	return true
end

-- a piece of an upload; the last one finishes it
function PH.piece(player, data)
	local up = PH.uploads[player]
	local i, n = math.floor(tonumber(data.i) or 0), math.floor(tonumber(data.n) or 0)
	local token = tostring(data.up or "")
	if i == 1 then
		up = { token = token, n = n, got = {}, size = 0, purpose = tostring(data.purpose or "") }
		PH.uploads[player] = up
	end
	if not up or up.token ~= token or n ~= up.n or n < 1 or n > 64 or i < 1 or i > n then return false, "the picture didn't arrive" end
	local piece = tostring(data.data or "")
	if #piece > PH.PIECE then PH.uploads[player] = nil return false, "the picture didn't arrive" end
	up.size = up.size + #piece
	if up.size * 3 / 4 > PH.MAX_BYTES then PH.uploads[player] = nil return false, "the picture is too big" end
	up.got[i] = piece
	if i < n then return true end
	PH.uploads[player] = nil
	for k = 1, n do if not up.got[k] then return false, "the picture didn't arrive" end end
	local bytes = BOBBA.util.base64Decode(table.concat(up.got))
	if not bytes then return false, "the picture didn't arrive" end
	return PH.finish(player, up.purpose, bytes)
end

-- a picture for someone's game, in pieces
function PH.send(player, id)
	id = math.floor(tonumber(id) or 0)
	local bytes = id > 0 and P().dataExists(PH.path(id)) and P().readData(PH.path(id))
	if not bytes then P().send("photo.data", { id = id, i = 1, n = 0 }, player) return end
	local text = BOBBA.util.base64Encode(bytes)
	local n = math.max(1, math.ceil(#text / PH.PIECE))
	for i = 1, n do
		P().send("photo.data", { id = id, i = i, n = n, data = text:sub((i - 1) * PH.PIECE + 1, i * PH.PIECE) }, player)
	end
end

function PH.start()
	PH.migrate()
	-- a bought photo: a furni hung on a wall that shows it (client/camera.lua draws it)
	BOBBA.items.define(PH.KIND, { width = 1, length = 1, height = 0, wall = true, name = "Photo" })
	local p = P()
	p.onLeave(function(player) PH.uploads[player] = nil end)
	-- (the camera's price, for its buy button)
	BOBBA.events.on("roomEntered", "bobba.photos", function(_, u)
		if u.player then p.send("camera.price", price(), u.player) end
	end)
	p.receive("camera.upload", function(player, data)
		local ok, why = PH.piece(player, data)
		if not ok then p.send("camera.error", { message = tostring(why) }, player) end
	end)
	-- (at most 30 pictures a minute each)
	local asked = {}
	p.onLeave(function(player) asked[player] = nil end)
	p.receive("photo.get", function(player, data)
		local now = p.clock()
		local a = asked[player]
		if not a or now - a.t > 60 then a = { t = now, n = 0 } asked[player] = a end
		a.n = a.n + 1
		if a.n > 30 then return end
		PH.send(player, data.id)
	end)
end
