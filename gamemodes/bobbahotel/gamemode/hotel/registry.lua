-- The registry: everything the hotel has (furni, clothes, windows, layouts, wired, languages, ...)
-- is registered here by type and id. Bobba's own default content goes through the same calls as
-- anyone's addon, so an addon can add more of anything, or replace something on purpose.
--
--   BOBBA.registry.defineType("furni", { fields = { name = "string", size = "table" }, defaults = {...},
--                                       validate = function(def) ... return true / false, "why" end })
--   BOBBA.registry.register("furni", "bobba_sofa_1", { name = "Sofa", ... })
--   BOBBA.registry.register("furni", "bobba_sofa_1", {...}, { replace = true })   -- replace on purpose
--   BOBBA.registry.get("furni", "bobba_sofa_1")      BOBBA.registry.list("furni")

BOBBA.registry = BOBBA.registry or { types = {}, items = {} }
local reg = BOBBA.registry
local util = BOBBA.util

-- The addon that is loading right now (set by the addon loader), so each entry knows where it came from.
reg.currentAddon = reg.currentAddon or "core"

local FIELD_TYPES = { string = true, number = true, boolean = true, table = true, ["function"] = true }

function reg.defineType(name, spec)
	assert(util.validId(name), "type name must be an id: " .. tostring(name))
	spec = spec or {}
	for field, kind in pairs(spec.fields or {}) do
		local k = kind:gsub("%?$", "")
		assert(FIELD_TYPES[k], "type " .. name .. ": field " .. field .. " has unknown kind " .. kind)
	end
	reg.types[name] = { name = name, fields = spec.fields or {}, defaults = spec.defaults or {}, validate = spec.validate }
	reg.items[name] = reg.items[name] or {}
end

local function check(typeSpec, def)
	for field, kind in pairs(typeSpec.fields) do
		local optional = kind:sub(-1) == "?"
		local k = optional and kind:sub(1, -2) or kind
		local v = def[field]
		if v == nil then
			if not optional then return false, "missing field '" .. field .. "'" end
		elseif type(v) ~= k then
			return false, "field '" .. field .. "' must be a " .. k .. ", not " .. type(v)
		end
	end
	if typeSpec.validate then
		local ok, why = typeSpec.validate(def)
		if not ok then return false, why or "not valid" end
	end
	return true
end

-- Registers (or, with opts.replace, replaces) one entry. Returns true, or false and why.
-- A bad entry is logged and left out; it never stops other entries or addons from loading.
function reg.register(typeName, id, def, opts)
	opts = opts or {}
	local typeSpec = reg.types[typeName]
	if not typeSpec then
		BOBBA.warn("%s: unknown type '%s' for '%s'", reg.currentAddon, tostring(typeName), tostring(id))
		return false, "unknown type"
	end
	if not util.validId(id) then
		BOBBA.warn("%s: bad %s id '%s' (lowercase letters, digits, _ . - only)", reg.currentAddon, typeName, tostring(id))
		return false, "bad id"
	end
	if type(def) ~= "table" then
		BOBBA.warn("%s: %s '%s' must be a table", reg.currentAddon, typeName, id)
		return false, "not a table"
	end
	local entry = util.copy(typeSpec.defaults)
	for k, v in pairs(def) do entry[k] = v end
	local ok, why = check(typeSpec, entry)
	if not ok then
		BOBBA.warn("%s: %s '%s' left out: %s", reg.currentAddon, typeName, id, why)
		return false, why
	end
	local existing = reg.items[typeName][id]
	-- The same addon registering the same id again is a reload (GMod reloads changed files), not a clash.
	if existing and not opts.replace and existing.addon ~= reg.currentAddon then
		BOBBA.warn("%s: %s '%s' already exists (from %s); pass { replace = true } to replace it", reg.currentAddon, typeName, id, existing.addon)
		return false, "exists"
	end
	entry.id = id
	entry.addon = reg.currentAddon
	if existing and existing.addon ~= entry.addon then entry.replaced = existing.addon end
	reg.items[typeName][id] = entry
	BOBBA.events.emit("registered", typeName, id, entry)
	return true
end

function reg.unregister(typeName, id)
	local items = reg.items[typeName]
	if items and items[id] then
		items[id] = nil
		BOBBA.events.emit("unregistered", typeName, id)
		return true
	end
	return false
end

function reg.get(typeName, id)
	local items = reg.items[typeName]
	return items and items[id] or nil
end

-- All entries of a type, sorted by `order` (then id).
function reg.list(typeName)
	local out = {}
	for _, entry in pairs(reg.items[typeName] or {}) do out[#out + 1] = entry end
	table.sort(out, function(a, b)
		local oa, ob = a.order or 0, b.order or 0
		if oa ~= ob then return oa < ob end
		return a.id < b.id
	end)
	return out
end

function reg.count(typeName)
	local n = 0
	for _ in pairs(reg.items[typeName] or {}) do n = n + 1 end
	return n
end
