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
