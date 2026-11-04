-- The room's TV (hotel/videos.lua)
local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	local owner, a, b = { key = "2001", name = "Owner" }, { key = "2002", name = "Ann" }, { key = "2003", name = "Ben" }
	local room = BOBBA.live.create(owner.key, "Owner", "model_a", "Cinema")
	for _, p in ipairs({ owner, a, b }) do P.fromPlayer(p, "room.ready", {}) BOBBA.live.enter(p, room) end
	return owner, a, b, room
end
local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end

T["links: YouTube's kinds, others not"] = function()
	start()
	local V = BOBBA.videos
	eq(select(2, V.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10")), "dQw4w9WgXcQ")
	eq(select(2, V.parse("https://youtu.be/dQw4w9WgXcQ")), "dQw4w9WgXcQ")
	eq(select(2, V.parse("https://www.youtube.com/shorts/abcdefghijk")), "abcdefghijk")
	eq(V.parse("https://example.com/video.mp4"), nil)
end

T["added, played for the room, the next one after it; a vote of half skips"] = function()
	local owner, a, b = start()
	P.fromPlayer(a, "videos.add", { url = "https://youtu.be/aaaaaaaaaaa" })
	local st = last(b, "videos.state")
	eq(st.playing.video, "aaaaaaaaaaa")
	eq(st.playing.by, "Ann")
	P.fromPlayer(b, "videos.add", { url = "https://youtu.be/bbbbbbbbbbb" })
	eq(#last(owner, "videos.state").queue, 1)
	-- the player says how long it is: 60 s
	P.fromPlayer(b, "videos.meta", { id = st.playing.id, title = "First", duration = 60 })
	eq(last(owner, "videos.state").playing.title, "First")
	-- too early to say it ended
	P.fromPlayer(b, "videos.ended", { id = st.playing.id })
	eq(last(owner, "videos.state").playing.video, "aaaaaaaaaaa")
	P.now = P.now + 64
	P.runTimers()
	eq(last(owner, "videos.state").playing.video, "bbbbbbbbbbb")
	-- Ann votes (1 of 3: needs 2), then the owner skips at once
	P.fromPlayer(a, "videos.skip", {})
	eq(last(owner, "videos.state").playing.votes, 1)
	P.fromPlayer(owner, "videos.add", { url = "dQw4w9WgXcQ" })
	P.fromPlayer(owner, "videos.skip", {})
	eq(last(a, "videos.state").playing.video, "dQw4w9WgXcQ")
end

T["the owner turns the room's TV off; the hotel can turn videos off"] = function()
	local owner, a = start()
	P.fromPlayer(a, "videos.room", { on = false })
	eq(last(a, "videos.error").message, "only the room's owner can turn the TV off or on")
	P.fromPlayer(owner, "videos.room", { on = false })
	P.fromPlayer(a, "videos.add", { url = "https://youtu.be/aaaaaaaaaaa" })
	eq(last(a, "videos.error").message, "the room's TV is off")
	P.fromPlayer(owner, "videos.room", { on = true })
	BOBBA.store.setSetting("videos.enabled", "0")
	P.fromPlayer(a, "videos.add", { url = "https://youtu.be/aaaaaaaaaaa" })
	eq(last(a, "videos.error").message, "videos are off in this hotel")
end

return T
