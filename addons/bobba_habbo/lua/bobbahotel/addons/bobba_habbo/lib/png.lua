-- Writes RGBA pixels as a PNG file (so GMod can load it as a material). Plain Lua.
--   local bytes = BOBBA.habbo.png.encode(width, height, pixels, deflateZlib)
--   pixels = { r, g, b, a, r, g, b, a, ... } (0-255, rows from the top); deflateZlib(bytes) -> zlib bytes
--   local a = BOBBA.habbo.png.alphaReader(bytes, inflateZlib)   -- for a PNG made by encode() only
--   a(x, y) -> 0-255, how solid pixel x, y is (its alpha; 0-based); nil if it's not such a PNG

local PNG = {}
local char, byte = string.char, string.byte
local bit = bit or bit32

local crcTable = {}
for i = 0, 255 do
	local c = i
	for _ = 1, 8 do
		if bit.band(c, 1) == 1 then c = bit.bxor(0xEDB88320, bit.rshift(c, 1)) else c = bit.rshift(c, 1) end
	end
	crcTable[i] = c
end

local function crc32(s)
	local c = 0xFFFFFFFF
	for i = 1, #s do
		c = bit.bxor(crcTable[bit.band(bit.bxor(c, byte(s, i)), 0xFF)], bit.rshift(c, 8))
	end
	c = bit.bxor(c, 0xFFFFFFFF)
	if c < 0 then c = c + 4294967296 end
	return c
end
PNG.crc32 = crc32

local function u32(v)
	return char(math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256)
end

local function chunk(kind, data)
	return u32(#data) .. kind .. data .. u32(crc32(kind .. data))
end

function PNG.encode(width, height, pixels, deflateZlib)
	-- every row: filter type 0 (none), then its pixels
	local rows = {}
	local parts = {}
	local i = 1
	for y = 1, height do
		parts[1] = "\0"
		local p = 2
		for _ = 1, width do
			parts[p] = char(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
			p = p + 1
			i = i + 4
		end
		for k = p, #parts do parts[k] = nil end
		rows[y] = table.concat(parts)
	end
	local raw = table.concat(rows)
	local header = u32(width) .. u32(height) .. char(8, 6, 0, 0, 0) -- 8 bits, RGBA
	return "\137PNG\r\n\26\n" .. chunk("IHDR", header) .. chunk("IDAT", deflateZlib(raw)) .. chunk("IEND", "")
end

-- Reads back a PNG that encode() wrote (one IDAT, every row filter 0): how see-through each pixel is
local function be32(s, i)
	local a, b, c, d = byte(s, i, i + 3)
	return ((a * 256 + b) * 256 + c) * 256 + d
end

function PNG.alphaReader(bytes, inflateZlib)
	if not bytes or bytes:sub(1, 8) ~= "\137PNG\r\n\26\n" or bytes:sub(13, 16) ~= "IHDR" then return nil end
	local width, height = be32(bytes, 17), be32(bytes, 21)
	if byte(bytes, 25) ~= 8 or byte(bytes, 26) ~= 6 then return nil end
	local pos = 34
	local raw
	while pos + 8 <= #bytes do
		local len, kind = be32(bytes, pos), bytes:sub(pos + 4, pos + 7)
		if kind == "IDAT" then
			if raw then return nil end
			raw = inflateZlib(bytes:sub(pos + 8, pos + 7 + len))
		end
		pos = pos + 12 + len
	end
	local row = 1 + width * 4
	if not raw or #raw ~= row * height then return nil end
	for y = 0, height - 1 do
		if byte(raw, y * row + 1) ~= 0 then return nil end
	end
	return function(x, y)
		if x < 0 or y < 0 or x >= width or y >= height then return 0 end
		return byte(raw, y * row + 1 + x * 4 + 4)
	end
end

return PNG
