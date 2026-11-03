-- The core's files, in load order. "PLATFORM" is where the platform layer is loaded: on GMod
-- platform/gmod.lua, in the tests a stand-in (later also the custom server's).
return {
	"hotel/core.lua",
	"hotel/util.lua",
	"hotel/events.lua",
	"hotel/registry.lua",
	"PLATFORM",
	"hotel/lang.lua",
	"lang/en.lua",
	"hotel/perms.lua",
	"hotel/store.lua",
	"nitro/port.lua",
	"nitro/avatar.lua",
	"nitro/furni.lua",
	"hotel/rooms.lua",
	"hotel/layouts.lua",
	"hotel/pathfinder.lua",
	"hotel/roomlive.lua",
	"hotel/items.lua",
	"hotel/addons.lua",
}
