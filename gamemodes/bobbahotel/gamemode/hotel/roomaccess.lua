-- Who may come into a room and what they may do there (server), the way Arcturus does it (with the
-- gaps it has filled in, like retail Habbo): the room's settings (Nitro's room settings window),
-- rights, the doorbell and the password, kicking, banning and muting, deleting a room, favourites
-- and your home room, the room categories, and the hotel's name.
--
-- Rights levels (sent to each player as room.rights { level }):
--   0 none, 1 rights (may build, answer the doorbell, kick/ban/mute as the room allows), 4 owner,
--   5 staff acting as owner (bobba.staff.anyroom)
--
-- Messages from players:
--   room.settings.get { id }                 -> room.settings { ... } (owner/staff)
--   room.settings.save { id, name, description, state, password, maxUsers, category, tags = {..},
--       trade, allowPets, allowPetsEat, allowWalkthrough, hideWall, wallThickness, floorThickness, movement,
--       chatMode, chatWeight, chatSpeed, chatDistance, chatProtection, whoMute, whoKick, whoBan }
--                                             -> room.settings.saved { id } or room.settings.error { id, code }
--   room.delete { id }
--   room.rights.give { unit } / { key, name }   room.rights.remove { keys = {..} }
--   room.rights.removeAll {}                    room.rights.removeOwn { id }
--   room.kick { unit }   room.ban { unit, kind = "hour" | "day" | "perm" }   room.unban { id, key }
--   room.mute { unit, minutes = 2 | 5 | 10 }    room.muteAll {}
--   room.doorbell.answer { name, accept }
--   room.leave {}                              (to the hotel view)
--   room.favourite { id, on }   room.home { id }
--   navigator.roominfo { id }                  -> navigator.roominfo { room }
-- Messages to players:
--   room.rights { level }   room.info { ... }  (the room's settings everyone sees, after a change)
--   room.denied { id, reason = "banned" | "full" | "password" | "doorbell" | "noanswer" | "kicked" }
--   room.password { id, name }   (the room wants its password: ask for it)
--   room.doorbell.waiting { id, name }   room.doorbell.ring { name }   room.doorbell.hide { name }
--   room.hotelview {}   room.muted { seconds }   room.muteAll { on }
--   room.favourites { ids = {..} }   room.home { id }   hotel.info { name }

BOBBA.access = BOBBA.access or {}
local A = BOBBA.access
local live = BOBBA.live

A.STATES = { [0] = "open", [1] = "doorbell", [2] = "password", [3] = "invisible" }
A.MAX_USERS = { 10, 15, 20, 25, 30, 35, 40, 45, 50 } -- (Nitro's settings: 10 to 50 in fives)
A.MAX_USERS_STAFF = 100
A.MAX_FAVOURITES = 30
A.MAX_TAGS, A.TAG_LENGTH = 2, 15
A.NAME_LENGTH, A.DESCRIPTION_LENGTH, A.PASSWORD_LENGTH = 50, 255, 20
A.STAFF_TAGS = { "staff", "official", "habbo" }
A.BANS = { hour = 3600, day = 86400, perm = 315360000 }
A.MUTES = { [2] = true, [5] = true, [10] = true }

-- Habbo's room categories (Arcturus navigator_flatcats): official is for staff
A.CATEGORIES = {
	{ id = 1, code = "BC" }, { id = 2, code = "BUILDING" }, { id = 3, code = "CHAT" }, { id = 4, code = "FANSITE" },
	{ id = 5, code = "GAMES" }, { id = 6, code = "HELP" }, { id = 7, code = "LIFE" }, { id = 8, code = "OFFICIAL", staff = true },
	{ id = 9, code = "PARTY" }, { id = 10, code = "PERSONAL" }, { id = 11, code = "REVIEWS" }, { id = 12, code = "TRADING" },
}

BOBBA.perms.define("bobba.staff.enteranyroom", { default = "admin", description = "Go into any room (locked, password, banned, full)" })
BOBBA.perms.define("bobba.staff.unkickable", { default = "admin", description = "Can't be kicked, banned or muted in rooms" })

function A.migrate()
	BOBBA.store.migrate("core.015_room_access", {
		"ALTER TABLE bobbahotel_rooms ADD COLUMN state INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN password TEXT NOT NULL DEFAULT ''",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN tags TEXT NOT NULL DEFAULT ''",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN allow_pets INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN allow_pets_eat INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN allow_walkthrough INTEGER NOT NULL DEFAULT 1",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN hide_wall INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN wall_thickness INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN floor_thickness INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN chat_mode INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN chat_weight INTEGER NOT NULL DEFAULT 1",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN chat_speed INTEGER NOT NULL DEFAULT 1",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN chat_distance INTEGER NOT NULL DEFAULT 50",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN chat_protection INTEGER NOT NULL DEFAULT 2",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN who_mute INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN who_kick INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE bobbahotel_rooms ADD COLUMN who_ban INTEGER NOT NULL DEFAULT 0",
		"CREATE TABLE bobbahotel_room_rights (room INTEGER NOT NULL, key TEXT NOT NULL, name TEXT NOT NULL, PRIMARY KEY (room, key))",
		"CREATE TABLE bobbahotel_room_bans (room INTEGER NOT NULL, key TEXT NOT NULL, name TEXT NOT NULL, ends INTEGER NOT NULL, PRIMARY KEY (room, key))",
		"CREATE TABLE bobbahotel_favourites (key TEXT NOT NULL, room INTEGER NOT NULL, PRIMARY KEY (key, room))",
		"CREATE TABLE bobbahotel_home_rooms (key TEXT PRIMARY KEY, room INTEGER NOT NULL)",
	})
	-- how people may move in the room: 0 both, 1 clicking only, 2 steering only (roomlive.lua)
	BOBBA.store.migrate("core.017_room_movement", {
		"ALTER TABLE bobbahotel_rooms ADD COLUMN movement INTEGER NOT NULL DEFAULT 0",
	})
end

local function P() return BOBBA.platform end
local function num(v, d) return tonumber(v) or d end

-- --- who someone is in a room ----------------------------------------------------------------------
function A.isOwner(player, info)
	if not player then return true end
	return info.owner == P().playerKey(player)
end
function A.isStaff(player) return player ~= nil and BOBBA.perms.has(player, "bobba.staff.anyroom") end

function A.rightsList(roomId)
	local rows = BOBBA.store.query("SELECT key, name FROM bobbahotel_room_rights WHERE room = ? ORDER BY name", { tonumber(roomId) })
	local out = {}
	for _, r in ipairs(rows) do out[#out + 1] = { key = r.key, name = r.name } end
	return out
end
function A.hasRightsKey(roomId, key)
	return BOBBA.store.row("SELECT key FROM bobbahotel_room_rights WHERE room = ? AND key = ?", { tonumber(roomId), tostring(key) }) ~= nil
end

-- 0 none, 1 rights, 4 owner, 5 staff
function A.level(player, info)
	if not player then return 4 end
	if A.isOwner(player, info) then return 4 end
	if A.isStaff(player) then return 5 end
	if A.hasRightsKey(info.id, P().playerKey(player)) then return 1 end
	return 0
end
function A.hasRights(player, info) return A.level(player, info) > 0 end
function A.ownerLevel(player, info) return A.level(player, info) >= 4 end

-- what the room's kick/ban/mute settings let this player do to others (0 = only the owner,
-- 1 = rights holders, 2 = everyone (kick only))
local function allowedBy(option, level)
	if level >= 4 then return true end
	if option >= 2 then return true end
	if option == 1 then return level >= 1 end
	return false
end
function A.canKick(player, info) return allowedBy(num(info.who_kick, 0), A.level(player, info)) end
function A.canBan(player, info) return allowedBy(num(info.who_ban, 0), A.level(player, info)) end
function A.canMute(player, info) return allowedBy(num(info.who_mute, 0), A.level(player, info)) end

-- can't be kicked/banned/muted: the owner, staff; banning and muting not rights holders either
local function protected(target, info, strict)
	if not target.player then return true end
	if A.isOwner(target.player, info) then return true end
	if BOBBA.perms.has(target.player, "bobba.staff.unkickable") then return true end
	if strict and A.hasRightsKey(info.id, target.key) then return true end
	return false
end

-- --- the room's data as everyone may see it ---------------------------------------------------------
function A.tags(info)
	local out = {}
	for t in tostring(info.tags or ""):gmatch("[^;]+") do out[#out + 1] = t end
	return out
end

function A.publicInfo(info, r)
	return {
		id = info.id, name = info.name, description = info.description or "", owner = info.owner_name,
		state = A.STATES[num(info.state, 0)] or "open", tags = A.tags(info), category = num(info.category, 0),
		maxUsers = num(info.max_users, 25), trade = num(info.trade, 0),
		allowPets = num(info.allow_pets, 0) == 1, allowWalkthrough = num(info.allow_walkthrough, 1) == 1,
		hideWall = num(info.hide_wall, 0) == 1, wallThickness = num(info.wall_thickness, 0), floorThickness = num(info.floor_thickness, 0),
		chatMode = num(info.chat_mode, 0), chatWeight = num(info.chat_weight, 1), chatSpeed = num(info.chat_speed, 1),
		chatDistance = num(info.chat_distance, 50), chatProtection = num(info.chat_protection, 2),
		whoMute = num(info.who_mute, 0), whoKick = num(info.who_kick, 0), whoBan = num(info.who_ban, 0),
		muted = r and r.mutedAll or false, ownerKey = info.owner, movement = num(info.movement, 0),
	}
end

-- what one player gets in room.load: their level, and what they may do
function A.forPlayer(r, u)
	local level = u.player and A.level(u.player, r.info) or 0
	local info = A.publicInfo(r.info, r)
	info.level = level
	info.canKick = u.player ~= nil and A.canKick(u.player, r.info)
	info.canBan = u.player ~= nil and A.canBan(u.player, r.info)
	info.canMute = u.player ~= nil and A.canMute(u.player, r.info)
	-- (the owner knows who has rights: the avatar menu's give / remove rights)
	if level >= 4 then
		-- (a list: JSON would turn SteamID keys into numbers)
		info.rightsKeys = {}
		for _, x in ipairs(A.rightsList(r.id)) do info.rightsKeys[#info.rightsKeys + 1] = x.key end
	end
	return info
end

local function players(r)
	local out = {}
	for _, id in ipairs(r.order) do local u = r.units[id] if u.player then out[#out + 1] = u.player end end
	return out
end

-- tell everyone in a loaded room its settings and their rights again
function A.refreshRoom(roomId)
	local r = live.rooms[tonumber(roomId)]
	if not r then return end
	r.info = live.info(r.id)
	for _, id in ipairs(r.order) do
		local u = r.units[id]
		if u.player then
			P().send("room.info", A.forPlayer(r, u), u.player)
		end
	end
end

-- --- settings -----------------------------------------------------------------------------------------
local function bansOf(roomId)
	local now = P().time()
	BOBBA.store.query("DELETE FROM bobbahotel_room_bans WHERE ends <= ?", { now })
	local rows = BOBBA.store.query("SELECT key, name, ends FROM bobbahotel_room_bans WHERE room = ? ORDER BY name", { tonumber(roomId) })
	local out = {}
	for _, b in ipairs(rows) do out[#out + 1] = { key = b.key, name = b.name, ends = tonumber(b.ends) } end
	return out
end
A.bans = bansOf

function A.settingsFor(player, id)
	local info = live.info(id)
	if not info or not A.ownerLevel(player, info) then return nil end
	local s = A.publicInfo(info, live.rooms[info.id])
	s.hasPassword = (info.password or "") ~= ""
	s.rights = A.rightsList(info.id)
	s.bans = bansOf(info.id)
	s.maxUsersAllowed = A.isStaff(player) and A.MAX_USERS_STAFF or 50
	return s
end

local function clamp(v, lo, hi, d)
	v = math.floor(tonumber(v) or d)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end
local function clean(s, n)
	s = tostring(s or ""):gsub("[%c]", " ")
	s = s:match("^%s*(.-)%s*$")
	-- (whole UTF-8 characters)
	local out, k = {}, 0
	for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		k = k + 1
		if k > n then break end
		out[#out + 1] = ch
	end
	return table.concat(out)
end
local function utf8len(s) local n = 0 for _ in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end return n end

-- RoomSettingsSaveEvent, checked. Returns true or false and an error code (Nitro's
-- RoomSettingsErrorEvent codes: 5 password required, 7 name missing, 11/12 tags, 13 tags too long)
function A.save(player, data)
	local info = live.info(data.id)
	if not info then return false, 0 end
	if not A.ownerLevel(player, info) then return false, 0 end
	local name = clean(data.name, 60)
	if name == "" then return false, 7 end
	name = clean(name, A.NAME_LENGTH)
	local desc = tostring(data.description or ""):gsub("[%c]", " ")
	if utf8len(desc) > A.DESCRIPTION_LENGTH then return false, 10 end
	local state = clamp(data.state, 0, 3, 0)
	local password = clean(data.password, A.PASSWORD_LENGTH)
	if state == 2 and password == "" and (info.password or "") == "" then return false, 5 end
	if password == "" then password = info.password or "" end
	local tags = {}
	for i, t in ipairs(type(data.tags) == "table" and data.tags or {}) do
		if i > A.MAX_TAGS then break end
		t = tostring(t):gsub("[%c;]", ""):match("^%s*(.-)%s*$")
		if utf8len(t) > A.TAG_LENGTH then return false, 13 end
		if t ~= "" then
			if not A.isStaff(player) then
				for _, bad in ipairs(A.STAFF_TAGS) do if t:lower():find(bad, 1, true) then return false, 12 end end
			end
			tags[#tags + 1] = t
		end
	end
	local maxAllowed = A.isStaff(player) and A.MAX_USERS_STAFF or 50
	local maxUsers = clamp(data.maxUsers, 1, maxAllowed, num(info.max_users, 25))
	local category = num(info.category, 0)
	local want = math.floor(num(data.category, category))
	for _, c in ipairs(A.CATEGORIES) do
		if c.id == want and (not c.staff or A.isStaff(player)) then category = want end
	end
	if want == 0 then category = 0 end
	BOBBA.store.query([[UPDATE bobbahotel_rooms SET name = ?, description = ?, state = ?, password = ?, tags = ?, max_users = ?,
		category = ?, trade = ?, allow_pets = ?, allow_pets_eat = ?, allow_walkthrough = ?, hide_wall = ?, wall_thickness = ?,
		floor_thickness = ?, chat_mode = ?, chat_weight = ?, chat_speed = ?, chat_distance = ?, chat_protection = ?,
		who_mute = ?, who_kick = ?, who_ban = ?, movement = ? WHERE id = ?]], {
		name, desc, state, password, (#tags > 0) and (table.concat(tags, ";") .. ";") or "", maxUsers,
		category, clamp(data.trade, 0, 2, 0), data.allowPets and 1 or 0, data.allowPetsEat and 1 or 0,
		data.allowWalkthrough and 1 or 0, data.hideWall and 1 or 0, clamp(data.wallThickness, -2, 1, 0),
		clamp(data.floorThickness, -2, 1, 0), clamp(data.chatMode, 0, 1, 0), clamp(data.chatWeight, 0, 2, 1),
		clamp(data.chatSpeed, 0, 2, 1), clamp(math.abs(num(data.chatDistance, 50)), 0, 99, 50), clamp(data.chatProtection, 0, 2, 2),
		clamp(data.whoMute, 0, 1, 0), clamp(data.whoKick, 0, 2, 0), clamp(data.whoBan, 0, 1, 0),
		clamp(data.movement, 0, 2, num(info.movement, 0)), info.id,
	})
	A.refreshRoom(info.id)
	BOBBA.events.emit("roomSettingsSaved", info.id)
	return true
end

-- --- rights -------------------------------------------------------------------------------------------
local function unitIn(r, unitId)
	return r and r.units[tonumber(unitId) or -1]
end
local function unitByKey(r, key)
	if not r then return nil end
	for _, id in ipairs(r.order) do local u = r.units[id] if u.key == key then return u end end
end

local function sendLevel(r, u)
	if u and u.player then P().send("room.info", A.forPlayer(r, u), u.player) end
end

-- the owner's rights list, again, to the owners in the room
local function sendRightsList(r)
	if not r then return end
	for _, id in ipairs(r.order) do
		local u = r.units[id]
		if u.player and A.ownerLevel(u.player, r.info) then
			P().send("room.rights.list", { id = r.id, rights = A.rightsList(r.id) }, u.player)
		end
	end
end

function A.giveRights(player, r, key, name)
	if not A.ownerLevel(player, r.info) then return false, "only the room's owner can give rights" end
	if key == r.info.owner then return false, "the owner has them" end
	if A.hasRightsKey(r.id, key) then return true end
	BOBBA.store.query("INSERT OR REPLACE INTO bobbahotel_room_rights (room, key, name) VALUES (?, ?, ?)", { r.id, tostring(key), tostring(name) })
	sendLevel(r, unitByKey(r, key))
	sendRightsList(r)
	return true
end

-- (taking rights sends what they built in the room back to their inventory, as Arcturus does)
local function ejectFurni(r, key, roomId)
	if not r then
		BOBBA.store.query("UPDATE bobbahotel_items SET room = 0, x = 0, y = 0, z = 0, wall = '' WHERE room = ? AND owner = ?", { roomId, key })
		return
	end
	local list = {}
	for id, it in pairs(r.items) do if it.owner == key then list[#list + 1] = id end end
	for _, id in ipairs(list) do BOBBA.items.pickup(r, nil, id) end
end

function A.removeRights(player, roomId, keys)
	local info = live.info(roomId)
	if not info then return false end
	local r = live.rooms[info.id]
	for _, key in ipairs(keys) do
		key = tostring(key)
		local own = player and P().playerKey(player) == key
		if own or A.ownerLevel(player, info) then
			if A.hasRightsKey(info.id, key) then
				BOBBA.store.query("DELETE FROM bobbahotel_room_rights WHERE room = ? AND key = ?", { info.id, key })
				ejectFurni(r, key, info.id)
				if r then sendLevel(r, unitByKey(r, key)) end
			end
		end
	end
	sendRightsList(r)
	return true
end

function A.removeAllRights(player, r)
	if not A.ownerLevel(player, r.info) then return false end
	local keys = {}
	for _, x in ipairs(A.rightsList(r.id)) do keys[#keys + 1] = x.key end
	return A.removeRights(player, r.id, keys)
end

-- --- kick, ban, mute ----------------------------------------------------------------------------------
-- out of the room to the hotel view
function A.toHotelView(player)
	live.leave(player)
	P().send("room.hotelview", {}, player)
end

function A.kick(player, r, unitId)
	local t = unitIn(r, unitId)
	if not t or not t.player or t.player == player then return false end
	if not A.canKick(player, r.info) then return false, "you can't kick here" end
	if protected(t, r.info, false) then return false, "you can't kick " .. t.name end
	P().send("room.denied", { id = r.id, reason = "kicked" }, t.player)
	-- (Habbo: they walk to the door, then they're out; out at once when the way there is short)
	local door = r.layout.door
	local walking = live.walk(t.player, door.x, door.y)
	t.kicked = true
	if not walking or not t.path or #t.path <= 1 then
		A.toHotelView(t.player)
	end
	return true
end

function A.ban(player, r, unitId, kind)
	local t = unitIn(r, unitId)
	local seconds = A.BANS[kind]
	if not t or not t.player or not seconds or t.player == player then return false end
	if not A.canBan(player, r.info) then return false, "you can't ban here" end
	if protected(t, r.info, true) then return false, "you can't ban " .. t.name end
	BOBBA.store.query("INSERT OR REPLACE INTO bobbahotel_room_bans (room, key, name, ends) VALUES (?, ?, ?, ?)", { r.id, t.key, t.name, P().time() + seconds })
	local target = t.player
	A.toHotelView(target)
	P().send("room.denied", { id = r.id, reason = "banned" }, target)
	return true
end

function A.isBanned(roomId, key)
	local b = BOBBA.store.row("SELECT ends FROM bobbahotel_room_bans WHERE room = ? AND key = ?", { tonumber(roomId), tostring(key) })
	if not b then return false end
	if tonumber(b.ends) <= P().time() then
		BOBBA.store.query("DELETE FROM bobbahotel_room_bans WHERE room = ? AND key = ?", { tonumber(roomId), tostring(key) })
		return false
	end
	return true
end

function A.unban(player, roomId, key)
	local info = live.info(roomId)
	if not info or not A.ownerLevel(player, info) then return false end
	BOBBA.store.query("DELETE FROM bobbahotel_room_bans WHERE room = ? AND key = ?", { info.id, tostring(key) })
	return true
end

function A.mute(player, r, unitId, minutes)
	local t = unitIn(r, unitId)
	minutes = math.floor(tonumber(minutes) or 0)
	if not t or not t.player or not A.MUTES[minutes] then return false end
	if not A.canMute(player, r.info) then return false, "you can't mute here" end
	if protected(t, r.info, true) then return false, "you can't mute " .. t.name end
	r.mutes = r.mutes or {}
	r.mutes[t.key] = P().clock() + minutes * 60
	P().send("room.muted", { seconds = minutes * 60 }, t.player)
	return true
end

-- seconds left of someone's mute in this room (0 = not muted)
function A.mutedFor(r, u)
	if u.player and A.hasRights(u.player, r.info) then return 0 end
	local untilT = r.mutes and r.mutes[u.key]
	if not untilT then return 0 end
	local left = untilT - P().clock()
	if left <= 0 then r.mutes[u.key] = nil return 0 end
	return math.ceil(left)
end

function A.muteAll(player, r)
	if not A.ownerLevel(player, r.info) then return false end
	r.mutedAll = not r.mutedAll
	for _, p in ipairs(players(r)) do P().send("room.muteAll", { on = r.mutedAll }, p) end
	A.refreshRoom(r.id)
	return true
end

-- --- going in: banned, the doorbell, the password, full -----------------------------------------------
-- (live.enter asks): true to let them in now, or false and why ("banned", "full", "password",
-- "wrongpassword", "doorbell", "noanswer", "invisible")
function A.check(r, player, opts)
	opts = opts or {}
	local info = r.info
	local key = P().playerKey(player)
	local staff = BOBBA.perms.has(player, "bobba.staff.enteranyroom")
	if not staff and A.isBanned(r.id, key) then return false, "banned" end
	local rights = A.hasRights(player, info)
	if not (opts.override or rights or staff or num(info.state, 0) == 0) then
		local state = num(info.state, 0)
		if state == 1 then return false, "doorbell" end
		if state == 2 then
			if not opts.password or opts.password == "" then return false, "password" end
			if tostring(opts.password):lower() ~= tostring(info.password or ""):lower() then return false, "wrongpassword" end
		elseif state == 3 then
			return false, "invisible"
		end
	end
	if not (rights or staff) and #r.order >= num(info.max_users, 25) then return false, "full" end
	return true
end

-- the doorbell: the rights holders in the room hear it; nobody there, no answer
function A.ring(r, player)
	local list = {}
	for _, id in ipairs(r.order) do
		local u = r.units[id]
		if u.player and A.hasRights(u.player, r.info) then list[#list + 1] = u.player end
	end
	if #list == 0 then return false end
	local name = P().playerName(player)
	r.queue = r.queue or {}
	r.queue[player] = name
	A.waiting = A.waiting or {}
	A.waiting[player] = r.id
	P().send("room.doorbell.ring", { name = name }, list)
	P().send("room.doorbell.waiting", { id = r.id, name = r.info.name }, player)
	return true
end

local function unqueue(player)
	local id = A.waiting and A.waiting[player]
	if not id then return end
	A.waiting[player] = nil
	local r = live.rooms[id]
	if r and r.queue and r.queue[player] then
		local name = r.queue[player]
		r.queue[player] = nil
		for _, p in ipairs(players(r)) do P().send("room.doorbell.hide", { name = name }, p) end
	end
end
A.unqueue = unqueue

function A.answer(player, r, name, accept)
	if not A.hasRights(player, r.info) then return false end
	for p, n in pairs(r.queue or {}) do
		if n:lower() == tostring(name):lower() then
			unqueue(p)
			if accept then
				local ok, why = live.enter(p, r.id, nil, { override = true })
				if not ok then P().send("room.denied", { id = r.id, reason = why or "full" }, p) end
			else
				P().send("room.denied", { id = r.id, reason = "doorbell" }, p)
			end
			return true
		end
	end
	return false
end

local function denyQueue(r)
	for p in pairs(r.queue or {}) do
		if A.waiting then A.waiting[p] = nil end
		P().send("room.denied", { id = r.id, reason = "noanswer" }, p)
	end
	r.queue = {}
end
A.denyQueue = denyQueue

-- (every room tick: nobody with rights left in a room, nobody can open its door)
function A.tick()
	for _, r in pairs(live.rooms) do
		if r.queue and next(r.queue) then
			local any = false
			for _, id in ipairs(r.order) do
				local u = r.units[id]
				if u.player and A.hasRights(u.player, r.info) then any = true break end
			end
			if not any then denyQueue(r) end
		end
	end
end

-- --- deleting a room -------------------------------------------------------------------------------------
function A.delete(player, id)
	local info = live.info(id)
	if not info then return false, "no such room" end
	if not A.ownerLevel(player, info) then return false, "only the room's owner can delete it" end
	if tonumber(BOBBA.store.setting("home_room", "")) == info.id then return false, "the hotel's first room can't be deleted" end
	local r = live.rooms[info.id]
	-- everyone out
	if r then
		local list = players(r)
		for _, p in ipairs(list) do A.toHotelView(p) end
		live.rooms[info.id] = nil
	end
	-- every furni back to its owner's inventory
	local rows = BOBBA.store.query("SELECT DISTINCT owner FROM bobbahotel_items WHERE room = ?", { info.id })
	BOBBA.store.query("UPDATE bobbahotel_items SET room = 0, x = 0, y = 0, z = 0, wall = '' WHERE room = ?", { info.id })
	for _, row in ipairs(rows) do
		local p = A.playerFor(row.owner)
		if p then P().send("inventory.items", BOBBA.inventory.list(row.owner), p) end
	end
	for _, t in ipairs({ "bobbahotel_room_rights", "bobbahotel_room_bans", "bobbahotel_favourites" }) do
		BOBBA.store.query("DELETE FROM " .. t .. " WHERE room = ?", { info.id })
	end
	BOBBA.store.query("DELETE FROM bobbahotel_home_rooms WHERE room = ?", { info.id })
	BOBBA.store.query("DELETE FROM bobbahotel_rooms WHERE id = ?", { info.id })
	BOBBA.events.emit("roomDeleted", info.id)
	return true
end

function A.playerFor(key)
	for player, u in pairs(live.byPlayer) do if u.key == key then return player end end
	if BOBBA.wallet and BOBBA.wallet.online then
		for player, k in pairs(BOBBA.wallet.online) do if k == key then return player end end
	end
end

-- --- favourites and home room ------------------------------------------------------------------------------
function A.favourites(key)
	local rows = BOBBA.store.query("SELECT room FROM bobbahotel_favourites WHERE key = ? ORDER BY room", { tostring(key) })
	local out = {}
	for _, r in ipairs(rows) do out[#out + 1] = tonumber(r.room) end
	return out
end
function A.setFavourite(key, id, on)
	id = tonumber(id)
	if not id or not live.info(id) then return false end
	if on then
		if #A.favourites(key) >= A.MAX_FAVOURITES then return false, "you have too many favourite rooms" end
		BOBBA.store.query("INSERT OR IGNORE INTO bobbahotel_favourites (key, room) VALUES (?, ?)", { tostring(key), id })
	else
		BOBBA.store.query("DELETE FROM bobbahotel_favourites WHERE key = ? AND room = ?", { tostring(key), id })
	end
	return true
end
function A.home(key)
	local r = BOBBA.store.row("SELECT room FROM bobbahotel_home_rooms WHERE key = ?", { tostring(key) })
	local id = r and tonumber(r.room)
	if id and id ~= 0 and live.info(id) then return id end
	return nil
end
function A.setHome(key, id)
	id = tonumber(id) or 0
	if id ~= 0 and not live.info(id) then return false end
	BOBBA.store.query("INSERT OR REPLACE INTO bobbahotel_home_rooms (key, room) VALUES (?, ?)", { tostring(key), id })
	return true
end

-- --- the hotel's name ----------------------------------------------------------------------------------------
A.DEFAULT_NAME = "Bobba Hotel"
function A.hotelName()
	local n = BOBBA.store.setting("hotel_name", "")
	if n == nil or n == "" then return A.DEFAULT_NAME end
	return n
end
function A.setHotelName(name)
	name = clean(name, 32)
	if name == "" then name = A.DEFAULT_NAME end
	BOBBA.store.setSetting("hotel_name", name)
	P().send("hotel.info", { name = name })
	return name
end

-- --- messages -------------------------------------------------------------------------------------------------
function A.start()
	A.migrate()
	local p = P()
	local function inRoom(player)
		local u = live.byPlayer[player]
		return u and u.room, u
	end
	local function err(player, why) if why then p.send("room.error", { message = tostring(why) }, player) end end
	p.receive("room.settings.get", function(player, data)
		local s = A.settingsFor(player, data.id)
		if s then p.send("room.settings", s, player) end
	end)
	p.receive("room.settings.save", function(player, data)
		local ok, code = A.save(player, data)
		if ok then p.send("room.settings.saved", { id = tonumber(data.id) }, player)
		else p.send("room.settings.error", { id = tonumber(data.id), code = code }, player) end
	end)
	p.receive("room.delete", function(player, data)
		local ok, why = A.delete(player, data.id)
		if not ok then err(player, why) end
	end)
	p.receive("room.rights.give", function(player, data)
		local r, me = inRoom(player)
		if not r then return end
		local t = data.unit and unitIn(r, data.unit)
		local ok, why
		if t then ok, why = A.giveRights(player, r, t.key, t.name)
		elseif data.key then ok, why = A.giveRights(player, r, tostring(data.key), tostring(data.name or data.key)) end
		if ok == false then err(player, why) end
	end)
	p.receive("room.rights.remove", function(player, data)
		local r = inRoom(player)
		local keys = type(data.keys) == "table" and data.keys or {}
		if data.unit and r then local t = unitIn(r, data.unit) if t then keys = { t.key } end end
		A.removeRights(player, data.id or (r and r.id), keys)
	end)
	p.receive("room.rights.removeAll", function(player)
		local r = inRoom(player)
		if r then A.removeAllRights(player, r) end
	end)
	p.receive("room.rights.removeOwn", function(player, data)
		A.removeRights(player, data.id, { p.playerKey(player) })
	end)
	p.receive("room.kick", function(player, data)
		local r = inRoom(player)
		if r then local ok, why = A.kick(player, r, data.unit) if not ok then err(player, why) end end
	end)
	p.receive("room.ban", function(player, data)
		local r = inRoom(player)
		if r then local ok, why = A.ban(player, r, data.unit, data.kind) if not ok then err(player, why) end end
	end)
	p.receive("room.unban", function(player, data)
		if A.unban(player, data.id, data.key) then
			local s = A.settingsFor(player, data.id)
			if s then p.send("room.settings", s, player) end
		end
	end)
	p.receive("room.mute", function(player, data)
		local r = inRoom(player)
		if r then local ok, why = A.mute(player, r, data.unit, data.minutes) if not ok then err(player, why) end end
	end)
	p.receive("room.muteAll", function(player)
		local r = inRoom(player)
		if r then A.muteAll(player, r) end
	end)
	p.receive("room.doorbell.answer", function(player, data)
		local r = inRoom(player)
		if r then A.answer(player, r, data.name, data.accept and true or false) end
	end)
	p.receive("room.leave", function(player)
		unqueue(player)
		A.toHotelView(player)
	end)
	p.receive("room.favourite", function(player, data)
		local key = p.playerKey(player)
		local ok, why = A.setFavourite(key, data.id, data.on and true or false)
		if not ok then err(player, why) end
		p.send("room.favourites", { ids = A.favourites(key) }, player)
	end)
	p.receive("room.home", function(player, data)
		local key = p.playerKey(player)
		A.setHome(key, data.id)
		p.send("room.home", { id = A.home(key) or 0 }, player)
	end)
	-- chat: muted people aren't heard (the whole room muted: only rights holders are)
	BOBBA.events.on("roomChat", "bobba.access.mute", function(r, u)
		local left = A.mutedFor(r, u)
		if left > 0 then
			if u.player then p.send("room.muted", { seconds = left }, u.player) end
			return false
		end
		if r.mutedAll and not (u.player and A.hasRights(u.player, r.info)) then return false end
	end)
	-- walking through others when the room lets them
	BOBBA.events.on("roomSettingsSaved", "bobba.access.walk", function(id)
		local r = live.rooms[id]
		if r then r.grid.allowWalkthrough = num(r.info.allow_walkthrough, 1) == 1 end
	end)
	-- kicked: once at the door, out
	BOBBA.events.on("unitStepped", "bobba.access.kicked", function(r, u)
		if u.kicked and u.player and (not u.path or #u.path == 0) then
			local player = u.player
			p.after(0, function() if live.byPlayer[player] == u then A.toHotelView(player) end end)
		end
	end)
	p.onLeave(function(player) unqueue(player) end)
	-- (a room nobody's in any more: whoever rings there gets no answer)
	BOBBA.events.on("roomUnloaded", "bobba.access.queue", function(r) denyQueue(r) end)
	p.every("rooms.access", 0.5, A.tick)
end
