-- The other windows the toolbar and "me" menu open (client), as nitro-react draws them, ready for
-- their features: the inventory (InventoryView, its empty view; the furni are in shop.lua, like the
-- catalogue), the friends list (FriendsListView:
-- folding sets), the chat history (ChatHistoryView, with what's been said) and the settings
-- (UserSettingsView). Sizes measured from nitro-react's CSS in a browser (chatdev/winref).

local U = BOBBA.ui
local HUD = BOBBA.hud
local C = BOBBA.room.chatState

-- a text wrapped to a width: its lines
local function wrapText(d, text, size, maxW, bold)
	local lines, line = {}, ""
	for word in tostring(text):gmatch("%S+") do
		local try = (line == "") and word or (line .. " " .. word)
		if line ~= "" and d:textWidth(try, size, bold) > maxW then
			lines[#lines + 1] = line
			line = word
		else
			line = try
		end
	end
	if line ~= "" then lines[#lines + 1] = line end
	return lines
end
U.wrapText = wrapText

-- --- the inventory ----------------------------------------------------------------------------------
local INV = { tab = "inventory.furni" }
local INV_TABS = {
	{ id = "inventory.furni", fallback = "Furni", empty = { "inventory.empty.title", "Your inventory is empty!", "inventory.empty.desc", "The inventory holds all your furni. Your furni are stored here when you're not using them in your rooms." } },
	{ id = "inventory.bots", fallback = "Bots", empty = { "inventory.empty.bots.title", "You don't have any bots!", "inventory.empty.bots.desc", "Your bots are stored here when you're not using them in your rooms." } },
	{ id = "inventory.furni.tab.pets", fallback = "Pets", empty = { "inventory.empty.pets.title", "You don't have any pets!", "inventory.empty.pets.desc", "Your pets are stored here when they're not in your rooms." } },
	{ id = "inventory.badges", fallback = "Badges" },
}

local function drawInventory(w, d)
	local tabs = {}
	for _, t in ipairs(INV_TABS) do tabs[#tabs + 1] = { id = t.id, label = U.text(t.id, t.fallback) } end
	d:card(U.text("inventory.title", "Inventory"), tabs, INV.tab, function(id) INV.tab = id end)
	local tab
	for _, t in ipairs(INV_TABS) do if t.id == INV.tab then tab = t end end
	if not tab or not tab.empty then return end
	if tab.id == "inventory.furni" and BOBBA.shop and BOBBA.shop.drawInventoryFurni(w, d) then return end
	-- InventoryCategoryEmptyView: Habbo's picture on the left (5 of 12), the title and text (7 of 12)
	d:icon("inventory-empty", 48.4 + 64.5 - 65.5, 102.5 + 90.5 - 91.5)
	local tx, tw = 224.8, 294.2
	local lines = wrapText(d, U.plain(U.text(tab.empty[3], tab.empty[4])), 14.4, tw)
	-- (the title wraps when Habbo's is longer than the room it has)
	local title = wrapText(d, U.plain(U.text(tab.empty[1], tab.empty[2])), 18, tw, true)
	local titleH = #title * 21
	local blockH = titleH + 8 + #lines * 16
	local ty = 67 + 8 + (252 - 16 - blockH) / 2
	for i, l in ipairs(title) do d:text(l, 18, tx, ty + (i - 1) * 21 + 10.5, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true) end
	for i, l in ipairs(lines) do d:text(l, 14.4, tx, ty + titleH + 8 + (i - 1) * 16 + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
end

HUD.actions.inventory = function()
	U.toggle("inventory", function()
		U.window("inventory", 528, 320, drawInventory)
		if BOBBA.shop then BOBBA.shop.inventoryOpened() end
	end)
end

-- --- the friends list -------------------------------------------------------------------------------
local FR = { open = { true, false, true, false } }
local function drawFriends(w, d)
	d:slimCard(U.text("friendlist.friends", "Friends"))
	local sets = {
		U.text("friendlist.friends", "Friends") .. " (0)",
		U.text("friendlist.friends.offlinecaption", "Offline Friends") .. " (0)",
		U.text("friendlist.tab.friendrequests", "Friend Requests") .. " (0)",
		U.text("people.search.title", "Search Habbos"),
	}
	-- the open sets share the height left over by the headers
	local top, bottom = 29, d.height - 1
	local openCount = 0
	for i = 1, #sets do if FR.open[i] then openCount = openCount + 1 end end
	local share = openCount > 0 and ((bottom - top) - #sets * 25) / openCount or 0
	local y = top
	for i, label in ipairs(sets) do
		local h = 25 + (FR.open[i] and share or 0)
		if FR.open[i] then
			d:rect(1, y, d.width - 2, h, Color(255, 255, 255, 128))
			d:rect(1, y + h - 1, d.width - 2, 1, Color(0, 0, 0, 51))
		end
		d:click(1, y, d.width - 2, 25, function() FR.open[i] = not FR.open[i] end)
		d:text(label, 14.4, 9, y + 12, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		d:rect(1, y + 24, d.width - 2, 1, Color(0, 0, 0, 51))
		-- FaCaretUp / FaCaretDown
		local cx, cy = d.width - 1 - 8 - 7.2 - 0.4, y + 4 + 7.2
		local s = d.s
		draw.NoTexture()
		surface.SetDrawColor(0, 0, 0, 255)
		if FR.open[i] then
			surface.DrawPoly({ { x = (cx - 4.5) * s, y = (cy + 2.5) * s }, { x = cx * s, y = (cy - 2.5) * s }, { x = (cx + 4.5) * s, y = (cy + 2.5) * s } })
		else
			surface.DrawPoly({ { x = (cx - 4.5) * s, y = (cy - 2.5) * s }, { x = (cx + 4.5) * s, y = (cy - 2.5) * s }, { x = cx * s, y = (cy + 2.5) * s } })
		end
		y = y + h
	end
end

HUD.actions.friends = function() U.toggle("friends", function() U.window("friends", 250, 300, drawFriends) end) end

-- --- the chat history -------------------------------------------------------------------------------
local function drawHistory(w, d)
	d:slimCard(U.text("room.chathistory.button.text", "Chat history"))
	local search = d:input("search", 9, 37, 282, 28.9, { placeholder = U.text("generic.search", "Search"), max = 100 })
	local filter = (search:GetValue() or ""):lower()
	local rows = {}
	for _, e in ipairs(C.history or {}) do
		if filter == "" or (e.name or ""):lower():find(filter, 1, true) or (e.text or ""):lower():find(filter, 1, true) then rows[#rows + 1] = e end
	end
	-- each row: the time and the bubble (or the room's icon and name), 8 apart; the newest at the bottom
	local top, bottom = 37 + 28.9 + 8, d.height - 1 - 8
	local s = d.s
	local heights, total = {}, 0
	local timeW = d:textWidth("00:00", 14.4) + 8
	for i, e in ipairs(rows) do
		if e.type == "chat" then
			-- (at the window's size: made again when that changes)
			if e.bubble and e.bubbleScale ~= s then e.bubble = nil end
			if not e.bubble and C.makeBubble and C.atScale then
				C.atScale(s, function() e.bubble = C.makeBubble({ id = e.unit, name = e.name }, e.text, e.kind, e.style, math.floor(282 - 8 - timeW)) end)
				e.bubbleScale = s
			end
			if e.bubble then e.bubble.color = e.color end
			heights[i] = math.max(24, (e.bubble and e.bubble.height / s or 26) + 8)
		else
			local lines = wrapText(d, e.name or "", 14.4, 282 - 8 - 17 - 8)
			heights[i] = math.max(24, #lines * 16 + 8)
		end
		total = total + heights[i] + (i > 1 and 8 or 0)
	end
	-- (InfiniteScroll scrollToBottom: it starts at the bottom and follows new lines)
	local sc = w.scrolls.rows
	local atBottom = not sc or sc.offset >= (sc.max or 0) - 1
	local off = d:scroll("rows", 9, top, 282, bottom - top, total)
	if atBottom then w.scrolls.rows.offset = w.scrolls.rows.max off = w.scrolls.rows.offset end
	d:clip(9, top, 282, bottom - top, function()
		local y = top - off
		for i, e in ipairs(rows) do
			local h = heights[i]
			if y + h > top and y < bottom then
				if e.type == "chat" then
					d:text(e.time or "", 14.4, 13, y + h / 2, Color(108, 117, 125), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					if e.bubble and C.drawBubble then
						C.atScale(s, function() C.drawBubble(e.bubble, math.floor((13 + timeW) * s), math.floor((y + (h - e.bubble.height / s) / 2) * s)) end)
					end
				else
					d:icon("small-room", 13, y + (h - 16) / 2)
					local lines = wrapText(d, e.name or "", 14.4, 282 - 8 - 17 - 8)
					for j, l in ipairs(lines) do d:text(l, 14.4, 13 + 17 + 8, y + 4 + (j - 1) * 16 + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
				end
			end
			y = y + h + 8
		end
	end)
end

HUD.actions.chatHistory = function() U.toggle("chat-history", function() U.window("chat-history", 300, 300, drawHistory) end) end

-- --- the settings -----------------------------------------------------------------------------------
-- (kept on the player's own PC; what they change comes with the features: old chat, sounds, ...)
local function cv(name, default) return CreateClientConVar("bobba_setting_" .. name, default, true, false) end
local SET = {
	checks = {
		{ cv("oldchat", "0"), "memenu.settings.chat.prefer.old.chat", "Prefer old chat" },
		{ cv("roominvites", "0"), "memenu.settings.other.ignore.room.invites", "Ignore room invites" },
		{ cv("camerafollow", "0"), "memenu.settings.other.disable.room.camera.follow", "Disable room camera follow" },
		{ cv("placemultiple", "0"), "memenu.settings.other.place.multiple.objects", "Place multiple objects" },
		{ cv("skipconfirm", "0"), "memenu.settings.other.skip.purchase.confirmation", "Skip purchase confirmation" },
	},
	volumes = {
		{ cv("volume_ui", "100"), "widget.memenu.settings.volume.ui", "UI" },
		{ cv("volume_furni", "100"), "widget.memenu.settings.volume.furni", "Furni" },
		{ cv("volume_trax", "100"), "widget.memenu.settings.volume.trax", "Trax" },
	},
}

local function speaker(d, x, y, waves, c)
	-- FaVolumeDown / Up / Mute, 14.4 wide: the speaker, then the waves
	d:rect(x + 0.5, y + 5, 3.5, 4.4, c)
	local s = d.s
	draw.NoTexture()
	surface.SetDrawColor(c.r, c.g, c.b, c.a or 255)
	surface.DrawPoly({ { x = (x + 3.5) * s, y = (y + 5) * s }, { x = (x + 7.5) * s, y = (y + 1.5) * s }, { x = (x + 7.5) * s, y = (y + 12.9) * s }, { x = (x + 3.5) * s, y = (y + 9.4) * s } })
	if waves >= 1 then d:ring(x + 7.5, y + 7.2, 3.2, 1.3, c) end
	if waves >= 2 then d:ring(x + 7.5, y + 7.2, 5.8, 1.3, c) end
end

local function drawSettings(w, d)
	d:slimCard(U.text("widget.memenu.settings.title", "Settings"))
	local y = 37
	for _, c in ipairs(SET.checks) do
		local on = c[1]:GetBool()
		d:click(9, y, d.width - 18, 16, function() RunConsoleCommand(c[1]:GetName(), on and "0" or "1") end)
		-- form-check-input: white, a 1px border, 3.6 corners; checked: $primary with a tick
		if on then
			d:round(3.6, 9, y + 0.8, 14.4, 14.4, U.C.primary)
			d:line(9 + 3.5, y + 0.8 + 7.5, 9 + 6, y + 0.8 + 10.2, 2, U.C.white)
			d:line(9 + 6, y + 0.8 + 10.2, 9 + 11, y + 0.8 + 4.3, 2, U.C.white)
		else
			d:box(9, y + 0.8, 14.4, 14.4, 1, 3.6, Color(0, 0, 0, 64), U.C.white)
		end
		d:text(U.text(c[2], c[3]), 14.4, 27.4, y + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		y = y + 20
	end
	y = 141
	d:text(U.text("widget.memenu.settings.volume", "Volume"), 14.4, 9, y + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
	y = 165
	for _, v in ipairs(SET.volumes) do
		d:text(U.text(v[2], v[3]), 14.4, 9, y + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local value = math.Clamp(v[1]:GetInt(), 0, 100)
		local ry = y + 20
		local muted = Color(108, 117, 125)
		speaker(d, 9, ry + 0.8, value == 0 and 0 or 1, value >= 50 and muted or U.C.black)
		-- the slider (the browser's: a blue filled track, a blue thumb)
		-- (between the two speakers, 4 from each; the thumb stays inside the track)
		local sx, sw = 9 + 14.4 + 4, d.width - 2 * (9 + 14.4 + 4)
		local tx = sx + 8 + (sw - 16) * value / 100
		d:round(2, sx, ry + 6, sw, 4, Color(239, 239, 239))
		d:round(2, sx, ry + 6, tx - sx, 4, Color(0, 117, 255))
		d:circle(tx, ry + 8, 8, Color(0, 117, 255))
		d:click(sx, ry, sw, 16, function()
			local mx = w.mx or sx
			RunConsoleCommand(v[1]:GetName(), tostring(math.Clamp(math.floor((mx - sx - 8) / (sw - 16) * 100 + 0.5), 0, 100)))
		end)
		speaker(d, d.width - 9 - 14.4, ry + 0.8, 2, value < 50 and muted or U.C.black)
		y = y + 44
	end
end

HUD.actions.settings = function() U.toggle("settings", function() U.window("settings", 250, 300, drawSettings) end) end
