-- Hotel addons. A Workshop addon (or a folder in garrysmod/addons) becomes a hotel addon by having
--
--   lua/bobbahotel/addons/<id>/addon.lua     returns { id = "<id>", name = "...", version = "1.0",
--                                                      requires = { "other_addon_id", ... },
--                                                      description = "...", author = "...",
--                                                      settings = { ... } (hotel/manage.lua) }
--   lua/bobbahotel/addons/<id>/shared.lua    loaded on server and players   (all optional)
--   lua/bobbahotel/addons/<id>/server.lua    loaded on the server only
--   lua/bobbahotel/addons/<id>/client.lua    loaded on players only
--
-- Addons load in an order where everything an addon requires loads before it. An addon whose
-- requirement is missing or switched off doesn't load (and says why). Server owners switch addons
-- off with the setting "disabled_addons" (ids separated by commas).

BOBBA.addons = BOBBA.addons or { loaded = {}, skipped = {} }
local addons = BOBBA.addons
local util = BOBBA.util

-- Reads the manifests (id -> manifest). `found` is a list of { folder = "...", manifest = {...} }.
function addons.checkManifests(found)
	local byId, problems = {}, {}
	for _, f in ipairs(found) do
		local m = f.manifest
		if type(m) ~= "table" then
			problems[#problems + 1] = { id = f.folder, why = "addon.lua must return a table" }
		elseif m.id ~= f.folder then
			problems[#problems + 1] = { id = f.folder, why = "id in addon.lua ('" .. tostring(m.id) .. "') must match its folder name" }
		elseif not util.validId(m.id) then
			problems[#problems + 1] = { id = f.folder, why = "bad id (lowercase letters, digits, _ . - only)" }
		else
			m.name = type(m.name) == "string" and m.name or m.id
			m.version = type(m.version) == "string" and m.version or "?"
			m.requires = type(m.requires) == "table" and m.requires or {}
			m.folder = f.folder
			byId[m.id] = m
		end
	end
	return byId, problems
end

-- The load order: requirements first; ties alphabetical. Returns order, skipped (id -> why).
function addons.order(byId, disabled)
	disabled = disabled or {}
	local skipped = {}
	for id in pairs(disabled) do
		if byId[id] then skipped[id] = "switched off by the server" end
	end
	-- Anything needing a missing or skipped addon is skipped too (repeat until nothing changes).
	local changed = true
	while changed do
		changed = false
		for _, id in ipairs(util.keys(byId)) do
			if not skipped[id] then
				for _, need in ipairs(byId[id].requires) do
					if not byId[need] then
						skipped[id] = "needs '" .. tostring(need) .. "', which isn't installed"
						changed = true
						break
					elseif skipped[need] then
						skipped[id] = "needs '" .. need .. "', which isn't loading"
						changed = true
						break
					end
				end
			end
		end
	end
	local order, state = {}, {}
	local function visit(id, path)
		if state[id] == "done" or skipped[id] then return end
		if state[id] == "visiting" then
			for _, p in ipairs(path) do skipped[p] = "requirement loop: " .. table.concat(path, " -> ") .. " -> " .. id end
			return
		end
		state[id] = "visiting"
		path[#path + 1] = id
		local reqs = util.copy(byId[id].requires)
		table.sort(reqs)
		for _, need in ipairs(reqs) do visit(need, path) end
		path[#path] = nil
		state[id] = "done"
		if not skipped[id] then order[#order + 1] = id end
	end
	for _, id in ipairs(util.keys(byId)) do visit(id, {}) end
	-- Something in a loop may have been added before the loop was found; take it out again.
	local final = {}
	for _, id in ipairs(order) do
		if not skipped[id] then final[#final + 1] = id end
	end
	return final, skipped
end

-- Finds, orders and loads every hotel addon. Uses the platform to list folders and run files.
function addons.loadAll()
	local p = BOBBA.platform
	local found = {}
	for _, folder in ipairs(p.addonFolders()) do
		local ok, manifest = BOBBA.safe("addon " .. folder .. " addon.lua", p.runAddonFile, folder, "addon.lua")
		found[#found + 1] = { folder = folder, manifest = ok and manifest or nil }
	end
	local byId, problems = addons.checkManifests(found)
	-- (every one found, on or off: the hotel's Manage screen lists them)
	addons.all = byId
	for _, prob in ipairs(problems) do
		addons.skipped[prob.id] = prob.why
		BOBBA.warn("addon %s skipped: %s", prob.id, prob.why)
	end
	local disabled = {}
	for _, id in ipairs(util.split(p.disabledAddons and p.disabledAddons() or "", ",")) do disabled[id] = true end
	local order, skipped = addons.order(byId, disabled)
	for id, why in pairs(skipped) do
		addons.skipped[id] = why
		BOBBA.warn("addon %s skipped: %s", id, why)
	end
	for _, id in ipairs(order) do
		local m = byId[id]
		BOBBA.registry.currentAddon = id
		p.loadAddon(m.folder)
		BOBBA.registry.currentAddon = "core"
		addons.loaded[id] = m
		BOBBA.info("addon loaded: %s %s", m.name, m.version)
	end
	BOBBA.events.emit("addonsLoaded", order)
	return order
end
