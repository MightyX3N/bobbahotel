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
