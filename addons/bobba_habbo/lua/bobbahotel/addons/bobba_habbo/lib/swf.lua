-- Reads Habbo's SWF files (furniture, avatar parts, room textures): which names the pieces have
-- (SymbolClass), the XML data inside (DefineBinaryData) and the pictures (DefineBitsLossless and
-- DefineBitsLossless2), the same things Nitro's converter takes out of them. Plain Lua.
--
--   local swf = BOBBA.habbo.swf.read(bytes, inflate)   -- inflate(zlibBytes) -> bytes
--   swf.symbols[id] = "throne_throne_64_a_0_0"   (the first name; one picture can have several)
--   swf.names = { { id = 7, name = "..." }, ... }   every name, in file order
--   swf.binaries[id] = "<visualizationData ...>"
--   swf.images[id] = { width = 64, height = 80, pixels = { r, g, b, a, r, g, b, a, ... } }  (not premultiplied)
--   SWF.read(bytes, inflate, { images = false })   -- only names and XML (fast, for big files)
--   SWF.read(bytes, inflate, { images = "later" })  -- pictures kept packed: swf.packed[id], to unpack
--     one at a time with SWF.unpackImage(swf.packed[id], inflate) (so a long job can pause between)

local SWF = {}

local byte, sub = string.byte, string.sub

local function reader(s, pos)
	local r = { s = s, pos = pos or 1, bitBuf = 0, bitLeft = 0 }
	function r.u8() local v = byte(r.s, r.pos) r.pos = r.pos + 1 return v end
	function r.u16() local a, b = byte(r.s, r.pos, r.pos + 1) r.pos = r.pos + 2 return a + b * 256 end
	function r.u32() local a, b, c, d = byte(r.s, r.pos, r.pos + 3) r.pos = r.pos + 4 return a + b * 256 + c * 65536 + d * 16777216 end
	function r.bytes(n) local v = sub(r.s, r.pos, r.pos + n - 1) r.pos = r.pos + n return v end
	function r.cstring()
		local e = string.find(r.s, "\0", r.pos, true)
		local v = sub(r.s, r.pos, e - 1)
		r.pos = e + 1
		return v
	end
	-- bits, most significant first (for the RECT in the header)
	function r.ubits(n)
		local v = 0
		for _ = 1, n do
			if r.bitLeft == 0 then r.bitBuf = r.u8() r.bitLeft = 8 end
			r.bitLeft = r.bitLeft - 1
			v = v * 2 + (math.floor(r.bitBuf / 2 ^ r.bitLeft) % 2)
		end
		return v
	end
	function r.align() r.bitLeft = 0 end
	return r
end

-- The bytes of a SWF without its compression: "FWS" plain, "CWS" zlib after the first 8 bytes.
function SWF.uncompress(bytes, inflate)
	local sig = sub(bytes, 1, 3)
	if sig == "FWS" then return bytes end
	if sig == "CWS" then
		local body = inflate(sub(bytes, 9))
		if not body then return nil, "could not unpack the SWF" end
		return "FWS" .. sub(bytes, 4, 8) .. body
	end
	if sig == "ZWS" then return nil, "LZMA SWF files are not supported" end
	return nil, "not a SWF file"
end

-- 32-bit pixels in SWF are ARGB with the colour premultiplied by alpha; PNG wants it straight
local function unpremultiply(c, a)
	if a == 0 then return 0 end
	if a == 255 then return c end
	local v = math.floor(c * 255 / a + 0.5)
	if v > 255 then v = 255 end
	return v
end

local function lossless(data, inflate, withAlpha)
	local r = reader(data)
	local id = r.u16()
	local format = r.u8()
	local width, height = r.u16(), r.u16()
	local tableSize
	if format == 3 then tableSize = r.u8() + 1 end
	local raw = inflate(sub(data, r.pos))
	if not raw then return id, nil, "could not unpack picture " .. id end
	local px = {}
	local n = 0
	if format == 3 then
		-- a colour table (RGB or RGBA), then one byte per pixel, rows padded to 4 bytes
		local entry = withAlpha and 4 or 3
		local colors = {}
		for i = 0, tableSize - 1 do
			local o = i * entry + 1
			local cr, cg, cb = byte(raw, o, o + 2)
			local ca = withAlpha and byte(raw, o + 3) or 255
			colors[i] = { unpremultiply(cr, ca), unpremultiply(cg, ca), unpremultiply(cb, ca), ca }
		end
		local rowLen = width + (4 - width % 4) % 4
		local base = tableSize * entry
		for y = 0, height - 1 do
			for x = 0, width - 1 do
				local c = colors[byte(raw, base + y * rowLen + x + 1)] or { 0, 0, 0, 0 }
				px[n + 1], px[n + 2], px[n + 3], px[n + 4] = c[1], c[2], c[3], c[4]
				n = n + 4
			end
		end
	elseif format == 5 then
		-- 32 bits a pixel: (A or padding) R G B
		for i = 1, width * height * 4, 4 do
			local a, cr, cg, cb = byte(raw, i, i + 3)
			if not withAlpha then a = 255 end
			px[n + 1], px[n + 2], px[n + 3], px[n + 4] = unpremultiply(cr, a), unpremultiply(cg, a), unpremultiply(cb, a), a
			n = n + 4
		end
	elseif format == 4 then
		-- 15 bits a pixel (only in DefineBitsLossless), rows padded to 4 bytes
		local rowLen = width * 2 + (4 - (width * 2) % 4) % 4
		for y = 0, height - 1 do
			for x = 0, width - 1 do
				local o = y * rowLen + x * 2 + 1
				local hi, lo = byte(raw, o, o + 1)
				local v = hi * 256 + lo
				local cr, cg, cb = math.floor(v / 1024) % 32, math.floor(v / 32) % 32, v % 32
				px[n + 1], px[n + 2], px[n + 3], px[n + 4] = math.floor(cr * 255 / 31), math.floor(cg * 255 / 31), math.floor(cb * 255 / 31), 255
				n = n + 4
			end
		end
	else
		return id, nil, "picture " .. id .. " has an unknown format " .. format
	end
	return id, { width = width, height = height, pixels = px }
end

function SWF.read(bytes, inflate, opts)
	local wantImages = not (opts and opts.images == false)
	local later = opts and opts.images == "later"
	local s, err = SWF.uncompress(bytes, inflate)
	if not s then return nil, err end
	local r = reader(s, 9)
	-- the stage size (a RECT), then frame rate and count
	local nbits = r.ubits(5)
	r.ubits(nbits) r.ubits(nbits) r.ubits(nbits) r.ubits(nbits)
	r.align()
	r.u16() r.u16()
	local out = { symbols = {}, names = {}, binaries = {}, images = {}, packed = {}, problems = {} }
	while r.pos <= #s do
		local head = r.u16()
		local code, len = math.floor(head / 64), head % 64
		if len == 63 then len = r.u32() end
		local start = r.pos
		r.pos = r.pos + len
		local wanted = code == 76 or code == 87 or (wantImages and (code == 20 or code == 36))
		local data = wanted and sub(s, start, start + len - 1)
		if code == 0 then break end
		if code == 76 then -- SymbolClass
			local t = reader(data)
			for _ = 1, t.u16() do
				local id = t.u16()
				local name = t.cstring()
				-- Habbo gives one picture several names (the same image for many frames)
				if out.symbols[id] == nil then out.symbols[id] = name end
				out.names[#out.names + 1] = { id = id, name = name }
			end
		elseif code == 87 then -- DefineBinaryData
			local t = reader(data)
			local id = t.u16()
			t.u32() -- reserved
			out.binaries[id] = sub(data, t.pos)
		elseif wantImages and (code == 20 or code == 36) then -- DefineBitsLossless / DefineBitsLossless2
			if later then
				out.packed[byte(data, 1) + byte(data, 2) * 256] = { data = data, alpha = code == 36 }
			else
				local id, img, problem = lossless(data, inflate, code == 36)
				if img then out.images[id] = img else out.problems[#out.problems + 1] = problem end
			end
		end
	end
	-- by name, which is how Habbo's files refer to everything
	out.byName = {}
	for _, n in ipairs(out.names) do
		out.byName[n.name] = { id = n.id, image = out.images[n.id], packed = out.packed[n.id], binary = out.binaries[n.id] }
	end
	return out
end

-- a picture kept packed by SWF.read(..., { images = "later" }): img or nil, problem
function SWF.unpackImage(packed, inflate)
	local _, img, problem = lossless(packed.data, inflate, packed.alpha)
	return img, problem
end

return SWF
