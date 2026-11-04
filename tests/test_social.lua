-- Friends and messages (hotel/friends.lua), groups (hotel/groups.lua), room events (hotel/roomevents.lua)
local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	local mia, bo, ida = { key = "1001", name = "Mia" }, { key = "1002", name = "Bo" }, { key = "1003", name = "Ida" }
	for _, p in ipairs({ mia, bo, ida }) do P.fromPlayer(p, "room.ready", {}) end
	return mia, bo, ida
end
local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end
local function friendNamed(list, name)
	for _, f in ipairs(list.friends) do if f.name == name then return f end end
end

T["a friend request, accepted: both see each other online, in which room"] = function()
	local mia, bo = start()
	P.fromPlayer(mia, "friends.request", { name = "bo" })
	eq(last(bo, "friends.requested").name, "Mia")
	eq(last(bo, "friends.list").requests[1].name, "Mia")
	eq(#last(mia, "friends.list").sent, 1)
	P.fromPlayer(bo, "friends.accept", { key = mia.key })
	local f = friendNamed(last(mia, "friends.list"), "Bo")
	assert(f and f.online, "Bo is a friend, online")
	eq(f.room, BOBBA.live.byPlayer[bo].room.id)
	eq(#last(bo, "friends.list").requests, 0)
	-- Bo goes away: Mia hears it
	P.disconnect(bo)
	eq(last(mia, "friends.update").online, false)
end

T["asking someone who asked you makes you friends at once; no asking yourself or strangers"] = function()
	local mia, bo = start()
	P.fromPlayer(mia, "friends.request", { name = "Bo" })
	P.fromPlayer(bo, "friends.request", { name = "Mia" })
	assert(BOBBA.friends.areFriends(mia.key, bo.key))
	P.fromPlayer(mia, "friends.request", { name = "Mia" })
	eq(last(mia, "friends.error").message, "that's you")
	P.fromPlayer(mia, "friends.request", { name = "Nobody" })
	eq(last(mia, "friends.error").message, "no one called Nobody")
end

T["messages: only between friends, kept, unread until read"] = function()
	local mia, bo = start()
	P.fromPlayer(mia, "messenger.send", { to = bo.key, text = "hi" })
	eq(last(mia, "friends.error").message, "you can only message your friends")
	BOBBA.friends.request(mia.key, "Bo")
	BOBBA.friends.accept(bo.key, mia.key)
	P.fromPlayer(mia, "messenger.send", { to = bo.key, text = "  come to the rooftop  " })
	eq(last(bo, "messenger.message").text, "come to the rooftop")
	eq(last(bo, "messenger.message").mine, false)
	eq(last(mia, "messenger.message").mine, true)
	eq(BOBBA.friends.unread(bo.key), 1)
	P.fromPlayer(bo, "messenger.history", { with = mia.key })
	local h = last(bo, "messenger.history")
	eq(#h.messages, 1)
	eq(h.messages[1].text, "come to the rooftop")
	eq(BOBBA.friends.unread(bo.key), 0)
	-- the list has the last message
	P.fromPlayer(mia, "friends.get", {})
	eq(friendNamed(last(mia, "friends.list"), "Bo").last.text, "come to the rooftop")
end

T["following a friend into their room"] = function()
	local mia, bo = start()
	BOBBA.friends.request(mia.key, "Bo")
	BOBBA.friends.accept(bo.key, mia.key)
	local room = BOBBA.live.create(bo.key, "Bo", "model_a", "Bo's place")
	BOBBA.live.enter(bo, room)
	P.fromPlayer(mia, "friends.follow", { key = bo.key })
	eq(BOBBA.live.byPlayer[mia].room.id, room)
end

T["groups: made (paid), joined, a message in a channel reaches the members"] = function()
	local mia, bo, ida = start()
	local before = BOBBA.wallet.get(mia.key).credits
	P.fromPlayer(mia, "groups.create", { name = "Builders", color = "b98cff", description = "We build" })
	local id = last(mia, "groups.created").id
	eq(BOBBA.wallet.get(mia.key).credits, before - 10)
	local info = last(mia, "groups.info")
	eq(info.name, "Builders")
	eq(info.rank, 2)
	eq(#info.channels, 2)
	eq(info.channels[1].name, "general")
	eq(info.channels[2].kind, "voice")
	P.fromPlayer(bo, "groups.join", { id = id })
	eq(last(bo, "groups.list").groups[1].name, "Builders")
	P.fromPlayer(bo, "groups.send", { channel = info.channels[1].id, text = "anyone have pillars?" })
	eq(last(mia, "groups.message").message.text, "anyone have pillars?")
	eq(last(mia, "groups.message").message.name, "Bo")
	-- (Ida isn't in it)
	eq(#P.inbox(ida, "groups.message"), 0)
	P.fromPlayer(ida, "groups.send", { channel = info.channels[1].id, text = "hi" })
	eq(last(ida, "groups.error").message, "you're not in the group")
	-- Mia's unread, then read
	P.fromPlayer(mia, "groups.mine", {})
	eq(last(mia, "groups.list").groups[1].unread, 1)
	P.fromPlayer(mia, "groups.history", { channel = info.channels[1].id })
	eq(#last(mia, "groups.history").messages, 1)
	P.fromPlayer(mia, "groups.mine", {})
	eq(last(mia, "groups.list").groups[1].unread, 0)
	-- search
	P.fromPlayer(ida, "groups.search", { query = "build" })
	eq(last(ida, "groups.results").groups[1].members, 2)
end

T["groups: a closed one asks; admins let in; channels; owner can't leave; deleted"] = function()
	local mia, bo, ida = start()
	local id = BOBBA.groups.create(mia.key, { name = "Staff", open = false })
	P.fromPlayer(bo, "groups.join", { id = id })
	eq(BOBBA.groups.rank(id, bo.key), nil)
	eq(last(mia, "groups.asked").name, "Bo")
	eq(last(bo, "groups.info").requested, true)
	P.fromPlayer(bo, "groups.accept", { id = id, key = bo.key })
	eq(last(bo, "groups.error").message, "only the group's admins can let people in")
	P.fromPlayer(mia, "groups.accept", { id = id, key = bo.key })
	eq(BOBBA.groups.rank(id, bo.key), 0)
	P.fromPlayer(mia, "groups.rank", { id = id, key = bo.key, rank = 1 })
	eq(BOBBA.groups.rank(id, bo.key), 1)
	P.fromPlayer(bo, "groups.channel.add", { id = id, name = "Show Your Room", kind = "text" })
	local chans = BOBBA.groups.info(id, bo.key).channels
	eq(chans[#chans].name, "show-your-room")
	P.fromPlayer(mia, "groups.leave", { id = id })
	eq(last(mia, "groups.error").message, "the owner can't leave: delete the group instead")
	P.fromPlayer(bo, "groups.delete", { id = id })
	eq(last(bo, "groups.error").message, "only the owner can delete it")
	P.fromPlayer(mia, "groups.delete", { id = id })
	eq(BOBBA.groups.get(id), nil)
	eq(last(bo, "groups.deleted").id, id)
end

T["room events: an owner's room is in the navigator's events while it's on"] = function()
	local mia, bo = start()
	local room = BOBBA.live.create(mia.key, "Mia", "model_a", "Rooftop")
	P.fromPlayer(bo, "events.create", { room = room, name = "Quiz night", hours = 2 })
	eq(last(bo, "events.error").message, "you can only put on an event in your own room")
	P.fromPlayer(mia, "events.create", { room = room, name = "Quiz night", description = "Prizes!", hours = 9 })
	eq(last(bo, "events.started").name, "Quiz night")
	local evs = last(mia, "events.list").events
	eq(#evs, 1)
	eq(evs[1].ends - evs[1].starts, 3 * 3600, "at most 3 hours")
	eq(evs[1].mine, true)
	P.fromPlayer(bo, "navigator.search", { view = "roomads_view" })
	local r = last(bo, "navigator.result").blocks[1].rooms[1]
	eq(r.name, "Rooftop")
	eq(r.event.name, "Quiz night")
	P.now = P.now + 3 * 3600 + 1
	P.fromPlayer(bo, "events.list", {})
	eq(#last(bo, "events.list").events, 0)
end

return T
