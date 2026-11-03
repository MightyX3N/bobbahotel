-- The hotel's windows (client), drawn the way nitro-react draws its cards (src/common: NitroCardView,
-- NitroCardHeaderView, NitroCardTabsView, LayoutGridItem, Button; colours and sizes from its
-- compiled SCSS). Sizes are CSS pixels; everything is drawn U.scale() times as big (1 below 4K).
--
-- A window is one panel that draws everything itself and keeps a list of what can be clicked:
--   local w = BOBBA.ui.window("id", 620, 374, function(w, d) ... end)   -- d: drawing helpers
--   w:close(), w.panel
-- In the draw function: d.card(title, tabs, activeTab), d.gridItem(...), d.button(...),
-- d.click(x, y, w, h, fn), d.scroll(id, x, y, w, h, contentHeight) -> offset ...

BOBBA.ui = BOBBA.ui or { windows = {} }
local U = BOBBA.ui
local V = BOBBA.view

-- nitro-react's colours ($primary, $secondary, $muted, $light, ...; assets/styles/bootstrap/_variables.scss)
U.C = {
	border = Color(40, 63, 93), primary = Color(30, 114, 149), secondary = Color(24, 93, 121), muted = Color(182, 190, 197),
	light = Color(223, 223, 223), white = Color(255, 255, 255), black = Color(0, 0, 0), tabBar = Color(194, 201, 209),
	gridItem = Color(205, 211, 217), gridActive = Color(236, 236, 236), paleSky = Color(103, 113, 129),
	success = Color(0, 128, 11), closeTop = Color(245, 80, 65), closeBottom = Color(194, 48, 39), closeBorder = Color(146, 25, 17),
}

-- The UI's size (toolbar, purse, windows, chat input): Habbo's pixels up to 2159 pixels high, 2x
-- from 2160 (4K), like a browser at 100% shows Nitro. (Rooms and their chat bubbles have their own,
-- bigger size: V.uiScale.)
function U.scale(h) return math.max(1, math.floor((h or ScrH()) / 1080)) end

-- Nitro's font at a CSS size: its "Ubuntu" is Ubuntu Condensed (nitro-react's fonts.scss, Ubuntu-C.ttf,
-- shipped in addons/bobbahotel/resource/fonts; bold is made from it, as the browser does).
-- GMod's font size is the letters' whole height: ascent + descent, 1.121 of CSS's size.
U.FONT, U.FONT_CELL = "Ubuntu Condensed", 1.121
local fonts = {}
function U.font(px, bold)
	local size = math.floor(px * U.FONT_CELL * U.scale() + 0.5)
	local name = "BobbaUIU" .. size .. (bold and "b" or "")
	if not fonts[name] then
		surface.CreateFont(name, { font = U.FONT, size = size, weight = bold and 700 or 500, antialias = true, extended = true })
		fonts[name] = true
	end
	return name, size
end

-- --- drawing helpers, in CSS pixels from the window's corner ---------------------------------------
local D = {}
D.__index = D

local function px(d, v) return math.floor(v * d.s + 0.5) end

function D:rect(x, y, w, h, c)
	surface.SetDrawColor(c.r, c.g, c.b, c.a or 255)
	surface.DrawRect(px(self, x), px(self, y), px(self, x + w) - px(self, x), px(self, y + h) - px(self, y))
end

function D:round(r, x, y, w, h, c, tl, tr, bl, br)
	local X, Y = px(self, x), px(self, y)
	local W, H = px(self, x + w) - X, px(self, y + h) - Y
	if tl == nil then draw.RoundedBox(math.max(0, math.floor(r * self.s)), X, Y, W, H, c)
	else draw.RoundedBoxEx(math.max(0, math.floor(r * self.s)), X, Y, W, H, c, tl, tr, bl, br) end
end

-- a box with a border (bootstrap: border + border-radius)
function D:box(x, y, w, h, bw, r, border, fill, tl, tr, bl, br)
	self:round(r, x, y, w, h, border, tl, tr, bl, br)
	self:round(math.max(0, r - bw), x + bw, y + bw, w - 2 * bw, h - 2 * bw, fill, tl, tr, bl, br)
end

function D:text(t, size, x, y, c, ax, ay, bold)
	local font = U.font(size, bold)
	draw.SimpleText(t, font, px(self, x), px(self, y), c, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP)
end

function D:textWidth(t, size, bold)
	surface.SetFont((U.font(size, bold)))
	local w = surface.GetTextSize(t)
	return w / self.s
end

-- something to click: fn(), and hover when the mouse is over it
function D:click(x, y, w, h, fn, cursor)
	self.w.clicks[#self.w.clicks + 1] = { x = x, y = y, w = w, h = h, fn = fn }
	return self.w.mx and self.w.mx >= x and self.w.mx < x + w and self.w.my >= y and self.w.my < y + h
end

-- a part of the window that scrolls (overflow: auto): the offset to draw its content at
function D:scroll(id, x, y, w, h, contentHeight)
	local sc = self.w.scrolls[id] or { offset = 0 }
	self.w.scrolls[id] = sc
	sc.x, sc.y, sc.w, sc.h, sc.max = x, y, w, h, math.max(0, contentHeight - h)
	if sc.offset > sc.max then sc.offset = sc.max end
	if sc.offset < 0 then sc.offset = 0 end
	return sc.offset
end

-- only draw inside x, y, w, h (in CSS pixels) while fn runs
-- (clips inside clips: the inner one is cut to the outer one, and the outer one comes back after)
local clips = {}
function D:clip(x, y, w, h, fn)
	local ox, oy = self.w.panel:LocalToScreen(0, 0)
	local r = { ox + px(self, x), oy + px(self, y), ox + px(self, x + w), oy + px(self, y + h) }
	local outer = clips[#clips]
	if outer then
		r[1], r[2] = math.max(r[1], outer[1]), math.max(r[2], outer[2])
		r[3], r[4] = math.max(r[1], math.min(r[3], outer[3])), math.max(r[2], math.min(r[4], outer[4]))
	end
	clips[#clips + 1] = r
	render.SetScissorRect(r[1], r[2], r[3], r[4], true)
	local ok, err = pcall(fn)
	clips[#clips] = nil
	if outer then render.SetScissorRect(outer[1], outer[2], outer[3], outer[4], true) else render.SetScissorRect(0, 0, 0, 0, false) end
	if not ok then ErrorNoHalt("[Bobba] window: " .. tostring(err) .. "\n") end
end

-- NitroCardView + NitroCardHeaderView + NitroCardTabsView (theme-primary)
function D:card(title, tabs, active, onTab)
	local W, H = self.width, self.height
	-- box-shadow: 0 2px 0 rgba(0,0,0,.45)
	self:round(4, 0, 2, W, H, Color(0, 0, 0, 115))
	self:round(4, 0, 0, W, H, U.C.border)
	-- the header: 33 high, the title in the middle, the close button 8 from the right
	self:round(3, 1, 1, W - 2, H - 2, U.C.light)
	self:round(3, 1, 1, W - 2, 33, U.C.primary, true, true, false, false)
	-- (text-shadow: 0 4px 4px rgba(0,0,0,.25))
	self:text(title, 20.976, W / 2, 1 + 33 / 2 + 2, Color(0, 0, 0, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	self:text(title, 20.976, W / 2, 1 + 33 / 2, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local cx, cy = W - 1 - 8 - 20, 8
	local hover = self:click(cx, cy, 20, 20, function() self.w:close() end)
	-- white ring (box-shadow 0 0 0 1.6px), a 2px dark red border, red split in two
	self:round(5, cx - 1.6, cy - 1.6, 23.2, 23.2, U.C.white)
	self:round(4, cx, cy, 20, 20, U.C.closeBorder)
	local top, bottom = U.C.closeTop, U.C.closeBottom
	if hover then top, bottom = Color(255, 96, 78), Color(233, 58, 47) end
	self:round(2, cx + 2, cy + 2, 16, 8, top, true, true, false, false)
	self:round(2, cx + 2, cy + 10, 16, 8, bottom, false, false, true, true)
	-- the X (FaTimes, 12 x 12)
	local s = self.s
	local x0, y0 = (cx + 4) * s, (cy + 4) * s
	surface.SetDrawColor(255, 255, 255, 255)
	draw.NoTexture()
	for i = 0, math.max(1, math.floor(2 * s)) - 1 do
		surface.DrawLine(x0 + i, y0, x0 + 12 * s - 1, y0 + 12 * s - 1 - i)
		surface.DrawLine(x0, y0 + i, x0 + 12 * s - 1 - i, y0 + 12 * s - 1)
		surface.DrawLine(x0 + 12 * s - 1 - i, y0, x0, y0 + 12 * s - 1 - i)
		surface.DrawLine(x0 + 12 * s - 1, y0 + i, x0 + i, y0 + 12 * s - 1)
	end
	-- the tabs bar: 33 high, tabs centred 4 apart, each 29 high from 4 down
	if tabs then
		self:rect(1, 34, W - 2, 33, U.C.secondary)
		self:rect(1, 66, W - 2, 1, U.C.border)
		local widths, total = {}, 0
		for i, t in ipairs(tabs) do
			widths[i] = math.ceil((t.icon and 14.4 or self:textWidth(t.label, 14.4)) + 12.8 * 2 + 2)
			total = total + widths[i] + (i > 1 and 4 or 0)
		end
		local x = math.floor((W - total) / 2)
		for i, t in ipairs(tabs) do
			local isActive = t.id == active
			local w = widths[i]
			self:click(x, 38, w, 29, function() if onTab then onTab(t.id) end end)
			self:box(x, 38, w, isActive and 29 or 28, 1, 4, U.C.border, isActive and U.C.light or U.C.muted, true, true, false, false)
			-- (::before: a 3 high bar, 93% wide, 1.5 from the top)
			local bw = w * 0.93
			self:round(2, x + (w - bw) / 2, 38 + 1.5, bw, 3, isActive and U.C.white or U.C.tabBar)
			if t.icon then self:fa(t.icon, x + (w - 14.4) / 2, 38 + (29 - 14.4) / 2 + 1, 14.4, U.C.black)
			else self:text(t.label, 14.4, x + w / 2, 38 + 29 / 2 + 1, U.C.black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
			x = x + w + 4
		end
	end
end

-- NitroCardView theme-primary-slim (the friends list, the chat history, the settings): a 28 high header
-- in two light blues with a white line under it, the title 18px, a smaller close button
function D:slimCard(title)
	local W, H = self.width, self.height
	self:round(4, 0, 2, W, H, Color(0, 0, 0, 115))
	self:round(4, 0, 0, W, H, U.C.border)
	self:round(3, 1, 1, W - 2, H - 2, U.C.light)
	-- the header: #2dabc2 over #2b91a7, a 2px #267f93 line at its bottom, white under that
	self:round(3, 1, 1, W - 2, 13, Color(45, 171, 194), true, true, false, false)
	self:rect(1, 14, W - 2, 13, Color(43, 145, 167))
	self:rect(1, 27, W - 2, 2, Color(38, 127, 147))
	self:rect(1, 29, W - 2, 2, U.C.white)
	self:rect(1, 1, W - 2, 2, Color(255, 255, 255, 77))
	self:text(title, 18, W / 2, 1 + 2 + 2 + 21 / 2 + 2, Color(0, 0, 0, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	self:text(title, 18, W / 2, 1 + 2 + 2 + 21 / 2, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	-- the close button: 20 x 16
	local cx, cy = W - 1 - 8 - 20, 7
	local hover = self:click(cx, cy, 20, 16, function() self.w:close() end)
	self:round(5, cx - 1.6, cy - 1.6, 23.2, 19.2, U.C.white)
	self:round(4, cx, cy, 20, 16, U.C.closeBorder)
	local top, bottom = U.C.closeTop, U.C.closeBottom
	if hover then top, bottom = Color(255, 96, 78), Color(233, 58, 47) end
	self:round(2, cx + 2, cy + 2, 16, 6, top, true, true, false, false)
	self:round(2, cx + 2, cy + 8, 16, 6, bottom, false, false, true, true)
	self:fa("times", cx + 10 - 5.4, cy + 8 - 5.4, 10.8, U.C.white)
end

-- LayoutGridItem: 2px muted border (white when active), #cdd3d9 (or #ececec, or its colour)
function D:gridItem(x, y, w, h, active, color, highlight)
	local fill = color or (active and U.C.gridActive or U.C.gridItem)
	self:box(x, y, w, h, 2, 4, active and U.C.white or U.C.muted, fill)
	if highlight then
		-- has-highlight::after: the top half, white at 10%
		self:round(2, x + 2, y + 2, w - 4, (h - 4) / 2, Color(255, 255, 255, 26), true, true, false, false)
	end
end

-- Button (btn-sm): a colour, inset light at the top and dark at the bottom
function D:button(x, y, w, h, color, fn, corners)
	local hover = self:click(x, y, w, h, fn)
	local c = color
	if hover then c = Color(math.min(255, c.r + 18), math.min(255, c.g + 18), math.min(255, c.b + 18)) end
	local tl, tr, bl, br = true, true, true, true
	if corners then tl, tr, bl, br = corners[1], corners[2], corners[3], corners[4] end
	self:round(3.2, x, y + 1, w, h, Color(0, 0, 0, 26), tl, tr, bl, br)
	self:round(3.2, x, y, w, h, c, tl, tr, bl, br)
	self:rect(x + 1, y + 1, w - 2, 2, Color(255, 255, 255, 38))
	self:rect(x + 1, y + h - 3, w - 2, 2, Color(0, 0, 0, 26))
	return hover
end

-- Habbo's pictures for the UI (the toolbar's icons, the purse's coins, ...), by the name nitro-react
-- gives them ("rooms", "catalog", "currency-credits", ...). An addon says where they are:
--   BOBBA.ui.iconProvider = function(name) return { material = m, width = w, height = h, u = u, v = v } end
-- (the picture is the top-left u x v of the material). Without one, nothing is drawn.
U.iconProvider = U.iconProvider
function U.icon(name)
	if not U.iconProvider then return nil end
	local ok, ic = pcall(U.iconProvider, name)
	return ok and ic or nil
end

-- an icon at its own size, its top-left corner at x, y; or in the middle of a box (CSS's
-- background-position: center) when w and h are given. opts: shadow (Nitro's hover: drop-shadow
-- 2px 2px black at 80%, the icon 1px up and left), black (its shape in black), alpha, flip.
-- Returns whether it was drawn.
function D:icon(name, x, y, w, h, opts)
	local ic = U.icon(name)
	if not ic or not ic.material then return false end
	opts = opts or {}
	if w then x = x + math.floor((w - ic.width) / 2) end
	if h then y = y + math.floor((h - ic.height) / 2) end
	local function put(dx, dy, r, g, b, a)
		local X, Y = px(self, x + dx), px(self, y + dy)
		local W, H = px(self, x + dx + ic.width) - X, px(self, y + dy + ic.height) - Y
		surface.SetMaterial(ic.material)
		surface.SetDrawColor(r, g, b, a)
		if opts.flip then surface.DrawTexturedRectUV(X, Y, W, H, ic.u, 0, 0, ic.v)
		else surface.DrawTexturedRectUV(X, Y, W, H, 0, 0, ic.u, ic.v) end
	end
	render.PushFilterMag(TEXFILTER.POINT)
	render.PushFilterMin(TEXFILTER.POINT)
	local a = opts.alpha or 255
	if opts.black then
		put(0, 0, 0, 0, 0, a)
	elseif opts.shadow then
		put(1, 1, 0, 0, 0, a * 0.8)
		put(-1, -1, 255, 255, 255, a)
	else
		put(0, 0, 255, 255, 255, a)
	end
	render.PopFilterMin()
	render.PopFilterMag()
	return true
end

function U.iconSize(name)
	local ic = U.icon(name)
	if ic then return ic.width, ic.height end
end

-- Nitro's dark boxes (the toolbar, the purse, the room tools): $dark at 95%, inset 5px lighter at the
-- top and 4px darker at the bottom
U.C.dark = Color(28, 28, 32, 242)
function D:darkBox(x, y, w, h, r, tl, tr, bl, br)
	r = r or 0
	if tl == nil then tl, tr, bl, br = true, true, true, true end
	self:round(r, x, y, w, h, U.C.dark, tl, tr, bl, br)
	-- (the bands follow the box's corners)
	self:round(math.min(r, 2), x, y, w, 5, Color(34, 34, 39, 153), tl, tr, false, false)
	self:round(math.min(r, 2), x, y + h - 4, w, 4, Color(18, 18, 21, 153), false, false, bl, br)
end

-- --- shapes ---------------------------------------------------------------------------------------
-- a filled circle (a polygon, clockwise as GMod wants) in CSS px
function D:circle(cx, cy, r, c)
	local s = self.s
	local pts, n = {}, math.max(10, math.floor(r * s * 1.5))
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		pts[#pts + 1] = { x = (cx + math.cos(a) * r) * s, y = (cy + math.sin(a) * r) * s }
	end
	surface.SetDrawColor(c.r, c.g, c.b, c.a or 255)
	draw.NoTexture()
	surface.DrawPoly(pts)
end

-- a ring (a circle's outline, w thick)
function D:ring(cx, cy, r, w, c)
	local s = self.s
	local n = math.max(12, math.floor(r * s * 1.5))
	surface.SetDrawColor(c.r, c.g, c.b, c.a or 255)
	draw.NoTexture()
	for i = 0, n - 1 do
		local a0, a1 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2
		surface.DrawPoly({
			{ x = (cx + math.cos(a0) * r) * s, y = (cy + math.sin(a0) * r) * s },
			{ x = (cx + math.cos(a1) * r) * s, y = (cy + math.sin(a1) * r) * s },
			{ x = (cx + math.cos(a1) * (r - w)) * s, y = (cy + math.sin(a1) * (r - w)) * s },
			{ x = (cx + math.cos(a0) * (r - w)) * s, y = (cy + math.sin(a0) * (r - w)) * s },
		})
	end
end

-- a line w thick from (x1, y1) to (x2, y2)
function D:line(x1, y1, x2, y2, w, c)
	local s = self.s
	local dx, dy = x2 - x1, y2 - y1
	local l = math.sqrt(dx * dx + dy * dy)
	if l == 0 then return end
	local nx, ny = -dy / l * w / 2, dx / l * w / 2
	surface.SetDrawColor(c.r, c.g, c.b, c.a or 255)
	draw.NoTexture()
	local pts = { { x = (x1 + nx) * s, y = (y1 + ny) * s }, { x = (x2 + nx) * s, y = (y2 + ny) * s },
		{ x = (x2 - nx) * s, y = (y2 - ny) * s }, { x = (x1 - nx) * s, y = (y1 - ny) * s } }
	-- (either way round)
	local area = 0
	for i = 1, 4 do local a, b = pts[i], pts[i % 4 + 1] area = area + (a.x * b.y - b.x * a.y) end
	if area < 0 then pts = { pts[4], pts[3], pts[2], pts[1] } end
	surface.DrawPoly(pts)
end

-- Font Awesome's icons as nitro-react uses them (react-icons/fa), size = 1em (CSS px), the box's
-- top-left at x, y: plus, minus, bars, th, search, user, chevron-left/right, times, window-maximize
function D:fa(name, x, y, size, c)
	local u = size / 16
	if name == "plus" then
		self:round(1.5 * u, x + 6.3 * u, y + 1.1 * u, 3.4 * u, 13.8 * u, c)
		self:round(1.5 * u, x + 1.1 * u, y + 6.3 * u, 13.8 * u, 3.4 * u, c)
	elseif name == "minus" then
		self:round(1.5 * u, x + 1.1 * u, y + 6.3 * u, 13.8 * u, 3.4 * u, c)
	elseif name == "bars" then
		for i = 0, 2 do self:round(1 * u, x + 0.5 * u, y + (2.2 + i * 4.8) * u, 15 * u, 2.6 * u, c) end
	elseif name == "th" then
		for i = 0, 2 do for j = 0, 2 do self:round(0.8 * u, x + (0 + i * 5.7) * u, y + (1 + j * 5.0) * u, 4.6 * u, 4.0 * u, c) end end
	elseif name == "search" then
		self:ring(x + 6.5 * u, y + 6.5 * u, 6.2 * u, 2.5 * u, c)
		self:line(x + 10.5 * u, y + 10.5 * u, x + 15 * u, y + 15 * u, 3 * u, c)
	elseif name == "user" then
		self:circle(x + 7 * u, y + 4 * u, 4 * u, c)
		self:round(3 * u, x + 0, y + 9 * u, 14 * u, 7 * u, c)
	elseif name == "chevron-left" or name == "chevron-right" then
		local d = name == "chevron-left" and -1 or 1
		local cx, cy = x + 5 * u, y + 8 * u
		self:line(cx - d * 3 * u, cy - 5.5 * u, cx + d * 3 * u, cy, 3.2 * u, c)
		self:line(cx + d * 3 * u, cy, cx - d * 3 * u, cy + 5.5 * u, 3.2 * u, c)
	elseif name == "times" then
		self:line(x + 3 * u, y + 3 * u, x + 13 * u, y + 13 * u, 3.2 * u, c)
		self:line(x + 13 * u, y + 3 * u, x + 3 * u, y + 13 * u, 3.2 * u, c)
	elseif name == "window-maximize" then
		self:round(2 * u, x + 0.5 * u, y + 1.5 * u, 15 * u, 13 * u, c)
		self:rect(x + 2.5 * u, y + 5.5 * u, 11 * u, 7 * u, Color(255, 255, 255))
	end
end

-- a text cut to a width with "…" (text-overflow: ellipsis)
function D:fit(t, size, maxW, bold)
	t = tostring(t or "")
	if self:textWidth(t, size, bold) <= maxW then return t end
	local chars = {}
	for ch in t:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
	for n = #chars - 1, 0, -1 do
		local cut = table.concat(chars, "", 1, n)
		if self:textWidth(cut .. "…", size, bold) <= maxW then return cut .. "…" end
	end
	return "…"
end

-- --- form controls ----------------------------------------------------------------------------------
-- Bootstrap's form-control-sm / form-select-sm as nitro-react has them: white, a 1px #ced4da border,
-- 12.6px text 9 from the left. Inputs are real text boxes (GMod's DTextEntry) kept on the window.
U.C.inputBorder = Color(206, 212, 218)
U.C.placeholder = Color(108, 117, 125)
U.C.inputFocus = Color(143, 185, 202)

-- a text box: opts.placeholder, opts.value (first time), opts.max, opts.multiline, opts.onEnter(text),
-- opts.onChange(text). Returns the DTextEntry (its :GetValue() is what's typed).
function D:input(id, x, y, w, h, opts)
	opts = opts or {}
	local win = self.w
	win.inputs = win.inputs or {}
	local e = win.inputs[id]
	if not IsValid(e) then
		e = vgui.Create("DTextEntry", win.panel)
		e:SetPaintBackground(false)
		e:SetMultiline(opts.multiline or false)
		e.bobbaMultiline = opts.multiline or false
		e:SetUpdateOnType(true)
		e:SetText(opts.value or "")
		e.bobbaMax = opts.max
		e.AllowInput = function(self2)
			local t = self2:GetValue() or ""
			return self2.bobbaMax and (utf8.len(t) or #t) >= self2.bobbaMax or false
		end
		e.OnEnter = function(self2) if self2.bobbaEnter then self2.bobbaEnter(self2:GetValue()) end end
		e.OnValueChange = function(self2, v) if self2.bobbaChange then self2.bobbaChange(v) end end
		e.Paint = function(self2, pw, ph)
			local font = self2.bobbaFont
			if not font then return end
			self2:SetFont(font)
			self2:DrawTextEntryText(Color(0, 0, 0), Color(143, 185, 202), Color(0, 0, 0))
			if (self2:GetValue() or "") == "" and self2.bobbaPlaceholder then
				local multi = self2.bobbaMultiline
				draw.SimpleText(self2.bobbaPlaceholder, font, 2, multi and 1 or ph / 2, U.C.placeholder, TEXT_ALIGN_LEFT, multi and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
			end
		end
		win.inputs[id] = e
		win.panel:SetKeyboardInputEnabled(true)
	end
	e.bobbaEnter, e.bobbaChange, e.bobbaPlaceholder = opts.onEnter, opts.onChange, opts.placeholder
	e.bobbaFont = U.font(12.6)
	e.bobbaSeen = true
	local focus = e:HasFocus()
	-- the box (focus: Bootstrap's light blue border)
	self:box(x, y, w, h, 1, 3.2, focus and U.C.inputFocus or U.C.inputBorder, U.C.white)
	local s = self.s
	local X, Y = math.floor((x + 7) * s + 0.5), math.floor((y + (opts.multiline and 4 or 1)) * s + 0.5)
	e:SetPos(X, Y)
	e:SetSize(math.floor((x + w - 7) * s + 0.5) - X, math.floor((y + h - (opts.multiline and 4 or 1)) * s + 0.5) - Y)
	if not e:IsVisible() then e:SetVisible(true) end
	-- (a click on the box puts the caret in it)
	self:click(x, y, w, h, function() e:RequestFocus() end)
	return e
end

-- a drop-down (form-select-sm): options = { { value, label }, ... }; onChange(value)
function D:select(id, x, y, w, h, options, value, onChange)
	local win = self.w
	local label = ""
	for _, o in ipairs(options) do if o[1] == value then label = o[2] end end
	local open = win.openSelect == id
	self:click(x, y, w, h, function() win.openSelect = (win.openSelect ~= id) and id or nil end)
	win.clicks[#win.clicks].isSelect = true
	self:box(x, y, w, h, 1, 4, open and U.C.inputFocus or U.C.inputBorder, U.C.white)
	-- (the browser cuts the text where the arrow's room starts, no "…")
	self:clip(x + 1, y, w - 1 - 36, h, function()
		self:text(label, 12.6, x + 9, y + h / 2, U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end)
	-- Bootstrap's arrow: a chevron 16 x 12, 8 from the right (stroke 2 in a 16 x 16 box, squashed)
	local ax, ay = x + w - 8 - 16, y + h / 2 - 6
	local dark = Color(52, 58, 64)
	self:line(ax + 2, ay + 3.75, ax + 8, ay + 8.25, 1.6, dark)
	self:line(ax + 8, ay + 8.25, ax + 14, ay + 3.75, 1.6, dark)
	if open then
		-- the list under it, over everything else in the window
		win.overlays = win.overlays or {}
		win.overlays[#win.overlays + 1] = function(d)
			local rowH = 19
			local lw = w
			for _, o in ipairs(options) do lw = math.max(lw, d:textWidth(o[2], 12.6) + 18) end
			d:rect(x, y + h, lw, #options * rowH + 2, Color(118, 118, 118))
			d:rect(x + 1, y + h + 1, lw - 2, #options * rowH, U.C.white)
			for i, o in ipairs(options) do
				local ry = y + h + 1 + (i - 1) * rowH
				local hover = d:click(x + 1, ry, lw - 2, rowH, function() win.openSelect = nil if onChange then onChange(o[1]) end end)
				if hover or (o[1] == value and not hover and false) then d:rect(x + 1, ry, lw - 2, rowH, Color(30, 144, 255)) end
				d:text(o[2], 12.6, x + 6, ry + rowH / 2, hover and U.C.white or U.C.black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end
	end
end

-- Bootstrap's buttons (btn): a colour with nitro-react's insets; fn on click; returns hover
function D:btn(x, y, w, h, color, fn, disabled)
	local hover = (not disabled) and self:click(x, y, w, h, fn) or false
	local c = color
	if hover then c = Color(math.floor(c.r * 0.85), math.floor(c.g * 0.85), math.floor(c.b * 0.85)) end
	local a = disabled and 166 or 255
	self:round(4, x, y + 1, w, h, Color(0, 0, 0, math.floor(26 * a / 255)))
	self:round(4, x, y, w, h, Color(c.r, c.g, c.b, a))
	self:rect(x + 1, y + 1, w - 2, 2, Color(255, 255, 255, math.floor(38 * a / 255)))
	self:rect(x + 1, y + h - 3, w - 2, 2, Color(0, 0, 0, math.floor(26 * a / 255)))
	return hover
end

U.C.danger, U.C.warning, U.C.secondaryText = Color(168, 26, 18), Color(255, 193, 7), Color(24, 93, 121)

-- --- windows --------------------------------------------------------------------------------------
local Window = {}
Window.__index = Window

function Window:close()
	if IsValid(self.panel) then self.panel:Remove() end
	U.windows[self.id] = nil
	if self.onClose then self.onClose(self) end
end

-- opening a window that's open closes it (the toolbar's buttons); returns whether it's open now
function U.toggle(id, open)
	if U.windows[id] then U.windows[id]:close() return false end
	open()
	return true
end

function U.isOpen(id) return U.windows[id] ~= nil end

function U.window(id, width, height, draw)
	if U.windows[id] then U.windows[id]:close() end
	local w = setmetatable({ id = id, width = width, height = height, draw = draw, clicks = {}, scrolls = {} }, Window)
	U.windows[id] = w
	local s = U.scale()
	local p = vgui.Create("EditablePanel")
	w.panel = p
	p:SetSize(math.floor(width * s + 0.5), math.floor((height + 2) * s + 0.5))
	p:Center()
	p:MakePopup()
	p:SetKeyboardInputEnabled(false)
	p.bobbaWindow = true
	p.Paint = function(self, pw, ph)
		w.clicks = {}
		w.overlays = {}
		for _, e in pairs(w.inputs or {}) do if IsValid(e) then e.bobbaSeen = false end end
		local scale = U.scale()
		local mx, my = self:CursorPos()
		w.mx, w.my = mx / scale, my / scale
		local d = setmetatable({ w = w, s = scale, width = w.width, height = w.height }, D)
		local ok, err = pcall(w.draw, w, d)
		if not ok then ErrorNoHalt("[Bobba] window " .. id .. ": " .. tostring(err) .. "\n") end
		-- (what opens over the rest: a drop-down's list)
		for _, o in ipairs(w.overlays) do
			local ok2, err2 = pcall(o, d)
			if not ok2 then ErrorNoHalt("[Bobba] window " .. id .. ": " .. tostring(err2) .. "\n") end
		end
		-- text boxes not drawn this time are hidden
		for _, e in pairs(w.inputs or {}) do if IsValid(e) and not e.bobbaSeen and e:IsVisible() then e:SetVisible(false) end end
	end
	p.OnMousePressed = function(self, code)
		if code ~= MOUSE_LEFT then return end
		local scale = U.scale()
		local mx, my = self:CursorPos()
		mx, my = mx / scale, my / scale
		local wasOpen = w.openSelect
		for i = #w.clicks, 1, -1 do
			local c = w.clicks[i]
			if mx >= c.x and mx < c.x + c.w and my >= c.y and my < c.y + c.h then
				c.fn()
				-- (a click anywhere else closes an open drop-down)
				if wasOpen and w.openSelect == wasOpen and not c.isSelect then w.openSelect = nil end
				return
			end
		end
		w.openSelect = nil
		-- the header moves the window (.drag-handler)
		if my < 34 then
			w.drag = { mx = mx * scale, my = my * scale }
			self:MouseCapture(true)
		end
	end
	p.OnMouseReleased = function(self)
		if w.drag then w.drag = nil self:MouseCapture(false) end
	end
	p.Think = function(self)
		if w.drag then
			local x, y = input.GetCursorPos()
			self:SetPos(math.Clamp(x - w.drag.mx, 0, ScrW() - self:GetWide()), math.Clamp(y - w.drag.my, 0, ScrH() - self:GetTall()))
		end
	end
	p.OnMouseWheeled = function(self, delta)
		local scale = U.scale()
		local mx, my = self:CursorPos()
		mx, my = mx / scale, my / scale
		for _, sc in pairs(w.scrolls) do
			if sc.x and mx >= sc.x and mx < sc.x + sc.w and my >= sc.y and my < sc.y + sc.h then
				sc.offset = math.Clamp(sc.offset - delta * 40, 0, sc.max or 0)
				return true
			end
		end
	end
	return w
end

-- --- the parts of the screen that stay (the toolbar, the purse, the room tools) ----------------------
-- U.hud(id, place, draw): a panel that isn't a card and doesn't move; place() says where it is in CSS
-- pixels of the screen (x, y, w, h; screen width and height are passed), and it's moved when that
-- changes. It sits over the room and under the windows. U.hudRemove(id) takes it away.
U.huds = U.huds or {}
function U.hud(id, place, draw)
	if U.huds[id] and IsValid(U.huds[id].panel) then U.huds[id].panel:Remove() end
	local w = setmetatable({ id = id, place = place, draw = draw, clicks = {}, scrolls = {} }, Window)
	U.huds[id] = w
	local p = vgui.Create("EditablePanel")
	w.panel = p
	p:SetZPos(10)
	p:SetMouseInputEnabled(true)
	p:SetKeyboardInputEnabled(false)
	local function layout()
		local s = U.scale()
		local x, y, cw, ch = place(ScrW() / s, ScrH() / s)
		if not x then p:SetVisible(false) return end
		w.width, w.height = cw, ch
		local X, Y, W, H = math.floor(x * s + 0.5), math.floor(y * s + 0.5), math.floor((x + cw) * s + 0.5), math.floor((y + ch) * s + 0.5)
		if not p:IsVisible() then p:SetVisible(true) end
		local px0, py0 = p:GetPos()
		if px0 ~= X or py0 ~= Y then p:SetPos(X, Y) end
		if p:GetWide() ~= W - X or p:GetTall() ~= H - Y then p:SetSize(W - X, H - Y) end
	end
	layout()
	-- (from a Think hook, not the panel's own Think: GMod doesn't run a hidden panel's Think, and these
	-- are hidden until a room shows)
	w.layout = layout
	p.Paint = function(self)
		w.clicks = {}
		if not w.width then return end
		local scale = U.scale()
		local mx, my = self:CursorPos()
		w.mx, w.my = mx / scale, my / scale
		if not self:IsHovered() and not self:IsChildHovered() then w.mx, w.my = nil, nil end
		local d = setmetatable({ w = w, s = scale, width = w.width, height = w.height }, D)
		local ok, err = pcall(w.draw, w, d)
		if not ok then ErrorNoHalt("[Bobba] " .. id .. ": " .. tostring(err) .. "\n") end
	end
	p.OnMousePressed = function(self, code)
		if code ~= MOUSE_LEFT then return end
		local scale = U.scale()
		local mx, my = self:CursorPos()
		mx, my = mx / scale, my / scale
		for i = #w.clicks, 1, -1 do
			local c = w.clicks[i]
			if mx >= c.x and mx < c.x + c.w and my >= c.y and my < c.y + c.h then c.fn() return end
		end
	end
	return w
end

hook.Add("Think", "bobba.ui.huds", function()
	for _, w in pairs(U.huds) do
		if IsValid(w.panel) and w.layout then w.layout() end
	end
end)

function U.hudRemove(id)
	local w = U.huds[id]
	if w and IsValid(w.panel) then w.panel:Remove() end
	U.huds[id] = nil
end

