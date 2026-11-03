-- The hotel's windows (client), drawn the way nitro-react draws its cards (src/common: NitroCardView,
-- NitroCardHeaderView, NitroCardTabsView, LayoutGridItem, Button; colours and sizes from its
-- compiled SCSS). Sizes are CSS pixels; everything is drawn U.scale() times as big, the size the
-- room opens at for this screen (V.uiScale), like the chat.
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

function U.scale() return (V and V.uiScale) and V.uiScale() or 1 end

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
			widths[i] = math.ceil(self:textWidth(t.label, 14.4) + 12.8 * 2 + 2)
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
			self:text(t.label, 14.4, x + w / 2, 38 + 29 / 2 + 1, U.C.black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			x = x + w + 4
		end
	end
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

-- --- windows --------------------------------------------------------------------------------------
local Window = {}
Window.__index = Window

function Window:close()
	if IsValid(self.panel) then self.panel:Remove() end
	U.windows[self.id] = nil
	if self.onClose then self.onClose(self) end
end

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
	p.Paint = function(self, pw, ph)
		w.clicks = {}
		local scale = U.scale()
		local mx, my = self:CursorPos()
		w.mx, w.my = mx / scale, my / scale
		local d = setmetatable({ w = w, s = scale, width = width, height = height }, D)
		local ok, err = pcall(w.draw, w, d)
		if not ok then ErrorNoHalt("[Bobba] window " .. id .. ": " .. tostring(err) .. "\n") end
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
