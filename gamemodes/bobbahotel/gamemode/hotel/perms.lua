-- Permissions for staff actions. Each one has a name and who gets it when nobody configured it
-- ("user", "admin" or "superadmin"). On GMod they are handed to CAMI, so ULX, SAM and other admin
-- mods show them in their own menus; without an admin mod, GMod's admin/superadmin decide.
--
--   BOBBA.perms.define("bobba.staff.deletefurni", { default = "admin", description = "Delete furni for good" })
--   BOBBA.perms.has(player, "bobba.staff.deletefurni")  --> true / false

BOBBA.perms = BOBBA.perms or {}
local perms = BOBBA.perms

local LEVELS = { user = true, admin = true, superadmin = true }

BOBBA.registry.defineType("permission", {
	fields = { default = "string", description = "string" },
	defaults = { default = "superadmin", description = "" },
	validate = function(def)
		if not LEVELS[def.default] then return false, "default must be user, admin or superadmin" end
		return true
	end,
})

function perms.define(name, spec)
	spec = spec or {}
	local ok = BOBBA.registry.register("permission", name, { default = spec.default, description = spec.description }, { replace = spec.replace })
	if ok then BOBBA.platform.definePermission(name, BOBBA.registry.get("permission", name).default, spec.description or "") end
	return ok
end

-- Does this player have the permission? Unknown permissions are denied.
function perms.has(player, name)
	local def = BOBBA.registry.get("permission", name)
	if not def then
		BOBBA.warn("permission '%s' checked but never defined", tostring(name))
		return false
	end
	return BOBBA.platform.hasPermission(player, name, def.default) == true
end

-- The hotel's own staff permissions.
perms.define("bobba.staff.deletefurni", { default = "admin", description = "Delete furni for good (it doesn't go to an inventory)" })
perms.define("bobba.staff.place", { default = "admin", description = "Place furni straight from the catalogue" })
perms.define("bobba.staff.kick", { default = "admin", description = "Kick players out of any room" })
perms.define("bobba.staff.anyroom", { default = "admin", description = "Act as owner in every room" })
perms.define("bobba.staff.givecoins", { default = "superadmin", description = "Give or take coins and club time" })
perms.define("bobba.admin.catalogue", { default = "superadmin", description = "Edit the catalogue and prices" })
perms.define("bobba.admin.settings", { default = "superadmin", description = "Change hotel settings (name, lobby, ...)" })
