-- Habbo's six classic rooms for new users (the "pick a room" of 2009 to 2012), as the hotel's
-- starter rooms (the gamemode's hotel/starter.lua): one for each colour of Habbo's "noob" furni,
-- each with that colour's table and two stools, a double window, its own wallpaper and floor, and a
-- gift with a lamp of the same colour in it.

if not (BOBBA.registry and BOBBA.registry.types.starter_room) then return end

-- colour number (the furni's *1 ... *6), name, the card's colour (furnidata's), wallpaper, floor
local ROOMS = {
	{ 1, "Orange", { r = 243, g = 132, b = 32 }, "101", "202" },
	{ 2, "Navy", { r = 76, g = 82, b = 110 }, "202", "111" },
	{ 3, "Brown", { r = 152, g = 90, b = 71 }, "1901", "302" },
	{ 4, "Light blue", { r = 148, g = 203, b = 215 }, "1801", "110" },
	{ 5, "Pink", { r = 245, g = 119, b = 159 }, "907", "104" },
	{ 6, "Olive", { r = 177, g = 180, b = 0 }, "212", "107" },
}

for i, r in ipairs(ROOMS) do
	local n = r[1]
	BOBBA.registry.register("starter_room", "habbo_classic_" .. n, {
		name = r[2], color = r[3], order = i, layout = "model_a", wallpaper = r[4], floor = r[5],
		furni = {
			{ kind = "noob_table*" .. n, x = 6, y = 4, dir = 0 },
			{ kind = "noob_stool*" .. n, x = 5, y = 4, dir = 2 },
			{ kind = "noob_stool*" .. n, x = 8, y = 5, dir = 6 },
			{ kind = "noob_window_double", wall = ":w=7,0 l=6,47 r" },
		},
		gift = { kind = "noob_lamp*" .. n, box = "present_gen" .. n, x = 9, y = 8, dir = 0, message = "Welcome to your new room!" },
	})
end
