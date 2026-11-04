-- Wired (hotel/wired.lua), its script boxes (hotel/wiredscript.lua) and linking teleports
local T = {}
local P

local function start()
	P = BOBBA.platform
	BOBBA.live.start()
	local I = BOBBA.items
	I.define("lamp", { width = 1, length = 1, height = 1, states = 2 })
	I.define("block", { width = 1, length = 1, height = 1 })
	I.define("plate", { width = 1, length = 1, height = 0.1, walk = true })
	I.define("tele", { width = 1, length = 1, height = 2, states = 3, category = "teleport", directions = { 0, 2, 4, 6 } })
	for kind in pairs(BOBBA.wired.HABBO) do I.define(kind, { width = 1, length = 1, height = 0.5, states = 2 }) end
	local mia, bo = { key = "765611980001", name = "Mia" }, { key = "765611980002", name = "Bo" }
	local id = BOBBA.live.create(mia.key, mia.name, "model_a", "Mia's room")
	BOBBA.live.enter(mia, id)
	BOBBA.live.enter(bo, id)
	return mia, bo, BOBBA.live.rooms[id]
end
local function last(p, name)
	local box = P.inbox(p, name)
	return box[#box]
end
local function place(r, who, kind, x, y, dir)
	local got, why
	BOBBA.items.place(r, who, kind, x, y, dir or 0, function(it, w) got, why = it, w end)
	assert(got, "placed " .. kind .. ": " .. tostring(why))
	return got
end
local function save(who, box, data)
	data.id = box.id
	P.fromPlayer(who, "wired.save", data)
	local e = last(who, "wired.error")
	return last(who, "wired.saved"), e
end
local function say(who, text) P.now = P.now + 2 P.fromPlayer(who, "room.chat", { text = text, kind = "talk" }) end
local function unitOf(p) return BOBBA.live.byPlayer[p] end

T["a keyword switches a lamp; only the one who said it sees it; the box's settings stay secret"] = function()
	local mia, bo, r = start()
	local lamp = place(r, mia, "lamp", 8, 8)
	local trg = place(r, mia, "wf_trg_says_something", 5, 5)
	local eff = place(r, mia, "wf_act_toggle_state", 5, 5)
	-- Bo can't open or change them
	P.fromPlayer(bo, "room.item.use", { id = trg.id })
	eq(last(bo, "wired.open"), nil)
	save(bo, trg, { text = "lights", ints = { 0 } })
	eq(last(bo, "wired.error").message, "only those with rights can change wired")
	-- Mia opens and saves
	P.fromPlayer(mia, "room.item.use", { id = trg.id })
	eq(last(mia, "wired.open").type, "says")
	assert(save(mia, trg, { text = "lights", ints = { 0 } }))
	assert(save(mia, eff, { items = { lamp.id }, delay = 0 }))
	eq(BOBBA.items.snapshot(trg).data, nil, "not sent to the room")
	local heard = #P.inbox(mia, "room.chat")
	say(bo, "turn the LIGHTS on")
	eq(lamp.state, 1)
	eq(#P.inbox(mia, "room.chat"), heard, "Mia didn't hear it")
	eq(last(bo, "room.chat").kind, "whisper", "Bo sees it as a whisper")
	say(bo, "hello")
	eq(lamp.state, 1)
	eq(#P.inbox(mia, "room.chat"), heard + 1)
	-- owner only
	save(mia, trg, { text = "lights", ints = { 1 } })
	say(bo, "lights")
	eq(lamp.state, 1, "not Bo")
	say(mia, "lights")
	eq(lamp.state, 0)
end

T["conditions: all must hold; walking onto a plate teleports; random and unseen add-ons"] = function()
	local mia, bo, r = start()
	local plate = place(r, mia, "plate", 6, 6)
	local target = place(r, mia, "plate", 10, 10)
	local trg = place(r, mia, "wf_trg_walks_on_furni", 4, 2)
	local cnd = place(r, mia, "wf_cnd_user_count_in", 4, 2)
	local eff = place(r, mia, "wf_act_teleport_to", 4, 2)
	save(mia, trg, { items = { plate.id } })
	save(mia, cnd, { ints = { 3, 50 } })
	save(mia, eff, { items = { target.id } })
	BOBBA.live.warp(r, unitOf(bo), 6, 6)
	eq(unitOf(bo).x .. "," .. unitOf(bo).y, "6,6", "two here: not enough")
	save(mia, cnd, { ints = { 2, 50 } })
	BOBBA.live.warp(r, unitOf(bo), 7, 6)
	BOBBA.live.warp(r, unitOf(bo), 6, 6)
	eq(unitOf(bo).x .. "," .. unitOf(bo).y, "10,10", "teleported")
	-- add-ons: three lamps, one effect each
	local lamps, effs = {}, {}
	local trg2 = place(r, mia, "wf_trg_says_something", 4, 3)
	save(mia, trg2, { text = "go" })
	for i = 1, 3 do
		lamps[i] = place(r, mia, "lamp", 7 + i, 3)
		effs[i] = place(r, mia, "wf_act_toggle_state", 4, 3)
		save(mia, effs[i], { items = { lamps[i].id } })
	end
	local unseen = place(r, mia, "wf_xtra_unseen", 4, 3)
	for _ = 1, 3 do say(mia, "go") end
	eq(lamps[1].state .. lamps[2].state .. lamps[3].state, "111", "each once, in turn")
	BOBBA.items.pickup(r, mia, unseen.id)
	place(r, mia, "wf_xtra_random", 4, 3)
	say(mia, "go")
	local on = lamps[1].state + lamps[2].state + lamps[3].state
	eq(on, 2, "one of them")
end

T["timers: repeating, at a time after the reset; moving furni"] = function()
	local mia, bo, r = start()
	local block = place(r, mia, "block", 8, 8)
	local trg = place(r, mia, "wf_trg_periodically", 4, 2)
	local eff = place(r, mia, "wf_act_move_rotate", 4, 2)
	save(mia, trg, { ints = { 2 } })   -- every second
	save(mia, eff, { items = { block.id }, ints = { 6, 0 } }) -- down
	for _ = 1, 4 do P.now = P.now + 0.5 BOBBA.wired.tick() end
	eq(block.y, 10, "two seconds: two tiles")
	local trg2 = place(r, mia, "wf_trg_at_given_time", 4, 3)
	local lamp = place(r, mia, "lamp", 6, 3)
	local eff2 = place(r, mia, "wf_act_toggle_state", 4, 3)
	save(mia, trg2, { ints = { 4 } })  -- 2 seconds after the reset
	save(mia, eff2, { items = { lamp.id } })
	BOBBA.wired.state(r).timer = P.now
	for _ = 1, 3 do P.now = P.now + 0.5 BOBBA.wired.tick() end
	eq(lamp.state, 0)
	for _ = 1, 4 do P.now = P.now + 0.5 BOBBA.wired.tick() end
	eq(lamp.state, 1, "once")
end

T["a script: moves furni, whispers, remembers; can't reach the server; stopped when it loops"] = function()
	local mia, bo, r = start()
	local block = place(r, mia, "block", 8, 8)
	local trg = place(r, mia, "wf_trg_says_something", 4, 2)
	local eff = place(r, mia, "wf_test_act", 4, 2)
	save(mia, trg, { text = "go" })
	local _, e = save(mia, eff, { items = { block.id }, code = "this isn't lua (" })
	assert(e and e.message:find("mistake"), "checked when saved")
	assert(save(mia, eff, { items = { block.id }, code = [[
		memory.n = (memory.n or 0) + 1
		local b = selected[1]
		b:move(b.x + 1, b.y)
		say("moved " .. memory.n .. " " .. tostring(BOBBA) .. " " .. tostring(os.execute) .. " " .. tostring(require) .. " " .. tostring(debug))
	]] }))
	say(bo, "go")
	eq(block.x, 9)
	local w = last(bo, "room.chat")
	eq(w.text, "moved 1 nil nil nil nil")
	say(bo, "go")
	eq(block.x, 10)
	eq(last(bo, "room.chat").text:sub(1, 7), "moved 2")
	-- wait: later, with the same names
	save(mia, eff, { items = { block.id }, code = "local b = selected[1] wait(1, function() b:move(b.x + 1, b.y) say('later') end)" })
	say(bo, "go")
	eq(block.x, 11)
	eq(last(bo, "room.chat").text, "later")
	-- an endless loop: stopped, the box says why, the room goes on
	save(mia, eff, { code = "while true do end" })
	say(bo, "go")
	local err = BOBBA.wired.state(r).errors[eff.id]
	assert(err and err:find("too long"), "stopped: " .. tostring(err))
	-- pcall can't keep it going
	save(mia, eff, { code = "while true do pcall(function() while true do end end) end" })
	say(bo, "go")
	assert(BOBBA.wired.state(r).errors[eff.id]:find("too long"), "stopped through pcall")
	-- too much memory
	save(mia, eff, { code = "local t = {} for i = 1, 1e7 do t[i] = {} end" })
	say(bo, "go")
	local m = BOBBA.wired.state(r).errors[eff.id]
	assert(m and (m:find("memory") or m:find("too long")), "stopped: " .. tostring(m))
	-- the hook is gone afterwards
	eq(debug.gethook(), nil)
	-- an error: its line
	save(mia, eff, { code = "local x = nil\nx.y = 1" })
	say(bo, "go")
	assert(BOBBA.wired.state(r).errors[eff.id]:find("^line 2"), BOBBA.wired.state(r).errors[eff.id])
	-- switched off by the hotel
	BOBBA.store.setSetting("wired.scripts", "0")
	local _, e2 = save(mia, eff, { code = "say('hi')" })
	assert(e2 and e2.message:find("switched off"))
	BOBBA.store.setSetting("wired.scripts", "1")
end

T["a script condition: true lets the stack run"] = function()
	local mia, bo, r = start()
	local lamp = place(r, mia, "lamp", 8, 8)
	local trg = place(r, mia, "wf_trg_says_something", 4, 2)
	local cnd = place(r, mia, "wf_test_cnd", 4, 2)
	local eff = place(r, mia, "wf_act_toggle_state", 4, 2)
	save(mia, trg, { text = "go" })
	save(mia, eff, { items = { lamp.id } })
	save(mia, cnd, { code = "return user ~= nil and user.name == 'Mia'" })
	say(bo, "go")
	eq(lamp.state, 0)
	say(mia, "go")
	eq(lamp.state, 1)
end

T["teleports: unlinked; linked one way to any of yours; several to one; not someone else's; traded: unlinked"] = function()
	local mia, bo, r = start()
	local a = place(r, mia, "tele", 6, 3, 4)
	local b = place(r, mia, "tele", 8, 3, 4)
	local c = place(r, mia, "tele", 10, 3, 4)
	local inv = BOBBA.inventory.give(mia.key, "tele", 1)[1]
	P.fromPlayer(mia, "tele.links", { id = a.id })
	local list = last(mia, "tele.links")
	eq(list.to, 0)
	eq(#list.rooms, 1)
	eq(#list.rooms[1].teleports, 3)
	eq(#list.inventory, 1)
	P.fromPlayer(mia, "tele.link", { id = a.id, to = c.id })
	P.fromPlayer(mia, "tele.link", { id = b.id, to = c.id })
	eq(BOBBA.items.partner(a.id), c.id)
	eq(BOBBA.items.partner(b.id), c.id)
	eq(BOBBA.items.partner(c.id), nil, "one way")
	P.fromPlayer(mia, "tele.link", { id = a.id, to = a.id })
	eq(BOBBA.items.partner(a.id), c.id, "not to itself")
	-- not Bo's
	local bos = BOBBA.inventory.give(bo.key, "tele", 1)[1]
	P.fromPlayer(mia, "tele.link", { id = a.id, to = bos.id })
	eq(BOBBA.items.partner(a.id), c.id)
	P.fromPlayer(bo, "tele.link", { id = a.id, to = bos.id })
	eq(BOBBA.items.partner(a.id), c.id)
	-- unlinked by hand
	P.fromPlayer(mia, "tele.link", { id = b.id, to = 0 })
	eq(BOBBA.items.partner(b.id), nil)
	-- traded away: no links to or from it
	P.fromPlayer(mia, "tele.link", { id = inv.id, to = c.id })
	P.fromPlayer(mia, "tele.link", { id = c.id, to = inv.id })
	r.info.trade = 2
	P.fromPlayer(mia, "trade.open", { unit = unitOf(bo).id })
	P.fromPlayer(mia, "trade.offer", { ids = { inv.id } })
	P.fromPlayer(mia, "trade.accept", { on = true })
	P.fromPlayer(bo, "trade.accept", { on = true })
	P.fromPlayer(mia, "trade.confirm")
	P.fromPlayer(bo, "trade.confirm")
	eq(BOBBA.items.partner(inv.id), nil)
	eq(BOBBA.items.partner(c.id), nil)
	eq(BOBBA.items.partner(a.id), c.id, "others stay")
end

return T
