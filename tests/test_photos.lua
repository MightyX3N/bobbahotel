-- The camera's pictures (hotel/photos.lua)
local T = {}
local P

-- a PNG's first bytes, w x h (only the header: the server only reads that)
local function png(w, h)
	local function u32(n) return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) end
	return "\137PNG\r\n\26\n" .. u32(13) .. "IHDR" .. u32(w) .. u32(h) .. string.rep("x", 200)
end

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	local mia, bo = { key = "765611980001", name = "Mia" }, { key = "765611980002", name = "Bo" }
	local id = BOBBA.live.create(mia.key, mia.name, "model_a", "Mia's room")
	BOBBA.live.enter(mia, id)
	BOBBA.live.enter(bo, id)
	return mia, bo, id
end
local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end
local function upload(p, purpose, bytes, piece)
	local text = BOBBA.util.base64Encode(bytes)
	piece = piece or 100
	local n = math.ceil(#text / piece)
	for i = 1, n do P.fromPlayer(p, "camera.upload", { up = "u1", i = i, n = n, data = text:sub((i - 1) * piece + 1, i * piece), purpose = purpose }) end
end

T["base64 both ways"] = function()
	local s = ""
	for i = 0, 255 do s = s .. string.char(i) end
	for _, t in ipairs({ s, "a", "ab", "abc", "" }) do eq(BOBBA.util.base64Decode(BOBBA.util.base64Encode(t)), t) end
end

T["buying a photo: paid for, kept, a photo furni in the inventory; anyone can fetch it"] = function()
	local mia, bo = start()
	local before = BOBBA.wallet.get(mia.key).credits
	local bytes = png(320, 320)
	upload(mia, "photo", bytes)
	local id = last(mia, "camera.purchased").id
	assert(id, "bought")
	eq(BOBBA.wallet.get(mia.key).credits, before - 2)
	local inv = BOBBA.inventory.list(mia.key)
	eq(inv[#inv].kind .. " " .. inv[#inv].data, "photo " .. id)
	P.fromPlayer(bo, "photo.get", { id = id })
	local parts = {}
	for _, m in ipairs(P.inbox(bo, "photo.data")) do parts[m.i] = m.data end
	eq(BOBBA.util.base64Decode(table.concat(parts)), bytes)
	-- wrong size; not a PNG
	upload(mia, "photo", png(100, 100))
	eq(last(mia, "camera.error").message, "that isn't a picture from the camera")
	upload(mia, "photo", "hello")
	eq(last(mia, "camera.error").message, "that isn't a picture from the camera")
	-- no money
	BOBBA.wallet.add(mia.key, "credits", -BOBBA.wallet.get(mia.key).credits)
	upload(mia, "photo", bytes)
	eq(last(mia, "camera.error").message, "you don't have enough to buy the photo")
end

T["room thumbnails: the owner's, shown in the navigator and the room's info"] = function()
	local mia, bo, room = start()
	upload(bo, "thumbnail", png(110, 110))
	eq(last(bo, "camera.error").message, "only the room's owner can change its picture")
	upload(mia, "thumbnail", png(110, 110))
	local t = last(mia, "camera.thumbnail")
	eq(t.room, room)
	eq(BOBBA.access.publicInfo(BOBBA.live.info(room)).thumbnail, t.id)
	eq(BOBBA.navigator.roomData(BOBBA.live.info(room)).thumbnail, t.id)
end

return T
