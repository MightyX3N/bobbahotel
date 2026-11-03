-- Reads files out of a ZIP archive (Habbo's desktop client comes as one). Plain Lua.
--
--   local zip = BOBBA.habbo.zip.open(bytes)            -- nil, why if it isn't a ZIP
--   zip.names                                          -- { "HabboAir.swf", ... }
--   local data, why = zip.read("HabboAir.swf", inflateRaw)   -- inflateRaw(deflateBytes) -> bytes

local ZIP = {}

local byte, sub = string.byte, string.sub

local function u16(s, p) local a, b = byte(s, p, p + 1) return a + b * 256 end
local function u32(s, p) local a, b, c, d = byte(s, p, p + 3) return a + b * 256 + c * 65536 + d * 16777216 end

function ZIP.open(s)
	if type(s) ~= "string" or #s < 22 then return nil, "not a ZIP file" end
	-- the end-of-directory record is in the last 64 KB (after it only a comment)
	local eocd
	for p = #s - 21, math.max(1, #s - 65557), -1 do
		if byte(s, p) == 0x50 and byte(s, p + 1) == 0x4B and byte(s, p + 2) == 5 and byte(s, p + 3) == 6 then
			eocd = p
			break
		end
	end
	if not eocd then return nil, "not a ZIP file" end
	local count, pos = u16(s, eocd + 10), u32(s, eocd + 16) + 1
	local zip = { names = {}, entries = {} }
	for _ = 1, count do
		if u32(s, pos) ~= 0x02014B50 then return nil, "damaged ZIP directory" end
		local method, packed, size = u16(s, pos + 10), u32(s, pos + 20), u32(s, pos + 24)
		local nameLen, extraLen, commentLen = u16(s, pos + 28), u16(s, pos + 30), u16(s, pos + 32)
		local name = sub(s, pos + 46, pos + 45 + nameLen)
		zip.entries[name] = { method = method, packed = packed, size = size, header = u32(s, pos + 42) + 1 }
		zip.names[#zip.names + 1] = name
		pos = pos + 46 + nameLen + extraLen + commentLen
	end
	function zip.read(name, inflateRaw)
		local e = zip.entries[name]
		if not e then return nil, name .. " is not in the ZIP" end
		local h = e.header
		if u32(s, h) ~= 0x04034B50 then return nil, "damaged ZIP entry " .. name end
		local start = h + 30 + u16(s, h + 26) + u16(s, h + 28)
		local data = sub(s, start, start + e.packed - 1)
		if e.method == 0 then return data end
		if e.method ~= 8 then return nil, name .. " uses an unknown packing (" .. e.method .. ")" end
		local out = inflateRaw(data)
		if not out or #out ~= e.size then return nil, "could not unpack " .. name end
		return out
	end
	return zip
end

return ZIP
