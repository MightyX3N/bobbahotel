-- The Rooms app (the phone's navigator): the rooms to go to by list (popular, all, events, yours),
-- a search, and making a room. The same messages as the navigator window (client/navigator.lua).

local DV = BOBBA.device
local U = BOBBA.ui
local P = BOBBA.platform
local R = BOBBA.room
local V = BOBBA.view
local NAV = BOBBA.navigator
local C, G = DV.C, DV.G
local alpha = DV.alpha
local T = function(k, f, v) return U.text(k, f, v) end

local VIEWS = {
	{ id = "official_view", key = "bobba.phone.rooms.popular", fallback = "Popular" },
	{ id = "hotel_view", key = "bobba.phone.rooms.all", fallback = "All rooms" },
	{ id = "roomads_view", key = "bobba.phone.rooms.events", fallback = "Events" },
	{ id = "myworld_view", key = "bobba.phone.rooms.mine", fallback = "Yours" },
}
local ROOM_COLORS = { C.blue, C.pink, C.green, C.yellow, C.purple, C.peach, C.sky }

local function blockTitle(block)
	local cat = block.code:match("^category%.(.+)$")
	return cat and T("navigator.flatcategory.global." .. cat, cat) or T("navigator.searchcode.title." .. block.code, block.code)
end

-- a room's picture: its thumbnail, else a colour with its first letter
local function roomPicture(d, room, x, y, w, h, r)
	local CAM = BOBBA.camera
	local mat = room.thumbnail and CAM and CAM.photo and CAM.photo(room.thumbnail)
	if mat then
		d:round(r, x, y, w, h, C.mist)
		d:clip(x, y, w, h, function() d:material(mat, x, y, w, h) end)
		return
	end
	d:round(r, x, y, w, h, ROOM_COLORS[(tonumber(room.id) or 1) % #ROOM_COLORS + 1])
	d:glyph(G.rooms, x + w / 2 - w * 0.22, y + h / 2 - h * 0.22, math.min(w, h) * 0.44, alpha(C.navy, 0.7), 2)
end

-- how full: green, yellow, red
local function fullColor(room)
	local n = (room.users or 0) / math.max(1, room.maxUsers or 1)
	if n >= 0.92 then return C.red elseif n >= 0.5 then return C.yellow elseif n > 0 then return C.green end
	return C.line
end

local function go(room)
	DV.home()
	DV.show(false)
	local RW = BOBBA.roomWindows
	if RW and RW.visit then RW.visit(room) else P.send("room.enter", { id = room.id }) end
end

local function lockGlyph(room)
	if room.door == "doorbell" then return "M6 16V11a6 6 0 0 1 12 0v5l2 2H4zM10 20a2 2 0 0 0 4 0" end
	if room.door == "password" or room.door == "invisible" then return G.lock end
end

-- --- the list ---------------------------------------------------------------------------------------
local function roomsView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local S = NAV.client
	local st = ctx.state
	if not st.started then
		st.started = true
		st.view = st.view or (R.current and "official_view" or "official_view")
		NAV.search(st.view, "")
	end
	d:rect(0, 0, W, H, C.paper)
	local tablet = ctx.kind == "tablet"
	local top = ctx.top + ctx:header(T("bobba.phone.app.rooms", "Rooms"), { big = true, right = {
		{ glyph = G.plus, fn = function() ctx:push(DV.roomCreateView, {}) end },
	} })
	local x, w = 20, W - 40
	if tablet then x, w = 40, W - 80 end
	-- the search
	d:input("roomsearch", x, top + 4, w, 44, { placeholder = T("bobba.phone.rooms.search", "Search rooms, owners, #tags"), max = 100,
		onEnter = function(t)
			local q = t or ""
			if q:sub(1, 1) == "#" then q = "tag:" .. q:sub(2) end
			NAV.search(st.view, q)
		end })
	d:glyph(G.search, x + w - 36, top + 4 + 12, 20, C.ink2, 2.2)
	local y = top + 4 + 44 + 12
	local list = {}
	for _, v in ipairs(VIEWS) do list[#list + 1] = { id = v.id, label = T(v.key, v.fallback) } end
	d:chips("roomviews", x, y, w, list, st.view, function(id) st.view = id NAV.search(id, "") end)
	y = y + 32 + 12
	-- where you are: back to the hotel view, or home
	if V.mode == "room" and R.current then
		local c = R.current
		d:round(20, x, y, w, 60, C.navy)
		d:text(T("bobba.phone.widget.youin", "YOU'RE IN"), 11, x + 16, y + 12, C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
		d:text(d:fit(c.name or "", 15, w - 150, 800), 15, x + 16, y + 28, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		d:button(x + w - 120, y + 13, 108, 34, T("bobba.phone.rooms.leave", "Leave"), "paper", function()
			DV.home()
			local HUD = BOBBA.hud
			if HUD and HUD.actions.hotelView then HUD.actions.hotelView() end
		end)
		y = y + 60 + 12
	end
	-- the rooms, in their lists
	local blocks = S.result and S.result.blocks or {}
	local rowH = tablet and 96 or 76
	local cols = tablet and 2 or 1
	local colW = (w - (cols - 1) * 16) / cols
	local content = 0
	for _, b in ipairs(blocks) do content = content + 34 + math.ceil(#b.rooms / cols) * rowH + 8 end
	if #blocks == 0 then content = 80 end
	local listTop = y
	local off = d:scroll("rooms", 0, listTop, W, H - listTop, content + 40)
	d:clip(0, listTop, W, H - listTop, function()
		local yy = listTop - off
		if S.loading and #blocks == 0 then
			d:text(T("bobba.phone.loading", "Loading…"), 14, W / 2, yy + 40, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		elseif #blocks == 0 then
			d:text(T("bobba.phone.rooms.none", "No rooms here yet."), 14, W / 2, yy + 40, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		end
		for _, b in ipairs(blocks) do
			d:text(blockTitle(b):upper(), 12, x + 4, yy + 16, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
			yy = yy + 34
			for i, room in ipairs(b.rooms) do
				local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
				local rx, ry = x + col * (colW + 16), yy + row * rowH
				if ry + rowH > listTop and ry < H then
					local hov = d:click(rx, ry, colW, rowH - 8, function() go(room) end)
					d:round(20, rx, ry, colW, rowH - 8, hov and C.line or C.white)
					local ph = rowH - 8 - 16
					roomPicture(d, room, rx + 8, ry + 8, ph, ph, 14)
					local tx = rx + 8 + ph + 12
					local lk = lockGlyph(room)
					local nameW = colW - (tx - rx) - 70 - (lk and 22 or 0)
					d:text(d:fit(room.name or "", 15, nameW, 800), 15, tx, ry + (rowH - 8) / 2 - 10, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
					if lk then d:glyph(lk, tx + math.min(nameW, d:textWidth(d:fit(room.name or "", 15, nameW, 800), 15, 800)) + 6, ry + (rowH - 8) / 2 - 18, 16, C.ink2, 2.2) end
					local sub = room.owner or ""
					if room.description and room.description ~= "" and tablet then sub = sub .. " · " .. room.description end
					d:text(d:fit(sub, 13, colW - (tx - rx) - 70), 13, tx, ry + (rowH - 8) / 2 + 11, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					-- how many are in it
					local cnt = tostring(room.users or 0)
					local cw = d:textWidth(cnt, 13, 800) + 34
					local cc = fullColor(room)
					d:pill(rx + colW - 12 - cw, ry + (rowH - 8) / 2 - 14, cw, 28, cc)
					d:glyph("M12 4a3 3 0 1 1 0 6a3 3 0 1 1 0-6M6 20a6 6 0 0 1 12 0", rx + colW - 12 - cw + 8, ry + (rowH - 8) / 2 - 8, 16, C.navy, 2.4)
					d:text(cnt, 13, rx + colW - 12 - cw + 27, ry + (rowH - 8) / 2, C.navy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
				end
			end
			yy = yy + math.ceil(#b.rooms / cols) * rowH + 8
		end
	end)
end

-- --- making a room ----------------------------------------------------------------------------------
function DV.roomCreateView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local st = ctx.state
	st.model = st.model or "a"
	st.maxUsers = st.maxUsers or 10
	st.category = st.category or 0
	st.name = st.name or ""
	d:rect(0, 0, W, H, C.paper)
	local tablet = ctx.kind == "tablet"
	local top = ctx.top + ctx:header(T("navigator.createroom.title", "Room creation"))
	local x, w = 20, W - 40
	if tablet then x, w = math.max(20, (W - 720) / 2), math.min(720, W - 40) end
	local ok = (utf8.len(st.name) or #st.name) >= 3
	local footer = 84
	local off = d:scroll("create", 0, top, W, H - top - footer, st.contentH or H)
	d:clip(0, top, W, H - top - footer, function()
		local y = top + 8 - off
		local function label(t) d:text(t, 13, x + 4, y + 8, C.ink2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700) y = y + 22 end
		label(T("navigator.createroom.roomnameinfo", "Room name"))
		local e = d:input("roomname", x, y, w, 46, { placeholder = T("bobba.phone.rooms.namehint", "At least 3 letters"), max = 60, value = st.name, bg = C.white,
			onChange = function(v) st.name = v end })
		st.name = e:GetValue() or ""
		y = y + 46 + 14
		label(T("navigator.createroom.roomdescinfo", "Room Description"))
		local de = d:input("roomdesc", x, y, w, 80, { placeholder = T("bobba.phone.rooms.deschint", "What's it for?"), max = 255, multiline = true, value = st.description, bg = C.white, radius = 18,
			onChange = function(v) st.description = v end })
		st.description = de:GetValue() or ""
		y = y + 80 + 14
		-- how many visitors: - n +
		label(T("navigator.maxvisitors", "Maximum amount of visitors"))
		d:round(23, x, y, w, 46, C.white)
		d:text(tostring(st.maxUsers), 17, x + w / 2, y + 23, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
		local list = NAV.MAX_USERS or { 10, 20, 30, 40, 50 }
		local idx = 1
		for i, v in ipairs(list) do if v == st.maxUsers then idx = i end end
		d:button(x + 6, y + 6, 34, 34, "−", "light", function() st.maxUsers = list[math.max(1, idx - 1)] end)
		d:button(x + w - 40, y + 6, 34, 34, "+", "light", function() st.maxUsers = list[math.min(#list, idx + 1)] end)
		y = y + 46 + 14
		-- the category
		label(T("navigator.category", "Category"))
		local cats = { { id = 0, label = T("navigator.category.no_category", "No category") } }
		for _, c in ipairs(BOBBA.roomWindows and BOBBA.roomWindows.CATEGORIES or {}) do
			if not c.staff then cats[#cats + 1] = { id = c.id, label = T("navigator.flatcategory.global." .. c.code, c.name) } end
		end
		d:chips("cats", x, y, w, cats, st.category, function(id) st.category = id end, { off = C.white })
		y = y + 32 + 14
		-- the room's shape
		label(T("bobba.phone.rooms.shape", "Shape"))
		local cols = tablet and 4 or 2
		local cw = (w - (cols - 1) * 10) / cols
		local ch = 110
		local purse = BOBBA.hud and BOBBA.hud.purse
		for i, mdl in ipairs(NAV.MODELS or {}) do
			local name, tiles, club = mdl[1], mdl[2], mdl[3]
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			local mx, my = x + col * (cw + 10), y + row * (ch + 10)
			local locked = club > ((purse and purse.clubLevel) or 0)
			local on = st.model == name
			d:click(mx, my, cw, ch, function() if not locked then st.model = name end end)
			d:round(18, mx, my, cw, ch, on and C.navy or C.white)
			-- the shape, small
			local shape = NAV.modelShape and NAV.modelShape(name) or {}
			if #shape > 0 then
				local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
				for _, t in ipairs(shape) do
					local sx, sy = (t[1] - t[2]), (t[1] + t[2]) / 2 - (t[3] or 0) / 2
					minX, maxX = math.min(minX, sx - 1), math.max(maxX, sx + 1)
					minY, maxY = math.min(minY, sy), math.max(maxY, sy + 1)
				end
				local k = math.min((cw - 30) / (maxX - minX), 60 / (maxY - minY), 4)
				local ox, oy = mx + cw / 2 - (minX + maxX) / 2 * k, my + 44 - (minY + maxY) / 2 * k
				local s = d.s
				local col2 = d:col(on and C.orange or C.mist)
				surface.SetDrawColor(col2.r, col2.g, col2.b, col2.a)
				draw.NoTexture()
				for _, t in ipairs(shape) do
					local sx, sy = (t[1] - t[2]), (t[1] + t[2]) / 2 - (t[3] or 0) / 2
					local px, py = ox + sx * k + d.ox, oy + sy * k + d.oy
					surface.DrawPoly({ { x = px * s, y = py * s }, { x = (px + k) * s, y = (py + k / 2) * s }, { x = px * s, y = (py + k) * s }, { x = (px - k) * s, y = (py + k / 2) * s } })
				end
			end
			d:text(tiles .. " " .. T("navigator.createroom.tilesize", "tiles"), 12, mx + cw / 2, my + ch - 16, on and C.paper or C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
			if club > 0 then
				d:pill(mx + cw - 48, my + 8, 40, 20, C.gold)
				d:text(T("bobba.phone.app.club", "Club"), 10, mx + cw - 28, my + 18, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
			end
			if locked then d:round(18, mx, my, cw, ch, Color(244, 246, 251, 150)) end
		end
		y = y + math.ceil(#(NAV.MODELS or {}) / cols) * (ch + 10) + 20
		st.contentH = y + off - top
	end)
	-- make it
	d:rect(0, H - footer, W, footer, C.paper)
	d:button(x, H - footer + 10, w, 50, T("navigator.createroom.create", "Create room"), ok and "primary" or "light", function()
		P.send("navigator.create", { name = st.name, description = st.description or "", model = st.model, maxUsers = st.maxUsers, trade = 0, category = st.category })
		DV.home()
		DV.show(false)
	end, not ok)
end

DV.app({ id = "rooms", name = T("bobba.phone.app.rooms", "Rooms"), accent = true, glyph = G.rooms, dock = true, order = 3, removable = false,
	phone = roomsView, tablet = roomsView })
