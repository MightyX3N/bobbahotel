-- The navigator window (client): nitro-react's NavigatorView. Its tabs are Habbo's four views (Public,
-- All Rooms, Events, My World) and "+" for making a room (NavigatorRoomCreatorView); a search box
-- with Habbo's filters; the results in lists that fold (NavigatorSearchResultView), each room a row
-- (NavigatorSearchResultItemView): how many are in it, its name, an info button. Clicking a room
-- goes in. Sizes measured from nitro-react's CSS in a browser (chatdev/navref).

local U = BOBBA.ui
local HUD = BOBBA.hud
local P = BOBBA.platform
local NAV = BOBBA.navigator
local V = BOBBA.view

local W, H = 420, 440
local VIEWS = { "official_view", "hotel_view", "roomads_view", "myworld_view" }
local FALLBACK = { official_view = "Public", hotel_view = "All Rooms", roomads_view = "Events", myworld_view = "My World" }
local FILTERS = { { "anything", nil }, { "room.name", "roomname" }, { "owner", "owner" }, { "tag", "tag" }, { "group", "group" } }
local FILTER_TEXT = { anything = "Anything", ["room.name"] = "Room Name", owner = "Owner", tag = "Tag", group = "Group" }

NAV.client = NAV.client or { view = "official_view", filter = 1, folded = {}, creator = false }
local S = NAV.client

local function search(view, query)
	S.view = view or S.view
	S.loading = true
	P.send("navigator.search", { view = S.view, query = query or "" })
end

P.receive("navigator.result", function(_, data)
	S.result = data
	S.loading = false
	local w = U.windows.navigator
	if w and w.scrolls.results then w.scrolls.results.offset = 0 end
end)

-- --- a list of rooms --------------------------------------------------------------------------------
local BADGE = { primary = U.C.primary, success = U.C.success, warning = U.C.warning, danger = U.C.danger }
local function counterColor(room)
	local n = 100 * (room.users / math.max(1, room.maxUsers))
	if n >= 92 then return BADGE.danger elseif n >= 50 then return BADGE.warning elseif n > 0 then return BADGE.success end
	return BADGE.primary
end

local function blockHeight(block)
	local open = not S.folded[block.code]
	return 2 + 24 + (open and #block.rooms * 26 or 0)
end

local function drawBlock(d, block, x, y, w, clipTop, clipBottom)
	local h = blockHeight(block)
	d:box(x, y, w, h, 1, 4, U.C.muted, U.C.white)
	-- the header: fold (−/+) and the list's name; on the right the view switch (th)
	local open = not S.folded[block.code]
	if y + 25 > clipTop and y < clipBottom then
		d:click(x + 1, y + 1, w - 60, 24, function() S.folded[block.code] = open or nil end)
		d:fa(open and "minus" or "plus", x + 9, y + 5.8, 14.4, U.C.secondaryText)
		-- (a category's list is called by the category)
		local cat = block.code:match("^category%.(.+)$")
		local title = cat and U.text("navigator.flatcategory.global." .. cat, cat) or U.text("navigator.searchcode.title." .. block.code, block.code)
		d:text(title, 14.4, x + 27.4, y + 1 + 12, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		d:fa("th", x + w - 9 - 14.4, y + 5.8, 14.4, U.C.secondaryText)
	end
	if not open then return h end
	for i, room in ipairs(block.rooms) do
		local ry = y + 25 + (i - 1) * 26
		if ry + 26 > clipTop and ry < clipBottom then
			if i % 2 == 1 then d:rect(x + 1, ry, w - 2, 26, U.C.gridActive) end
			local hover = d:click(x + 1, ry, w - 2, 26, function()
				-- (a doorbell or a password asks first: roomwindows.lua)
				if BOBBA.roomWindows and BOBBA.roomWindows.visit then BOBBA.roomWindows.visit(room) else P.send("room.enter", { id = room.id }) end
			end)
			-- the badge: 35 wide, the person and how many
			local c = counterColor(room)
			d:round(4, x + 9, ry + 4.3, 35, 17.5, c)
			local num = tostring(room.users)
			local tw = d:textWidth(num, 9.45, true)
			local cw = 9.4 + 4 + tw
			local bx = x + 9 + (35 - cw) / 2
			d:fa("user", bx, ry + 4.3 + 4, 9.4, U.C.white)
			d:text(num, 9.45, bx + 9.4 + 4, ry + 4.3 + 17.5 / 2, U.C.white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
			-- the name, cut to fit before the icons: the door's lock (13 x 16) and the info button
			local lock = ({ doorbell = "nav-locked", password = "nav-password", invisible = "nav-invisible" })[room.door or ""]
			local nameW = w - 2 - 8 - 35 - 8 - 8 - 18 - 8 - (lock and 17 or 0)
			d:text(d:fit(room.name, 12.6, nameW), 12.6, x + 52, ry + 13, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			d:icon("nav-info", x + w - 9 - 18, ry + 4, 18, 18)
			-- the mouse on the "i": the room's info beside it (NavigatorSearchResultItemInfoView)
			local mx, my = d.w.mx, d.w.my
			local ix, iy = x + w - 9 - 18, ry + 4
			if mx and mx >= ix and mx < ix + 18 and my >= iy and my < iy + 18 and my >= clipTop and my < clipBottom then
				local sx, sy = d.w.panel:LocalToScreen(0, 0)
				S.popover = { room = room, x = sx / d.s + ix + 18, y = sy / d.s + iy + 9, seen = SysTime() }
			end
			if lock then d:icon(lock, x + w - 9 - 18 - 4 - 13, ry + 5, 13, 16) end
			if hover then d:rect(x + 1, ry, w - 2, 26, Color(0, 0, 0, 10)) end
		end
	end
	return h
end

-- --- the "i" popover (NavigatorSearchResultItemInfoView): a #DFDFDF box with a dark blue edge to the
-- right of the "i", its arrow pointing at it; the thumbnail (110 x 110, the placeholder until rooms
-- have pictures) with the door's lock, the name, the owner, the description, how many are in it
local POP_W, POP_H, ARROW = 275, 126, 8
local function drawPopover(w, d)
	local p = S.popover
	if not p then return end
	local room = p.room
	local edge, fill = Color(40, 63, 93), Color(223, 223, 223)
	-- (box-shadow 0 2px rgba(0,0,0,.45))
	d:round(4, ARROW, 2, POP_W + 2, POP_H + 2, Color(0, 0, 0, 115))
	d:round(4, ARROW, 0, POP_W + 2, POP_H + 2, edge)
	d:round(3, ARROW + 1, 1, POP_W, POP_H, fill)
	-- the arrow, on the left, pointing at the "i"
	local s = d.s
	local cy = (POP_H + 2) / 2
	draw.NoTexture()
	surface.SetDrawColor(edge)
	surface.DrawPoly(V.clockwise({ { x = 0, y = cy * s }, { x = (ARROW + 1) * s, y = (cy - 8) * s }, { x = (ARROW + 1) * s, y = (cy + 8) * s } }))
	surface.SetDrawColor(fill)
	surface.DrawPoly(V.clockwise({ { x = 1.5 * s, y = cy * s }, { x = (ARROW + 2) * s, y = (cy - 7) * s }, { x = (ARROW + 2) * s, y = (cy + 7) * s } }))
	local x, y = ARROW + 1 + 8, 1 + 8
	-- the thumbnail
	d:box(x, y, 110, 110, 1, 4, edge, Color(0, 0, 0, 32))
	if not (room.thumbnail and BOBBA.camera and BOBBA.camera.drawPhoto(d, room.thumbnail, x + 1, y + 1, 108, 108)) then
		d:icon("nav-thumbnail", x + 10, y + 10, 90, 90)
	end
	local lock = ({ doorbell = "nav-locked", password = "nav-password", invisible = "nav-invisible" })[room.door or ""]
	if lock then d:icon(lock, x + 110 - 4 - 13, y + 110 - 4 - 16, 13, 16) end
	local cx = x + 110 + 8
	local cw = ARROW + 1 + POP_W - 8 - cx
	d:text(d:fit(room.name or "", 12.6, cw, true), 12.6, cx, y, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	local ty = y + 17
	local oc = U.text("navigator.roomownercaption", "Owner:")
	local ow = d:textWidth(oc, 12.6)
	d:text(oc, 12.6, cx, ty, Color(108, 117, 125))
	d:text(d:fit(room.owner or "", 12.6, cw - ow - 8), 12.6, cx + ow + 8, ty, U.C.black)
	ty = ty + 21
	local lines = d:wrap(room.description or "", 12.6, cw)
	for i = 1, math.min(#lines, 3) do d:text(lines[i], 12.6, cx, ty + (i - 1) * 17, U.C.black) end
	-- how many are in it (the badge, bottom right)
	local num = tostring(room.users or 0)
	local bw = 9.4 + 4 + d:textWidth(num, 9, true) + 8
	local bx, by = ARROW + 1 + POP_W - 8 - bw, 1 + POP_H - 8 - 17
	d:round(4, bx, by, bw, 17, counterColor(room))
	d:fa("user", bx + 4, by + 4, 9.4, U.C.white)
	d:text(num, 9, bx + 4 + 9.4 + 4, by + 17 / 2, U.C.white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
end
hook.Add("Think", "bobba.navigator.popover", function()
	local p = S.popover
	-- (gone when the mouse left the "i": the navigator draws it every frame while it's there)
	if p and (SysTime() - p.seen > 0.1 or not U.isOpen("navigator")) then S.popover, p = nil, nil end
	if p and not U.huds["nav-popover"] then
		U.hud("nav-popover", function(sw, sh)
			local q = S.popover
			if not q then return nil end
			local h = POP_H + 4
			return q.x, math.max(0, math.min(sh - h, q.y - h / 2)), POP_W + ARROW + 4, h
		end, drawPopover)
		if IsValid(U.huds["nav-popover"].panel) then U.huds["nav-popover"].panel:SetZPos(32000) end
	elseif not p and U.huds["nav-popover"] then
		U.hudRemove("nav-popover")
	end
end)

-- --- the room creator -------------------------------------------------------------------------------
S.make = S.make or { name = "", description = "", maxUsers = 10, trade = 0, category = 0, model = "a" }

-- a room model's floor, drawn small: its tiles in Habbo's angle, fitted into the box
local shapes = {}
local function modelShape(name)
	if shapes[name] ~= nil then return shapes[name] end
	local layout = BOBBA.registry.get("layout", "model_" .. name)
	local tiles = {}
	if layout then
		local y = 0
		for row in (layout.heightmap .. "\r"):gmatch("([^\r\n]*)[\r\n]") do
			for x = 1, #row do
				local c = row:sub(x, x):lower()
				if c ~= "x" then tiles[#tiles + 1] = { x - 1, y, BOBBA.rooms.charHeight and BOBBA.rooms.charHeight(c) or 0 } end
			end
			y = y + 1
		end
	end
	shapes[name] = tiles
	return tiles
end

local function drawModel(d, name, cx, cy, maxW, maxH)
	local tiles = modelShape(name)
	if #tiles == 0 then return end
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, t in ipairs(tiles) do
		local sx, sy = (t[1] - t[2]), (t[1] + t[2]) / 2 - (t[3] or 0) / 2
		minX, maxX = math.min(minX, sx - 1), math.max(maxX, sx + 1)
		minY, maxY = math.min(minY, sy), math.max(maxY, sy + 1)
	end
	local k = math.min(maxW / (maxX - minX), maxH / (maxY - minY), 4)
	local ox, oy = cx - (minX + maxX) / 2 * k, cy - (minY + maxY) / 2 * k
	local s = d.s
	draw.NoTexture()
	for _, t in ipairs(tiles) do
		local sx, sy = (t[1] - t[2]), (t[1] + t[2]) / 2 - (t[3] or 0) / 2
		local px, py = ox + sx * k, oy + sy * k
		surface.SetDrawColor(152, 152, 152, 255)
		surface.DrawPoly({ { x = px * s, y = py * s }, { x = (px + k) * s, y = (py + k / 2) * s }, { x = px * s, y = (py + k) * s }, { x = (px - k) * s, y = (py + k / 2) * s } })
	end
end

local function drawCreator(w, d)
	local x0, y0 = 9, 75
	local colW = 197
	local m = S.make
	local function label(t, y) d:text(t, 14.4, x0, y + 8, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	label(U.text("navigator.createroom.roomnameinfo", "Room name"), y0)
	local nameBox = d:input("name", x0, y0 + 20, colW, 28.9, { placeholder = U.text("navigator.createroom.roomnameinfo", "Room name"), max = 60, value = m.name,
		onChange = function(v) m.name = v end })
	m.name = nameBox:GetValue() or ""
	label(U.text("navigator.createroom.roomdescinfo", "Room Description"), 127.9)
	local descBox = d:input("description", x0, 147.9, colW, 80.8, { placeholder = U.text("navigator.createroom.roomdescinfo", "Room Description"), max = 255, multiline = true, value = m.description,
		onChange = function(v) m.description = v end })
	m.description = descBox:GetValue() or ""
	label(U.text("navigator.category", "Category"), 232.7)
	local cats = { { 0, U.text("navigator.category.no_category", "No category") } }
	for _, c in ipairs(BOBBA.roomWindows and BOBBA.roomWindows.CATEGORIES or {}) do
		if not c.staff then cats[#cats + 1] = { c.id, U.text("navigator.flatcategory.global." .. c.code, c.name) } end
	end
	d:select("category", x0, 252.7, colW, 28.9, cats, m.category, function(v) m.category = v end)
	label(U.text("navigator.maxvisitors", "Maximum amount of visitors"), 285.6)
	local maxOpts = {}
	for _, v in ipairs(NAV.MAX_USERS) do maxOpts[#maxOpts + 1] = { v, tostring(v) } end
	d:select("max", x0, 305.6, colW, 28.9, maxOpts, m.maxUsers, function(v) m.maxUsers = v end)
	label(U.text("navigator.tradesettings", "Trade settings"), 338.5)
	d:select("trade", x0, 358.5, colW, 28.9, {
		{ 0, U.text("navigator.roomsettings.trade_not_allowed", "Trading not allowed") },
		{ 1, U.text("navigator.roomsettings.trade_not_with_Controller", "Room owners and users with rights") },
		{ 2, U.text("navigator.roomsettings.trade_allowed", "Everyone can trade") },
	}, m.trade, function(v) m.trade = v end)
	-- the models: one under the other, 88 high, 4 apart; club ones dimmed with Habbo Club's coin
	local mx, mw, top, bottom = 214, 197, y0, y0 + 312.4
	local itemH = 88
	local total = #NAV.MODELS * (itemH + 4) - 4
	local off = d:scroll("models", mx, top, mw, bottom - top, total)
	d:clip(mx, top, mw, bottom - top, function()
		for i, mdl in ipairs(NAV.MODELS) do
			local iy = top + (i - 1) * (itemH + 4) - off
			if iy + itemH > top and iy < bottom then
				local name, tiles, club = mdl[1], mdl[2], mdl[3]
				local purse = BOBBA.hud and BOBBA.hud.purse
				local disabled = club > ((purse and purse.clubLevel) or 0)
				local active = m.model == name
				d:click(mx, math.max(iy, top), mw, math.min(iy + itemH, bottom) - math.max(iy, top), function()
					if not disabled then m.model = name end
				end)
				d:gridItem(mx, iy, mw, itemH, active)
				drawModel(d, name, mx + mw / 2, iy + 6 + 30, mw - 30, 56)
				d:text(tiles .. " " .. U.text("navigator.createroom.tilesize", "tiles"), 14.4, mx + mw / 2, iy + itemH - 6 - 8, U.C.black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
				if club > 0 then U.clubIcon(d, U.clubKindFor(club), mx + mw - 4 - 15, iy + 4, 15, 15) end
				if disabled then d:round(4, mx + 2, iy + 2, mw - 4, itemH - 4, Color(205, 211, 217, 204)) end
			end
		end
	end)
	-- create: red and off until the name has 3 letters, then green
	local ok = (utf8.len(m.name) or #m.name) >= 3
	local by = 395.4
	d:btn(x0, by, 402, 35.6, ok and U.C.success or U.C.danger, function()
		P.send("navigator.create", { name = m.name, description = m.description, model = m.model, maxUsers = m.maxUsers, trade = m.trade, category = m.category })
	end, not ok)
	d:text(U.text("navigator.createroom.create", "Create room"), 14.4, x0 + 201, by + 35.6 / 2, Color(255, 255, 255, ok and 255 or 166), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- --- the window -------------------------------------------------------------------------------------
local function drawNavigator(w, d)
	local tabs = {}
	for _, v in ipairs(VIEWS) do tabs[#tabs + 1] = { id = v, label = U.text("navigator.toplevelview." .. v, FALLBACK[v]) } end
	tabs[#tabs + 1] = { id = "create", icon = "plus" }
	local title = S.creator and U.text("navigator.createroom.title", "Room creation") or U.text("navigator.title", "Navigator")
	d:card(title, tabs, S.creator and "create" or S.view, function(id)
		if id == "create" then S.creator = true return end
		S.creator = false
		search(id, "")
	end)
	if S.creator then drawCreator(w, d) return end
	-- the search: Habbo's filters, the box, the button
	local opts = {}
	for i, f in ipairs(FILTERS) do opts[#opts + 1] = { i, U.text("navigator.filter." .. f[1], FILTER_TEXT[f[1]]) } end
	-- (as wide as its longest choice, like the browser makes a select: 9 before the text, 36 after)
	local selW = 0
	for _, o in ipairs(opts) do selW = math.max(selW, d:textWidth(o[2], 12.6)) end
	selW = math.ceil(selW + 9 + 36 + 2)
	local y = 75
	local function go()
		local box = w.inputs and w.inputs.search
		local text = box and box:GetValue() or ""
		local f = FILTERS[S.filter] or FILTERS[1]
		search(S.view, ((text ~= "" and f[2]) and (f[2] .. ":") or "") .. text)
	end
	d:select("filter", 9, y, selW, 28.9, opts, S.filter, function(v) S.filter = v end)
	local box = d:input("search", 9 + selW + 4, y, 402 - selW - 4 - 4 - 40.4, 28.9, { placeholder = U.text("navigator.filter.input.placeholder", "filter rooms by..."), max = 100, onEnter = go })
	-- (a search from elsewhere: its filter and text in the box)
	if S.pendingQuery then
		local kind, text = S.pendingQuery:match("^(%a+):(.*)$")
		S.filter = 1
		for i, f in ipairs(FILTERS) do if f[2] == kind then S.filter = i end end
		box:SetText(text or S.pendingQuery)
		S.pendingQuery = nil
	end
	d:btn(411 - 40.4, y, 40.4, 28.9, U.C.primary, go)
	d:fa("search", 411 - 40.4 + 13, y + 7.3, 14.4, U.C.white)
	-- the results, scrolling
	local top, bottom = y + 28.9 + 8, H - 1 - 8
	local blocks = S.result and S.result.blocks or {}
	local total = 0
	for i, b in ipairs(blocks) do total = total + blockHeight(b) + (i > 1 and 8 or 0) end
	local off = d:scroll("results", 9, top, 402, bottom - top, total)
	d:clip(9, top, 402, bottom - top, function()
		local by = top - off
		for _, b in ipairs(blocks) do
			by = by + drawBlock(d, b, 9, by, 402, top, bottom) + 8
		end
	end)
	-- while it's looking: the content dimmed (bg-muted at 50%)
	if S.loading then d:rect(1, 67, W - 2, H - 68, Color(182, 190, 197, 128)) end
end

-- (query: a search to show, e.g. "tag:party" from a room's tag)
function NAV.open(view, query)
	if view then S.view = view S.creator = false end
	U.window("navigator", W, H, drawNavigator)
	search(S.view, query or "")
	if query and query ~= "" then S.pendingQuery = query end
end

-- the toolbar's rooms button, and the "me" menu's (My World)
HUD.actions.navigator = function() U.toggle("navigator", function() NAV.open() end) end
HUD.actions.myRooms = function() NAV.open("myworld_view") end

-- going into a room closes it (and a new room made here is gone into by the server)
BOBBA.events.on("roomShown", "bobba.navigator.close", function()
	if U.windows.navigator then U.windows.navigator:close() end
	S.creator = false
end)
P.receive("navigator.created", function() S.make = { name = "", description = "", maxUsers = 10, trade = 0, category = 0, model = "a" } end)

concommand.Add("bobba_navigator", function() NAV.open() end)
