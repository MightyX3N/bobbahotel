-- JSON the way GMod's util.TableToJSON / util.JSONToTable do it: a table numbered 1..n is a list,
-- anything else an object; reading back, object keys that are numbers become numbers again.

local J = {}

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function str(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return escapes[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end

local function num(n)
	if n ~= n or n == math.huge or n == -math.huge then return "0" end
	if n == math.floor(n) and math.abs(n) < 2 ^ 53 then return string.format("%d", n) end
	return string.format("%.17g", n)
end

local function isList(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then return false end
		n = n + 1
	end
	for i = 1, n do if t[i] == nil then return false end end
	return true, n
end

local encode
encode = function(v, out, seen)
	local t = type(v)
	if t == "table" then
		if seen[v] then out[#out + 1] = "null" return end
		seen[v] = true
		local list, n = isList(v)
		if list then
			out[#out + 1] = "["
			for i = 1, n do
				if i > 1 then out[#out + 1] = "," end
				encode(v[i], out, seen)
			end
			out[#out + 1] = "]"
		else
			out[#out + 1] = "{"
			local first = true
			for k, x in pairs(v) do
				local kt = type(k)
				if kt == "string" or kt == "number" then
					local xt = type(x)
					if xt == "table" or xt == "string" or xt == "number" or xt == "boolean" then
						if not first then out[#out + 1] = "," end
						first = false
						out[#out + 1] = str(kt == "number" and num(k) or k)
						out[#out + 1] = ":"
						encode(x, out, seen)
					end
				end
			end
			out[#out + 1] = "}"
		end
		seen[v] = nil
	elseif t == "string" then out[#out + 1] = str(v)
	elseif t == "number" then out[#out + 1] = num(v)
	elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
	else out[#out + 1] = "null" end
end

function J.encode(v)
	local out = {}
	encode(v, out, {})
	return table.concat(out)
end

-- reading
local function utf8char(c)
	if c < 0x80 then return string.char(c) end
	if c < 0x800 then return string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64) end
	if c < 0x10000 then return string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64) end
	return string.char(0xF0 + math.floor(c / 262144), 0x80 + math.floor(c / 4096) % 64, 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
end

local function decoder(s)
	local i = 1
	local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
	local value
	local function readString()
		i = i + 1
		local parts = {}
		while true do
			local j = s:find('["\\]', i)
			if not j then error("unfinished text") end
			parts[#parts + 1] = s:sub(i, j - 1)
			if s:sub(j, j) == '"' then i = j + 1 break end
			local e = s:sub(j + 1, j + 1)
			if e == "u" then
				local c = tonumber(s:sub(j + 2, j + 5), 16) or 63
				i = j + 6
				if c >= 0xD800 and c < 0xDC00 and s:sub(i, i + 1) == "\\u" then
					local lo = tonumber(s:sub(i + 2, i + 5), 16)
					if lo and lo >= 0xDC00 and lo < 0xE000 then
						c = 0x10000 + (c - 0xD800) * 1024 + (lo - 0xDC00)
						i = i + 6
					end
				end
				parts[#parts + 1] = utf8char(c)
			else
				local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
				parts[#parts + 1] = map[e] or e
				i = j + 2
			end
		end
		return table.concat(parts)
	end
	value = function()
		ws()
		local c = s:sub(i, i)
		if c == "{" then
			i = i + 1
			local t = {}
			ws()
			if s:sub(i, i) == "}" then i = i + 1 return t end
			while true do
				ws()
				local k = readString()
				ws()
				i = i + 1 -- :
				local v = value()
				t[tonumber(k) or k] = v
				ws()
				local d = s:sub(i, i)
				i = i + 1
				if d == "}" then return t end
			end
		elseif c == "[" then
			i = i + 1
			local t, n = {}, 0
			ws()
			if s:sub(i, i) == "]" then i = i + 1 return t end
			while true do
				n = n + 1
				t[n] = value()
				ws()
				local d = s:sub(i, i)
				i = i + 1
				if d == "]" then return t end
			end
		elseif c == '"' then
			return readString()
		elseif c == "t" then i = i + 4 return true
		elseif c == "f" then i = i + 5 return false
		elseif c == "n" then i = i + 4 return nil
		else
			local j = s:find("[^%d%.eE%+%-]", i) or #s + 1
			local n = tonumber(s:sub(i, j - 1))
			if not n then error("not JSON at " .. i) end
			i = j
			return n
		end
	end
	return value
end

-- nil when it isn't JSON
function J.decode(s)
	if type(s) ~= "string" or s == "" then return nil end
	local ok, v = pcall(decoder(s))
	if not ok then return nil end
	return v
end

return J
