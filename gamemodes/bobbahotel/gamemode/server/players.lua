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
