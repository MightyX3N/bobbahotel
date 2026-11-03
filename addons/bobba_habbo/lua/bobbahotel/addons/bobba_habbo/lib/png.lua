-- Writes RGBA pixels as a PNG file (so GMod can load it as a material). Plain Lua.
--   local bytes = BOBBA.habbo.png.encode(width, height, pixels, deflateZlib)
--   pixels = { r, g, b, a, r, g, b, a, ... } (0-255, rows from the top); deflateZlib(bytes) -> zlib bytes
--   local a = BOBBA.habbo.png.alphaReader(bytes, inflateZlib)   -- for a PNG made by encode() only
--   a(x, y) -> 0-255, how solid pixel x, y is (its alpha; 0-based); nil if it's not such a PNG
--   local img, why = BOBBA.habbo.png.decode(bytes, inflateZlib)   -- any 8-bit (or less) PNG that
--     isn't interlaced: truecolour, with alpha, greyscale or a palette -> { width, height, pixels }

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

-- PNG's filters, undone row by row (each row starts with its filter type)
local function unfilter(raw, rows, rowBytes, bpp)
	local out = {}
	local prev = {}
	for i = 1, rowBytes do prev[i] = 0 end
	local pos = 1
	for y = 1, rows do
		local f = byte(raw, pos)
		local cur = { byte(raw, pos + 1, pos + rowBytes) }
		pos = pos + 1 + rowBytes
		if f == 1 then
			for i = bpp + 1, rowBytes do cur[i] = (cur[i] + cur[i - bpp]) % 256 end
		elseif f == 2 then
			for i = 1, rowBytes do cur[i] = (cur[i] + prev[i]) % 256 end
		elseif f == 3 then
			for i = 1, rowBytes do
				local left = i > bpp and cur[i - bpp] or 0
				cur[i] = (cur[i] + math.floor((left + prev[i]) / 2)) % 256
			end
		elseif f == 4 then
			for i = 1, rowBytes do
				local a = i > bpp and cur[i - bpp] or 0
				local b = prev[i]
				local c = i > bpp and prev[i - bpp] or 0
				local p = a + b - c
				local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
				local pr
				if pa <= pb and pa <= pc then pr = a elseif pb <= pc then pr = b else pr = c end
				cur[i] = (cur[i] + pr) % 256
			end
		elseif f ~= 0 then
			return nil
		end
		out[y] = cur
		prev = cur
	end
	return out
end

function PNG.decode(bytes, inflateZlib)
	if not bytes or bytes:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil, "not a PNG" end
	local pos = 9
	local width, height, depth, kind, interlace
	local idat, palette, trns = {}, nil, nil
	while pos + 8 <= #bytes do
		local len, name = be32(bytes, pos), bytes:sub(pos + 4, pos + 7)
		local data = bytes:sub(pos + 8, pos + 7 + len)
		if name == "IHDR" then
			width, height = be32(data, 1), be32(data, 5)
			depth, kind, interlace = byte(data, 9), byte(data, 10), byte(data, 13)
		elseif name == "PLTE" then palette = data
		elseif name == "tRNS" then trns = data
		elseif name == "IDAT" then idat[#idat + 1] = data
		elseif name == "IEND" then break end
		pos = pos + 12 + len
	end
	if not width then return nil, "a PNG without its header" end
	if interlace ~= 0 then return nil, "interlaced PNGs are not supported" end
	if depth > 8 then return nil, "16-bit PNGs are not supported" end
	local channels = ({ [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 })[kind]
	if not channels then return nil, "unknown PNG colour type " .. tostring(kind) end
	local raw = inflateZlib(table.concat(idat))
	if not raw then return nil, "could not unpack the PNG" end
	local bitsPerPixel = channels * depth
	local rowBytes = math.ceil(width * bitsPerPixel / 8)
	local rows = unfilter(raw, height, rowBytes, math.max(1, bitsPerPixel / 8))
	if not rows then return nil, "a damaged PNG" end
	local px, n = {}, 0
	local maxv = 2 ^ depth - 1
	for y = 1, height do
		local row = rows[y]
		for x = 0, width - 1 do
			local r, g, b, a
			if depth < 8 then
				-- several pixels in a byte, from its top bits
				local bitPos = x * depth
				local v = math.floor(row[math.floor(bitPos / 8) + 1] / 2 ^ (8 - depth - bitPos % 8)) % (2 ^ depth)
				if kind == 3 then
					local o = v * 3 + 1
					r, g, b = byte(palette or "", o, o + 2)
					a = trns and byte(trns, v + 1) or 255
				else
					r = math.floor(v * 255 / maxv + 0.5) g, b, a = r, r, 255
				end
			else
				local o = x * channels + 1
				if kind == 6 then r, g, b, a = row[o], row[o + 1], row[o + 2], row[o + 3]
				elseif kind == 2 then r, g, b, a = row[o], row[o + 1], row[o + 2], 255
				elseif kind == 0 then r = row[o] g, b, a = r, r, 255
				elseif kind == 4 then r = row[o] g, b, a = r, r, row[o + 1]
				else
					local v = row[o]
					local po = v * 3 + 1
					r, g, b = byte(palette or "", po, po + 2)
					a = trns and byte(trns, v + 1) or 255
				end
			end
			px[n + 1], px[n + 2], px[n + 3], px[n + 4] = r or 0, g or 0, b or 0, a or 255
			n = n + 4
		end
	end
	return { width = width, height = height, pixels = px }
end

return PNG
