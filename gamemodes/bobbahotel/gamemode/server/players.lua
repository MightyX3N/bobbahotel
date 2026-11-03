-- Players on a GMod server: the hotel is played through the room view, so their GMod character is
-- kept still and out of sight. And the room console commands.

hook.Add("PlayerSpawn", "bobba.players", function(ply)
	ply:SetMoveType(MOVETYPE_NONE)
	ply:SetNoDraw(true)
	ply:SetNotSolid(true)
	ply:DrawShadow(false)
	ply:StripWeapons()
end)

-- No GMod spawn menu, noclip or suicide: the hotel has its own ways
hook.Add("PlayerNoClip", "bobba.players", function() return false end)
hook.Add("CanPlayerSuicide", "bobba.players", function() return false end)

local function reply(ply, text)
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, text) else print(text) end
end

-- bobba_rooms: every room
concommand.Add("bobba_rooms", function(ply)
	for _, r in ipairs(BOBBA.live.list()) do
		local loaded = BOBBA.live.rooms[tonumber(r.id)]
		reply(ply, string.format("%4d  %-30s %-12s by %s%s", r.id, r.name, r.layout, r.owner_name, loaded and ("  (" .. #loaded.order .. " in)") or ""))
	end
end)

-- bobba_room_create <layout> <name...>: make a room and go in
concommand.Add("bobba_room_create", function(ply, _, args)
	if IsValid(ply) and not BOBBA.perms.has(ply, "bobba.room.create") then return end
	local layout = args[1]
	local name = table.concat(args, " ", 2)
	if not layout or name == "" then reply(ply, "bobba_room_create <layout> <name>   (layouts: bobba_preview)") return end
	local key = IsValid(ply) and BOBBA.platform.playerKey(ply) or "server"
	local owner = IsValid(ply) and ply:Nick() or "Bobba Hotel"
	local id, err = BOBBA.live.create(key, owner, layout, name)
	if not id then reply(ply, err) return end
	reply(ply, "room " .. id .. " made")
	if IsValid(ply) then BOBBA.live.enter(ply, id) end
end)

-- bobba_room_wallheight <value>: the wall height of the room you're in (0 to 16, walls are 3.6 + 2 x
-- that high; -1 = follow the hotel's default). For the room's owner and admins.
concommand.Add("bobba_room_wallheight", function(ply, _, args)
	if not IsValid(ply) then print("use it in game, in the room") return end
	local u = BOBBA.live.byPlayer[ply]
	if not u then return end
	local owner = u.room.info.owner == BOBBA.platform.playerKey(ply)
	if not owner and not BOBBA.perms.has(ply, "bobba.admin.settings") then reply(ply, "only the room's owner or an admin") return end
	if not BOBBA.live.setWallHeight(u.room.id, args[1]) then reply(ply, "bobba_room_wallheight <-1, or 0 to 16>") end
end)

-- bobba_default_wallheight <value>: the hotel's default wall height, for rooms that follow it
-- (admins; 0.375 = lined up with Habbo, -1 = Nitro's automatic walls)
concommand.Add("bobba_default_wallheight", function(ply, _, args)
	if IsValid(ply) and not BOBBA.perms.has(ply, "bobba.admin.settings") then return end
	if BOBBA.live.setDefaultWallHeight(args[1]) then reply(ply, "new rooms get wall height " .. BOBBA.live.defaultWallHeight())
	else reply(ply, "bobba_default_wallheight <-1, or 0 to 16>") end
end)

-- bobba_room_floor <id> / bobba_room_wallpaper <id>: the floor or wallpaper of the room you're in
-- (for its owner and admins; "default" puts the default back). bobba_habbo_floors and
-- bobba_habbo_wallpapers list Habbo's.
for _, what in ipairs({ "floor", "wallpaper" }) do
	concommand.Add("bobba_room_" .. what, function(ply, _, args)
		if not IsValid(ply) then print("use it in game, in the room") return end
		local u = BOBBA.live.byPlayer[ply]
		if not u then return end
		if not BOBBA.items.canEdit(ply, u.room) then reply(ply, "only the room's owner or an admin") return end
		if not args[1] or not BOBBA.live.setLook(u.room.id, what, args[1]) then reply(ply, "bobba_room_" .. what .. " <id>   (or default)") end
	end)
end

-- bobba_give <player name or steamid64> <credits|duckets|diamonds|club> <amount>: gives a player money
-- or days of Habbo Club (a minus takes it). For staff with bobba.staff.currency.
concommand.Add("bobba_give", function(ply, _, args)
	if IsValid(ply) and not BOBBA.perms.has(ply, "bobba.staff.currency") then reply(ply, "that's for staff") return end
	local who, what, amount = args[1], args[2], tonumber(args[3])
	if not who or not what or not amount then reply(ply, "bobba_give <player|steamid64> <credits|duckets|diamonds|club> <amount>") return end
	local key
	for _, p in ipairs(player.GetAll()) do
		if p:SteamID64() == who or string.find(string.lower(p:Nick()), string.lower(who), 1, true) then key = BOBBA.platform.playerKey(p) break end
	end
	key = key or (who:match("^%d+$") and who)
	if not key then reply(ply, "no one called " .. who) return end
	if what == "club" then
		BOBBA.wallet.addClub(key, amount)
	elseif not BOBBA.wallet.add(key, what, amount) then
		reply(ply, "couldn't: " .. what .. " isn't credits, duckets or diamonds, or they don't have that much")
		return
	end
	local p = BOBBA.wallet.purse(key)
	reply(ply, string.format("%s now has %d credits, %d duckets, %d diamonds, %d days of club", key, p.credits, p.duckets, p.diamonds, p.clubDays))
end)

-- bobba_wallet_setting <name> [value]: the hotel's money settings (wallet.start.credits,
-- wallet.pay.every, wallet.pay.duckets, club.price.31, catalog.price, ...). For admins.
concommand.Add("bobba_wallet_setting", function(ply, _, args)
	if IsValid(ply) and not BOBBA.perms.has(ply, "bobba.admin.settings") then return end
	if not args[1] then
		for k, v in SortedPairs(BOBBA.wallet.DEFAULTS) do reply(ply, k .. " = " .. BOBBA.wallet.setting(k) .. "  (default " .. v .. ")") end
		return
	end
	if args[2] then
		BOBBA.store.setSetting(args[1], args[2])
		if args[1]:find("^club%.") or args[1]:find("^catalog%.") then BOBBA.catalog.reset() end
	end
	reply(ply, args[1] .. " = " .. tostring(BOBBA.store.setting(args[1], "")))
end)
