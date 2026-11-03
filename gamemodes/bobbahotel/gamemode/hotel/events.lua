-- Events: the core and addons announce things (`emit`) and listen for them (`on`).
-- A listener that errors is logged and skipped; the others still run.

BOBBA.events = BOBBA.events or { listeners = {} }
local events = BOBBA.events

-- Listen for an event. `id` names the listener so it can be replaced or removed.
function events.on(name, id, fn)
	assert(type(name) == "string" and type(id) == "string" and type(fn) == "function", "events.on(name, id, fn)")
	local list = events.listeners[name]
	if not list then
		list = {}
		events.listeners[name] = list
	end
	for i, l in ipairs(list) do
		if l.id == id then
			list[i] = { id = id, fn = fn }
			return
		end
	end
	list[#list + 1] = { id = id, fn = fn }
end

function events.off(name, id)
	local list = events.listeners[name]
	if not list then return end
	for i, l in ipairs(list) do
		if l.id == id then
			table.remove(list, i)
			return
		end
	end
end

-- Announce an event. Returns the first non-nil value a listener returned (so a listener can say
-- "no" to something, e.g. return false to block it).
function events.emit(name, ...)
	local list = events.listeners[name]
	if not list then return nil end
	local copy = {}
	for i, l in ipairs(list) do copy[i] = l end
	for _, l in ipairs(copy) do
		local ok, res = pcall(l.fn, ...)
		if not ok then
			BOBBA.err("event %s, listener %s: %s", name, l.id, tostring(res))
		elseif res ~= nil then
			return res
		end
	end
	return nil
end
