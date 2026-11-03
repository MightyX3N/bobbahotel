-- Rooms: settings, rights, the doorbell and the password, kick, ban, mute, deleting, favourites and
-- the home room (hotel/roomaccess.lua)
local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	BOBBA.items.define("chair", { width = 1, length = 1, height = 1, sit = true, directions = { 0, 2, 4, 6 } })
	local mia, bo, cy = { key = "765611980001", name = "Mia" }, { key = "765611980002", name = "Bo" }, { key = "765611980003", name = "Cy" }
	local id = BOBBA.live.create(mia.key, mia.name, "model_a", "Mia's room")
	BOBBA.live.enter(mia, id)
	return mia, bo, cy, BOBBA.live.rooms[id]
end

local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end
local function tick(n)
	for _ = 1, n or 1 do
		P.now = P.now + 0.5
		P.runTimers()
	end
end
local function unitOf(p) return BOBBA.live.byPlayer[p] end
local function settings(r, over)
	local s = { id = r.id, name = r.info.name, description = "", state = 0, password = "", maxUsers = 25, category = 0, tags = {},
		trade = 0, allowPets = false, allowPetsEat = false, allowWalkthrough = true, hideWall = false, wallThickness = 0, floorThickness = 0,
		chatMode = 0, chatWeight = 1, chatSpeed = 1, chatDistance = 50, chatProtection = 2, whoMute = 0, whoKick = 0, whoBan = 0 }
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

T["settings: only the owner reads and saves them; checked; everyone in the room told"] = function()
	local mia, bo, _, r = start()
	BOBBA.live.enter(bo, r.id)
	P.fromPlayer(bo, "room.settings.get", { id = r.id })
	eq(last(bo, "room.settings"), nil, "Bo can't read them")
	P.fromPlayer(mia, "room.settings.get", { id = r.id })
	eq(last(mia, "room.settings").name, "Mia's room")
	P.fromPlayer(bo, "room.settings.save", settings(r, { name = "Bo's now" }))
	eq(BOBBA.live.info(r.id).name, "Mia's room", "Bo can't save")
	P.fromPlayer(mia, "room.settings.save", settings(r, { name = "   " }))
	eq(last(mia, "room.settings.error").code, 7, "a name is needed")
	P.fromPlayer(mia, "room.settings.save", settings(r, { state = 2, password = "" }))
	eq(last(mia, "room.settings.error").code, 5, "a password room needs a password")
	P.fromPlayer(mia, "room.settings.save", settings(r, { tags = { "official" } }))
	eq(last(mia, "room.settings.error").code, 12, "staff tags")
	P.fromPlayer(mia, "room.settings.save", settings(r, { tags = { string.rep("a", 16) } }))
	eq(last(mia, "room.settings.error").code, 13, "a tag of 16 letters")
	P.fromPlayer(mia, "room.settings.save", settings(r, { name = "Disco", description = "Dance!", tags = { "party", "dance", "third" }, maxUsers = 999,
		category = 9, chatDistance = -30, wallThickness = 5, whoKick = 2 }))
	eq(last(mia, "room.settings.saved").id, r.id)
	local info = BOBBA.live.info(r.id)
	eq(info.name .. "|" .. info.tags .. "|" .. info.max_users .. "|" .. info.category .. "|" .. info.chat_distance .. "|" .. info.wall_thickness,
		"Disco|party;dance;|50|9|30|1", "two tags, at most 50 people, distance made positive, thickness clamped")
	local told = last(bo, "room.info")
	eq(told.name .. " " .. told.whoKick .. " " .. tostring(told.canKick), "Disco 2 true", "Bo is told, and may kick now")
	P.fromPlayer(mia, "room.settings.save", settings(r, { category = 8 }))
	eq(BOBBA.live.info(r.id).category, "9", "the official category is for staff (it stays as it was)")
end

T["rights: given by the owner, let someone build; taken, their furni goes back"] = function()
	local mia, bo, _, r = start()
	BOBBA.live.enter(bo, r.id)
	local boUnit = unitOf(bo).id
	eq(BOBBA.items.canEdit(bo, r), false)
	P.fromPlayer(bo, "room.rights.give", { unit = unitOf(mia).id })
	eq(BOBBA.access.hasRightsKey(r.id, mia.key), false, "Bo can't give rights")
	P.fromPlayer(mia, "room.rights.give", { unit = boUnit })
	eq(BOBBA.items.canEdit(bo, r), true, "Bo may build")
	eq(last(bo, "room.info").level, 1, "Bo is told")
	eq(#last(mia, "room.rights.list").rights, 1, "the owner sees the list")
	BOBBA.inventory.give(bo.key, "chair", 1)
	local id = BOBBA.inventory.list(bo.key)[1].id
	P.fromPlayer(bo, "inventory.place", { id = id, x = 6, y = 6, dir = 2 })
	assert(r.items[id], "Bo placed his chair")
	-- the owner's furni: Bo can't pick it up
	local mine
	BOBBA.items.place(r, mia, "chair", 8, 8, 2, function(it) mine = it end)
	eq(BOBBA.items.pickup(r, bo, mine.id), false, "not the owner's")
	P.fromPlayer(mia, "room.rights.remove", { keys = { bo.key } })
	eq(BOBBA.items.canEdit(bo, r), false)
	eq(r.items[id], nil, "his chair left the room")
	eq(BOBBA.inventory.list(bo.key)[1].id, id, "back in his inventory")
	eq(last(bo, "room.info").level, 0)
	-- giving back, then Bo gives his own up
	P.fromPlayer(mia, "room.rights.give", { unit = boUnit })
	P.fromPlayer(bo, "room.rights.removeOwn", { id = r.id })
	eq(BOBBA.access.hasRightsKey(r.id, bo.key), false)
end

T["the doorbell: rights holders inside hear it and open; nobody there, no answer"] = function()
	local mia, bo, cy, r = start()
	P.fromPlayer(mia, "room.settings.save", settings(r, { state = 1 }))
	local lounge = BOBBA.live.homeRoom()
	BOBBA.live.enter(bo, lounge)
	P.fromPlayer(bo, "room.enter", { id = r.id })
	eq(last(bo, "room.doorbell.waiting").id, r.id, "Bo is waiting")
	eq(BOBBA.live.byPlayer[bo], nil, "in the hotel view meanwhile")
	eq(last(mia, "room.doorbell.ring").name, "Bo", "Mia hears it")
	P.fromPlayer(cy, "room.enter", { id = r.id })
	P.fromPlayer(mia, "room.doorbell.answer", { name = "cy", accept = false })
	eq(last(cy, "room.denied").reason, "doorbell", "Cy isn't let in")
	P.fromPlayer(mia, "room.doorbell.answer", { name = "Bo", accept = true })
	eq(unitOf(bo).room.id, r.id, "Bo is let in")
	eq(last(mia, "room.doorbell.hide").name, "Bo")
	-- with nobody who can open inside
	BOBBA.live.leave(mia)
	BOBBA.live.leave(bo)
	BOBBA.live.enter(bo, lounge)
	P.fromPlayer(bo, "room.enter", { id = r.id })
	eq(last(bo, "room.denied").reason, "noanswer")
	-- the owner walks straight in
	P.fromPlayer(mia, "room.enter", { id = r.id })
	eq(unitOf(mia).room.id, r.id)
	-- a waiting ringer is turned away when the last rights holder leaves
	P.fromPlayer(cy, "room.enter", { id = r.id })
	eq(last(cy, "room.doorbell.waiting").id, r.id)
	BOBBA.live.enter(mia, lounge)
	tick()
	eq(last(cy, "room.denied").reason, "noanswer")
end

T["the password: asked for, checked (any case)"] = function()
	local mia, bo, _, r = start()
	P.fromPlayer(mia, "room.settings.save", settings(r, { state = 2, password = "Secret" }))
	P.fromPlayer(bo, "room.enter", { id = r.id })
	eq(last(bo, "room.password").id, r.id, "asked")
	P.fromPlayer(bo, "room.enter", { id = r.id, password = "nope" })
	eq(last(bo, "room.denied").reason, "wrongpassword")
	P.fromPlayer(bo, "room.enter", { id = r.id, password = "SECRET" })
	eq(unitOf(bo).room.id, r.id)
	-- saving again with an empty password keeps it
	P.fromPlayer(mia, "room.settings.save", settings(r, { state = 2, password = "" }))
	eq(BOBBA.live.info(r.id).password, "Secret")
end

T["full rooms: the owner and rights holders still come in"] = function()
	local mia, bo, cy, r = start()
	P.fromPlayer(mia, "room.settings.save", settings(r, { maxUsers = 1 }))
	P.fromPlayer(bo, "room.enter", { id = r.id })
	eq(last(bo, "room.denied").reason, "full")
	P.fromPlayer(mia, "room.rights.give", { key = cy.key, name = cy.name })
	P.fromPlayer(cy, "room.enter", { id = r.id })
	eq(unitOf(cy).room.id, r.id)
end

T["kick, ban, mute: as the room's settings allow; the owner can't be"] = function()
	local mia, bo, cy, r = start()
	BOBBA.live.enter(bo, r.id)
	BOBBA.live.enter(cy, r.id)
	P.fromPlayer(bo, "room.kick", { unit = unitOf(cy).id })
	eq(unitOf(cy).kicked, nil, "Bo can't kick: only the owner (who can kick: 0)")
	P.fromPlayer(mia, "room.settings.save", settings(r, { whoKick = 2 }))
	P.fromPlayer(bo, "room.kick", { unit = unitOf(mia).id })
	eq(unitOf(mia).kicked, nil, "nobody kicks the owner")
	-- (Cy away from the door, so he has to walk back to it)
	P.now = P.now + 1
	assert(BOBBA.live.walk(cy, 9, 9))
	tick(30)
	P.fromPlayer(bo, "room.kick", { unit = unitOf(cy).id })
	eq(last(cy, "room.denied").reason, "kicked")
	eq(unitOf(cy).kicked, true, "walking to the door")
	tick(30)
	eq(BOBBA.live.byPlayer[cy], nil, "out at the door")
	eq(last(cy, "room.hotelview") ~= nil, true)
	-- banning
	BOBBA.live.enter(cy, r.id)
	P.fromPlayer(bo, "room.ban", { unit = unitOf(cy).id, kind = "hour" })
	eq(unitOf(cy).room.id, r.id, "Bo can't ban (only the owner)")
	P.fromPlayer(mia, "room.ban", { unit = unitOf(cy).id, kind = "hour" })
	eq(BOBBA.live.byPlayer[cy], nil, "out")
	eq(last(cy, "room.denied").reason, "banned")
	P.fromPlayer(cy, "room.enter", { id = r.id })
	eq(last(cy, "room.denied").reason, "banned", "can't come back")
	P.fromPlayer(mia, "room.settings.get", { id = r.id })
	eq(last(mia, "room.settings").bans[1].name, "Cy", "in the banned list")
	P.now = P.now + 3601
	P.fromPlayer(cy, "room.enter", { id = r.id })
	eq(unitOf(cy).room.id, r.id, "an hour later")
	P.fromPlayer(mia, "room.ban", { unit = unitOf(cy).id, kind = "perm" })
	P.fromPlayer(mia, "room.unban", { id = r.id, key = cy.key })
	P.fromPlayer(cy, "room.enter", { id = r.id })
	eq(unitOf(cy).room.id, r.id, "unbanned")
	-- muting
	P.fromPlayer(mia, "room.mute", { unit = unitOf(cy).id, minutes = 2 })
	eq(last(cy, "room.muted").seconds, 120)
	local before = #P.inbox(mia, "room.chat")
	P.fromPlayer(cy, "room.chat", { text = "hello" })
	eq(#P.inbox(mia, "room.chat"), before, "not heard")
	P.now = P.now + 121
	P.fromPlayer(cy, "room.chat", { text = "hello again" })
	eq(#P.inbox(mia, "room.chat"), before + 1, "heard after two minutes")
	-- the whole room muted: only those with rights are heard
	P.fromPlayer(mia, "room.muteAll", {})
	eq(last(bo, "room.muteAll").on, true)
	P.now = P.now + 10
	P.fromPlayer(bo, "room.chat", { text = "anyone?" })
	eq(#P.inbox(mia, "room.chat"), before + 1)
	P.fromPlayer(mia, "room.chat", { text = "quiet please" })
	eq(#P.inbox(mia, "room.chat"), before + 2, "the owner is heard")
end

T["deleting a room: everyone out, the furni back to its owners"] = function()
	local mia, bo, _, r = start()
	BOBBA.live.enter(bo, r.id)
	local chair
	BOBBA.items.place(r, mia, "chair", 6, 6, 2, function(it) chair = it end)
	P.fromPlayer(bo, "room.delete", { id = r.id })
	assert(BOBBA.live.info(r.id), "Bo can't")
	P.fromPlayer(mia, "room.delete", { id = r.id })
	eq(BOBBA.live.info(r.id), nil, "gone")
	eq(BOBBA.live.byPlayer[bo], nil, "Bo is in the hotel view")
	eq(BOBBA.inventory.list(mia.key)[1].id, chair.id, "Mia's chair is in her inventory")
	P.fromPlayer(mia, "room.delete", { id = BOBBA.live.homeRoom() })
	assert(BOBBA.live.info(BOBBA.live.homeRoom()), "the hotel's first room stays")
end

T["favourites and the home room: listed, and the home room is where you start"] = function()
	local mia, bo, _, r = start()
	P.fromPlayer(bo, "room.favourite", { id = r.id, on = true })
	eq(last(bo, "room.favourites").ids[1], r.id)
	P.fromPlayer(bo, "navigator.search", { view = "myworld_view", query = "" })
	local blocks = last(bo, "navigator.result").blocks
	eq(blocks[2].code .. " " .. blocks[2].rooms[1].id, "favorites " .. r.id)
	P.fromPlayer(bo, "navigator.roominfo", { id = r.id })
	eq(last(bo, "navigator.roominfo").favourite, true)
	P.fromPlayer(bo, "room.home", { id = r.id })
	eq(last(bo, "room.home").id, r.id)
	P.fromPlayer(bo, "room.ready")
	eq(unitOf(bo).room.id, r.id, "Bo starts in his home room")
	P.fromPlayer(bo, "room.home", { id = 0 })
	eq(last(bo, "room.home").id, 0, "and can have none again")
	eq(BOBBA.access.home(bo.key), nil)
end

T["the navigator: room doors, tags, invisible rooms, categories"] = function()
	local mia, bo, _, r = start()
	P.fromPlayer(mia, "room.settings.save", settings(r, { state = 1, tags = { "Party" }, category = 9 }))
	P.fromPlayer(bo, "navigator.search", { view = "hotel_view", query = "tag:party" })
	local room = last(bo, "navigator.result").blocks[1].rooms[1]
	eq(room.door .. " " .. room.tags[1], "doorbell Party")
	P.fromPlayer(bo, "navigator.search", { view = "hotel_view", query = "" })
	local codes = {}
	for _, b in ipairs(last(bo, "navigator.result").blocks) do codes[#codes + 1] = b.code end
	eq(table.concat(codes, " "), "popular category.PARTY")
	P.fromPlayer(mia, "room.settings.save", settings(r, { state = 3 }))
	P.fromPlayer(bo, "navigator.search", { view = "hotel_view", query = "" })
	eq(#last(bo, "navigator.result").blocks[1].rooms, 0, "Bo doesn't see it")
	P.fromPlayer(mia, "navigator.search", { view = "hotel_view", query = "" })
	eq(#last(mia, "navigator.result").blocks[1].rooms, 1, "Mia does")
	P.fromPlayer(bo, "room.enter", { id = r.id })
	eq(last(bo, "room.denied").reason, "invisible")
end

T["the hotel's name: sent on arrival, changed by the admin"] = function()
	local mia = start()
	P.fromPlayer(mia, "room.ready")
	eq(last(mia, "hotel.info").name, "Bobba Hotel")
	eq(BOBBA.access.setHotelName("  Pixel Palace "), "Pixel Palace")
	eq(BOBBA.access.hotelName(), "Pixel Palace")
end

return T
