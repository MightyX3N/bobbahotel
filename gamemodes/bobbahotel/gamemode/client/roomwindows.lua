-- Rooms' own windows (client), as nitro-react has them:
--   the room settings (NavigatorRoomSettingsView: Basic, Access, Rights, chat, Moderation; every
--   change is saved at once), the room info (NavigatorRoomInfoView, from the room tools' cog), the
--   doorbell and the password (NavigatorDoorStateView), the doorbell for those inside
--   (DoorbellWidgetView), the menu over an avatar (AvatarInfoWidgetAvatarView: kick, ban, mute,
--   rights) with its infostand (InfoStandWidgetUserView), and the alerts when you can't come in.
-- Sizes and texts from nitro-react (scratchpad spec_nitro_rooms.md); the server's side is
-- hotel/roomaccess.lua.

BOBBA.roomWindows = BOBBA.roomWindows or {}
local RW = BOBBA.roomWindows
local U = BOBBA.ui
local P = BOBBA.platform
local R = BOBBA.room
local V = BOBBA.view
local HUD = BOBBA.hud
local T = function(key, fallback, vars) return U.text(key, fallback, vars) end

local BLACK, WHITE, MUTED = Color(0, 0, 0), Color(255, 255, 255), Color(108, 117, 125)
local DANGER = Color(168, 26, 18)

local function access()
	local a = R.current and R.current.access or {}
	if a.rightsKeys and not a.rights then
		a.rights = {}
		for _, k in ipairs(a.rightsKeys) do a.rights[k] = true end
	end
	return a
end

-- --- what the server tells us ------------------------------------------------------------------------------
P.receive("room.info", function(_, data)
	local c = R.current
	if not c or c.id ~= data.id then return end
	local old = c.access or {}
	c.access = data
	data.rights = {}
	for _, k in ipairs(data.rightsKeys or {}) do data.rights[k] = true end
	c.name, c.description = data.name, data.description
	c.canEdit = (data.level or 0) > 0
	-- the look changed (walls, thickness): drawn again
	if old.hideWall ~= data.hideWall or old.wallThickness ~= data.wallThickness or old.floorThickness ~= data.floorThickness then
		R.show()
	end
	if R.updateInfo then R.updateInfo() end
end)
P.receive("room.rights.list", function(_, data)
	local c = R.current
	if c and c.id == data.id and c.access then
		c.access.rights = {}
		for _, x in ipairs(data.rights or {}) do c.access.rights[x.key] = true end
	end
	if RW.settings and RW.settings.id == data.id then RW.settings.rights = data.rights end
end)
P.receive("room.favourites", function(_, data)
	RW.favourites = {}
	for _, id in ipairs(data.ids or {}) do RW.favourites[id] = true end
end)
P.receive("room.home", function(_, data) RW.home = tonumber(data.id) or 0 end)
P.receive("hotel.info", function(_, data)
	BOBBA.hotelName = tostring(data.name or "Bobba Hotel")
	BOBBA.events.emit("hotelName", BOBBA.hotelName)
end)

-- --- alerts when you can't come in, or are put out ----------------------------------------------------------
local DENIED = {
	full = { "navigator.guestroomfull.title", "Room full", "navigator.guestroomfull.text", "This room is full. Try again later." },
	banned = { "navigator.banned.title", "Banned", "navigator.banned.text", "You've been banned from this room." },
	kicked = { "generic.alert.title", "Notice", "room.error.kicked", "You were kicked out of the room." },
	invisible = { "room.queue.error.title", "Can't enter", "room.queue.error.title", "Can't enter" },
}
P.receive("room.denied", function(_, data)
	local why = data.reason
	-- (the doorbell's and the password's answers go to their window)
	if why == "doorbell" or why == "noanswer" then RW.door(nil, "noanswer") return end
	if why == "wrongpassword" then RW.door(nil, "wrongpassword") return end
	local a = DENIED[why]
	if a then U.alert(T(a[1], a[2]), T(a[3], a[4]))
	else U.alert(T("room.queue.error.title", "Can't enter"), tostring(why)) end
end)
P.receive("room.muted", function(_, data)
	local m = math.ceil((tonumber(data.seconds) or 0) / 60)
	chat.AddText(Color(255, 120, 120), "[Bobba] ", color_white, T("room.muted.text", "You're muted here for %minutes% more minutes.", { minutes = m }))
	if BOBBA.chat and BOBBA.chat.muted then BOBBA.chat.muted(tonumber(data.seconds) or 0) end
end)
P.receive("room.muteAll", function(_, data) if R.current and R.current.access then R.current.access.muted = data.on end end)

-- --- going into a room: the doorbell, the password (NavigatorDoorStateView) --------------------------------
-- RW.visit(room): from the navigator; rooms with a doorbell or password ask first (not your own)
function RW.visit(room)
	local mine = room.owner == (LocalPlayer and IsValid(LocalPlayer()) and LocalPlayer():Nick() or nil)
	if not mine and room.door == "doorbell" then RW.door(room, "doorbell") return end
	if not mine and room.door == "password" then RW.door(room, "password") return end
	P.send("room.enter", { id = room.id })
end

-- the window: state "doorbell" (ring), "waiting", "noanswer", "password", "wrongpassword"
RW.doorState = RW.doorState or {}
function RW.door(room, state)
	local S = RW.doorState
	if room then S.room = room end
	if not S.room then return end
	S.state = state
	local W = 250
	local isBell = state == "doorbell" or state == "waiting" or state == "noanswer"
	U.window("door-state", W, 160, function(w, d)
		d:slimCard(T(isBell and "navigator.doorbell.title" or "navigator.password.title", isBell and "Doorbell" or "Password"))
		local x, y = 9, 31 + 8
		d:text(S.room.name or "", 14.4, x, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
		y = y + 21.6 + 4
		local msg = ({
			doorbell = { "navigator.doorbell.info", "This room has a doorbell. Ring it and wait for someone to let you in." },
			waiting = { "navigator.doorbell.waiting", "Waiting for someone to open the door..." },
			noanswer = { "navigator.doorbell.no.answer", "Nobody answered." },
			password = { "navigator.password.info", "This room is locked with a password." },
			wrongpassword = { "navigator.password.retryinfo", "Wrong password. Try again." },
		})[S.state]
		for _, l in ipairs(d:wrap(T(msg[1], msg[2]), 14.4, W - 18)) do
			d:text(l, 14.4, x, y, BLACK)
			y = y + 21.6
		end
		y = y + 8
		if isBell then
			if S.state == "doorbell" then
				d:btn(x, y, W - 18, 28, U.C.success, function()
					S.state = "pending"
					w:close()
					P.send("room.enter", { id = S.room.id })
				end)
				d:text(T("navigator.doorbell.button.ring", "Ring"), 12.6, W / 2, y + 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				y = y + 28 + 4
			end
		else
			d:text(T("navigator.password.enter", "Password"), 14.4, x, y, BLACK)
			y = y + 21.6 + 4
			local box = d:input("pw", x, y, W - 18, 28.9, { password = true, max = 20, onEnter = function(t)
				w:close()
				P.send("room.enter", { id = S.room.id, password = t })
			end })
			y = y + 28.9 + 8
			d:btn(x, y, W - 18, 28, U.C.success, function()
				local t = box:GetValue() or ""
				w:close()
				P.send("room.enter", { id = S.room.id, password = t })
			end)
			d:text(T("navigator.password.button.try", "Enter"), 12.6, W / 2, y + 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			y = y + 28 + 4
		end
		d:btn(x, y, W - 18, 28, U.C.danger, function()
			-- (stop waiting: to the hotel view, the server takes you out of the queue)
			if S.state == "waiting" then P.send("room.leave", {}) end
			S.room = nil
			w:close()
		end)
		d:text(T("generic.cancel", "Cancel"), 12.6, W / 2, y + 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		w:setHeight(y + 28 + 8)
	end)
end
P.receive("room.doorbell.waiting", function(_, data)
	RW.door(RW.doorState.room or { id = data.id, name = data.name }, "waiting")
end)
P.receive("room.password", function(_, data)
	RW.door(RW.doorState.room or { id = data.id, name = data.name }, "password")
end)

-- --- the doorbell for those inside (DoorbellWidgetView: 300 x 200) -----------------------------------------
RW.ringing = RW.ringing or {}
local function drawDoorbell(w, d)
	d:slimCard(T("navigator.doorbell.title", "Doorbell"))
	local x, y, cw = 9, 31 + 8, 300 - 18
	d:text(T("generic.username", "Username"), 14.4, x + 4, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	y = y + 21.6 + 4
	d:rect(x, y, cw, 1, U.C.border)
	y = y + 8
	for i, name in ipairs(RW.ringing) do
		if i % 2 == 1 then d:rect(x, y, cw, 36, Color(0, 0, 0, 13)) end
		d:text(name, 14.4, x + 4, y + 18, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local function answer(yes)
			P.send("room.doorbell.answer", { name = name, accept = yes })
			table.remove(RW.ringing, i)
			if #RW.ringing == 0 then w:close() end
		end
		local bw1 = d:textWidth(T("generic.accept", "Accept"), 12.6) + 16
		local bw2 = d:textWidth(T("generic.deny", "Deny"), 12.6) + 16
		local bx = x + cw - 4 - bw2
		d:btn(bx, y + 4, bw2, 28, U.C.danger, function() answer(false) end)
		d:text(T("generic.deny", "Deny"), 12.6, bx + bw2 / 2, y + 18, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		bx = bx - 4 - bw1
		d:btn(bx, y + 4, bw1, 28, U.C.success, function() answer(true) end)
		d:text(T("generic.accept", "Accept"), 12.6, bx + bw1 / 2, y + 18, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		y = y + 36
		d:rect(x, y, cw, 1, U.C.border)
	end
end
P.receive("room.doorbell.ring", function(_, data)
	for _, n in ipairs(RW.ringing) do if n == data.name then return end end
	RW.ringing[#RW.ringing + 1] = data.name
	if not U.isOpen("doorbell") then U.window("doorbell", 300, 200, drawDoorbell) end
end)
P.receive("room.doorbell.hide", function(_, data)
	for i, n in ipairs(RW.ringing) do if n == data.name then table.remove(RW.ringing, i) break end end
	if #RW.ringing == 0 and U.windows.doorbell then U.windows.doorbell:close() end
end)

-- --- the room settings (NavigatorRoomSettingsView, 400 wide) ---------------------------------------------
local TABS = { { 1, "Basic" }, { 2, "Access" }, { 3, "Rights" }, { 4, "Habbo Club" }, { 5, "Moderation" } }
RW.settingsTab = RW.settingsTab or 1

-- (every change: the whole settings saved, as nitro-react sends SaveRoomSettingsComposer)
local function save(changes)
	local s = RW.settings
	if not s then return end
	for k, v in pairs(changes or {}) do s[k] = v end
	P.send("room.settings.save", {
		id = s.id, name = s.name, description = s.description, state = s.stateNum, password = changes and changes.password or "",
		maxUsers = s.maxUsers, category = s.category, tags = s.tags, trade = s.trade, allowPets = s.allowPets,
		allowPetsEat = s.allowPetsEat, allowWalkthrough = s.allowWalkthrough, hideWall = s.hideWall,
		wallThickness = s.wallThickness, floorThickness = s.floorThickness, chatMode = s.chatMode, chatWeight = s.chatWeight,
		chatSpeed = s.chatSpeed, chatDistance = s.chatDistance, chatProtection = s.chatProtection,
		whoMute = s.whoMute, whoKick = s.whoKick, whoBan = s.whoBan, movement = s.movement,
	})
end
local STATE_NUM = { open = 0, doorbell = 1, password = 2, invisible = 3 }
-- the room's movement setting (hotel/roomlive.lua): 0 both, 1 clicking only, 2 steering only
function RW.MOVEMENT_OPTIONS()
	return {
		{ 0, T("bobba.roomsettings.movement.both", "Clicking and free movement") },
		{ 1, T("bobba.roomsettings.movement.click", "Clicking only") },
		{ 2, T("bobba.roomsettings.movement.free", "Free movement only (keys, controller)") },
	}
end

local function label(d, t, x, y, bold) d:text(t, 14.4, x, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, bold) end

local function tabBasic(w, d, x, y, cw)
	local s = RW.settings
	local lw, cx = cw * 0.25, x + cw * 0.25 + 4
	local ccw = cw - cw * 0.25 - 4
	-- name
	label(d, T("navigator.roomname", "Room name"), x, y + 4)
	local name = d:input("name", cx, y, ccw, 28.9, { max = 60, value = s.name, onBlur = function(t)
		if t ~= s.name and (utf8.len(t) or #t) >= 3 then save({ name = t }) end
	end })
	y = y + 28.9
	local typed = name:GetValue() or ""
	if (utf8.len(typed) or #typed) < 3 then
		d:text(T("navigator.roomsettings.roomnameismandatory", "Your room needs a name."), 12.6, cx, y + 1, DANGER, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
		y = y + 18.9
	end
	y = y + 8
	-- description
	label(d, T("navigator.roomsettings.desc", "Description"), x, y + 4)
	d:input("desc", cx, y, ccw, 47.8, { max = 255, multiline = true, value = s.description, onBlur = function(t)
		if t ~= s.description then save({ description = t }) end
	end })
	y = y + 47.8 + 8
	-- category
	label(d, T("navigator.category", "Category"), x, y + 4)
	local cats = { { 0, T("navigator.category.no_category", "No category") } }
	for _, c in ipairs(RW.CATEGORIES) do
		if not c.staff or (access().level or 0) >= 5 then cats[#cats + 1] = { c.id, T("navigator.flatcategory.global." .. c.code, c.name) } end
	end
	local selects = {}
	local cy0 = y
	selects[#selects + 1] = function() d:select("category", cx, cy0, ccw, 28.9, cats, s.category, function(v) save({ category = v }) end) end
	y = y + 28.9 + 8
	-- max visitors
	label(d, T("navigator.maxvisitors", "Max visitors"), x, y + 4)
	local maxOpts = {}
	for v = 10, s.maxUsersAllowed or 50, 5 do maxOpts[#maxOpts + 1] = { v, tostring(v) } end
	local my = y
	selects[#selects + 1] = function() d:select("max", cx, my, ccw, 28.9, maxOpts, s.maxUsers, function(v) save({ maxUsers = v }) end) end
	y = y + 28.9 + 8
	-- trading
	label(d, T("navigator.tradesettings", "Trading"), x, y + 4)
	local ty = y
	selects[#selects + 1] = function() d:select("trade", cx, ty, ccw, 28.9, {
		{ 0, T("navigator.roomsettings.trade_not_allowed", "No trading") },
		{ 1, T("navigator.roomsettings.trade_not_with_Controller", "Only players with rights") },
		{ 2, T("navigator.roomsettings.trade_allowed", "Everyone can trade") },
	}, s.trade, function(v) save({ trade = v }) end) end
	y = y + 28.9 + 8
	-- moving: clicking, free movement with keys or a controller, or both (steering.lua)
	label(d, T("bobba.roomsettings.movement", "Movement"), x, y + 4)
	local mvy = y
	selects[#selects + 1] = function() d:select("movement", cx, mvy, ccw, 28.9, RW.MOVEMENT_OPTIONS(), s.movement or 0, function(v) save({ movement = v }) end) end
	y = y + 28.9 + 8
	-- tags: two boxes side by side
	label(d, T("navigator.tags", "Tags"), x, y + 4)
	local tw = (ccw - 4) / 2
	local function tagBox(i)
		return d:input("tag" .. i, cx + (i - 1) * (tw + 4), y, tw, 28.9, { max = 15, value = s.tags[i] or "", onBlur = function()
			local t1 = (w.inputs.tag1 and w.inputs.tag1:GetValue() or ""):gsub("^%s+", ""):gsub("%s+$", "")
			local t2 = (w.inputs.tag2 and w.inputs.tag2:GetValue() or ""):gsub("^%s+", ""):gsub("%s+$", "")
			local list = {}
			if t1 ~= "" then list[#list + 1] = t1 end
			if t2 ~= "" then list[#list + 1] = t2 end
			if table.concat(list, ";") ~= table.concat(s.tags, ";") then RW.lastTagError = nil save({ tags = list }) end
		end })
	end
	tagBox(1)
	tagBox(2)
	y = y + 28.9
	if RW.lastTagError then
		d:text(T(RW.lastTagError[1], RW.lastTagError[2]), 12.6, cx, y + 1, DANGER, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
		y = y + 18.9
	end
	y = y + 8
	-- walking through each other
	d:check(cx, y + 3.6, s.allowWalkthrough, false, function() save({ allowWalkthrough = not s.allowWalkthrough }) end)
	d:click(cx + 18, y, ccw - 18, 21.6, function() save({ allowWalkthrough = not s.allowWalkthrough }) end)
	d:text(T("navigator.roomsettings.allow_walk_through", "Players can walk through each other"), 14.4, cx + 14.4 + 4, y, BLACK)
	y = y + 21.6 + 8
	-- delete
	local dt = T("navigator.roomsettings.delete", "Delete room")
	local dw = d:textWidth(dt, 14.4, true) + 14.4 + 4
	local dx = x + (cw - dw) / 2
	d:click(dx, y, dw, 21.6, function()
		U.confirm(T("navigator.roomsettings.deleteroom.confirm.title", "Delete room?"),
			T("navigator.roomsettings.deleteroom.confirm.message", "Delete %room_name%? Furni in the room goes back to your inventory.", { room_name = s.name }),
			function()
				P.send("room.delete", { id = s.id })
				w:close()
				if BOBBA.navigator and BOBBA.navigator.open then BOBBA.navigator.open("myworld_view") end
			end)
	end)
	d:fa("times", dx, y + 3.6, 14.4, DANGER)
	d:text(dt, 14.4, dx + 14.4 + 4, y, DANGER, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	d:rect(dx + 14.4 + 4, y + 19, dw - 18.4, 1, DANGER)
	y = y + 21.6
	-- (the drop-downs last: their lists go over what's under them)
	for i = #selects, 1, -1 do selects[i]() end
	return y
end

local function radio(d, x, y, on, text, fn)
	d:check(x, y + 3.6, on, true, fn)
	d:click(x, y, d:textWidth(text, 14.4) + 18.4, 21.6, fn)
	d:text(text, 14.4, x + 18.4, y, BLACK)
	return y + 21.6 + 4
end

local function tabAccess(w, d, x, y, cw)
	local s = RW.settings
	label(d, T("navigator.roomsettings.roomaccess.caption", "Room access"), x, y, true)
	y = y + 21.6 + 4
	for _, l in ipairs(d:wrap(U.plain(T("navigator.roomsettings.roomaccess.info", "Choose who can enter your room.")), 14.4, cw)) do
		label(d, l, x, y)
		y = y + 21.6
	end
	y = y + 8
	label(d, T("navigator.roomsettings.doormode", "Who can come in?"), x, y, true)
	y = y + 21.6 + 4
	local trying = RW.tryingPassword
	local function setState(n) RW.tryingPassword = false save({ stateNum = n }) end
	y = radio(d, x, y, s.stateNum == 0 and not trying, T("navigator.roomsettings.doormode.open", "Open to everyone"), function() setState(0) end)
	y = radio(d, x, y, s.stateNum == 1 and not trying, T("navigator.roomsettings.doormode.doorbell", "Ring the doorbell"), function() setState(1) end)
	y = radio(d, x, y, s.stateNum == 3 and not trying, T("navigator.roomsettings.doormode.invisible", "Hidden (only players with rights)"), function() setState(3) end)
	local pwOn = trying or s.stateNum == 2
	d:check(x, y + 3.6, pwOn, true, function() RW.tryingPassword = true end)
	if not pwOn then
		d:click(x, y, 200, 21.6, function() RW.tryingPassword = true end)
		d:text(T("navigator.roomsettings.doormode.password", "Password"), 14.4, x + 18.4, y, BLACK)
		y = y + 21.6 + 8
	else
		local px = x + 18.4
		d:text(T("navigator.roomsettings.doormode.password", "Password"), 14.4, px, y, BLACK)
		y = y + 21.6 + 4
		local bw = (cw - 18.4) * 0.3333
		local a = d:input("pw1", px, y, bw, 28.9, { password = true, max = 20, placeholder = T("navigator.roomsettings.password", "Password") })
		if a:HasFocus() then RW.tryingPassword = true end
		y = y + 28.9 + 4
		local p1 = a:GetValue() or ""
		if RW.tryingPassword and p1 == "" then
			d:text(T("navigator.roomsettings.passwordismandatory", "Please enter a password."), 12.6, px, y, DANGER, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
			y = y + 18.9 + 4
		end
		local b = d:input("pw2", px, y, bw, 28.9, { password = true, max = 20, placeholder = T("navigator.roomsettings.passwordconfirm", "Repeat password"), onBlur = function(p2)
			if p1 ~= "" and p1 == p2 then
				RW.tryingPassword = false
				save({ stateNum = 2, password = p1 })
				w.inputs.pw1:SetText("")
				w.inputs.pw2:SetText("")
			end
		end })
		y = y + 28.9 + 4
		local p2 = b:GetValue() or ""
		if RW.tryingPassword and p2 ~= "" and p1 ~= p2 then
			d:text(T("navigator.roomsettings.invalidconfirm", "The passwords don't match."), 12.6, px, y, DANGER, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
			y = y + 18.9 + 4
		end
		y = y + 4
	end
	label(d, T("navigator.roomsettings.pets", "Pets"), x, y, true)
	y = y + 21.6 + 4
	d:check(x, y + 3.6, s.allowPets, false, function() save({ allowPets = not s.allowPets }) end)
	d:text(T("navigator.roomsettings.allowpets", "Visitors can bring pets"), 14.4, x + 18.4, y, BLACK)
	y = y + 21.6 + 4
	d:check(x, y + 3.6, s.allowPetsEat, false, function() save({ allowPetsEat = not s.allowPetsEat }) end)
	d:text(T("navigator.roomsettings.allowfoodconsume", "Visitors can feed pets"), 14.4, x + 18.4, y, BLACK)
	return y + 21.6
end

-- a list in a white box (100 high): names you click
local function nameList(d, id, x, y, w, names, onClick)
	d:round(4, x, y, w, 100, WHITE)
	local total = #names * (21.6 + 4)
	local off = d:scroll(id, x + 8, y + 8, w - 16, 84, total)
	d:clip(x + 8, y + 8, w - 16, 84, function()
		for i, n in ipairs(names) do
			local ry = y + 8 + (i - 1) * (21.6 + 4) - off
			local hover = d:click(x + 8, ry, w - 16, 21.6, function() onClick(n, i) end)
			d:icon("friends-profile", x + 8, ry + 5, 13, 11)
			d:text(n.name, 14.4, x + 8 + 13 + 4, ry, hover and U.C.primary or BLACK)
		end
	end)
end

local function tabRights(w, d, x, y, cw)
	local s = RW.settings
	local half = (cw - 8) / 2
	local list = s.rights or {}
	label(d, T("navigator.flatctrls.userswithrights", "Players with rights (%displayed% / %total%)", { displayed = #list, total = #list }), x, y, true)
	nameList(d, "rights", x, y + 21.6 + 8, half, list, function(n)
		P.send("room.rights.remove", { id = s.id, keys = { n.key } })
		for i, r in ipairs(list) do if r.key == n.key then table.remove(list, i) break end end
	end)
	local by = y + 21.6 + 8 + 100 - 28
	d:btn(x + half + 8, by, half, 28, U.C.danger, function()
		P.send("room.rights.removeAll", { id = s.id })
		s.rights = {}
	end, #list == 0)
	d:text(T("navigator.flatctrls.clear", "Remove all"), 12.6, x + half + 8 + half / 2, by + 14, Color(255, 255, 255, #list == 0 and 166 or 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	return y + 21.6 + 8 + 100
end

local function tabChat(w, d, x, y, cw)
	local s = RW.settings
	local half = (cw - 8) / 2
	label(d, T("navigator.roomsettings.vip.caption", "Habbo Club settings"), x, y, true)
	y = y + 21.6 + 4
	for _, l in ipairs(d:wrap(U.plain(T("navigator.roomsettings.vip.info", "Members of Habbo Club can change these.")), 14.4, cw)) do
		label(d, l, x, y)
		y = y + 21.6
	end
	y = y + 8
	local top = y
	local selects = {}
	-- left: chat
	local ly = y
	label(d, T("navigator.roomsettings.chat_settings", "Chat settings"), x, ly, true)
	ly = ly + 21.6 + 4
	for _, l in ipairs(d:wrap(U.plain(T("navigator.roomsettings.chat_settings.info", "How chat looks and is heard in your room.")), 14.4, half)) do
		label(d, l, x, ly)
		ly = ly + 21.6
	end
	ly = ly + 4
	local function sel(id, yy, opts, value, key)
		selects[#selects + 1] = function() d:select(id, x, yy, half, 28.9, opts, value, function(v) save({ [key] = v }) end) end
	end
	sel("mode", ly, { { 0, T("navigator.roomsettings.chat.mode.free.flow", "Free flow") }, { 1, T("navigator.roomsettings.chat.mode.line.by.line", "Line by line") } }, s.chatMode, "chatMode")
	ly = ly + 28.9 + 4
	sel("weight", ly, { { 1, T("navigator.roomsettings.chat.bubbles.width.normal", "Normal width") }, { 2, T("navigator.roomsettings.chat.bubbles.width.thin", "Thin") },
		{ 0, T("navigator.roomsettings.chat.bubbles.width.wide", "Wide") } }, s.chatWeight, "chatWeight")
	ly = ly + 28.9 + 4
	sel("speed", ly, { { 0, T("navigator.roomsettings.chat.speed.fast", "Fast scrolling") }, { 1, T("navigator.roomsettings.chat.speed.normal", "Normal scrolling") },
		{ 2, T("navigator.roomsettings.chat.speed.slow", "Slow scrolling") } }, s.chatSpeed, "chatSpeed")
	ly = ly + 28.9 + 4
	sel("flood", ly, { { 2, T("navigator.roomsettings.chat.flood.loose", "Loose flood filter") }, { 1, T("navigator.roomsettings.chat.flood.normal", "Normal flood filter") },
		{ 0, T("navigator.roomsettings.chat.flood.strict", "Strict flood filter") } }, s.chatProtection, "chatProtection")
	ly = ly + 28.9 + 4
	label(d, T("navigator.roomsettings.chat_settings.hearing.distance", "Hearing distance"), x, ly)
	ly = ly + 21.6 + 4
	d:input("distance", x, ly, half, 28.9, { max = 2, value = tostring(s.chatDistance), onBlur = function(t)
		local n = tonumber(t)
		if n and n ~= s.chatDistance then save({ chatDistance = math.floor(math.abs(n)) }) end
	end })
	ly = ly + 28.9
	-- right: the room's look
	local rx, ry = x + half + 8, top
	label(d, T("navigator.roomsettings.vip_settings", "Room look"), rx, ry, true)
	ry = ry + 21.6 + 4
	d:check(rx, ry + 3.6, s.hideWall, false, function() save({ hideWall = not s.hideWall }) end)
	d:text(T("navigator.roomsettings.hide_walls", "Hide walls"), 14.4, rx + 18.4, ry, BLACK)
	ry = ry + 21.6 + 4
	local function thick(kind)
		return { { 0, T("navigator.roomsettings." .. kind .. "_thickness.normal", "Normal") }, { 1, T("navigator.roomsettings." .. kind .. "_thickness.thick", "Thick") },
			{ -1, T("navigator.roomsettings." .. kind .. "_thickness.thin", "Thin") }, { -2, T("navigator.roomsettings." .. kind .. "_thickness.thinnest", "Thinnest") } }
	end
	local wy = ry
	selects[#selects + 1] = function() d:select("wallT", rx, wy, half, 28.9, thick("wall"), s.wallThickness, function(v) save({ wallThickness = v }) end) end
	ry = ry + 28.9 + 4
	local fy = ry
	selects[#selects + 1] = function() d:select("floorT", rx, fy, half, 28.9, thick("floor"), s.floorThickness, function(v) save({ floorThickness = v }) end) end
	for i = #selects, 1, -1 do selects[i]() end
	return math.max(ly, ry + 28.9)
end

local function tabModeration(w, d, x, y, cw)
	local s = RW.settings
	local half = (cw - 8) / 2
	local bans = s.bans or {}
	label(d, T("navigator.roomsettings.moderation.banned.users", "Banned players") .. " (" .. #bans .. ")", x, y, true)
	nameList(d, "bans", x, y + 21.6 + 8, half, bans, function(n) RW.selectedBan = n end)
	local by = y + 21.6 + 8 + 100 + 8
	local sel = RW.selectedBan
	d:btn(x, by, half, 28, U.C.primary, function()
		P.send("room.unban", { id = s.id, key = sel.key })
		RW.selectedBan = nil
	end, sel == nil)
	d:text(d:fit(T("navigator.roomsettings.moderation.unban", "Unban") .. " " .. (sel and sel.name or ""), 12.6, half - 8), 12.6, x + half / 2, by + 14,
		Color(255, 255, 255, sel and 255 or 166), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local rx, ry = x + half + 8, y
	local selects = {}
	local function block(head, id, opts, value, key)
		label(d, T(head[1], head[2]), rx, ry, true)
		ry = ry + 21.6 + 4
		local yy = ry
		selects[#selects + 1] = function() d:select(id, rx, yy, half, 28.9, opts, value, function(v) save({ [key] = v }) end) end
		ry = ry + 28.9 + 8
	end
	local none = { 0, T("navigator.roomsettings.moderation.none", "Nobody") }
	local rights = { 1, T("navigator.roomsettings.moderation.rights", "Players with rights") }
	block({ "navigator.roomsettings.moderation.mute.header", "Who can mute?" }, "mute", { none, rights }, s.whoMute, "whoMute")
	block({ "navigator.roomsettings.moderation.kick.header", "Who can kick?" }, "kick", { none, rights, { 2, T("navigator.roomsettings.moderation.all", "Everyone") } }, s.whoKick, "whoKick")
	block({ "navigator.roomsettings.moderation.ban.header", "Who can ban?" }, "ban", { none, rights }, s.whoBan, "whoBan")
	for i = #selects, 1, -1 do selects[i]() end
	return math.max(by + 28, ry - 8)
end

local function drawSettings(w, d)
	local s = RW.settings
	if not s then w:close() return end
	local tabs = {}
	for _, t in ipairs(TABS) do tabs[#tabs + 1] = { id = t[1], label = T("navigator.roomsettings.tab." .. t[1], t[2]) } end
	d:card(T("navigator.roomsettings", "Room settings"), tabs, RW.settingsTab, function(id) RW.settingsTab = id end)
	local x, y, cw = 9, 67 + 8, 400 - 18
	local fn = ({ tabBasic, tabAccess, tabRights, tabChat, tabModeration })[RW.settingsTab]
	-- (the text boxes of other tabs are put away)
	local bottom = fn(w, d, x, y, cw)
	w:setHeight(math.ceil(bottom + 8))
end

-- the settings from the server: opens the window (or fills it in again)
P.receive("room.settings", function(_, data)
	data.stateNum = STATE_NUM[data.state] or 0
	data.tags = data.tags or {}
	local first = not (RW.settings and RW.settings.id == data.id and U.isOpen("room-settings"))
	RW.settings = data
	if first then
		RW.settingsTab = 1
		RW.tryingPassword = false
		RW.lastTagError = nil
		RW.selectedBan = nil
		U.window("room-settings", 400, 400, drawSettings)
	end
end)
P.receive("room.settings.saved", function(_, data)
	if RW.settings and RW.settings.id == data.id then P.send("room.settings.get", { id = data.id }) end
end)
P.receive("room.settings.error", function(_, data)
	local code = tonumber(data.code)
	if code == 11 or code == 12 then RW.lastTagError = { "navigator.roomsettings.nonuserchoosabletag", "You can't use that tag." }
	elseif code == 13 then RW.lastTagError = { "navigator.roomsettings.toomanycharacters", "Too long!" }
	elseif code == 5 then RW.tryingPassword = true
	end
	-- (what the server kept)
	if RW.settings then P.send("room.settings.get", { id = RW.settings.id }) end
end)

function RW.openSettings(id)
	P.send("room.settings.get", { id = id })
end

-- Habbo's room categories (the server's list; hotel/roomaccess.lua)
RW.CATEGORIES = {
	{ id = 1, code = "BC", name = "Builders Club" }, { id = 2, code = "BUILDING", name = "Building" }, { id = 3, code = "CHAT", name = "Chat and discussion" },
	{ id = 4, code = "FANSITE", name = "Fansite" }, { id = 5, code = "GAMES", name = "Games" }, { id = 6, code = "HELP", name = "Help" },
	{ id = 7, code = "LIFE", name = "Life" }, { id = 8, code = "OFFICIAL", name = "Official", staff = true }, { id = 9, code = "PARTY", name = "Party" },
	{ id = 10, code = "PERSONAL", name = "Personal" }, { id = 11, code = "REVIEWS", name = "Reviews" }, { id = 12, code = "TRADING", name = "Trading" },
}

-- --- the room info (NavigatorRoomInfoView: primary-slim, 325 wide) ---------------------------------------
local function drawRoomInfo(w, d)
	local c = R.current
	if not c then w:close() return end
	local a = access()
	local W = 325
	d:slimCard(T("navigator.roomsettings.roominfo", "Room info"))
	local x, y = 9, 31 + 8
	-- the picture (110 x 110): the room's thumbnail, or Habbo's placeholder
	d:box(x, y, 110, 110, 1, 4, U.C.border, Color(0, 0, 0, 32))
	local thumb = tonumber(a.thumbnail) or 0
	if not (thumb > 0 and BOBBA.camera and BOBBA.camera.drawPhoto(d, thumb, x + 1, y + 1, 108, 108)) then
		d:icon("nav-thumbnail", x + 10, y + 10, 90, 90)
	end
	-- (the owner's camera on it: a new thumbnail, LayoutMiniCameraView)
	if (a.level or 0) >= 4 and BOBBA.camera then
		d:click(x + 110 - 4 - 28, y + 4, 28, 22, function() BOBBA.camera.openThumbnail() end)
		if not d:icon("camera_camera_icon", x + 110 - 4 - 28, y + 4) then d:icon("camera", x + 110 - 4 - 22, y + 4, 22, 22, { scale = 0.5 }) end
	end
	local cx = x + 110 + 8
	local cw = W - 9 - cx
	-- name with the house (your home room: clear; not: half see-through) and the favourite
	local home = RW.home == c.id
	-- (clicked again: not your home room any more)
	d:click(cx, y + 3, 19, 14, function() P.send("room.home", { id = home and 0 or c.id }) end)
	d:icon("house-small", cx, y + 3, 19, 14, { alpha = home and 255 or 128 })
	local fav = RW.favourites and RW.favourites[c.id]
	d:click(cx + 23, y + 2, 16, 16, function() P.send("room.favourite", { id = c.id, on = not fav }) end)
	d:icon(fav and "nav-fav-yes" or "nav-fav-no", cx + 23, y + 2, 16, 16)
	d:text(d:fit(c.name or "", 14.4, cw - 47 - 28, true), 14.4, cx + 43, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	-- the cog: the settings (owner and staff)
	local canSettings = (a.level or 0) >= 4
	if canSettings then
		d:click(W - 9 - 21, y, 21, 21, function() RW.openSettings(c.id) end)
		d:icon("room-settings", W - 9 - 21, y, 21, 21)
	end
	local ty = y + 21.6 + 4
	if c.owner then
		local ot = T("navigator.roomownercaption", "Owner:")
		d:text(ot, 14.4, cx, ty, MUTED)
		d:text(d:fit(c.owner, 14.4, cw - d:textWidth(ot, 14.4) - 6), 14.4, cx + d:textWidth(ot, 14.4) + 4, ty, BLACK)
		ty = ty + 21.6 + 4
	end
	-- how you move here, when it isn't the usual (clicking and steering)
	local mv = tonumber(a.movement) or 0
	if mv ~= 0 then
		local mt = T("bobba.roomsettings.movement", "Movement") .. ":"
		local label2 = RW.MOVEMENT_OPTIONS()[mv + 1][2]
		-- (a little four-way arrow)
		local ix, iy = cx + 7, ty + 10.8
		d:line(ix - 6, iy, ix + 6, iy, 1.6, MUTED)
		d:line(ix, iy - 6, ix, iy + 6, 1.6, MUTED)
		for _, k in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
			local px, py = ix + k[1] * 6, iy + k[2] * 6
			d:line(px, py, px - k[1] * 3 + k[2] * 3, py - k[2] * 3 + k[1] * 3, 1.6, MUTED)
			d:line(px, py, px - k[1] * 3 - k[2] * 3, py - k[2] * 3 - k[1] * 3, 1.6, MUTED)
		end
		d:text(mt, 14.4, cx + 18, ty, MUTED)
		d:text(d:fit(label2, 14.4, cw - 22 - d:textWidth(mt, 14.4)), 14.4, cx + 22 + d:textWidth(mt, 14.4), ty, BLACK)
		ty = ty + 21.6 + 4
	end
	-- tags: grey chips (a search for the tag)
	local tx = cx
	for _, t in ipairs(a.tags or {}) do
		local tw = d:textWidth("#" .. t, 14.4) + 8
		d:click(tx, ty, tw, 29.6, function() HUD.actions.tagSearch(t) end)
		d:round(4, tx, ty, tw, 29.6, U.C.muted)
		d:text("#" .. t, 14.4, tx + 4, ty + 4, BLACK)
		tx = tx + tw + 4
	end
	if #(a.tags or {}) > 0 then ty = ty + 29.6 + 4 end
	-- the description (at most 50 high)
	local lines = d:wrap(c.description or "", 14.4, cw)
	for i = 1, math.min(#lines, 2) do d:text(lines[i], 14.4, cx, ty + (i - 1) * 21.6, BLACK) end
	local by = math.max(y + 110, ty + math.min(#lines, 2) * 21.6) + 8
	-- buttons: mute all (owner and staff)
	if canSettings then
		d:btn(x, by, W - 18, 28, U.C.primary, function() P.send("room.muteAll", {}) end)
		d:text(a.muted and T("navigator.muteall_on", "Unmute all") or T("navigator.muteall_off", "Mute all"), 12.6, W / 2, by + 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		by = by + 28 + 4
		-- the floor plan editor (client/floorplan.lua)
		d:btn(x, by, W - 18, 28, U.C.primary, function() BOBBA.floorplanEditor.open() end)
		d:text(T("open.floor.plan.editor", "Floor plan editor"), 12.6, W / 2, by + 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		by = by + 28 + 4
	end
	w:setHeight(by + 8 - 4)
end

function RW.toggleRoomInfo()
	U.toggle("room-info", function() U.window("room-info", 325, 200, drawRoomInfo) end)
end
HUD.actions.roomSettings = RW.toggleRoomInfo
HUD.actions.tagSearch = function(tag)
	local NAV = BOBBA.navigator
	if NAV and NAV.open then NAV.open("hotel_view", "tag:" .. tag) end
end

-- leaving the room closes its windows
BOBBA.events.on("roomShown", "bobba.roomwindows", function(data)
	for _, id in ipairs({ "room-info", "room-settings", "doorbell", "door-state" }) do
		if U.windows[id] and not (id == "room-settings" and RW.settings and RW.settings.id == data.id) then U.windows[id]:close() end
	end
	RW.ringing = {}
	RW.doorState.room = nil
	RW.menu = nil
end)

-- --- the menu over an avatar (AvatarInfoWidgetAvatarView / ...OwnAvatarView) ------------------------------
-- RW.menu = { unit = id, mode = "normal" | "moderate" | "ban" | "mute" }; RW.collapsed (Nitro's COLLAPSED)
local MENU_W = 125
local function target() return RW.menu and R.units and R.units[RW.menu.unit] end

-- what I may do to someone (Nitro's canBeKicked/Banned/Muted from the room's settings, the owner never)
local function powers(u)
	local a = access()
	local lvl = a.level or 0
	local isOwnerTarget = u.key and u.key == a.ownerKey
	local hasRights = u.key and a.rights and a.rights[u.key]
	local p = {
		kick = not isOwnerTarget and a.canKick,
		ban = not isOwnerTarget and not hasRights and a.canBan,
		mute = not isOwnerTarget and not hasRights and a.canMute,
		giveRights = lvl >= 4 and not isOwnerTarget and not hasRights,
		removeRights = lvl >= 4 and hasRights,
	}
	p.any = p.kick or p.ban or p.mute or p.giveRights or p.removeRights
	return p
end

local function menuItems()
	local u = target()
	if not u then return {} end
	local m = RW.menu.mode or "normal"
	local items = {}
	local function item(text, fn, chevron) items[#items + 1] = { text = text, fn = fn, chevron = chevron } end
	local id = u.id
	local close = function() RW.menu = nil end
	if u.id == R.you then
		-- AvatarInfoWidgetOwnAvatarView: clothes, dances, expressions, signs
		local level = (HUD.purse and HUD.purse.clubLevel) or 0
		local club, vip = level >= 1, level >= 2
		local dancing = (u.dance or 0) > 0
		local function send(name, data) return function() P.send(name, data) close() end end
		if m == "normal" then
			item(T("widget.memenu.myclothes", "My clothes"), function() close() if BOBBA.avatarEditor then BOBBA.avatarEditor.open() end end)
			if club then item(T("widget.memenu.dance", "Dance"), function() RW.menu.mode = "dances" end, "right")
			elseif dancing then item(T("widget.memenu.dance.stop", "Stop dancing"), send("room.dance", { style = 0 }))
			else item(T("widget.memenu.dance", "Dance"), send("room.dance", { style = 1 })) end
			item(T("infostand.link.expressions", "Expressions"), function() RW.menu.mode = "expressions" end, "right")
			item(T("infostand.show.signs", "Signs"), function() RW.menu.mode = "signs" end, "right")
		elseif m == "dances" then
			if dancing then item(T("widget.memenu.dance.stop", "Stop dancing"), send("room.dance", { style = 0 })) end
			for i = 1, 4 do item(T("widget.memenu.dance" .. i, "Dance " .. i), send("room.dance", { style = i })) end
			item(T("generic.back", "Back"), function() RW.menu.mode = "normal" end, "left")
		elseif m == "expressions" then
			local lying = u.posture == "lay"
			if (u.posture or "std") == "std" then item(T("widget.memenu.sit", "Sit"), send("room.posture", { sit = true })) end
			if u.floorSit then item(T("widget.memenu.stand", "Stand"), send("room.posture", { sit = false })) end
			if not lying then
				item(T("widget.memenu.wave", "Wave"), send("room.expression", { id = 1 }))
				items[#items + 1] = { text = T("widget.memenu.blow", "Blow a kiss"), fn = send("room.expression", { id = 2 }), disabled = not vip, hc = not vip }
				items[#items + 1] = { text = T("widget.memenu.laugh", "Laugh"), fn = send("room.expression", { id = 3 }), disabled = not vip, hc = not vip }
			end
			item(T("widget.memenu.idle", "Idle"), send("room.expression", { id = 5 }))
			item(T("generic.back", "Back"), function() RW.menu.mode = "normal" end, "left")
		elseif m == "signs" then
			-- (Nitro's grid: three a row)
			local rows = { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 10, 11, 12 }, { 0, 13, 15 }, { 14, 17, 16 } }
			local icons = { [11] = "sign-heart", [12] = "sign-skull", [13] = "sign-exclamation", [14] = "sign-soccer", [15] = "sign-smile", [16] = "sign-red", [17] = "sign-yellow" }
			for _, row in ipairs(rows) do
				local cells = {}
				for _, n in ipairs(row) do cells[#cells + 1] = { text = tostring(n), icon = icons[n], fn = send("room.sign", { id = n }) } end
				items[#items + 1] = { cells = cells }
			end
			item(T("generic.back", "Back"), function() RW.menu.mode = "normal" end, "left")
		end
		return items
	end
	local p = powers(u)
	if m == "normal" then
		item(T("infostand.button.whisper", "Whisper"), function()
			close()
			-- (the chat input gets ":whisper name ", nitro-react's whisper prefix)
			local C = R.chatState
			if C and IsValid(C.input) and IsValid(C.input.entry) then
				local t = ":whisper " .. (u.name or "") .. " "
				C.input.entry:SetText(t)
				C.input.entry:SetCaretPos(#t)
				C.input.entry:RequestFocus()
			end
		end)
		if p.any then item(T("infostand.link.moderate", "Moderate"), function() RW.menu.mode = "moderate" end, "right") end
	elseif m == "moderate" then
		if p.kick then item(T("infostand.button.kick", "Kick"), function() P.send("room.kick", { unit = id }) close() end) end
		if p.mute then item(T("infostand.button.mute", "Mute"), function() RW.menu.mode = "mute" end, "right") end
		if p.ban then item(T("infostand.button.ban", "Ban"), function() RW.menu.mode = "ban" end, "right") end
		if p.giveRights then item(T("infostand.button.giverights", "Give rights"), function() P.send("room.rights.give", { unit = id }) close() end) end
		if p.removeRights then item(T("infostand.button.removerights", "Remove rights"), function() P.send("room.rights.remove", { unit = id }) close() end) end
		item(T("generic.back", "Back"), function() RW.menu.mode = "normal" end, "left")
	elseif m == "ban" then
		item(T("infostand.button.ban_hour", "Ban 1 hour"), function() P.send("room.ban", { unit = id, kind = "hour" }) close() end)
		item(T("infostand.button.ban_day", "Ban 1 day"), function() P.send("room.ban", { unit = id, kind = "day" }) close() end)
		item(T("infostand.button.perm_ban", "Ban forever"), function() P.send("room.ban", { unit = id, kind = "perm" }) close() end)
		item(T("generic.back", "Back"), function() RW.menu.mode = "moderate" end, "left")
	elseif m == "mute" then
		for _, n in ipairs({ 2, 5, 10 }) do
			item(T("infostand.button.mute_" .. n .. "min", "Mute " .. n .. " minutes"), function() P.send("room.mute", { unit = id, minutes = n }) close() end)
		end
		item(T("generic.back", "Back"), function() RW.menu.mode = "moderate" end, "left")
	end
	return items
end

local function menuSize()
	local n = RW.collapsed and 0 or #menuItems()
	-- border 2 + padding 2, header 25 + 2, items 24 + 2 each (the last without), the caret 18
	return MENU_W, 4 + 25 + 2 + (n > 0 and (n * 26 - 2) or 0) + 18 + 4 + 7
end

local function drawMenu(w, d)
	local u = target()
	if not u then return end
	local W, H = d.width, d.height - 7
	-- #1c323f with a 2px see-through white border, 4 round
	d:round(4, 0, 0, W, H, Color(255, 255, 255, 128))
	d:round(3, 2, 2, W - 4, H - 4, Color(28, 50, 63))
	-- the arrow under it (pointing at the avatar)
	local s = d.s
	draw.NoTexture()
	surface.SetDrawColor(255, 255, 255, 128)
	surface.DrawPoly(V.clockwise({ { x = (W / 2 - 7) * s, y = H * s }, { x = (W / 2 + 7) * s, y = H * s }, { x = (W / 2) * s, y = (H + 7) * s } }))
	local x, y, iw = 4, 4, W - 8
	-- the name (#3d5f6e, 16px)
	d:rect(x, y, iw, 25, Color(61, 95, 110))
	d:text(d:fit(u.name or "", 16, iw - 8), 16, W / 2, y + 12.5, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	y = y + 25 + 2
	if not RW.collapsed then
		local function cell(cx2, cw2, it)
			local hover = (not it.disabled) and d:click(cx2, y, cw2, 24, it.fn) or false
			-- two halves: #131e25 over #0d171d (hover #21516e / #1e465e)
			d:rect(cx2, y, cw2, 12, hover and Color(33, 81, 110) or Color(19, 30, 37))
			d:rect(cx2, y + 12, cw2, 12, hover and Color(30, 70, 94) or Color(13, 23, 29))
			local a = it.disabled and 128 or 255
			if it.icon and d:icon(it.icon, cx2, y, cw2, 24, { alpha = a }) then return end
			local tx2 = cx2 + cw2 / 2
			if it.hc then
				-- (Habbo Club's: the HC coin before it)
				local tw = d:textWidth(it.text, 12.6)
				d:icon("currency-hc", tx2 - tw / 2 - 10, y + 4, 16, 16, { alpha = a })
				tx2 = tx2 + 9
			end
			d:text(d:fit(it.text, 12.6, it.chevron and cw2 - 28 or cw2 - 6), 12.6, tx2, y + 12, Color(255, 255, 255, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		for i, it in ipairs(menuItems()) do
			if it.cells then
				-- (menu-list-split-3: a row of three, 2 apart)
				local n = #it.cells
				local cw2 = (iw - (n - 1) * 2) / n
				for j, c in ipairs(it.cells) do cell(x + (j - 1) * (cw2 + 2), cw2, c) end
			else
				cell(x, iw, it)
			end
			if it.chevron == "right" then d:fa("chevron-right", x + iw - 8 - 9, y + 5.7, 12.6, WHITE) end
			if it.chevron == "left" then d:fa("chevron-left", x + 8, y + 5.7, 12.6, WHITE) end
			y = y + 26
		end
		y = y - 2
	end
	-- the caret: folds the menu (and stays so for the next one)
	d:click(x, y, iw, 18, function() RW.collapsed = not RW.collapsed end)
	d:fa(RW.collapsed and "caret-up" or "caret-down", W / 2 - 8, y, 16, WHITE)
end

-- where it goes: its bottom at the top of the avatar (down 15 when standing), clamped to the screen
local function placeMenu(sw, sh)
	local u = target()
	if not u or V.mode ~= "room" or not R.unitPosition then return nil end
	local x, y, z = R.unitPosition(u)
	local sx, sy, k = V.project(x, y, z)
	if not sx then return nil end
	local s = U.scale()
	local mw, mh = menuSize()
	local lift = (u.posture == "sit" and 32 or (u.posture == "lay" and 70 or 0))
	local top = (sy - (110 - lift) * k) / s + 15
	local mx = math.floor(sx / s - mw / 2)
	local my = math.floor(top - mh)
	mx = math.max(10, math.min(sw - mw - 10, mx))
	my = math.max(10, math.min(sh - mh - 10, my))
	return mx, my, mw, mh
end

U.hud("avatar-menu", placeMenu, drawMenu)

-- --- the infostand for someone (InfoStandWidgetUserView: 190 wide, 10 from the right, 65 from the bottom) --
local function standSize() return 190, 8 + 21.6 + 4 + 1 + 4 + 130 + 4 + 1 + 4 + 26 + 8 end
local function drawStand(w, d)
	local u = target()
	if not u then return end
	local W, H = d.width, d.height
	d:darkBox(0, 0, W, H, 4)
	local x, y = 8, 8
	-- (the profile: the icon or the name)
	local HSo = BOBBA.habboSocial
	if u.key and HSo and HSo.openProfile then d:click(x, y, W - 16 - 18, 21.6, function() HSo.openProfile(u.key) end) end
	d:icon("friends-profile", x, y + 5, 13, 11)
	d:text(d:fit(u.name or "", 12.6, W - 16 - 13 - 4 - 18), 12.6, x + 13 + 4, y + 10.8, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	d:click(W - 8 - 14.4, y + 3.6, 14.4, 14.4, function() RW.menu = nil R.selectedUnit = nil end)
	d:fa("times", W - 8 - 14.4, y + 3.6, 14.4, WHITE)
	y = y + 21.6 + 4
	d:rect(x, y, W - 16, 1, Color(255, 255, 255, 26))
	y = y + 1 + 4
	-- the avatar (facing you-left, direction 4) on #343a40, 68 wide
	d:round(4, x, y, 68, 130, Color(52, 58, 64))
	if R.figureDrawer then
		local s = d.s
		d:clip(x, y, 68, 130, function()
			RW.standUnit = RW.standUnit or { id = "infostand" }
			RW.standUnit.figure, RW.standUnit.gender = u.figure, u.gender
			pcall(R.figureDrawer, RW.standUnit, { x = 0, y = 0, z = 0, sx = (x + 34) * s, sy = (y + 116) * s, k = s, dir = 4, posture = "std", now = SysTime(), talk = false })
		end)
	end
	y = y + 130 + 4
	d:rect(x, y, W - 16, 1, Color(255, 255, 255, 26))
	y = y + 1 + 4
	-- the motto: yours to change (a click: a small window to write it in), others' to read
	d:round(4, x, y, W - 16, 26, Color(52, 58, 64))
	if u.id == R.you then
		local hov = d:click(x, y, W - 16, 26, function() RW.editMotto(u) end)
		local t = (u.motto or "") ~= "" and u.motto or U.text("infostand.motto.change", "Click to change your motto...")
		d:text(d:fit(t, 12, W - 32), 12, x + 8, y + 13, (u.motto or "") ~= "" and WHITE or Color(255, 255, 255, hov and 200 or 130), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	else
		d:text(d:fit(u.motto or "", 12, W - 32), 12, x + 8, y + 13, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end
U.hud("avatar-stand", function(sw, sh)
	local u = target()
	if not u or V.mode ~= "room" then return nil end
	local w, h = standSize()
	return sw - 10 - w, sh - 65 - h, w, h
end, drawStand)

-- writing your motto (38 letters, as Habbo's)
function RW.editMotto(u)
	U.window("motto", 250, 120, function(w, d)
		d:slimCard(U.text("infostand.motto.change", "Change your motto"))
		local function save()
			local e = w.inputs and w.inputs.motto
			local t = IsValid(e) and e:GetValue() or ""
			u.motto = t
			P.send("user.motto", { text = t })
			w:close()
		end
		local e = d:input("motto", 9, 39, d.width - 18, 28, { max = 38, value = u.motto or "", onEnter = save })
		if not w.focused then w.focused = true e:RequestFocus() end
		d:btn(d.width - 9 - 90, 75, 90, 28, U.C.success, save)
		d:text(U.text("generic.save", "Save"), 12.6, d.width - 9 - 45, 89, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end)
end

-- clicking an avatar opens its menu (room.lua says which); clicking elsewhere closes it
function RW.selectUnit(id)
	if id then RW.menu = { unit = id, mode = "normal" } else RW.menu = nil end
	-- (your own while dancing, in Habbo Club: straight to the dances, as Nitro does)
	local u = id and R.units and R.units[id]
	if u and id == R.you and (u.dance or 0) > 0 and ((HUD.purse and HUD.purse.clubLevel) or 0) >= 1 then RW.menu.mode = "dances" end
end
