-- What stays on the screen in a room (client), the way nitro-react draws it:
--   the toolbar along the bottom (ToolbarView: your avatar, Habbo, rooms, catalogue, inventory, the
--   chat input, friends and the friend bar), the "me" menu over it (ToolbarMeView), the purse in the
--   top right (PurseView) and the room tools on the left (RoomToolsWidgetView).
-- Sizes are CSS pixels measured from nitro-react's compiled SCSS in a browser (tools: chatdev/hudref).
-- The pictures are Habbo's (BOBBA.ui.icon, from an addon). What the buttons open: BOBBA.hud.actions.

BOBBA.hud = BOBBA.hud or {}
local HUD = BOBBA.hud
local U = BOBBA.ui
local R = BOBBA.room
local V = BOBBA.view
local P = BOBBA.platform

-- a text from Habbo's texts when an addon gave them, else the English one here, with its values
-- filled in the way Nitro's getValueWithParameters does: %name% (any case: Habbo writes both), and
-- Habbo's plurals %{NAME|none|one|more} where %% in "more" is the number
local function pattern(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local function anyCase(s) return (s:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end)) end
-- the hotel's own name instead of Habbo's (hotel.info): "Habbo Hotel" is the whole name, "Habbo" on
-- its own the name without "Hotel" (Habbo Club -> Bobba Club, Habbos -> Bobbas)
function U.hotelText(t)
	local name = BOBBA.hotelName or "Bobba Hotel"
	local short = name:gsub("%s+[Hh]otel$", "")
	if short == "" then short = name end
	t = t:gsub("%f[%a]Habbo Hotel%f[%A]", (name:gsub("%%", "%%%%")))
	t = t:gsub("%f[%a]Habbo", (short:gsub("%%", "%%%%")))
	return t
end
function U.text(key, fallback, vars)
	local t = U.hotelText((BOBBA.lang.has(key) and BOBBA.lang.get(key)) or fallback or key)
	for k, v in pairs(vars or {}) do
		local name = anyCase(pattern(tostring(k)))
		local value = tostring(v)
		t = t:gsub("%%{" .. name .. "|([^|}]*)|([^|}]*)|([^|}]*)}", function(none, one, more)
			local n = tonumber(v)
			if n == 0 then return none end
			if n == 1 then return one end
			return (more:gsub("%%%%", (value:gsub("%%", "%%%%"))))
		end)
		t = t:gsub("%%" .. name .. "%%", (value:gsub("%%", "%%%%")))
	end
	return t
end

-- Habbo's texts can have a little HTML (Nitro shows it as HTML): the plain text of it
function U.plain(t)
	t = tostring(t or ""):gsub("<[bB][rR]%s*/?>", "\n"):gsub("<[^>]*>", "")
	return (t:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&nbsp;", " "):gsub("&amp;", "&"))
end

-- a text cut to a width with "…" (text-overflow: ellipsis)
function U.fit(d, t, size, maxW, bold)
	if d:textWidth(t, size, bold) <= maxW then return t end
	local n = utf8.len(t) or #t
	while n > 0 do
		local cut = utf8.sub and utf8.sub(t, 1, n) or t:sub(1, n)
		if d:textWidth(cut .. "…", size, bold) <= maxW then return cut .. "…" end
		n = n - 1
	end
	return "…"
end

HUD.TOOLBAR_H = 55
HUD.FONT = 14.4 -- $font-size-base
local WHITE = Color(255, 255, 255)

-- what each button does (other files fill these in: the navigator, the catalogue, ...)
HUD.actions = HUD.actions or {}
local function act(name, ...)
	local fn = HUD.actions[name]
	if fn then fn(...) end
end

local function inRoom() return V.mode == "room" and V.room ~= nil and not (BOBBA.loading and BOBBA.loading.active) end
-- the toolbar, purse and "me" menu are also there in the hotel view
local function inHotel() return (inRoom() or V.mode == "hotelview") and not (BOBBA.loading and BOBBA.loading.active) end

-- --- the toolbar -------------------------------------------------------------------------------------
-- left: your avatar (50 x 45), then the icons 8 apart, each in the middle of the bar's 47 high inside;
-- then the chat input (chat.lua draws it where HUD.chatInput says)
local LEFT = {
	{ id = "avatar", w = 50, h = 45 },
	{ id = "habbo", icon = "habbo", w = 28, h = 28, action = "hotelView" },
	{ id = "rooms", icon = "rooms", w = 44, h = 30, action = "navigator" },
	{ id = "catalog", icon = "catalog", w = 37, h = 36, action = "catalog" },
	{ id = "inventory", icon = "inventory", w = 44, h = 41, action = "inventory" },
	-- (in a room: the camera, client/camera.lua)
	{ id = "camera", icon = "camera", w = 38, h = 45, action = "camera", room = true },
}
-- the ones shown now
local function leftItems()
	local out = {}
	for _, it in ipairs(LEFT) do
		if not it.room or (V.mode == "room") then out[#out + 1] = it end
	end
	return out
end
local FRIEND_ITEM_W, FRIEND_BUTTON_W = 130, 36
local FRIENDS_SHOWN = 3

HUD.meOpen = false

-- where the chat input goes (CSS px of the screen): after the icons, 40 high in the middle, as wide
-- as what's typed (at least 173: a browser's 20-character input in Ubuntu Condensed) up to the
-- right side's things
function HUD.chatInput(screenW, screenH, textW)
	local x = 16
	for _, it in ipairs(leftItems()) do x = x + it.w + 8 end
	local inner = math.max(173, textW or 0)
	local w = 2 + 10 + inner + 10 + 17 + 10 + 2
	local rightW = 32 + (screenW >= 992 and (8 + FRIEND_BUTTON_W * 2 + (FRIEND_ITEM_W + 6) * FRIENDS_SHOWN) or 0)
	local maxW = screenW - 16 - rightW - 8 - x
	return x, screenH - HUD.TOOLBAR_H + 4 + (47 - 40) / 2, math.max(60, math.min(w, maxW)), 40
end

local function chevron(d, cx, cy, left, alpha)
	-- FaChevronLeft / Right at 1em (9 x 14.4)
	local s = d.s
	surface.SetDrawColor(255, 255, 255, alpha)
	draw.NoTexture()
	local dir = left and -1 or 1
	local x0, y0 = cx * s, cy * s
	local hw, hh = 3.5 * s, 6 * s
	for i = 0, math.max(1, math.floor(2.4 * s)) - 1 do
		surface.DrawLine(x0 - dir * hw + i, y0 - hh, x0 + dir * hw + i, y0)
		surface.DrawLine(x0 + dir * hw + i, y0, x0 - dir * hw + i, y0 + hh)
	end
end

-- LayoutItemCountView: a number in red with a black border, its top-right corner at right, top
function U.countBadge(d, n, right, top)
	local t = tostring(n)
	local w = d:textWidth(t, 9.5, true) + 8 + 2
	d:round(4, right - w, top, w, 15.5, U.C.black)
	d:round(3, right - w + 1, top + 1, w - 2, 13.5, U.C.danger)
	d:text(t, 9.5, right - w / 2, top + 15.5 / 2, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
end

local function drawToolbar(w, d)
	local W, H = d.width, d.height
	d:darkBox(0, 0, W, H)
	local x = 16
	for _, it in ipairs(leftItems()) do
		local y = 4 + (47 - it.h) / 2
		local hover = d:click(x, y, it.w, it.h, function()
			if it.id == "avatar" then HUD.meOpen = not HUD.meOpen
			-- (in the hotel view Habbo's logo is the house: back to your home room)
			elseif it.id == "habbo" and V.mode == "hotelview" then HUD.meOpen = false act("home")
			else HUD.meOpen = false act(it.action) end
		end)
		if it.id == "avatar" then
			-- the avatar facing right, cut to 50 x 45 (.item-avatar .avatar-image: margin -5px 25px)
			local me = R.units and R.units[R.you]
			if me then HUD.lastMe = { figure = me.figure, gender = me.gender } else me = HUD.lastMe end
			local AE = BOBBA.avatarEditor
			local dx = (hover and not HUD.meOpen) and -1 or 0
			if me and AE and AE.drawPreview then
				d:clip(x, y, it.w, it.h, function()
					AE.drawPreview(me.figure or "", me.gender or "M", 2, (x + 22.5 + dx) * d.s, (y - 38 + dx) * d.s, d.s)
				end)
			end
		elseif it.id == "habbo" and V.mode == "hotelview" then
			d:icon("house", x, y, it.w, it.h, { shadow = hover })
		else
			d:icon(it.icon, x, y, it.w, it.h, { shadow = hover })
		end
		-- (new furni in the inventory: their count on its icon, LayoutItemCountView)
		if it.id == "inventory" and BOBBA.shop and BOBBA.shop.unseenCount then
			local n = BOBBA.shop.unseenCount()
			if n > 0 then U.countBadge(d, n, x + it.w - 2, y + 2) end
		end
		x = x + it.w + 8
	end
	-- right: friends, then the friend bar (lg screens and up)
	local rx = W - 16
	if W >= 992 then
		local barW = FRIEND_BUTTON_W * 2 + (FRIEND_ITEM_W + 6) * FRIENDS_SHOWN
		rx = rx - barW
		local by = 4 + (47 - 31) / 2
		local bx = rx
		-- the arrows (btn-black, disabled: 65% see-through) and three "Find new friends"
		for side = 0, 1 do
			local ax = side == 0 and bx or (bx + barW - FRIEND_BUTTON_W)
			d:box(ax, by + 0.5, FRIEND_BUTTON_W, 30, 1, 4, Color(0, 0, 0, 166), Color(0, 0, 0, 166))
			chevron(d, ax + FRIEND_BUTTON_W / 2, by + 0.5 + 15, side == 0, 166)
		end
		local ix = bx + FRIEND_BUTTON_W + 3
		for _ = 1, FRIENDS_SHOWN do
			local hover = d:click(ix, by, FRIEND_ITEM_W, 31, function() act("findFriends") end)
			local c = hover and Color(26, 97, 127) or U.C.primary
			d:round(4, ix, by + 1, FRIEND_ITEM_W, 31, Color(0, 0, 0, 26))
			d:box(ix, by, FRIEND_ITEM_W, 31, 1, 4, c, c)
			d:rect(ix + 1, by + 1, FRIEND_ITEM_W - 2, 2, Color(255, 255, 255, 38))
			d:rect(ix + 1, by + 31 - 3, FRIEND_ITEM_W - 2, 2, Color(0, 0, 0, 26))
			d:icon("friend-search", ix + 6, by - 2)
			local t = U.fit(d, U.text("friend.bar.find.title", "Find new friends"), HUD.FONT, 78)
			d:text(t, HUD.FONT, ix + 39, by + 15.5, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			ix = ix + FRIEND_ITEM_W + 6
		end
		rx = rx - 8
	end
	local fy = 4 + (47 - 33) / 2
	local hover = d:click(rx - 32, fy, 32, 33, function() act("friends") end)
	d:icon("friendall", rx - 32, fy, 32, 33, { shadow = hover })
end

-- --- the "me" menu ----------------------------------------------------------------------------------
-- 15 from the left, 60 from the bottom; 8 inside a 1px border; the icons grey until the mouse is over
local ME = {
	{ icon = "me-achievements", w = 31, h = 30, action = "achievements" },
	{ icon = "me-profile", w = 32, h = 30, action = "profile" },
	{ icon = "me-rooms", w = 30, h = 30, action = "myRooms" },
	{ icon = "me-clothing", w = 27, h = 30, action = "avatarEditor" },
	{ icon = "me-settings", w = 28, h = 34, action = "settings" },
}
-- ... and "leave the hotel" last, where the game can be left from inside (HUD.actions.leaveHotel:
-- the desktop client goes back to its start page)
local LEAVE = { draw = "leave", w = 28, h = 30, action = "leaveHotel" }
local function meItems()
	if not HUD.actions.leaveHotel then return ME end
	local t = {}
	for i, it in ipairs(ME) do t[i] = it end
	t[#t + 1] = LEAVE
	return t
end
local function meSize()
	local w, h = 0, 0
	for i, it in ipairs(meItems()) do w = w + it.w + (i > 1 and 8 or 0) h = math.max(h, it.h) end
	return w + 18, h + 18
end

-- the leave icon: a door with an arrow going out of it
local function leaveIcon(d, x, y, c)
	d:rect(x + 2, y + 3, 14, 2, c)
	d:rect(x + 2, y + 25, 14, 2, c)
	d:rect(x + 2, y + 3, 2, 24, c)
	d:rect(x + 14, y + 3, 2, 6, c)
	d:rect(x + 14, y + 21, 2, 6, c)
	d:line(x + 9, y + 15, x + 22, y + 15, 3, c)
	d:line(x + 18, y + 10, x + 24, y + 15.5, 3, c)
	d:line(x + 18, y + 21, x + 24, y + 14.5, 3, c)
end

local function drawMe(w, d)
	local W, H = d.width, d.height
	-- background rgba(20,20,20,.95), border #101010, inset 2px 2px and -2px -2px white at 10%
	d:round(4, 0, 0, W, H, Color(16, 16, 16, 255))
	d:round(3, 1, 1, W - 2, H - 2, Color(20, 20, 20, 242))
	d:rect(1, 1, W - 2, 2, Color(255, 255, 255, 26))
	d:rect(1, 3, 2, H - 4, Color(255, 255, 255, 26))
	d:rect(1, H - 3, W - 2, 2, Color(255, 255, 255, 26))
	d:rect(W - 3, 1, 2, H - 4, Color(255, 255, 255, 26))
	local x = 9
	for _, it in ipairs(meItems()) do
		local y = (H - it.h) / 2
		local hover = d:click(x, y, it.w, it.h, function() HUD.meOpen = false act(it.action) end)
		if it.draw == "leave" then
			if hover then
				leaveIcon(d, x + 2, y + 2, Color(0, 0, 0, 204))
				leaveIcon(d, x, y, Color(255, 255, 255))
			else
				leaveIcon(d, x, y, Color(140, 140, 140))
			end
		elseif hover then
			-- grayscale(0) and drop-shadow(2px 2px 0 black 80%), not moved
			d:icon(it.icon, x + 2, y + 2, it.w, it.h, { alpha = 204, black = true })
			d:icon(it.icon, x, y, it.w, it.h)
		else
			d:icon(it.icon .. ":gray", x, y, it.w, it.h)
		end
		x = x + it.w + 8
	end
end

-- --- the purse --------------------------------------------------------------------------------------
-- 200 wide, 10 from the right; 4 inside: credits, duckets and diamonds (one under the other, the
-- amount right next to its coin), Habbo Club, then help and settings
HUD.purse = HUD.purse or { credits = 0, points = { [0] = 0, [5] = 0 }, club = false }
local function money(n)
	-- LocalizeFormattedNumber: 1,234,567
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- FriendlyTime.shortFormat (threshold 3): the biggest unit there's over 3 of
local function shortTime(seconds)
	local units = { { "years", 365 * 86400, "%amount% y" }, { "months", 30 * 86400, "%amount% mon." }, { "days", 86400, "%amount% d" },
		{ "hours", 3600, "%amount% h" }, { "minutes", 60, "%amount% min" } }
	for _, u in ipairs(units) do
		if seconds > 3 * u[2] then
			return U.text("friendlytime." .. u[1] .. ".short", u[3], { amount = math.floor(seconds / u[2] + 0.5) })
		end
	end
	return U.text("friendlytime.seconds.short", "%amount% s", { amount = math.max(0, math.floor(seconds + 0.5)) })
end

-- the server's user.purse (PurseView: credits, activity points 0 duckets and 5 diamonds, club)
BOBBA.platform.receive("user.purse", function(_, data)
	HUD.purse = {
		credits = data.credits or 0, points = { [0] = data.duckets or 0, [5] = data.diamonds or 0 },
		club = (data.clubLevel or 0) > 0, clubLevel = data.clubLevel or 0,
		clubDays = data.clubDays or 0, clubMinutes = data.clubMinutes or 0,
		clubKind = data.clubKind or "hc", clubMode = data.clubMode or "hc",
	}
	-- getClubText: under a day left it counts the minutes, else the days
	local p = HUD.purse
	if p.club then
		p.clubText = (p.clubMinutes < 60 * 24) and shortTime(p.clubMinutes * 60) or shortTime(p.clubDays * 86400)
	end
	BOBBA.events.emit("purseChanged", p)
end)
BOBBA.events.on("roomShown", "bobba.hud.purse", function() BOBBA.platform.send("user.purse.get", {}) end)

-- a club's coin (HC's, or VIP's badge made small) in a box
function U.clubIcon(d, kind, x, y, w, h)
	if kind == "vip" then return d:icon("currency-vip", x, y, w, h, { scale = 0.43 }) end
	return d:icon("currency-hc", x, y, w, h)
end

-- which club a club level is (HC 1, VIP 2 when there are both; else the one there is)
function U.clubKindFor(level)
	local mode = HUD.purse.clubMode or "hc"
	if mode == "both" then return level >= 2 and "vip" or "hc" end
	return mode
end

local function drawPurse(w, d)
	local W, H = d.width, d.height
	d:darkBox(0, 0, W, H, 4, false, false, true, true)
	local col = (192 - 11 * 4) / 12
	local x6, w6 = 4, col * 6 + 5 * 4
	local x4, w4 = x6 + w6 + 4, col * 4 + 3 * 4
	local x2, w2 = x4 + w4 + 4, col * 2 + 4
	local rows = { { "credits", HUD.purse.credits }, { "duckets", HUD.purse.points[0] }, { "diamonds", HUD.purse.points[5] } }
	for i, r in ipairs(rows) do
		local y = 4 + (i - 1) * 21
		local hover = d:click(x6, y, w6, 21, function() end)
		if hover then d:round(4, x6, y, w6, 21, Color(223, 223, 223, 26)) end
		d:icon("currency-" .. r[1], x6 + w6 - 2 - 15, y + 3, 15, 15)
		d:text(money(r[2]), 12.6, x6 + w6 - 2 - 15 - 4, y + 3 + 7.5, WHITE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	-- Habbo Club: its coin over "Join" (or the days left)
	local hover = d:click(x4, 4, w4, 63, function() act("club") end)
	d:round(4, x4, 4, w4, 63, Color(223, 223, 223, hover and 40 or 26))
	local clubText = HUD.purse.club and HUD.purse.clubText or U.text("purse.clubdays.zero.amount.text", "Join")
	U.clubIcon(d, HUD.purse.clubKind, x4 + (w4 - 15) / 2, 18.5, 15, 15)
	d:text(clubText, 12.6, x4 + w4 / 2, 37.5 + 7.5, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	-- help and settings, each half the height
	for i, b in ipairs({ { "help", "help" }, { "purse-cog", "settings" } }) do
		local y = 4 + (i - 1) * 31.5
		local hov = d:click(x2, y, w2, 31.5, function() act(b[2]) end)
		if hov then d:round(4, x2, y, w2, 31.5, Color(223, 223, 223, 26)) end
		d:icon(b[1], x2, y, w2, 31.5)
	end
end

-- --- the room tools ---------------------------------------------------------------------------------
-- 120 from the bottom on the left: settings, zoom, chat history; next to them the room's name and
-- owner for 5 seconds after coming in (sliding in and out)
local TOOLS = {
	{ icon = "room-settings", w = 21, h = 21, action = "roomSettings" },
	{ icon = "room-zoom", w = 12, h = 22, action = "zoom" },
	{ icon = "room-chat-history", w = 17, h = 21, action = "chatHistory" },
}
HUD.roomInfoShown = HUD.roomInfoShown or 0
local function toolsHeight()
	local h = 16
	for i, t in ipairs(TOOLS) do h = h + t.h + (i > 1 and 8 or 0) end
	return h
end

local function infoBox(d)
	local c = R.current
	if not c then return 0, 0 end
	local nameW = math.min(218, d:textWidth(c.name or "", 21.6))
	local ownerW = math.min(218, d:textWidth(c.owner or "", 18))
	-- the room's tags under them (#tag chips, 8 apart)
	local tags = c.access and c.access.tags or {}
	local tagsW = 0
	for i, t in ipairs(tags) do tagsW = tagsW + d:textWidth("#" .. t, 12.6) + 8 + (i > 1 and 8 or 0) end
	return math.min(250, math.max(nameW, ownerW, tagsW) + 32), 8 + 25 + 4 + 21 + (#tags > 0 and (8 + 26.9) or 0) + 8
end

local function drawTools(w, d)
	local th = toolsHeight()
	local H = d.height
	local ty = (H - th) / 2
	d:darkBox(0, ty, 37, th, 4, false, true, false, true)
	local y = ty + 8
	for _, t in ipairs(TOOLS) do
		local hover = d:click(0, y, 37, t.h, function() act(t.action) end)
		d:icon(t.icon, 0, y, 37, t.h, { shadow = false, alpha = hover and 255 or 255 })
		y = y + t.h + 8
	end
	-- the room's name: shown for 5 s, slid in/out over 0.3 s
	local since = SysTime() - HUD.roomInfoShown
	local slide
	if since < 0.3 then slide = 1 - since / 0.3
	elseif since < 5 then slide = 0
	elseif since < 5.3 then slide = (since - 5) / 0.3
	else return end
	local c = R.current
	if not c then return end
	local bw, bh = infoBox(d)
	local bx = 45 - (bw + 45) * slide
	local by = (H - bh) / 2
	d:clip(37, 0, d.width - 37, H, function()
		d:darkBox(bx, by, bw, bh, 4)
		d:text(c.name or "", 21.6, bx + 16, by + 8 + 12.5, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		d:text(c.owner or "", 18, bx + 16, by + 8 + 25 + 4 + 10.5, Color(108, 117, 125), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local tx = bx + 16
		for _, t in ipairs(c.access and c.access.tags or {}) do
			local tw = d:textWidth("#" .. t, 12.6) + 8
			local ty2 = by + 8 + 25 + 4 + 21 + 8
			d:click(tx, ty2, tw, 26.9, function() act("tagSearch", t) end)
			d:round(4, tx, ty2, tw, 26.9, U.C.primary)
			d:text("#" .. t, 12.6, tx + 4, ty2 + 26.9 / 2, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			tx = tx + tw + 8
		end
	end)
end

BOBBA.events.on("roomShown", "bobba.hud.roominfo", function() HUD.roomInfoShown = SysTime() end)

-- --- putting them on the screen ---------------------------------------------------------------------
function HUD.update()
	U.hud("toolbar", function(sw, sh)
		if not inHotel() then return nil end
		return 0, sh - HUD.TOOLBAR_H, sw, HUD.TOOLBAR_H
	end, drawToolbar)
	U.hud("me", function(sw, sh)
		if not inHotel() or not HUD.meOpen then return nil end
		local mw, mh = meSize()
		return 15, sh - 60 - mh, mw, mh
	end, drawMe)
	U.hud("purse", function(sw, sh)
		if not inHotel() then return nil end
		return sw - 10 - 200, 0, 200, 71
	end, drawPurse)
	U.hud("roomtools", function(sw, sh)
		if not inRoom() then return nil end
		local th = toolsHeight()
		return 0, sh - HUD.TOOLBAR_H - 65 - math.max(th, 66), 37 + 8 + 250, math.max(th, 66)
	end, drawTools)
end

-- the "me" menu closes when something else is clicked (document click in Nitro)
hook.Add("VGUIMousePressed", "bobba.hud.me", function(panel)
	if not HUD.meOpen then return end
	local me, tb = U.huds.me, U.huds.toolbar
	if (me and panel == me.panel) or (tb and panel == tb.panel) then return end
	HUD.meOpen = false
end)

HUD.update()

-- the buttons that already have something to open
HUD.actions.avatarEditor = function() if BOBBA.avatarEditor and BOBBA.avatarEditor.open then BOBBA.avatarEditor.open() end end
HUD.actions.zoom = function() if V.toggleZoom then V.toggleZoom() end end
-- the Habbo button: out of the room to the hotel view; in the hotel view the house: home
HUD.actions.hotelView = function() P.send("room.leave", {}) end
HUD.actions.home = function() P.send("room.ready", {}) end
