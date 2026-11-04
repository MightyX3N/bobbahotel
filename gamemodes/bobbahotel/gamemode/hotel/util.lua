-- Small helpers the core uses (plain Lua).

BOBBA.util = BOBBA.util or {}
local util = BOBBA.util

function util.copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = util.copy(v) end
	return out
end

-- Sorted list of a table's keys.
function util.keys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
	return out
end

function util.split(s, sep)
	local out = {}
	if s == nil or s == "" then return out end
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
		part = part:match("^%s*(.-)%s*$")
		if part ~= "" then out[#out + 1] = part end
	end
	return out
end

-- An id: lowercase letters, digits, _ . - (what addons may use for ids of anything).
function util.validId(id)
	return type(id) == "string" and id:match("^[a-z0-9_%.%-]+$") ~= nil and #id <= 64
end

-- Fills "{name}" placeholders from vars.
function util.format(text, vars)
	if not vars then return text end
	return (text:gsub("{([%w_]+)}", function(k)
		local v = vars[k]
		if v == nil then return "{" .. k .. "}" end
		return tostring(v)
	end))
end

-- An empty value in SQL parameters (Lua can't keep nil in a list): { "a", BOBBA.util.NULL, 5 }
util.NULL = util.NULL or setmetatable({}, { __tostring = function() return "NULL" end })

-- SQL with ? placeholders and values, made into one statement. `quote` escapes a string the way
-- the database wants it (the platform gives it; GMod's own SQLite has no prepared statements).
function util.bindSql(sqlText, params, quote)
	params = params or {}
	local i = 0
	local out = sqlText:gsub("%?", function()
		i = i + 1
		local v = params[i]
		if v == nil or v == util.NULL then return "NULL" end
		if type(v) == "number" then
			if v ~= v or v == math.huge or v == -math.huge then error("bad number in SQL parameter " .. i) end
			return tostring(v)
		end
		if type(v) == "boolean" then return v and "1" or "0" end
		return quote(tostring(v))
	end)
	if i ~= #params then error(string.format("SQL has %d placeholders but got %d values", i, #params), 2) end
	return out
end

-- Base64 (the camera's pictures travel as text): GMod's own when there is one, else plain Lua
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function util.base64Encode(s)
	if _G.util and _G.util.Base64Encode then return (_G.util.Base64Encode(s):gsub("%s", "")) end
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local q = {}
		for k = 3, 0, -1 do q[4 - k] = B64:sub(math.floor(n / 64 ^ k) % 64 + 1, math.floor(n / 64 ^ k) % 64 + 1) end
		if not b then q[3], q[4] = "=", "=" elseif not c then q[4] = "=" end
		out[#out + 1] = table.concat(q)
	end
	return table.concat(out)
end
local B64R
function util.base64Decode(s)
	s = tostring(s or ""):gsub("[^%w%+/=]", "")
	if _G.util and _G.util.Base64Decode then return _G.util.Base64Decode(s) end
	if not B64R then B64R = {} for i = 1, 64 do B64R[B64:byte(i)] = i - 1 end end
	local out = {}
	for i = 1, #s, 4 do
		local c1, c2, c3, c4 = s:byte(i, i + 3)
		local a, b = B64R[c1], B64R[c2]
		if not a or not b then return nil end
		local c, d = c3 and B64R[c3], c4 and B64R[c4]
		local n = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
		out[#out + 1] = string.char(math.floor(n / 65536) % 256)
		if c then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
		if d then out[#out + 1] = string.char(n % 256) end
	end
	return table.concat(out)
end
