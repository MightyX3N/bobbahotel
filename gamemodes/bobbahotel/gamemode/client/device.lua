-- The phone and the tablet (client): the hotel's own look (BOBBA.ui.style() == "phone"), a device that
-- works like a real one. The phone sits at the bottom right and is put away and taken out (a key, the
-- phone button); the tablet opens over the room for the big apps.
--
-- Apps (this file has the shell; client/deviceapps.lua the hotel's own apps; addons add theirs):
--   BOBBA.device.app({
--     id = "videos", name = "Videos", color = Color(...), glyph = "M3 6h18v12H3z...",  -- a 24 x 24 SVG path
--     phone = function(ctx) ... end,      -- the phone's view (either or both)
--     tablet = function(ctx) ... end,     -- the tablet's view
--     badge = function() return 3 end,    -- a red number on its icon
--     removable = true,                   -- can be taken off the home screen (default true)
--     store = true,                       -- an addon's app: in the App Store, on the home screen once got
--     open = function() ... end,          -- instead of a view: something to do (opens a window)
--   })
--   A view draws with ctx.d (in the screen's points: 390 x 844 on the phone, 1180 x 820 on the
--   tablet; ctx.w, ctx.h) and moves with ctx:push(view, state) / ctx:pop(); ctx.state is its own.
--   An app with only a phone view opens on the tablet as a phone in the middle (iPad's way); one with
--   only a tablet view opened from the phone brings the tablet.
--   BOBBA.device.widget({ id, name, size = "small" / "wide", draw = function(d, w, h) end, click = fn })
--   BOBBA.device.notify({ app = id, title = "...", text = "...", color = Color, actions = { { "OK", fn } } })
--   BOBBA.device.tile({ id, name, glyph, state = fn -> text, on = fn -> bool, click = fn })   -- the shade
-- The home screen's layout (pages, dock, widgets) is kept on the player's PC per hotel.

BOBBA.device = BOBBA.device or {}
local DV = BOBBA.device
local U = BOBBA.ui
local HUD = BOBBA.hud
local V = BOBBA.view
local P = BOBBA.platform

DV.apps = DV.apps or {}
DV.appOrder = DV.appOrder or {}
DV.widgets = DV.widgets or {}
DV.widgetOrder = DV.widgetOrder or {}
DV.tiles = DV.tiles or {}
DV.notes = DV.notes or {}

-- --- colours (the design's) -------------------------------------------------------------------------
local function hex(s)
	s = s:gsub("#", "")
	return Color(tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16), #s >= 8 and tonumber(s:sub(7, 8), 16) or 255)
end
DV.hex = hex
DV.C = {
	navy = hex("0F1A2E"), navy2 = hex("1B2D4F"), navy3 = hex("2A3F68"), paper = hex("F4F6FB"), mist = hex("C9D2E5"),
	slate = hex("8A97B2"), ink2 = hex("4A5875"), line = hex("E3E8F3"), black = hex("05080F"), shade = hex("070C17"),
	orange = hex("FF9F5A"), red = hex("F2475A"), green = hex("3FC6A0"), blue = hex("6E8BFF"), yellow = hex("FFD166"),
	pink = hex("F26B8A"), purple = hex("B98CFF"), gold = hex("E8C26A"), sky = hex("9DB4FF"), peach = hex("FFB37A"),
	white = Color(255, 255, 255),
}
local C = DV.C
local function alpha(c, a) return Color(c.r, c.g, c.b, math.floor((c.a or 255) * a + 0.5)) end
DV.alpha = alpha

-- the screens' sizes in points, and their frames
DV.SIZES = {
	phone = { w = 390, h = 844, bezel = 12, radius = 52, cols = 4, rows = 6, icon = 62, dock = 4 },
	tablet = { w = 1180, h = 820, bezel = 18, radius = 40, cols = 8, rows = 4, icon = 72, dock = 8 },
}

-- --- the phone's font: Plus Jakarta Sans (resource/fonts; its weights are families of their own) ------
-- GMod's font size is the letters' whole height as Windows measures it: 1.652 of CSS's size
DV.FONT_CELL = 1.652
local fontNames = {}
function DV.font(px, weight, s)
	weight = (weight == true) and 700 or (weight or 500)
	local family, w
	if weight >= 800 then family, w = "Plus Jakarta Sans ExtraBold", 800
	elseif weight >= 600 then family, w = "Plus Jakarta Sans", 700
	else family, w = "Plus Jakarta Sans Medium", 500 end
	local size = math.max(6, math.floor(px * DV.FONT_CELL * (s or 1) + 0.5))
	local name = "BobbaPJ" .. size .. "_" .. w
	if not fontNames[name] then
		surface.CreateFont(name, { font = family, size = size, weight = w, antialias = true, extended = true })
		fontNames[name] = true
	end
	return name
end

-- --- 24 x 24 SVG paths (the design's icons): M L H V C Q A Z, absolute and relative -------------------
local pathCache = {}
local function arcPoints(x1, y1, rx, ry, phi, large, sweep, x2, y2, out)
	if rx == 0 or ry == 0 then out[#out + 1] = { x2, y2 } return end
	rx, ry = math.abs(rx), math.abs(ry)
	local cp, sp = math.cos(math.rad(phi)), math.sin(math.rad(phi))
	local dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
	local x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
	local lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
	if lam > 1 then local k = math.sqrt(lam) rx, ry = rx * k, ry * k end
	local num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
	local den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
	local co = (den == 0) and 0 or math.sqrt(math.max(0, num / den))
	if large == sweep then co = -co end
	local cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
	local cx, cy = cp * cxp - sp * cyp + (x1 + x2) / 2, sp * cxp + cp * cyp + (y1 + y2) / 2
	local function ang(ux, uy, vx, vy)
		local a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
		return a
	end
	local t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
	local dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
	if sweep == 0 and dt > 0 then dt = dt - 2 * math.pi elseif sweep == 1 and dt < 0 then dt = dt + 2 * math.pi end
	local n = math.max(4, math.ceil(math.abs(dt) / (math.pi / 10)))
	for i = 1, n do
		local t = t1 + dt * i / n
		local ex, ey = rx * math.cos(t), ry * math.sin(t)
		out[#out + 1] = { cp * ex - sp * ey + cx, sp * ex + cp * ey + cy }
	end
end

-- the path as lines: { { {x, y}, ... , closed = bool }, ... }
function DV.parsePath(str)
	if pathCache[str] then return pathCache[str] end
	local toks = {}
	local pos = 1
	while pos <= #str do
		local ch = str:sub(pos, pos)
		if ch:match("[MmLlHhVvCcQqAaZz]") then
			toks[#toks + 1] = ch
			pos = pos + 1
		else
			local a, b = str:find("^%-?%d*%.?%d+", pos)
			if a then toks[#toks + 1] = str:sub(a, b) pos = b + 1 else pos = pos + 1 end
		end
	end
	local subs, cur = {}, nil
	local x, y, sx, sy = 0, 0, 0, 0
	local i, cmd = 1, nil
	local function num() local v = tonumber(toks[i]) i = i + 1 return v or 0 end
	while i <= #toks do
		local t = toks[i]
		if t:match("^[A-Za-z]$") then cmd = t i = i + 1 end
		local rel = cmd and cmd == cmd:lower()
		local c = cmd and cmd:upper()
		if c == "Z" then
			if cur then cur.closed = true end
			x, y = sx, sy
			cur = nil
		elseif c == "M" then
			local nx, ny = num(), num()
			if rel then nx, ny = x + nx, y + ny end
			x, y, sx, sy = nx, ny, nx, ny
			cur = { { x, y } }
			subs[#subs + 1] = cur
			-- (more pairs after M are lines)
			cmd = rel and "l" or "L"
		elseif c == "L" or c == "H" or c == "V" or c == "C" or c == "Q" or c == "A" then
			if not cur then cur = { { x, y } } subs[#subs + 1] = cur end
			if c == "L" then
				local nx, ny = num(), num()
				if rel then nx, ny = x + nx, y + ny end
				x, y = nx, ny
				cur[#cur + 1] = { x, y }
			elseif c == "H" then
				local nx = num() if rel then nx = x + nx end
				x = nx cur[#cur + 1] = { x, y }
			elseif c == "V" then
				local ny = num() if rel then ny = y + ny end
				y = ny cur[#cur + 1] = { x, y }
			elseif c == "C" then
				local a, b, cc, dd, e, f = num(), num(), num(), num(), num(), num()
				if rel then a, b, cc, dd, e, f = x + a, y + b, x + cc, y + dd, x + e, y + f end
				for k = 1, 8 do
					local t = k / 8
					local u = 1 - t
					cur[#cur + 1] = { u * u * u * x + 3 * u * u * t * a + 3 * u * t * t * cc + t * t * t * e,
						u * u * u * y + 3 * u * u * t * b + 3 * u * t * t * dd + t * t * t * f }
				end
				x, y = e, f
			elseif c == "Q" then
				local a, b, e, f = num(), num(), num(), num()
				if rel then a, b, e, f = x + a, y + b, x + e, y + f end
				for k = 1, 6 do
					local t = k / 6
					local u = 1 - t
					cur[#cur + 1] = { u * u * x + 2 * u * t * a + t * t * e, u * u * y + 2 * u * t * b + t * t * f }
				end
				x, y = e, f
			else
				local rx, ry, phi, large, sweep, nx, ny = num(), num(), num(), num(), num(), num(), num()
				if rel then nx, ny = x + nx, y + ny end
				arcPoints(x, y, rx, ry, phi, large, sweep, nx, ny, cur)
				x, y = nx, ny
			end
		else
			i = i + 1
		end
	end
	pathCache[str] = subs
	return subs
end

-- --- drawing: in points, from an origin that can move (sliding pages, sheets), with a fade -----------
local PD = {}
PD.__index = PD
DV.PD = PD

local function newDraw(surf, s)
	return setmetatable({ surf = surf, s = s, ox = 0, oy = 0, a = 1 }, PD)
end

function PD:X(v) return math.floor((v + self.ox) * self.s + 0.5) end
function PD:Y(v) return math.floor((v + self.oy) * self.s + 0.5) end
function PD:col(c) return Color(c.r, c.g, c.b, math.floor((c.a or 255) * self.a + 0.5)) end

-- moved by dx, dy while fn runs; faded to a (times the fade there is)
function PD:translate(dx, dy, fn)
	self.ox, self.oy = self.ox + dx, self.oy + dy
	local ok, err = pcall(fn)
	self.ox, self.oy = self.ox - dx, self.oy - dy
	if not ok then ErrorNoHalt("[Bobba] device: " .. tostring(err) .. "\n") end
end
function PD:fade(a, fn)
	local old = self.a
	self.a = old * math.Clamp(a, 0, 1)
	if self.a > 0.003 then
		local ok, err = pcall(fn)
		if not ok then ErrorNoHalt("[Bobba] device: " .. tostring(err) .. "\n") end
	end
	self.a = old
end

function PD:rect(x, y, w, h, c)
	local X, Y = self:X(x), self:Y(y)
	local c2 = self:col(c)
	surface.SetDrawColor(c2.r, c2.g, c2.b, c2.a)
	surface.DrawRect(X, Y, self:X(x + w) - X, self:Y(y + h) - Y)
end

-- a rounded box (r is clamped to half the smaller side: a pill)
function PD:round(r, x, y, w, h, c, tl, tr, bl, br)
	if w <= 0 or h <= 0 then return end
	local X, Y = self:X(x), self:Y(y)
	local W, H = self:X(x + w) - X, self:Y(y + h) - Y
	local R = math.min(math.floor(r * self.s), math.floor(math.min(W, H) / 2))
	R = math.max(0, R)
	if tl == nil then draw.RoundedBox(R, X, Y, W, H, self:col(c))
	else draw.RoundedBoxEx(R, X, Y, W, H, self:col(c), tl, tr, bl, br) end
end
function PD:pill(x, y, w, h, c) self:round(math.min(w, h) / 2, x, y, w, h, c) end
-- a rounded box with a border bw thick
function PD:outline(r, x, y, w, h, bw, c, fill)
	self:round(r, x, y, w, h, c)
	self:round(math.max(0, r - bw), x + bw, y + bw, w - 2 * bw, h - 2 * bw, fill or C.paper)
end

-- (the bold weights' spaces are narrow at small sizes: a hair space more, as the design has them)
local function spaced(t, weight)
	t = tostring(t or "")
	if (weight == true or (weight or 500) >= 600) and t:find(" ", 1, true) then t = t:gsub(" ", " \226\128\138") end
	return t
end
function PD:text(t, size, x, y, c, ax, ay, weight)
	draw.SimpleText(spaced(t, weight), DV.font(size, weight, self.s), self:X(x), self:Y(y), self:col(c), ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP)
end
function PD:textWidth(t, size, weight)
	surface.SetFont(DV.font(size, weight, self.s))
	local w = surface.GetTextSize(spaced(t, weight))
	return w / self.s
end
PD.fit = U.D.fit
PD.wrap = U.D.wrap

function PD:circle(cx, cy, r, c)
	local s = self.s
	local pts, n = {}, math.max(12, math.floor(r * s * 1.2))
	local X, Y = (cx + self.ox) * s, (cy + self.oy) * s
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		pts[#pts + 1] = { x = X + math.cos(a) * r * s, y = Y + math.sin(a) * r * s }
	end
	local c2 = self:col(c)
	surface.SetDrawColor(c2.r, c2.g, c2.b, c2.a)
	draw.NoTexture()
	surface.DrawPoly(pts)
end

function PD:ring(cx, cy, r, w, c)
	local s = self.s
	local n = math.max(16, math.floor(r * s * 1.2))
	local X, Y = (cx + self.ox) * s, (cy + self.oy) * s
	local c2 = self:col(c)
	surface.SetDrawColor(c2.r, c2.g, c2.b, c2.a)
	draw.NoTexture()
	for i = 0, n - 1 do
		local a0, a1 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2
		surface.DrawPoly({
			{ x = X + math.cos(a0) * r * s, y = Y + math.sin(a0) * r * s }, { x = X + math.cos(a1) * r * s, y = Y + math.sin(a1) * r * s },
			{ x = X + math.cos(a1) * (r - w) * s, y = Y + math.sin(a1) * (r - w) * s }, { x = X + math.cos(a0) * (r - w) * s, y = Y + math.sin(a0) * (r - w) * s },
		})
	end
end

local function poly(pts)
	-- (GMod wants them clockwise on the screen)
	local area = 0
	for i = 1, #pts do local a, b = pts[i], pts[i % #pts + 1] area = area + (a.x * b.y - b.x * a.y) end
	if area < 0 then
		local r = {}
		for i = #pts, 1, -1 do r[#r + 1] = pts[i] end
		pts = r
	end
	surface.DrawPoly(pts)
end

function PD:line(x1, y1, x2, y2, w, c)
	local s = self.s
	local dx, dy = x2 - x1, y2 - y1
	local l = math.sqrt(dx * dx + dy * dy)
	if l == 0 then return end
	local nx, ny = -dy / l * w / 2, dx / l * w / 2
	local ox, oy = self.ox, self.oy
	local c2 = self:col(c)
	surface.SetDrawColor(c2.r, c2.g, c2.b, c2.a)
	draw.NoTexture()
	poly({ { x = (x1 + nx + ox) * s, y = (y1 + ny + oy) * s }, { x = (x2 + nx + ox) * s, y = (y2 + ny + oy) * s },
		{ x = (x2 - nx + ox) * s, y = (y2 - ny + oy) * s }, { x = (x1 - nx + ox) * s, y = (y1 - ny + oy) * s } })
end

-- a 24 x 24 path drawn size big at x, y: its lines stroke thick (round ends), or filled (convex shapes)
function PD:glyph(path, x, y, size, c, stroke, fill)
	if not path or path == "" then return end
	local k = size / 24
	local w = (stroke or 2) * k
	for _, sub in ipairs(DV.parsePath(path)) do
		if fill then
			local pts = {}
			for _, p in ipairs(sub) do pts[#pts + 1] = { x = (x + p[1] * k + self.ox) * self.s, y = (y + p[2] * k + self.oy) * self.s } end
			if #pts >= 3 then
				local c2 = self:col(c)
				surface.SetDrawColor(c2.r, c2.g, c2.b, c2.a)
				draw.NoTexture()
				poly(pts)
			end
		else
			local n = #sub
			for i = 1, n - 1 do
				local ax, ay, bx, by = x + sub[i][1] * k, y + sub[i][2] * k, x + sub[i + 1][1] * k, y + sub[i + 1][2] * k
				-- (a dot: "h.01")
				if math.abs(bx - ax) + math.abs(by - ay) < 0.2 then self:circle(ax, ay, math.max(w / 2, 1 / self.s), c)
				else self:line(ax, ay, bx, by, w, c) end
			end
			if sub.closed and n > 2 then self:line(x + sub[n][1] * k, y + sub[n][2] * k, x + sub[1][1] * k, y + sub[1][2] * k, w, c) end
			-- (round joins and ends)
			if w * self.s >= 2 then
				for i = 1, n do self:circle(x + sub[i][1] * k, y + sub[i][2] * k, w / 2, c) end
			end
		end
	end
end

-- an avatar (the room's figure drawer), its head at x, y
function PD:avatar(figure, gender, dir, x, y, k, effect)
	local AE = BOBBA.avatarEditor
	if not (AE and AE.drawPreview) or not figure then return false end
	AE.drawPreview(figure, gender or "M", dir or 2, (x + self.ox) * self.s, (y + self.oy) * self.s, (k or 1) * self.s, effect)
	return true
end

-- a picture (a material) stretched into x, y, w, h
function PD:material(mat, x, y, w, h, c)
	if not mat then return false end
	local X, Y = self:X(x), self:Y(y)
	surface.SetMaterial(mat)
	local c2 = self:col(c or C.white)
	surface.SetDrawColor(c2.r, c2.g, c2.b, c2.a)
	surface.DrawTexturedRect(X, Y, self:X(x + w) - X, self:Y(y + h) - Y)
	return true
end

-- one of the pack's UI pictures (BOBBA.ui.icon, e.g. Habbo's), its middle in x, y, w, h; k: its size
function PD:uiIcon(name, x, y, w, h, k)
	local ic = U.icon(name)
	if not ic or not ic.material then return false end
	k = k or 1
	local iw, ih = ic.width * k, ic.height * k
	local X, Y = self:X(x + (w - iw) / 2), self:Y(y + (h - ih) / 2)
	render.PushFilterMag(TEXFILTER.POINT)
	render.PushFilterMin(k < 1 and TEXFILTER.LINEAR or TEXFILTER.POINT)
	surface.SetMaterial(ic.material)
	local c2 = self:col(C.white)
	surface.SetDrawColor(c2.r, c2.g, c2.b, c2.a)
	surface.DrawTexturedRectUV(X, Y, math.floor(iw * self.s + 0.5), math.floor(ih * self.s + 0.5), 0, 0, ic.u, ic.v)
	render.PopFilterMin()
	render.PopFilterMag()
	return true
end

-- a furni's icon (or, preview = true, its picture as in a room) in x, y, w, h; data: a paint's number
function PD:furni(kind, x, y, w, h, data, preview, dir)
	local R = BOBBA.room
	local info = R.furniInfo and R.furniInfo(kind)
	local s = self.s
	local X, Y, W, H = self:X(x), self:Y(y), self:X(x + w) - self:X(x), self:Y(y + h) - self:Y(y)
	if data and info and info.paint and R.paintSwatch then
		if preview then R.paintSwatch(info.paint, data, X, Y, W, H, 2 * s)
		else
			local q = math.min(W, H) - math.floor(8 * s)
			R.paintSwatch(info.paint, data, X + math.floor((W - q) / 2), Y + math.floor((H - q) / 2), q, q, s)
		end
		return
	end
	if preview then
		if R.furniPreview then R.furniPreview(kind, X, Y, W, H, s, dir or 2) end
	elseif R.furniIcon then
		-- (Habbo's icons are small: bigger in a bigger box, never more than fits)
		local k = math.Clamp((math.min(w, h) - 12) / 44, 1, 2.5)
		R.furniIcon(kind, X, Y, W, H, s * k, 255, true)
	end
end

-- a row of choices (pills) that slides sideways when they don't fit; returns its height
function PD:chips(id, x, y, w, list, active, onPick, opts)
	opts = opts or {}
	local h = opts.h or 32
	local size = opts.size or 13
	local total = 0
	local widths = {}
	for i, it in ipairs(list) do widths[i] = self:textWidth(it.label, size, 700) + 28 total = total + widths[i] + 8 end
	total = total - 8
	local off = 0
	if total > w then
		local surf = self.surf
		local sc = surf.scrolls[id] or { offset = 0, v = 0 }
		surf.scrolls[id] = sc
		sc.max = total - w
		sc.offset = math.Clamp(sc.offset, 0, sc.max)
		self:dragZone(x, y, w, h, { vertical = false, start = function() sc.from = sc.offset return true end,
			move = function(_, _, dx) sc.offset = math.Clamp(sc.from - dx, 0, sc.max) end,
			wheel = function(delta) sc.offset = math.Clamp(sc.offset - delta * 60, 0, sc.max) return true end })
		off = sc.offset
	end
	local fg, bgOn, bgOff = opts.fg or C.navy, opts.on or C.navy, opts.off or C.line
	self:clip(x, y, w, h, function()
		local cx = x - off
		for i, it in ipairs(list) do
			local on = it.id == active
			local hov = self:click(math.max(cx, x), y, math.min(cx + widths[i], x + w) - math.max(cx, x), h, function() onPick(it.id) end)
			self:pill(cx, y, widths[i], h, on and bgOn or (hov and alpha(bgOff, 0.8) or bgOff))
			self:text(it.label, size, cx + widths[i] / 2, y + h / 2, on and (opts.onFg or C.paper) or fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
			cx = cx + widths[i] + 8
		end
	end)
	return h
end

-- a button: style "primary" (navy), "light", "outline", "danger", "gold"
function PD:button(x, y, w, h, label, style, fn, disabled)
	local hov = (not disabled) and fn and self:click(x, y, w, h, fn) or false
	local bg, fg = C.navy, C.paper
	if style == "light" then bg, fg = C.line, C.navy
	elseif style == "outline" then bg, fg = nil, C.navy
	elseif style == "outlineLight" then bg, fg = nil, C.paper
	elseif style == "danger" then bg, fg = C.red, C.white
	elseif style == "green" then bg, fg = C.green, C.navy
	elseif style == "gold" then bg, fg = C.gold, hex("14110B")
	elseif style == "paper" then bg, fg = C.paper, C.navy end
	if bg then
		if hov then bg = Color(math.min(255, bg.r + 20), math.min(255, bg.g + 20), math.min(255, bg.b + 20), bg.a) end
		self:pill(x, y, w, h, disabled and alpha(bg, 0.45) or bg)
	else
		self:round(h / 2, x, y, w, h, fg)
		self:round(h / 2 - 2, x + 2, y + 2, w - 4, h - 4, hov and alpha(fg, 0.12) or (self.bgUnder or C.paper))
	end
	self:text(self:fit(label, math.min(16, h * 0.36), w - 16, 800), math.min(16, h * 0.36), x + w / 2, y + h / 2, disabled and alpha(fg, 0.6) or fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
	return hov
end

-- someone's face in a rounded square (their avatar's head; the first letter of the name without one)
local FACE_COLORS = { C.blue, C.pink, C.green, C.yellow, C.purple, C.peach, C.sky }
function DV.face(d, figure, gender, name, x, y, size, bg)
	local n = 0
	for i = 1, #(name or "") do n = n + (name or ""):byte(i) end
	d:round(size * 0.32, x, y, size, size, bg or FACE_COLORS[n % #FACE_COLORS + 1])
	if figure and figure ~= "" then
		local k = size / 34
		d:clip(x, y, size, size, function() d:avatar(figure, gender, 2, x + size / 2, y - 14 * k, k) end)
	else
		d:text((name or "?"):sub(1, 1):upper(), size * 0.42, x + size / 2, y + size / 2, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
	end
end

-- a round button that turns something (a furni, an avatar)
function DV.turnButton(d, x, y, fn, left)
	local hov = d:click(x, y, 44, 44, fn)
	d:circle(x + 22, y + 22, 22, hov and C.white or C.paper)
	d:glyph(left and "M4 12a8 8 0 1 0 3-6.2M4 4v5h5" or "M20 12a8 8 0 1 1-3-6.2M20 4v5h-5", x + 10, y + 10, 24, C.navy, 2.4)
end

-- a price: "25 credits", "250 diamonds + 5 credits"
function DV.priceText(price, n)
	n = n or 1
	local parts = {}
	for _, c in ipairs({ "credits", "duckets", "diamonds" }) do
		local v = price and price[c]
		if v and v > 0 then parts[#parts + 1] = DV.money(v * n) .. " " .. U.text("bobba.phone.currency." .. c, c) end
	end
	if #parts == 0 then return U.text("bobba.phone.free", "Free") end
	return table.concat(parts, " + ")
end

-- a question over the screen: { title, text, ok = "Buy", cancel = "Cancel", fn = function() end, danger }
function DV.ask(q)
	q.at = SysTime()
	DV.question = q
end
local function drawQuestion(d, W, H)
	local q = DV.question
	if not q then return end
	local t = math.Clamp((SysTime() - q.at) / 0.18, 0, 1)
	d:rect(0, 0, W, H, Color(0, 0, 0, math.floor(120 * t)))
	d:click(0, 0, W, H, function() DV.question = nil end)
	local bw = math.min(W - 60, 320)
	local lines = d:wrap(q.text or "", 14, bw - 40)
	local bh = 24 + 26 + #lines * 19 + 20 + 44 + 20 + (q.alt and 54 or 0)
	local x, y = (W - bw) / 2, (H - bh) / 2 + (1 - t) * 30
	d:fade(t, function()
		d:round(26, x, y, bw, bh, C.paper)
		d:click(x, y, bw, bh, function() end)
		d:text(q.title or "", 17, W / 2, y + 24, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 800)
		for i, l in ipairs(lines) do d:text(l, 14, W / 2, y + 54 + (i - 1) * 19, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP) end
		local by = y + bh - 20 - 44 - (q.alt and 54 or 0)
		local half = (bw - 40 - 10) / 2
		if q.alt then
			d:button(x + 20, by + 54, bw - 40, 44, q.alt[1], "danger", function() DV.question = nil q.alt[2]() end)
		end
		d:button(x + 20, by, half, 44, q.cancel or U.text("generic.cancel", "Cancel"), "light", function() DV.question = nil end)
		d:button(x + 20 + half + 10, by, half, 44, q.ok or U.text("generic.ok", "OK"), q.danger and "danger" or "primary", function()
			DV.question = nil
			if q.fn then q.fn() end
		end)
	end)
end
DV.drawQuestion = drawQuestion

-- only draw inside x, y, w, h while fn runs (inside the clip there is)
local clips = {}
function PD:clip(x, y, w, h, fn)
	local px0, py0 = self.surf.panel:LocalToScreen(0, 0)
	local r = { px0 + self:X(x), py0 + self:Y(y), px0 + self:X(x + w), py0 + self:Y(y + h) }
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
	if not ok then ErrorNoHalt("[Bobba] device: " .. tostring(err) .. "\n") end
end

-- something to touch: fn when let go on it (not after a drag); opts.hold(press) after holding it
-- (may return a drag to go on with), opts.drag (a drag: { move = fn(mx, my, dx, dy), stop = fn() }).
-- Returns whether the pointer is over it.
function PD:click(x, y, w, h, fn, opts)
	local surf = self.surf
	local cx = self.clipRect
	local r = { x = x + self.ox, y = y + self.oy, w = w, h = h, fn = fn, opts = opts }
	surf.clicks[#surf.clicks + 1] = r
	local mx, my = surf.mx, surf.my
	if not mx or (surf.press and surf.press.moved) then return false end
	return mx >= r.x and mx < r.x + w and my >= r.y and my < r.y + h
end

-- a text box (a real one: GMod's DTextEntry on the screen): opts.placeholder, value (the first
-- time), max, onEnter(text), onChange(text), bg, fg, size, multiline. Returns the entry.
function PD:input(id, x, y, w, h, opts)
	opts = opts or {}
	local surf = self.surf
	surf.inputs = surf.inputs or {}
	local e = surf.inputs[id]
	if not IsValid(e) then
		e = vgui.Create("DTextEntry", surf.panel)
		e:SetPaintBackground(false)
		e:SetMultiline(opts.multiline or false)
		e:SetUpdateOnType(true)
		e:SetText(opts.value or "")
		e.AllowInput = function(self2)
			local t = self2:GetValue() or ""
			return self2.bobbaMax and (utf8.len(t) or #t) >= self2.bobbaMax or false
		end
		e.OnEnter = function(self2) if self2.bobbaEnter then self2.bobbaEnter(self2:GetValue()) end end
		e.OnValueChange = function(self2, v) if self2.bobbaChange then self2.bobbaChange(v) end end
		e.OnGetFocus = function() DV.keysAt = SysTime() end
		e.Paint = function(self2, pw, ph)
			if not self2.bobbaFont then return end
			self2:SetFont(self2.bobbaFont)
			local fg = self2.bobbaFg or C.navy
			self2:DrawTextEntryText(fg, Color(110, 139, 255), fg)
			if (self2:GetValue() or "") == "" and self2.bobbaPlaceholder then
				draw.SimpleText(self2.bobbaPlaceholder, self2.bobbaFont, 3, self2.bobbaMultiline and 2 or ph / 2, alpha(fg, 0.5), TEXT_ALIGN_LEFT, self2.bobbaMultiline and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
			end
		end
		e.bobbaMultiline = opts.multiline or false
		surf.inputs[id] = e
	end
	e.bobbaMax = opts.max
	e.bobbaEnter, e.bobbaChange, e.bobbaPlaceholder = opts.onEnter, opts.onChange, opts.placeholder
	e.bobbaFg = opts.fg
	e.bobbaFont = DV.font(opts.size or 15, 500, self.s)
	e.bobbaSeen = true
	if not opts.bare then self:round(opts.radius or math.min(h / 2, 22), x, y, w, h, opts.bg or C.line) end
	local padX = opts.padX or 16
	local X, Y = self:X(x + padX), self:Y(y + (opts.multiline and 8 or 2))
	e:SetPos(X, Y)
	e:SetSize(self:X(x + w - padX) - X, self:Y(y + h - (opts.multiline and 8 or 2)) - Y)
	if not e:IsVisible() then e:SetVisible(true) end
	self:click(x, y, w, h, function() DV.keysAt = SysTime() e:RequestFocus() end)
	return e
end

-- a part that's dragged (a page swipe, a pull): handler { start = fn(mx, my) -> bool, move, stop },
-- and the wheel (handler.wheel(delta))
function PD:dragZone(x, y, w, h, handler)
	local surf = self.surf
	surf.zones[#surf.zones + 1] = { x = x + self.ox, y = y + self.oy, w = w, h = h, handler = handler }
end

-- a part that scrolls up and down (dragged, or the wheel): the offset to draw its content at
function PD:scroll(id, x, y, w, h, contentH)
	local surf = self.surf
	local sc = surf.scrolls[id] or { offset = 0, v = 0 }
	surf.scrolls[id] = sc
	sc.max = math.max(0, contentH - h)
	if not sc.dragging then
		-- (thrown: it slides on and slows down)
		if math.abs(sc.v) > 1 then
			sc.offset = sc.offset + sc.v * FrameTime()
			sc.v = sc.v * math.exp(-FrameTime() * 4)
		else sc.v = 0 end
		sc.offset = math.Clamp(sc.offset, 0, sc.max)
	end
	self:dragZone(x, y, w, h, {
		vertical = true,
		start = function() sc.dragging = true sc.v = 0 sc.from = sc.offset return true end,
		move = function(_, _, dx, dy, vy) sc.offset = math.Clamp(sc.from - dy, 0, sc.max) sc.v = -(vy or 0) end,
		stop = function() sc.dragging = false end,
		wheel = function(delta) sc.offset = math.Clamp(sc.offset - delta * 60, 0, sc.max) sc.v = 0 return true end,
	})
	return sc.offset
end

-- --- a surface: a panel the device draws into (the screen; the phone inside the tablet) -------------
local function hitClick(surf, mx, my)
	for i = #surf.clicks, 1, -1 do
		local c = surf.clicks[i]
		if mx >= c.x and mx < c.x + c.w and my >= c.y and my < c.y + c.h then return c end
	end
end
local function hitZone(surf, mx, my, wantVertical)
	for i = #surf.zones, 1, -1 do
		local z = surf.zones[i]
		if mx >= z.x and mx < z.x + z.w and my >= z.y and my < z.y + z.h and (wantVertical == nil or (z.handler.vertical or false) == wantVertical or z.handler.both) then return z end
	end
end

local function makeSurface(parent, draw)
	local surf = { clicks = {}, zones = {}, scrolls = {}, draw = draw }
	local p = vgui.Create("EditablePanel", parent)
	surf.panel = p
	p:SetMouseInputEnabled(true)
	p.Paint = function(self, pw, ph)
		surf.clicks, surf.zones = {}, {}
		local s = surf.s or 1
		local mx, my = self:CursorPos()
		local inside = self:IsHovered() or self:IsChildHovered() or surf.press ~= nil
		surf.mx, surf.my = inside and mx / s or nil, inside and my / s or nil
		for _, e in pairs(surf.inputs or {}) do if IsValid(e) then e.bobbaSeen = false end end
		local d = newDraw(surf, s)
		local ok, err = pcall(surf.draw, d, pw / s, ph / s)
		if not ok then ErrorNoHalt("[Bobba] device: " .. tostring(err) .. "\n") end
		-- (text boxes not drawn this time are hidden)
		for _, e in pairs(surf.inputs or {}) do
			if IsValid(e) and not e.bobbaSeen and e:IsVisible() then e:SetVisible(false) if e:HasFocus() then e:KillFocus() end end
		end
	end
	p.OnMousePressed = function(self, code)
		if code ~= MOUSE_LEFT then return end
		local s = surf.s or 1
		local mx, my = self:CursorPos()
		mx, my = mx / s, my / s
		surf.press = { x = mx, y = my, lx = mx, ly = my, t = SysTime(), target = hitClick(surf, mx, my), vy = 0, vx = 0, lt = SysTime() }
		self:MouseCapture(true)
		DV.touched = SysTime()
	end
	p.OnMouseReleased = function(self, code)
		if code ~= MOUSE_LEFT then return end
		local pr = surf.press
		surf.press = nil
		self:MouseCapture(false)
		if not pr then return end
		if pr.drag then
			if pr.drag.stop then pcall(pr.drag.stop, pr.vx, pr.vy) end
			return
		end
		if pr.moved or pr.held then return end
		local s = surf.s or 1
		local mx, my = self:CursorPos()
		local c = hitClick(surf, mx / s, my / s)
		-- (the same thing as was pressed: things can slide a little while it's held)
		if c and pr.target and math.abs(c.x - pr.target.x) < 12 and math.abs(c.y - pr.target.y) < 12 and c.w == pr.target.w and c.fn then
			local ok, err = pcall(c.fn)
			if not ok then ErrorNoHalt("[Bobba] device: " .. tostring(err) .. "\n") end
		end
	end
	p.OnMouseWheeled = function(self, delta)
		local s = surf.s or 1
		local mx, my = self:CursorPos()
		mx, my = mx / s, my / s
		for i = #surf.zones, 1, -1 do
			local z = surf.zones[i]
			if z.handler.wheel and mx >= z.x and mx < z.x + z.w and my >= z.y and my < z.y + z.h then
				if z.handler.wheel(delta) then return true end
			end
		end
		return true
	end
	p.Think = function(self)
		local pr = surf.press
		if not pr then return end
		if not input.IsMouseDown(MOUSE_LEFT) and not (DV.test and DV.test.mouseDown) then
			-- (let go somewhere we didn't hear about)
			if pr.drag and pr.drag.stop then pcall(pr.drag.stop, 0, 0) end
			surf.press = nil
			self:MouseCapture(false)
			return
		end
		local s = surf.s or 1
		local mx, my = self:CursorPos()
		mx, my = mx / s, my / s
		local now = SysTime()
		local dtm = math.max(0.001, now - pr.lt)
		pr.vx = pr.vx * 0.6 + ((mx - pr.lx) / dtm) * 0.4
		pr.vy = pr.vy * 0.6 + ((my - pr.ly) / dtm) * 0.4
		pr.lx, pr.ly, pr.lt = mx, my, now
		local dx, dy = mx - pr.x, my - pr.y
		if pr.drag then
			if pr.drag.move then pcall(pr.drag.move, mx, my, dx, dy, pr.vy, pr.vx) end
			return
		end
		-- held still: the target's hold
		if not pr.moved and not pr.held and pr.target and pr.target.opts and pr.target.opts.hold and now - pr.t > 0.45 then
			pr.held = true
			local ok, res = pcall(pr.target.opts.hold, pr)
			if ok and type(res) == "table" then pr.drag = res end
			return
		end
		if not pr.moved and (dx * dx + dy * dy) > 36 then
			pr.moved = true
			-- what's dragged: the target's own drag, else a zone (up-down or sideways, as it moved)
			local drag
			local vertical = math.abs(dy) > math.abs(dx)
			if pr.target and pr.target.opts and pr.target.opts.drag then
				drag = pr.target.opts.drag
				-- (a slider only takes sideways drags: up and down scrolls what it's in)
				if drag.sideways and vertical then drag = nil end
			end
			if not drag then
				local z = hitZone(surf, pr.x, pr.y, vertical) or hitZone(surf, pr.x, pr.y)
				if z and (not z.handler.start or z.handler.start(pr.x, pr.y)) then drag = z.handler end
			end
			pr.drag = drag
			if drag and drag.move then pcall(drag.move, mx, my, dx, dy, pr.vy, pr.vx) end
		end
	end
	return surf
end

-- --- apps, widgets, tiles, notifications ------------------------------------------------------------
function DV.app(def)
	assert(def.id, "an app needs an id")
	if not DV.apps[def.id] then DV.appOrder[#DV.appOrder + 1] = def.id end
	def.order = def.order or #DV.appOrder
	if def.removable == nil then def.removable = true end
	def.color = def.color or C.blue
	DV.apps[def.id] = def
	DV.layoutDirty = true
	return def
end
function DV.widget(def)
	if not DV.widgets[def.id] then DV.widgetOrder[#DV.widgetOrder + 1] = def.id end
	def.size = def.size or "small"
	DV.widgets[def.id] = def
	return def
end
function DV.tile(def)
	for i, t in ipairs(DV.tiles) do if t.id == def.id then DV.tiles[i] = def return def end end
	DV.tiles[#DV.tiles + 1] = def
	return def
end

DV.dnd = DV.dnd or false
local noteCount = 0
function DV.notify(n)
	noteCount = noteCount + 1
	n.id = noteCount
	n.at = os.time()
	n.shownAt = SysTime()
	table.insert(DV.notes, 1, n)
	while #DV.notes > 30 do table.remove(DV.notes) end
	-- (quiet: only in the list, e.g. a friend coming online)
	DV.banner = (not DV.dnd and not n.quiet) and n or DV.banner
	if not n.quiet then DV.unseen = (DV.unseen or 0) + 1 end
	return n
end
function DV.dismiss(n)
	for i, x in ipairs(DV.notes) do if x == n then table.remove(DV.notes, i) break end end
	if DV.banner == n then DV.banner = nil end
end

-- "2 min", "now"
function DV.ago(t)
	local s = os.time() - (t or os.time())
	if s < 60 then return U.text("bobba.phone.now", "now") end
	if s < 3600 then return math.floor(s / 60) .. " min" end
	if s < 86400 then return math.floor(s / 3600) .. " h" end
	return math.floor(s / 86400) .. " d"
end

-- --- saved: the home screens (per hotel), the settings ----------------------------------------------
DV.lockVar = CreateClientConVar("bobba_phone_lock", "1", true, false, "The phone's lock screen (the PIN typing itself) when it's taken out after a while")
DV.deviceVar = CreateClientConVar("bobba_phone_device", "phone", true, false, "Your device: phone, or tablet (apps without a tablet view open as a phone on it)")
DV.accentVar = CreateClientConVar("bobba_phone_accent", "FF9F5A", true, false, "The phone's accent colour (hex)")
function DV.accent()
	local s = DV.accentVar:GetString():gsub("[^%x]", "")
	if #s ~= 6 then return C.orange end
	return hex(s)
end

local function hotelKey()
	local ip = (game and game.GetIPAddress and game.GetIPAddress()) or "local"
	ip = tostring(ip):gsub("[^%w%.]", "_")
	if ip == "" or ip:find("^loopback") or ip == "0.0.0.0" then ip = "local" end
	return ip
end
local function savePath() return "bobbahotel/device/" .. hotelKey() .. ".txt" end

DV.layouts = DV.layouts or nil
local function defaultLayout(kind)
	local L = { pages = { {} }, dock = {}, removed = {} }
	-- the widgets first (the room, the wallet and the clock), then the apps
	local first = L.pages[1]
	if kind == "phone" then
		if DV.widgets.room then first[#first + 1] = { kind = "widget", id = "room" } end
		if DV.widgets.wallet then first[#first + 1] = { kind = "widget", id = "wallet" } end
		if DV.widgets.clock then first[#first + 1] = { kind = "widget", id = "clock" } end
	else
		for _, id in ipairs({ "room", "wallet", "clock" }) do if DV.widgets[id] then first[#first + 1] = { kind = "widget", id = id } end end
	end
	return L
end

function DV.load()
	DV.layouts = { phone = defaultLayout("phone"), tablet = defaultLayout("tablet") }
	local raw = P.dataExists(savePath()) and P.readData(savePath())
	local t = raw and util.JSONToTable(raw)
	if type(t) == "table" then
		for _, kind in ipairs({ "phone", "tablet" }) do
			local L = t[kind]
			if type(L) == "table" and type(L.pages) == "table" then
				local clean = { pages = {}, dock = {}, removed = {} }
				for _, pg in ipairs(L.pages) do
					local page = {}
					for _, it in ipairs(type(pg) == "table" and pg or {}) do
						if type(it) == "table" and (it.kind == "app" or it.kind == "widget") and type(it.id) == "string" then page[#page + 1] = { kind = it.kind, id = it.id } end
					end
					clean.pages[#clean.pages + 1] = page
				end
				if #clean.pages == 0 then clean.pages[1] = {} end
				for _, id in ipairs(type(L.dock) == "table" and L.dock or {}) do if type(id) == "string" then clean.dock[#clean.dock + 1] = id end end
				for id, v in pairs(type(L.removed) == "table" and L.removed or {}) do if v then clean.removed[tostring(id)] = true end end
				clean.got = {}
				for id, v in pairs(type(L.got) == "table" and L.got or {}) do if v then clean.got[tostring(id)] = true end end
				DV.layouts[kind] = clean
			end
		end
	end
	DV.layoutDirty = true
end

function DV.save()
	if not DV.layouts then return end
	P.writeData(savePath(), util.TableToJSON(DV.layouts))
end

-- where an app is in a layout: "dock", i / page, i / nil
local function findApp(L, id)
	for i, d in ipairs(L.dock) do if d == id then return "dock", i end end
	for pi, pg in ipairs(L.pages) do
		for i, it in ipairs(pg) do if it.kind == "app" and it.id == id then return pi, i end end
	end
end

-- the layout follows the apps there are: new ones are added (at the end, or the dock while it has
-- room for the ones that want it), gone ones taken out
local function reconcile(kind)
	local L = DV.layouts[kind]
	local S = DV.SIZES[kind]
	L.got = L.got or {}
	-- (taken out: apps and widgets no longer there)
	for i = #L.dock, 1, -1 do if not DV.apps[L.dock[i]] then table.remove(L.dock, i) end end
	for _, pg in ipairs(L.pages) do
		for i = #pg, 1, -1 do
			local it = pg[i]
			if (it.kind == "app" and not DV.apps[it.id]) or (it.kind == "widget" and not DV.widgets[it.id]) then table.remove(pg, i) end
		end
	end
	-- (added: in their order)
	local ids = {}
	for _, id in ipairs(DV.appOrder) do ids[#ids + 1] = id end
	table.sort(ids, function(a, b) return (DV.apps[a].order or 0) < (DV.apps[b].order or 0) end)
	for _, id in ipairs(ids) do
		local app = DV.apps[id]
		local wanted = (not app.store or L.got[id]) and not L.removed[id] and not app.hidden
		local where = findApp(L, id)
		if wanted and not where then
			if app.dock and #L.dock < S.dock then L.dock[#L.dock + 1] = id
			else
				DV.placeItem(kind, { kind = "app", id = id })
			end
		elseif not wanted and where then
			-- (removed or not got: off the screens)
			if where == "dock" then table.remove(L.dock, select(2, findApp(L, id)))
			else local pi, i = findApp(L, id) table.remove(L.pages[pi], i) end
		end
	end
end

-- --- the grid: items flow into the page's cells (a widget takes 2 x 2 or 4 x 2) ---------------------
local function itemSpan(kind, it)
	if it.kind == "widget" then
		local w = DV.widgets[it.id]
		if w and w.size == "wide" then return 4, 2 end
		return 2, 2
	end
	return 1, 1
end

-- the cells each item is in: positions[i] = { col, row, cw, ch } (or nil: it didn't fit)
function DV.flow(kind, page)
	local S = DV.SIZES[kind]
	local used = {}
	local out = {}
	local function free(c, r, cw, ch)
		if c + cw - 1 > S.cols or r + ch - 1 > S.rows then return false end
		for x = c, c + cw - 1 do for y = r, r + ch - 1 do if used[y * 100 + x] then return false end end end
		return true
	end
	for i, it in ipairs(page) do
		local cw, ch = itemSpan(kind, it)
		local placed = false
		for r = 1, S.rows do
			for c = 1, S.cols do
				if free(c, r, cw, ch) then
					for x = c, c + cw - 1 do for y = r, r + ch - 1 do used[y * 100 + x] = true end end
					out[i] = { c, r, cw, ch }
					placed = true
					break
				end
			end
			if placed then break end
		end
	end
	return out
end

-- an item put on the last page with room (or a new page)
function DV.placeItem(kind, item, pageIndex)
	local L = DV.layouts[kind]
	if pageIndex then
		local pg = L.pages[pageIndex]
		table.insert(pg, 1, item)
		DV.spill(kind)
		return
	end
	for pi = 1, #L.pages do
		local pg = L.pages[pi]
		pg[#pg + 1] = item
		local pos = DV.flow(kind, pg)
		if pos[#pg] then return end
		pg[#pg] = nil
	end
	L.pages[#L.pages + 1] = { item }
end

-- what doesn't fit on a page goes to the start of the next one
function DV.spill(kind)
	local L = DV.layouts[kind]
	local pi = 1
	while pi <= #L.pages do
		local pg = L.pages[pi]
		local pos = DV.flow(kind, pg)
		local over = {}
		for i = #pg, 1, -1 do if not pos[i] then table.insert(over, 1, table.remove(pg, i)) end end
		if #over > 0 then
			if not L.pages[pi + 1] then L.pages[pi + 1] = {} end
			for j = #over, 1, -1 do table.insert(L.pages[pi + 1], 1, over[j]) end
		end
		pi = pi + 1
	end
end

-- empty pages after the first are dropped (when editing is done)
local function dropEmptyPages(kind)
	local L = DV.layouts[kind]
	for i = #L.pages, 2, -1 do if #L.pages[i] == 0 then table.remove(L.pages, i) end end
end

function DV.layout(kind)
	if not DV.layouts then DV.load() end
	if DV.layoutDirty then
		DV.layoutDirty = false
		reconcile("phone")
		reconcile("tablet")
	end
	return DV.layouts[kind]
end

-- getting an addon's app from the App Store (its icon goes on the home screen), and taking it off
function DV.getApp(id)
	if not DV.layouts then DV.load() end
	for _, kind in ipairs({ "phone", "tablet" }) do
		local L = DV.layouts[kind]
		L.got = L.got or {}
		L.got[id] = true
		L.removed[id] = nil
	end
	DV.layoutDirty = true
	DV.layout("phone")
	DV.save()
end
function DV.removeApp(id)
	if not DV.layouts then DV.load() end
	for _, kind in ipairs({ "phone", "tablet" }) do
		local L = DV.layouts[kind]
		L.removed[id] = true
		if L.got then L.got[id] = nil end
		local where, i = findApp(L, id)
		if where == "dock" then table.remove(L.dock, i) elseif where then table.remove(L.pages[where], i) end
	end
	DV.save()
end
function DV.onHome(id)
	local L = DV.layout("phone")
	return findApp(L, id) ~= nil
end

-- --- state ------------------------------------------------------------------------------------------
DV.open = DV.open or 0         -- 0 put away .. 1 out (eased)
DV.shown = DV.shown or false  -- wanted out
DV.kind = DV.kind or "phone"   -- the device showing: phone / tablet
DV.stack = DV.stack or {}      -- the open app: { app, screens = { { view, state } } }
DV.page = DV.page or 1
DV.pageX = DV.pageX or 0       -- the pages' slide (in pages)
DV.shade = DV.shade or 0       -- the pulled-down top bar: 0 .. 1
DV.edit = DV.edit or false
DV.locked = DV.locked or nil   -- { t0, digits } while the lock screen shows
DV.putAwayAt = DV.putAwayAt or 0
DV.LOCK_AFTER = 60

function DV.active() return U.style() == "phone" end
-- the tablet is out over the room (the chat box and the room's name make way)
function DV.covering() return DV.active() and DV.kind == "tablet" and (DV.open or 0) > 0.3 end
local function inHotel() return (V.mode == "room" and V.room ~= nil or V.mode == "hotelview") and not (BOBBA.loading and BOBBA.loading.active) end

local function ease(cur, target, speed)
	local k = 1 - math.exp(-FrameTime() * (speed or 14))
	local v = cur + (target - cur) * k
	if math.abs(target - v) < 0.002 then v = target end
	return v
end
DV.ease = ease

-- the device the player chose (the tablet as their own device, or the phone)
local function homeKind() return DV.deviceVar:GetString() == "tablet" and "tablet" or "phone" end

function DV.show(on)
	if on == nil then on = not DV.shown end
	if on == DV.shown then return end
	DV.shown = on
	if on then
		DV.kind = DV.kind or homeKind()
		if DV.lockVar:GetBool() and (SysTime() - (DV.putAwayAt or 0) > DV.LOCK_AFTER or not DV.everOpened) then DV.lock() end
		DV.everOpened = true
		DV.unseen = 0
	else
		DV.putAwayAt = SysTime()
		DV.shade = 0
		if DV.edit then DV.endEdit() end
	end
end
function DV.toggle() DV.show(not DV.shown) end

-- the lock screen: the PIN types itself (a little show), then it opens; a touch skips it
function DV.lock()
	local digits = {}
	for i = 1, 4 do digits[i] = math.random(0, 9) end
	DV.locked = { t0 = SysTime() + 0.25, digits = digits }
end
function DV.unlock()
	if DV.locked and not DV.locked.openingAt then DV.locked.openingAt = SysTime() end
end

-- going home: the app closes (on the tablet a phone-only app's little phone too)
function DV.home()
	if DV.edit then DV.endEdit() return end
	if DV.appOpen() then
		local a = DV.stack.app
		if a and a.onClose then pcall(a.onClose) end
		DV.question = nil
		DV.closing = { stack = DV.stack, at = SysTime() }
		DV.stack = {}
		-- (the tablet brought by an app goes back to the phone)
		if DV.kind == "tablet" and DV.tabletFor and homeKind() == "phone" then DV.switchKind("phone") end
		return
	end
	DV.page = 1
end

function DV.switchKind(kind)
	if DV.kind == kind then return end
	DV.kind = kind
	DV.tabletFor = nil
	DV.shade = 0
	DV.switchedAt = SysTime()
end

-- opening an app: its view on this device; a tablet-only one brings the tablet; a phone-only one on
-- the tablet opens as a phone in the middle
function DV.openApp(id, view, state)
	local app = DV.apps[id]
	if not app then return end
	if DV.edit then return end
	if app.open and not view then
		app.open()
		return
	end
	if not DV.shown then DV.show(true) end
	if DV.kind == "phone" and not app.phone and app.tablet then
		DV.switchKind("tablet")
		DV.tabletFor = id
	end
	DV.closing = nil
	local was = DV.stack.app
	if was and was ~= app and was.onClose then pcall(was.onClose) end
	-- (a fresh start: the app's lists from the top)
	if DV.surface then DV.surface.scrolls = {} end
	DV.stack = { app = app, screens = { { view = view or (DV.kind == "tablet" and (app.tablet or app.phone) or (app.phone or app.tablet)), state = state or {} } }, at = SysTime() }
	DV.stack.onPhone = DV.kind == "tablet" and not app.tablet and app.phone ~= nil
	if app.onOpen then pcall(app.onOpen, DV.stack) end
end
function DV.current() return DV.stack.app end
-- an app's background (a colour, or a function giving one)
function DV.appBg(app)
	if not app then return nil end
	if type(app.bg) == "function" then return app.bg() end
	return app.bg
end
-- (a light background: the status bar's text dark)
function DV.brightBg(app)
	local bg = DV.appBg(app)
	if not bg then return true end
	return (bg.r + bg.g + bg.b) > 450
end
function DV.appOpen() return DV.stack.screens ~= nil and #DV.stack.screens > 0 end

-- --- the view context an app draws with -------------------------------------------------------------
local Ctx = {}
Ctx.__index = Ctx
function Ctx:push(view, state)
	local st = self.stack or DV.stack
	st.screens[#st.screens + 1] = { view = view, state = state or {}, at = SysTime() }
end
function Ctx:pop()
	local st = self.stack or DV.stack
	if #st.screens > 1 then
		st.popping = { screen = table.remove(st.screens), at = SysTime() }
	else
		DV.home()
	end
end
function Ctx:close() DV.home() end

-- an app's header: back (when there's something to go back to), the title, things on the right
-- ({ glyph, fn } or { label, fn }). dark: on a dark background. Returns the height it took.
function Ctx:header(title, opts)
	opts = opts or {}
	local d = self.d
	local fg = opts.dark and C.paper or C.navy
	local top = self.top or 50
	local y = top + 4
	local hasBack = (#((self.stack or DV.stack).screens or {}) > 1) or opts.back
	local x = 20
	if hasBack then
		local hov = d:click(10, y, 44, 40, function() if opts.back then opts.back() else self:pop() end end)
		d:glyph("M15 5l-7 7 7 7", 14, y + 8, 24, alpha(fg, hov and 0.7 or 1), 2.4)
		x = 50
	end
	if opts.big and not hasBack then
		d:text(title or "", 30, 20, y + 6, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		if opts.small then d:text(opts.small, 13, 20, y - 10, alpha(fg, 0.7), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700) end
	else
		d:text(d:fit(title or "", 18, self.w - x - 70, 800), 18, x, y + 20, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
	end
	local rx = self.w - 16
	for i = #(opts.right or {}), 1, -1 do
		local b = opts.right[i]
		if b.glyph then
			local hov = d:click(rx - 40, y, 40, 40, b.fn)
			d:circle(rx - 20, y + 20, 20, alpha(fg, hov and 0.16 or 0.08))
			d:glyph(b.glyph, rx - 31, y + 9, 22, fg, 2.2)
			rx = rx - 46
		else
			local tw = d:textWidth(b.label, 14, 700) + 28
			local hov = d:click(rx - tw, y + 4, tw, 32, b.fn)
			d:pill(rx - tw, y + 4, tw, 32, b.primary and (hov and alpha(fg, 0.85) or fg) or alpha(fg, hov and 0.16 or 0.08))
			d:text(b.label, 14, rx - tw / 2, y + 20, b.primary and (opts.dark and C.navy or C.paper) or fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
			rx = rx - tw - 8
		end
	end
	return (opts.big and not hasBack) and 64 or 48
end

-- a list of rows (settings-like): { { title, sub, right = text / "toggle" / "chevron", on = bool, click }, ... }
-- drawn from y in a rounded card; returns the y after it
function Ctx:rows(x, y, w, rows, opts)
	opts = opts or {}
	local d = self.d
	local rh = opts.rowH or 54
	local bg = opts.bg or C.white
	local fg = opts.fg or C.navy
	d:round(20, x, y, w, rh * #rows, bg)
	for i, r in ipairs(rows) do
		local ry = y + (i - 1) * rh
		local hov = r.click and d:click(x, ry, w, rh, r.click) or false
		if hov then d:round(i == 1 and 20 or 0, x, ry, w, rh, alpha(fg, 0.05)) end
		local tx = x + 16
		if r.color then
			d:round(9, tx, ry + (rh - 30) / 2, 30, 30, r.color)
			if r.glyph then d:glyph(r.glyph, tx + 6, ry + (rh - 18) / 2, 18, C.navy, 2.2) end
			tx = tx + 42
		end
		if r.sub then
			d:text(d:fit(r.title, 15, w - (tx - x) - 90, 700), 15, tx, ry + rh / 2 - 9, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
			d:text(d:fit(r.sub, 12.5, w - (tx - x) - 90), 12.5, tx, ry + rh / 2 + 10, alpha(fg, 0.6), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		else
			d:text(d:fit(r.title, 15, w - (tx - x) - 90, 600), 15, tx, ry + rh / 2, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 600)
		end
		local rx = x + w - 16
		if r.right == "toggle" then
			DV.switch(d, rx - 50, ry + (rh - 30) / 2, r.on)
		elseif r.right == "check" then
			d:glyph("M5 12l5 5 9-10", rx - 22, ry + (rh - 22) / 2, 22, C.blue, 2.6)
		elseif r.right == "chevron" then
			d:glyph("M9 5l7 7-7 7", rx - 18, ry + (rh - 18) / 2, 18, alpha(fg, 0.4), 2.4)
		elseif r.right then
			d:text(r.right, 14, rx, ry + rh / 2, alpha(fg, 0.6), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 600)
		end
		if i < #rows then d:rect(tx, ry + rh - 1, w - (tx - x), 1, alpha(fg, 0.08)) end
	end
	return y + rh * #rows
end

-- an on/off switch (iOS's): 50 x 30
function DV.switch(d, x, y, on)
	d:pill(x, y, 50, 30, on and C.green or alpha(C.slate, 0.45))
	d:circle(on and (x + 35) or (x + 15), y + 15, 13, C.white)
end

-- a slider 0..1 (a pill track); onChange(v) while dragged or clicked
function DV.slider(d, x, y, w, h, v, onChange, fg, track)
	d:pill(x, y, w, h, track or C.navy3)
	d:pill(x, y, math.max(h, w * math.Clamp(v, 0, 1)), h, fg or C.paper)
	local ox = d.ox
	local surf = d.surf
	local function set(mx) onChange(math.Clamp((mx - x - ox) / w, 0, 1)) end
	d:click(x, y, w, h, function() set(surf.mx or (x + ox)) end, { drag = { sideways = true, move = function(mx) set(mx) end } })
end

-- --- drawing the parts ------------------------------------------------------------------------------
local function clockText() return os.date("%H:%M") end
local function battery()
	DV.bornAt = DV.bornAt or SysTime()
	return math.max(8, 100 - math.floor((SysTime() - DV.bornAt) / 360))
end

-- the status bar: the time on the left, the notch, signal and battery on the right
local function drawStatus(d, W, dark, kind)
	local fg = dark and C.navy or C.paper
	local h = kind == "tablet" and 40 or 50
	if kind == "tablet" then
		d:text(clockText() .. "  " .. os.date("%a %d %b"), 13, 28, h / 2, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
	else
		d:text(clockText(), 15, 34, h / 2, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
		d:pill(W / 2 - 55, 10, 110, 30, C.black)
	end
	-- signal bars, battery
	local rx = W - (kind == "tablet" and 28 or 30)
	local b = battery()
	local tw = d:textWidth(b .. "%", 13, 700)
	d:text(b .. "%", 13, rx, h / 2, fg, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 700)
	local bx = rx - tw - 8 - 16
	for i = 0, 3 do
		local bh = 3 + i * 3
		d:round(1, bx + i * 4.5, h / 2 + 6 - bh, 3, bh, alpha(fg, i == 3 and 0.4 or 1))
	end
	if DV.dnd then d:glyph("M12 3a9 9 0 1 0 9 9 7 7 0 0 1-9-9z", bx - 22, h / 2 - 8, 16, fg, 2.2) end
end

-- an app's icon: a rounded square in its colour, its glyph, the badge
function DV.drawIcon(d, app, x, y, size, opts)
	opts = opts or {}
	local col = app.accent and DV.accent() or app.color or C.blue
	d:round(size * 0.31, x, y, size, size, col)
	if app.drawIcon then app.drawIcon(d, x, y, size)
	elseif app.glyph then d:glyph(app.glyph, x + size * 0.27, y + size * 0.27, size * 0.46, app.glyphColor or C.navy, 2.1)
	else d:text((app.name or "?"):sub(1, 1), size * 0.36, x + size / 2, y + size / 2, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800) end
	local n = (not opts.noBadge) and app.badge and app.badge() or nil
	if n and n ~= 0 and n ~= "" then
		local t = tostring(n)
		local bw = math.max(22, d:textWidth(t, 12, 800) + 12)
		d:pill(x + size - bw + 8, y - 7, bw, 22, C.red)
		d:text(t, 12, x + size - bw / 2 + 8, y + 4, C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
	end
end

-- the cell's rectangle (in points) on a home page
local function cellRect(kind, W, c, r, cw, ch)
	local S = DV.SIZES[kind]
	local padX = kind == "tablet" and 56 or 18
	local top = kind == "tablet" and 64 or 66
	local cellW = (W - padX * 2) / S.cols
	local rowH = kind == "tablet" and 150 or 100
	return padX + (c - 1) * cellW, top + (r - 1) * rowH, cellW * cw, rowH * ch, cellW, rowH
end

-- a widget: a rounded card it draws in
local function drawWidget(d, it, x, y, w, h, editing)
	local wd = DV.widgets[it.id]
	if not wd then return end
	d:round(26, x, y, w, h, wd.bg or alpha(C.paper, 0.14))
	if wd.draw then
		d:clip(x, y, w, h, function() d:translate(x, y, function() wd.draw(d, w, h) end) end)
	end
end

-- --- editing the home screen ------------------------------------------------------------------------
function DV.startEdit()
	DV.edit = true
	DV.editAt = SysTime()
end
function DV.endEdit()
	DV.edit = false
	DV.lifted = nil
	DV.sheet = nil
	dropEmptyPages(DV.kind)
	if DV.page > #DV.layouts[DV.kind].pages then DV.page = #DV.layouts[DV.kind].pages end
	DV.save()
end

-- picking an item up: it leaves its place and follows the pointer; where it's let go it goes
local function lift(kind, from, index, item, mx, my, ox, oy)
	local L = DV.layouts[kind]
	if from == "dock" then table.remove(L.dock, index) else table.remove(L.pages[from], index) end
	DV.lifted = { item = item, mx = mx, my = my, ox = ox, oy = oy, from = from, index = index, kind = kind }
	-- (a gap where it would go: live, as the pointer moves)
	return {
		move = function(nx, ny) DV.lifted.mx, DV.lifted.my = nx, ny DV.liftedMoved = true end,
		stop = function() DV.drop() end,
	}
end

-- where the pointer is: the dock, or a page's index to put it before
local function dropTarget(kind, W, H, mx, my)
	local S = DV.SIZES[kind]
	local L = DV.layouts[kind]
	local dockTop = H - (kind == "tablet" and 120 or 118)
	if my >= dockTop and DV.lifted and DV.lifted.item.kind == "app" then
		local n = #L.dock
		if n >= S.dock and DV.lifted.from ~= "dock" then return nil end
		local slotW = (W - 28) / math.max(1, n + 1)
		return "dock", math.Clamp(math.floor((mx - 14) / slotW) + 1, 1, n + 1)
	end
	local pg = L.pages[DV.page]
	if not pg then return nil end
	local pos = DV.flow(kind, pg)
	for i, p in ipairs(pg) do
		local q = pos[i]
		if q then
			local x, y, w, h = cellRect(kind, W, q[1], q[2], q[3], q[4])
			if mx >= x and mx < x + w and my >= y and my < y + h then return DV.page, i end
		end
	end
	return DV.page, #pg + 1
end

function DV.drop()
	local lf = DV.lifted
	if not lf then return end
	local kind = lf.kind
	local L = DV.layouts[kind]
	local W, H = DV.SIZES[kind].w, DV.SIZES[kind].h
	local where, i = dropTarget(kind, W, H, lf.mx, lf.my)
	if where == "dock" then table.insert(L.dock, math.min(i, #L.dock + 1), lf.item.id)
	elseif where then
		local pg = L.pages[where]
		table.insert(pg, math.min(i, #pg + 1), lf.item)
	else
		-- (nowhere it can go: back where it was)
		if lf.from == "dock" then table.insert(L.dock, math.min(lf.index, #L.dock + 1), lf.item.id)
		else table.insert(L.pages[lf.from] or L.pages[1], lf.index, lf.item) end
	end
	DV.spill(kind)
	DV.lifted = nil
	DV.liftedMoved = nil
	DV.save()
end

-- --- the home screen --------------------------------------------------------------------------------
DV.itemPos = DV.itemPos or {}   -- (eased places: items slide to where they go)
local function eased(key, x, y)
	local p = DV.itemPos[key]
	if not p then p = { x = x, y = y } DV.itemPos[key] = p end
	p.x, p.y = ease(p.x, x, 18), ease(p.y, y, 18)
	p.seen = SysTime()
	return p.x, p.y
end

local function wiggle(seed)
	if not DV.edit then return 0, 0 end
	local t = SysTime() * 18 + seed * 1.7
	return math.sin(t) * 0.8, math.cos(t * 1.1) * 0.6
end

local function drawHomeItem(d, kind, it, x, y, w, h, key, from, index)
	local S = DV.SIZES[kind]
	local wx, wy = wiggle(#key)
	x, y = x + wx, y + wy
	if it.kind == "widget" then
		local pad = kind == "tablet" and 10 or 7
		drawWidget(d, it, x + pad, y + pad, w - pad * 2, h - pad * 2, DV.edit)
		local wd = DV.widgets[it.id]
		d:click(x, y, w, h, function()
			if DV.edit then return end
			if wd and wd.click then wd.click() end
		end, { hold = function(pr) DV.startEdit() return lift(kind, from, index, it, pr.lx, pr.ly, pr.lx - x, pr.ly - y) end,
			drag = DV.edit and { start = function() end, move = function(mx, my)
				if not DV.lifted then lift(kind, from, index, it, mx, my, d.surf.press.x - x, d.surf.press.y - y) end
				DV.lifted.mx, DV.lifted.my = mx, my
			end, stop = function() DV.drop() end } or nil })
		if DV.edit then
			local hov = d:click(x + pad - 6, y + pad - 6, 26, 26, function()
				table.remove(from == "dock" and DV.layouts[kind].dock or DV.layouts[kind].pages[from], index)
				DV.save()
			end)
			d:circle(x + pad + 5, y + pad + 5, 12, hov and C.white or C.mist)
			d:rect(x + pad - 1, y + pad + 4, 12, 2.4, C.navy)
		end
		return
	end
	local app = DV.apps[it.id]
	if not app then return end
	local ix = x + (w - S.icon) / 2
	local iy = y + (kind == "tablet" and 18 or 6)
	local hov = d:click(ix - 6, iy - 6, S.icon + 12, S.icon + 28, function()
		if DV.edit then return end
		DV.openApp(app.id)
	end, {
		hold = function(pr) DV.startEdit() return lift(kind, from, index, it, pr.lx, pr.ly, pr.lx - ix, pr.ly - iy) end,
		drag = DV.edit and { move = function(mx, my)
			if not DV.lifted then lift(kind, from, index, it, mx, my, d.surf.press.x - ix, d.surf.press.y - iy) end
			DV.lifted.mx, DV.lifted.my = mx, my
		end, stop = function() DV.drop() end } or nil,
	})
	if hov and not DV.edit and d.surf.press then d:fade(0.75, function() DV.drawIcon(d, app, ix, iy, S.icon) end)
	else DV.drawIcon(d, app, ix, iy, S.icon, { noBadge = DV.edit }) end
	if from ~= "dock" then
		d:text(d:fit(app.name or "", 12, w - 4, 600), 12, x + w / 2, iy + S.icon + 7, C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 600)
	end
	if DV.edit and app.removable ~= false then
		local hb = d:click(ix - 10, iy - 10, 26, 26, function() DV.removeApp(app.id) end)
		d:circle(ix + 1, iy + 1, 11, hb and C.white or C.mist)
		d:rect(ix - 5, iy, 12, 2.4, C.navy)
	end
end

local function drawWallpaper(d, W, H, kind)
	d:rect(0, 0, W, H, C.navy)
	local acc = DV.accent()
	if kind == "tablet" then
		d:circle(-120, H * 0.85, 420, C.navy2)
		d:circle(W - 60, 170, 140, acc)
	else
		d:circle(40, 680, 210, C.navy2)
		d:circle(W + 35, 435, 75, acc)
	end
end

local function drawHome(d, W, H, kind)
	local L = DV.layout(kind)
	local S = DV.SIZES[kind]
	drawWallpaper(d, W, H, kind)
	-- the pages slide (dragged sideways, the wheel)
	local n = #L.pages
	if DV.edit and DV.lifted and (#L.pages[n] > 0) then n = n + 1 if not L.pages[n] then L.pages[n] = {} end end
	DV.page = math.Clamp(DV.page, 1, #L.pages)
	if not DV.paging then DV.pageX = ease(DV.pageX, DV.page - 1, 16) end
	local gridTop, gridBottom = kind == "tablet" and 50 or 50, H - (kind == "tablet" and 130 or 140)
	d:dragZone(0, gridTop, W, gridBottom - gridTop, {
		start = function() if DV.lifted then return false end DV.paging = true DV.pageFrom = DV.pageX return true end,
		move = function(_, _, dx) DV.pageX = math.Clamp(DV.pageFrom - dx / W, -0.3, #L.pages - 0.7) end,
		stop = function(vx)
			DV.paging = false
			local target = math.floor(DV.pageX + 0.5) + 1
			if (vx or 0) < -500 then target = math.floor(DV.pageX) + 2 elseif (vx or 0) > 500 then target = math.floor(DV.pageX) + 1 end
			DV.page = math.Clamp(target, 1, #L.pages)
		end,
		wheel = function(delta) DV.page = math.Clamp(DV.page - (delta > 0 and 1 or -1), 1, #L.pages) return true end,
	})
	-- (a click on nothing ends editing)
	if DV.edit then d:click(0, gridTop, W, gridBottom - gridTop, function() DV.endEdit() end) end
	-- (a lifted item held at the page's side turns the page)
	local lf = DV.lifted
	if lf and lf.kind == kind then
		local edge = (lf.mx < 22 and -1) or (lf.mx > W - 22 and 1) or 0
		if edge ~= 0 and lf.my < gridBottom then
			DV.edgeAt = DV.edgeAt or SysTime()
			if SysTime() - DV.edgeAt > 0.6 then
				DV.page = math.Clamp(DV.page + edge, 1, #L.pages)
				DV.edgeAt = SysTime()
			end
		else DV.edgeAt = nil end
	end
	-- the pages near the one shown
	for pi = 1, #L.pages do
		local off = (pi - 1 - DV.pageX) * W
		if math.abs(off) < W then
			d:translate(off, 0, function()
				local pg = L.pages[pi]
				-- (the lifted item makes a gap where it would go)
				local view = pg
				if lf and lf.kind == kind and pi == DV.page and lf.my < gridBottom and DV.liftedMoved then
					local where, idx = dropTarget(kind, W, H, lf.mx, lf.my)
					if where == pi then
						view = {}
						for i, it in ipairs(pg) do view[i] = it end
						table.insert(view, math.min(idx, #view + 1), { kind = lf.item.kind, id = lf.item.id, ghost = true })
					end
				end
				local pos = DV.flow(kind, view)
				local realIndex = 0
				for i, it in ipairs(view) do
					if not it.ghost then
						realIndex = realIndex + 1
						local q = pos[i]
						if q then
							local x, y, w, h = cellRect(kind, W, q[1], q[2], q[3], q[4])
							local key = kind .. ":" .. it.kind .. ":" .. it.id
							local ex, ey = eased(key, x + off, y)
							drawHomeItem(d, kind, it, ex - off, ey, w, h, key, pi, realIndex)
						end
					end
				end
			end)
		end
	end
	-- the page dots
	local dots = #L.pages
	if dots > 1 then
		local dy = H - (kind == "tablet" and 112 or 122)
		local dw = dots * 14
		for i = 1, dots do
			d:circle(W / 2 - dw / 2 + (i - 1) * 14 + 7, dy, 3.5, alpha(C.paper, i == DV.page and 1 or 0.35))
		end
	end
	-- the dock
	local dockH = kind == "tablet" and 96 or 88
	local dockW = kind == "tablet" and math.min(W - 200, math.max(4, #L.dock + (lf and 1 or 0)) * 100 + 40) or (W - 28)
	local dockX, dockY = (W - dockW) / 2, H - dockH - (kind == "tablet" and 22 or 26)
	d:round(32, dockX, dockY, dockW, dockH, alpha(C.paper, 0.16))
	local dockItems = {}
	for i, id in ipairs(L.dock) do dockItems[#dockItems + 1] = { kind = "app", id = id, index = i } end
	if lf and lf.kind == kind and DV.liftedMoved then
		local where, idx = dropTarget(kind, W, H, lf.mx, lf.my)
		if where == "dock" then table.insert(dockItems, math.min(idx, #dockItems + 1), { ghost = true }) end
	end
	local slotW = dockW / math.max(1, #dockItems)
	for i, it in ipairs(dockItems) do
		if not it.ghost then
			local x = dockX + (i - 1) * slotW
			local key = kind .. ":dock:" .. it.id
			local ex = eased(key, x + (slotW - S.icon) / 2, dockY)
			drawHomeItem(d, kind, it, ex - (slotW - S.icon) / 2, dockY + (dockH - S.icon) / 2 - 6, slotW, dockH, key, "dock", it.index)
		end
	end
	-- editing: + widget and Done
	if DV.edit then
		local hw = d:click(16, 6, 110, 36, function() DV.sheet = { at = SysTime() } end)
		d:pill(16, 8, 110, 32, alpha(C.paper, hw and 0.28 or 0.18))
		d:text(U.text("bobba.phone.addwidget", "+ Widget"), 14, 16 + 55, 24, C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
		local tw = d:textWidth(U.text("bobba.phone.done", "Done"), 14, 800) + 32
		local hd = d:click(W - 16 - tw, 6, tw, 36, function() DV.endEdit() end)
		d:pill(W - 16 - tw, 8, tw, 32, hd and C.white or C.paper)
		d:text(U.text("bobba.phone.done", "Done"), 14, W - 16 - tw / 2, 24, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
	end
	-- the lifted item, under the pointer
	if lf and lf.kind == kind then
		local x, y = lf.mx - lf.ox, lf.my - lf.oy
		if lf.item.kind == "app" and DV.apps[lf.item.id] then
			d:round(S.icon * 0.31, x + 4, y + 10, S.icon, S.icon, Color(0, 0, 0, 90))
			DV.drawIcon(d, DV.apps[lf.item.id], x, y, S.icon * 1.06, { noBadge = true })
		elseif lf.item.kind == "widget" then
			local cw, ch = itemSpan(kind, lf.item)
			local _, _, w, h = cellRect(kind, W, 1, 1, cw, ch)
			d:fade(0.9, function() drawWidget(d, lf.item, x, y, w - 14, h - 14) end)
		end
	end
	-- the widget sheet
	if DV.sheet then DV.drawSheet(d, W, H, kind) end
end

-- the sheet to add widgets from
function DV.drawSheet(d, W, H, kind)
	local t = math.Clamp((SysTime() - DV.sheet.at) / 0.25, 0, 1)
	t = 1 - (1 - t) ^ 3
	local sh = kind == "tablet" and 560 or 470
	local y0 = H - sh * t
	d:click(0, 0, W, y0, function() DV.sheet = nil end)
	d:rect(0, 0, W, y0, Color(0, 0, 0, math.floor(90 * t)))
	d:round(30, 0, y0, W, sh + 40, C.navy2, true, true, false, false)
	d:click(0, y0, W, sh, function() end)
	d:pill(W / 2 - 20, y0 + 10, 40, 5, C.ink2)
	d:text(U.text("bobba.phone.widgets.title", "Add a widget"), 18, 20, y0 + 28, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	d:text(U.text("bobba.phone.widgets.sub", "Tap one to put it on this page"), 13, 20, y0 + 52, C.mist)
	local top = y0 + 80
	local listH = sh - 80
	-- two small ones to a row, a wide one alone
	local rows, row = {}, {}
	-- (each widget once: the ones already out aren't offered)
	local placed = {}
	for _, pg in ipairs(DV.layouts[kind].pages) do for _, it in ipairs(pg) do if it.kind == "widget" then placed[it.id] = true end end end
	for _, id in ipairs(DV.widgetOrder) do
		local wd = DV.widgets[id]
		if placed[id] then
		elseif wd.size == "wide" then
			if #row > 0 then rows[#rows + 1] = row row = {} end
			rows[#rows + 1] = { wd }
		else
			row[#row + 1] = wd
			if #row == 2 then rows[#rows + 1] = row row = {} end
		end
	end
	if #row > 0 then rows[#rows + 1] = row end
	if #rows == 0 then
		d:text(U.text("bobba.phone.widgets.all", "All the widgets are out already."), 14, W / 2, top + 40, C.mist, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
	end
	local cardW = (W - 40 - 12) / 2
	local smallH = math.min(150, cardW)
	if kind == "tablet" then cardW = 250 smallH = 150 end
	local content = 0
	for _, r in ipairs(rows) do content = content + smallH + 30 + 12 end
	local off = d:scroll("widgets", 0, top, W, listH, content)
	d:clip(0, top, W, listH, function()
		local y = top - off
		for _, r in ipairs(rows) do
			local x = 20
			for _, wd in ipairs(r) do
				local w = wd.size == "wide" and (kind == "tablet" and 512 or (W - 40)) or cardW
				local hov = d:click(x, y, w, smallH + 26, function()
					DV.placeItem(kind, { kind = "widget", id = wd.id }, DV.page)
					DV.sheet = nil
					DV.save()
				end)
				d:fade(hov and 0.85 or 1, function() drawWidget(d, { id = wd.id }, x, y, w, smallH) end)
				d:text(wd.name or wd.id, 13, x + 6, y + smallH + 6, C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 600)
				x = x + w + 12
			end
			y = y + smallH + 30 + 12
		end
	end)
end

-- --- an open app ------------------------------------------------------------------------------------
local function drawScreenView(d, W, H, screen, top, st)
	local ctx = setmetatable({ d = d, w = W, h = H, state = screen.state, app = st.app, top = top, kind = DV.kind, stack = st }, Ctx)
	local ok, err = pcall(screen.view, ctx)
	if not ok then
		ErrorNoHalt("[Bobba] app " .. tostring(st.app and st.app.id) .. ": " .. tostring(err) .. "\n")
		d:rect(0, 0, W, H, C.paper)
		d:text(U.text("bobba.phone.crashed", "This app stopped"), 16, W / 2, H / 2, C.navy, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
	end
end

local function drawApp(d, W, H, st, top)
	local screens = st.screens
	if not screens or #screens == 0 then return end
	local app = st.app
	-- the screen under the newest one (sliding in from the right as the newest comes)
	local cur = screens[#screens]
	local t = cur.at and math.Clamp((SysTime() - cur.at) / 0.25, 0, 1) or 1
	t = 1 - (1 - t) ^ 3
	if #screens > 1 and t < 1 then
		d:translate(-W * 0.3 * t, 0, function() drawScreenView(d, W, H, screens[#screens - 1], top, st) end)
	end
	local popping = st.popping
	if popping then
		local pt = math.Clamp((SysTime() - popping.at) / 0.22, 0, 1)
		if pt >= 1 then st.popping = nil
		else
			drawScreenView(d, W, H, cur, top, st)
			d:translate(W * pt, 0, function() drawScreenView(d, W, H, popping.screen, top, st) end)
			return
		end
	end
	d:translate(W * (1 - t), 0, function() drawScreenView(d, W, H, cur, top, st) end)
end

-- --- the pulled-down top bar ------------------------------------------------------------------------
local function drawShade(d, W, H, kind)
	local t = DV.shade
	if t <= 0.001 then return end
	local sh = H
	local y0 = -sh * (1 - t)
	d:fade(math.min(1, t * 1.6), function()
		d:rect(0, 0, W, H, Color(0, 0, 0, 120))
	end)
	d:translate(0, y0, function()
		d:rect(0, 0, W, sh, C.shade)
		d:click(0, 0, W, sh, function() end)
		local pad = kind == "tablet" and math.max(14, (W - 520) / 2) or 14
		local cw = W - pad * 2
		local y = kind == "tablet" and 50 or 56
		-- the tiles
		local tiles = {}
		for _, tl in ipairs(DV.tiles) do if not tl.visible or tl.visible() then tiles[#tiles + 1] = tl end end
		local rowsN = math.ceil(#tiles / 2)
		local boxH = 16 + rowsN * 74 + 60
		d:round(30, pad, y, cw, boxH, C.navy2)
		local tw = (cw - 32 - 10) / 2
		for i, tl in ipairs(tiles) do
			local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
			local x, ty = pad + 16 + col * (tw + 10), y + 16 + row * 74
			local on = tl.on and tl.on() or false
			local hov = d:click(x, ty, tw, 64, function() if tl.click then tl.click() end end)
			d:round(22, x, ty, tw, 64, on and (hov and C.white or C.paper) or (hov and alpha(C.navy3, 0.8) or C.navy3))
			local fg = on and C.navy or C.paper
			d:glyph(tl.glyph, x + 14, ty + 21, 22, fg, 2)
			d:text(d:fit(tl.name or "", 14, tw - 60, 700), 14, x + 46, ty + 22, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
			local stt = tl.state and tl.state() or ""
			d:text(d:fit(stt, 12, tw - 60), 12, x + 46, ty + 42, alpha(fg, 0.8), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		-- the volume (the furni's)
		local vy = y + 16 + rowsN * 74 + 10
		d:glyph("M4 9h4l5-4v14l-5-4H4zM17 9a4 4 0 0 1 0 6", pad + 16, vy + 7, 22, C.paper, 2)
		local vol = HUD.settings and HUD.settings.volumes and HUD.settings.volumes[2]
		if vol then
			DV.slider(d, pad + 50, vy, cw - 66, 36, vol[1]:GetInt() / 100, function(v)
				RunConsoleCommand(vol[1]:GetName(), tostring(math.floor(v * 100 + 0.5)))
			end, C.paper, C.navy3)
		end
		y = y + boxH + 16
		-- notifications
		d:text(U.text("bobba.phone.notifications", "Notifications"), 15, pad + 6, y + 10, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
		if #DV.notes > 0 then
			local ct = U.text("bobba.phone.clearall", "Clear all")
			local cwid = d:textWidth(ct, 13, 700)
			d:click(pad + cw - 6 - cwid - 8, y, cwid + 16, 24, function() DV.notes = {} DV.banner = nil end)
			d:text(ct, 13, pad + cw - 6, y + 10, C.mist, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 700)
		end
		y = y + 26
		local listH = sh - y - 40
		if #DV.notes == 0 then
			d:text(U.text("bobba.phone.nonotes", "Nothing new"), 14, pad + cw / 2, y + 40, C.slate, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		else
			local content = 0
			for _, n in ipairs(DV.notes) do content = content + DV.noteHeight(d, n, cw) + 8 end
			local off = d:scroll("shade", pad, y, cw, listH, content)
			d:clip(pad, y, cw, listH, function()
				local ny = y - off
				for i, n in ipairs(DV.notes) do
					local nh = DV.noteHeight(d, n, cw)
					if ny + nh > y and ny < y + listH then DV.drawNote(d, n, pad, ny, cw, i == 1) end
					ny = ny + nh + 8
				end
			end)
		end
		-- the handle: pushed up (or clicked) it goes back
		d:pill(W / 2 - 24, sh - 22, 48, 5, C.mist)
		d:click(0, sh - 44, W, 44, function() DV.shadeTo = 0 end, { drag = {
			move = function(_, _, _, dy) DV.shadeDrag = math.Clamp(1 + dy / sh, 0, 1) end,
			stop = function(_, vy) DV.shadeDrag = nil DV.shadeTo = ((vy or 0) < -300 or DV.shade < 0.7) and 0 or 1 end,
		} })
	end)
end

function DV.noteHeight(d, n, w)
	local lines = d:wrap(n.text or "", 14, w - 28 - 52)
	return 12 + 18 + #lines * 19 + (n.actions and 46 or 0) + 12
end

function DV.drawNote(d, n, x, y, w, bright)
	local h = DV.noteHeight(d, n, w)
	local light = bright
	local fg = light and C.navy or C.paper
	d:round(22, x, y, w, h, light and C.paper or alpha(C.paper, 0.12))
	local app = n.app and DV.apps[n.app]
	if app then DV.drawIcon(d, app, x + 14, y + 12, 40, { noBadge = true })
	else d:round(13, x + 14, y + 12, 40, 40, n.color or C.sky) end
	local tx = x + 14 + 52
	local title = (n.title or (app and app.name) or "")
	local meta = " · " .. ((app and app.name) or U.text("bobba.phone.hotel", "Hotel")) .. " · " .. DV.ago(n.at)
	local tw = d:textWidth(title, 13, 700)
	d:text(d:fit(title, 13, w - 80, 700), 13, tx, y + 12, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
	d:text(d:fit(meta, 13, math.max(0, w - 80 - tw)), 13, tx + tw, y + 12, alpha(fg, 0.6), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 500)
	local ly = y + 12 + 18
	for _, l in ipairs(d:wrap(n.text or "", 14, w - 28 - 52)) do
		d:text(l, 14, tx, ly, alpha(fg, 0.9), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		ly = ly + 19
	end
	if n.actions then
		local bx = tx
		for i, a in ipairs(n.actions) do
			local bw = d:textWidth(a[1], 13, 700) + 36
			local hov = d:click(bx, ly + 8, bw, 36, function() DV.dismiss(n) if a[2] then a[2]() end end)
			if i == 1 then d:pill(bx, ly + 8, bw, 36, hov and alpha(fg, 0.85) or fg)
			else d:outline(18, bx, ly + 8, bw, 36, 2, fg, light and C.paper or C.navy2) end
			d:text(a[1], 13, bx + bw / 2, ly + 26, i == 1 and (light and C.paper or C.navy) or fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
			bx = bx + bw + 8
		end
	else
		d:click(x, y, w, h, function()
			DV.dismiss(n)
			if n.click then n.click() elseif n.app then DV.shadeTo = 0 DV.openApp(n.app) end
		end)
	end
end

-- --- the lock screen --------------------------------------------------------------------------------
local function drawLock(d, W, H, kind)
	local lk = DV.locked
	if not lk then return end
	local now = SysTime()
	-- the PIN: a digit every 0.24 s, then it opens
	local typed = math.Clamp(math.floor((now - lk.t0) / 0.3) + 1, 0, 4)
	if now < lk.t0 then typed = 0 end
	if typed >= 4 and now - lk.t0 > 3 * 0.3 + 0.45 then DV.unlock() end
	local up = 0
	if lk.openingAt then
		up = math.Clamp((now - lk.openingAt) / 0.32, 0, 1)
		up = up * up
		if up >= 1 then DV.locked = nil return end
	end
	d:translate(0, -H * up, function()
		d:fade(1 - up * 0.6, function()
			d:rect(0, 0, W, H, C.navy)
			d:circle(40, 680, 210, C.navy2)
			d:circle(W + 35, 245, 75, DV.accent())
			d:click(0, 0, W, H, function() DV.unlock() end)
			local cx = W / 2
			local y = kind == "tablet" and 80 or 92
			d:glyph("M5 11h14v10H5zM8 11V7a4 4 0 0 1 8 0v4", cx - 9, y, 18, C.paper, 2)
			d:text(os.date("%A %d %B"), 17, cx, y + 34, C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
			d:text(clockText(), 88, cx, y + 100, C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
			y = y + 160
			local n = DV.notes[1]
			if n then
				local nw = math.min(W - 36, 360)
				local nh = 64
				d:round(22, cx - nw / 2, y, nw, nh, alpha(C.paper, 0.14))
				local app = n.app and DV.apps[n.app]
				if app then DV.drawIcon(d, app, cx - nw / 2 + 12, y + 13, 38, { noBadge = true }) else d:round(12, cx - nw / 2 + 12, y + 13, 38, 38, n.color or C.blue) end
				d:text(d:fit((n.title or "") .. " · " .. DV.ago(n.at), 13, nw - 70, 700), 13, cx - nw / 2 + 62, y + 14, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
				d:text(d:fit(n.text or "", 14, nw - 70), 14, cx - nw / 2 + 62, y + 34, C.line)
				y = y + nh
			end
			y = y + 30
			d:text(U.text("bobba.phone.unlocking", "Unlocking…"), 15, cx - 4, y, C.paper, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 600)
			d:text(U.text("bobba.phone.tapskip", "tap to skip"), 15, cx + 4, y, C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			y = y + 24
			for i = 1, 4 do
				local x = cx - 48 + (i - 1) * 32 + 7
				if i <= typed then d:circle(x, y + 7, 7, C.paper) else d:ring(x, y + 7, 7, 2, C.paper) end
			end
			y = y + 40
			-- the keypad: the key being "pressed" lights up
			local lit = (typed >= 1 and now - lk.t0 - (typed - 1) * 0.3 < 0.18) and lk.digits[typed] or nil
			local labels = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "" }
			local kw, kh, gx, gy = 72, 64, 22, 14
			local x0 = cx - (kw * 3 + gx * 2) / 2
			for i, l in ipairs(labels) do
				if l ~= "" then
					local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
					local kx, ky = x0 + col * (kw + gx), y + row * (kh + gy)
					local on = lit ~= nil and tostring(lit) == l
					d:pill(kx, ky, kw, kh, on and C.paper or alpha(C.paper, 0.16))
					d:text(l, 26, kx + kw / 2, ky + kh / 2, on and C.navy or C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
				end
			end
		end)
	end)
end

-- --- a notification sliding in at the top -----------------------------------------------------------
local function drawBanner(d, W, H, kind)
	local n = DV.banner
	if not n then return end
	local age = SysTime() - n.shownAt
	if age > 4.5 then DV.banner = nil return end
	local t = math.min(1, age / 0.25, (4.5 - age) / 0.3)
	t = 1 - (1 - math.Clamp(t, 0, 1)) ^ 3
	local bw = kind == "tablet" and 420 or (W - 20)
	local bh = DV.noteHeight(d, n, bw)
	local x, y = (W - bw) / 2, -bh - 10 + (bh + 10 + (kind == "tablet" and 44 or 54)) * t
	d:round(22, x + 2, y + 6, bw, bh, Color(0, 0, 0, 70))
	DV.drawNote(d, n, x, y, bw, true)
end

-- --- the screen -------------------------------------------------------------------------------------
-- the shade follows a drag on the status bar
local function shadeZone(d, W, kind)
	local h = kind == "tablet" and 40 or 50
	d:click(0, 0, W, h, function() DV.shadeTo = 1 end, { drag = {
		move = function(_, _, _, dy) DV.shadeDrag = math.Clamp(dy / (DV.SIZES[kind].h * 0.6), 0, 1) end,
		stop = function(_, vy) DV.shadeDrag = nil DV.shadeTo = ((vy or 0) > 300 or DV.shade > 0.3) and 1 or 0 end,
	} })
end

-- the home bar: a click (or a push up) goes home; at home it puts the phone away
local function homeBar(d, W, H, dark)
	local hov = d:click(W / 2 - 100, H - 28, 200, 28, function()
		if DV.locked then DV.unlock() return end
		if DV.shade > 0.05 then DV.shadeTo = 0 return end
		if DV.sheet then DV.sheet = nil return end
		if DV.appOpen() or DV.edit then DV.home() else DV.show(false) end
	end, { drag = { move = function() end, stop = function(_, vy)
		if (vy or 0) < -200 then if DV.appOpen() then DV.home() else DV.show(false) end end
	end } })
	d:pill(W / 2 - 67, H - 13, 134, 5, alpha(dark and C.navy or C.paper, hov and 1 or 0.85))
end

-- the screen's rounded corners: the frame's colour drawn over what's under them
local function corners(d, W, H, r, c)
	local s = d.s
	local col = d:col(c)
	surface.SetDrawColor(col.r, col.g, col.b, col.a)
	draw.NoTexture()
	local n = 10
	for _, k in ipairs({ { 0, 0, 1, 1 }, { W, 0, -1, 1 }, { 0, H, 1, -1 }, { W, H, -1, -1 } }) do
		local cx, cy, sx, sy = k[1], k[2], k[3], k[4]
		local ax, ay = cx + sx * r, cy + sy * r
		for i = 0, n - 1 do
			local a0, a1 = i / n * math.pi / 2, (i + 1) / n * math.pi / 2
			local p1 = { x = (ax - sx * r * math.cos(a0)) * s, y = (ay - sy * r * math.sin(a0)) * s }
			local p2 = { x = (ax - sx * r * math.cos(a1)) * s, y = (ay - sy * r * math.sin(a1)) * s }
			poly({ { x = cx * s, y = cy * s }, p1, p2 })
		end
	end
end

local drawScreenInside
local function drawScreen(d, W, H)
	-- (only on the screen: GMod keeps a panel's drawing inside it, the desktop app's doesn't always)
	d:clip(0, 0, W, H, function() drawScreenInside(d, W, H) end)
	corners(d, W, H, DV.SIZES[DV.kind].radius - DV.SIZES[DV.kind].bezel / 2, C.black)
end
function drawScreenInside(d, W, H)
	local kind = DV.kind
	local st = DV.stack
	local appOpen = st.screens ~= nil and #st.screens > 0
	local top = kind == "tablet" and 40 or 50
	-- the home screen, with the app opening over it (from small to the screen)
	local opening = appOpen and math.Clamp((SysTime() - (st.at or 0)) / 0.28, 0, 1) or 0
	opening = 1 - (1 - opening) ^ 3
	local cl = DV.closing
	local closing = cl and math.Clamp((SysTime() - cl.at) / 0.24, 0, 1) or nil
	if closing and closing >= 1 then DV.closing = nil closing = nil end
	local dark = false
	if not appOpen or opening < 1 or closing then drawHome(d, W, H, kind) end
	local function app(s)
		local a = s.app
		local bg = DV.appBg(a) or C.paper
		if s.onPhone then
			-- (a phone-only app on the tablet: a phone in the middle, the "bigger" button)
			DV.drawPhoneInTablet(d, W, H, s)
			return
		end
		d:rect(0, 0, W, H, bg)
		drawApp(d, W, H, s, top)
	end
	if closing then
		d:fade(1 - closing, function() d:translate(0, H * 0.08 * closing, function() app(cl.stack) end) end)
	elseif appOpen then
		if opening < 1 then
			d:fade(opening, function() d:translate(0, H * 0.06 * (1 - opening), function() app(st) end) end)
		else app(st) end
		dark = st.onPhone and false or DV.brightBg(st.app)
	end
	if DV.locked then dark = false end
	-- the status bar (the shade's handle; while editing the home screen its buttons are there)
	if DV.edit then
		if kind ~= "tablet" then d:pill(W / 2 - 55, 10, 110, 30, C.black) end
	else
		drawStatus(d, W, dark and DV.shade < 0.5, kind)
		if not DV.locked then shadeZone(d, W, kind) end
	end
	drawQuestion(d, W, H)
	drawBanner(d, W, H, kind)
	-- the shade: dragged, or easing to where it was let go
	if DV.shadeDrag then DV.shade = DV.shadeDrag
	elseif DV.shadeTo then DV.shade = ease(DV.shade, DV.shadeTo, 16) if DV.shade == DV.shadeTo then DV.shadeTo = nil end end
	drawShade(d, W, H, kind)
	if DV.shade > 0.5 then drawStatus(d, W, false, kind) end
	drawLock(d, W, H, kind)
	homeBar(d, W, H, dark and not DV.locked and DV.shade < 0.5)
end

-- a phone-only app on the tablet: drawn on a phone in the middle (the room's dim behind it); "bigger"
-- makes it as big as fits
DV.phoneBig = DV.phoneBig or false
function DV.drawPhoneInTablet(d, W, H, st)
	d:rect(0, 0, W, H, Color(5, 8, 15, 215))
	d:click(0, 0, W, H, function() DV.home() end)
	local PS = DV.SIZES.phone
	local k = DV.phoneBig and math.min((H - 60) / PS.h, 1) or 0.82
	local pw, ph = PS.w * k, PS.h * k
	local px, py = (W - pw) / 2, (H - ph) / 2 + 6
	-- (the bigger / smaller button)
	local label = DV.phoneBig and U.text("bobba.phone.smaller", "Smaller") or U.text("bobba.phone.bigger", "Bigger")
	local bw = d:textWidth(label, 13, 700) + 30
	local hov = d:click(px + pw + 20, py, bw, 34, function() DV.phoneBig = not DV.phoneBig end)
	d:pill(px + pw + 20, py, bw, 34, alpha(C.paper, hov and 0.3 or 0.18))
	d:text(label, 13, px + pw + 20 + bw / 2, py + 17, C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 700)
	-- the phone: drawn at its own scale (a second draw over the same panel)
	local s2 = d.s * k
	local d2 = newDraw(d.surf, s2)
	d2.a = d.a
	d2.ox, d2.oy = (px + d.ox) / k, (py + d.oy) / k
	d2:round(48, -9, -9, PS.w + 18, PS.h + 18, Color(48, 56, 74))
	d2:round(46, -8, -8, PS.w + 16, PS.h + 16, C.black)
	d2:clip(0, 0, PS.w, PS.h, function()
		d2:rect(0, 0, PS.w, PS.h, DV.appBg(st.app) or C.paper)
		-- (clicks are kept in the tablet's points: the phone's are put there)
		local before = #d.surf.clicks
		local smx, smy = d.surf.mx, d.surf.my
		if smx then d.surf.mx, d.surf.my = smx / k, smy / k end
		local zonesBefore = #d.surf.zones
		drawApp(d2, PS.w, PS.h, st, 50)
		d.surf.mx, d.surf.my = smx, smy
		local function scaled(h0)
			if not h0 then return nil end
			return setmetatable({ move = h0.move and function(mx, my, dx, dy, vy, vx) return h0.move(mx / k, my / k, dx / k, dy / k, (vy or 0) / k, (vx or 0) / k) end,
				stop = h0.stop and function(vx, vy) return h0.stop((vx or 0) / k, (vy or 0) / k) end }, { __index = h0 })
		end
		for i = before + 1, #d.surf.clicks do
			local c = d.surf.clicks[i]
			c.x, c.y, c.w, c.h = c.x * k, c.y * k, c.w * k, c.h * k
			if c.opts and c.opts.drag then c.opts = setmetatable({ drag = scaled(c.opts.drag) }, { __index = c.opts }) end
		end
		for i = zonesBefore + 1, #d.surf.zones do
			local z = d.surf.zones[i]
			z.x, z.y, z.w, z.h = z.x * k, z.y * k, z.w * k, z.h * k
			z.handler = scaled(z.handler)
		end
		drawStatus(d2, PS.w, DV.brightBg(st.app), "phone")
	end)
	corners(d2, PS.w, PS.h, 40, C.black)
end

-- --- the panels -------------------------------------------------------------------------------------
-- the device's place on the screen (pixels): the frame, and the screen inside it
local function placement()
	local sw, sh = ScrW(), ScrH()
	local S = DV.SIZES[DV.kind]
	local fw, fh = S.w + S.bezel * 2, S.h + S.bezel * 2
	if DV.kind == "tablet" then
		local s = math.min(sw * 0.92 / fw, sh * 0.92 / fh)
		local W, H = math.floor(fw * s), math.floor(fh * s)
		local x, y = math.floor((sw - W) / 2), math.floor((sh - H) / 2)
		return s, x, y, W, H
	end
	local s = math.min(sh * 0.72 / fh, sw * 0.34 / fw)
	local W, H = math.floor(fw * s), math.floor(fh * s)
	local margin = math.floor(math.min(sw, sh) * 0.025)
	return s, sw - W - margin * 2, sh - H - margin, W, H
end

local function buildPanels()
	if IsValid(DV.root) then return end
	local root = vgui.Create("EditablePanel")
	DV.root = root
	root:MakePopup()
	root:SetMouseInputEnabled(true)
	root:SetKeyboardInputEnabled(false)
	root.Paint = function(self, pw, ph)
		local o = DV.open
		if DV.kind == "tablet" then
			surface.SetDrawColor(5, 8, 15, math.floor(150 * o))
			surface.DrawRect(0, 0, pw, ph)
		end
		if not DV.frame then return end
		local s = DV.frame[1]
		local S = DV.SIZES[DV.kind]
		local x, y = DV.frame[2] - DV.rootX, DV.frame[3] - DV.rootY
		-- (a shadow, then the frame)
		draw.RoundedBox(math.floor(S.radius * s), x + math.floor(4 * s), y + math.floor(14 * s), DV.frame[4], DV.frame[5], Color(0, 0, 0, math.floor(110 * o)))
		draw.RoundedBox(math.floor(S.radius * s), x, y, DV.frame[4], DV.frame[5], Color(5, 8, 15, 255))
		draw.RoundedBox(math.floor(S.radius * s), x + 1, y + 1, DV.frame[4] - 2, DV.frame[5] - 2, Color(28, 34, 48, 255))
		draw.RoundedBox(math.floor((S.radius - 2) * s), x + math.floor(3 * s), y + math.floor(3 * s), DV.frame[4] - math.floor(6 * s), DV.frame[5] - math.floor(6 * s), Color(5, 8, 15, 255))
	end
	-- (a click on the room around the tablet: back to the phone, or away)
	root.OnMousePressed = function(self, code)
		if DV.kind ~= "tablet" then return end
		if DV.tabletFor then DV.home() elseif homeKind() == "tablet" then DV.show(false) else DV.switchKind("phone") end
	end
	DV.surface = makeSurface(root, function(d, W, H) drawScreen(d, W, H) end)
	-- the phone button, while it's put away
	local btn = vgui.Create("EditablePanel")
	DV.button = btn
	btn:SetZPos(19)
	btn:SetMouseInputEnabled(true)
	btn.Paint = function(self, pw, ph)
		local hov = self:IsHovered()
		draw.RoundedBox(math.floor(pw * 0.3), 0, 0, pw, ph, Color(5, 8, 15, 235))
		draw.RoundedBox(math.floor(pw * 0.26), 3, 3, pw - 6, ph - 6, hov and Color(42, 63, 104) or Color(27, 45, 79))
		local s = pw / 64
		local d = newDraw({ panel = self, clicks = {}, zones = {}, scrolls = {} }, s)
		d:round(5, 22, 13, 20, 38, C.paper)
		d:round(3, 24.5, 17, 15, 26, C.navy)
		d:pill(28, 46, 8, 2.5, C.navy)
		local n = (DV.unseen or 0)
		if n > 0 then
			d:pill(40, 4, 22, 22, C.red)
			d:text(n > 9 and "9+" or tostring(n), 11, 51, 15, C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
		end
	end
	btn.OnMousePressed = function(self, code) if code == MOUSE_LEFT then DV.show(true) end end
end

local function removePanels()
	if IsValid(DV.root) then DV.root:Remove() end
	if IsValid(DV.button) then DV.button:Remove() end
	DV.root, DV.button, DV.surface = nil, nil, nil
end

-- every frame: where the panels are, the easing out and in
hook.Add("Think", "bobba.device", function()
	if not DV.active() or not inHotel() then
		if IsValid(DV.root) then DV.root:SetVisible(false) end
		if IsValid(DV.button) then DV.button:SetVisible(false) end
		return
	end
	buildPanels()
	DV.open = ease(DV.open, DV.shown and 1 or 0, 13)
	local s, x, y, w, h = placement()
	DV.frame = { s, x, y, w, h }
	local S = DV.SIZES[DV.kind]
	local root, surf = DV.root, DV.surface
	-- (the phone slides up from below; the tablet fades in and grows a little)
	local o = DV.open
	if o <= 0.001 then
		root:SetVisible(false)
	else
		root:SetVisible(true)
		if DV.kind == "tablet" then
			DV.rootX, DV.rootY = 0, 0
			root:SetPos(0, 0)
			root:SetSize(ScrW(), ScrH())
			local k = 0.94 + 0.06 * o
			local cx, cy = x + w / 2, y + h / 2
			w, h = math.floor(w * k), math.floor(h * k)
			x, y = math.floor(cx - w / 2), math.floor(cy - h / 2) + math.floor((1 - o) * 30)
			DV.frame = { s * k, x, y, w, h }
			root:SetAlpha(math.floor(255 * math.min(1, o * 1.5)))
		else
			y = y + math.floor((1 - o) * (h + 40))
			DV.frame = { s, x, y, w, h }
			DV.rootX, DV.rootY = x, y
			root:SetPos(x, y)
			root:SetSize(w, h)
			root:SetAlpha(255)
		end
		local fs = DV.frame[1]
		surf.s = fs
		local b = math.floor(S.bezel * fs)
		surf.panel:SetPos(DV.frame[2] - DV.rootX + b, DV.frame[3] - DV.rootY + b)
		surf.panel:SetSize(DV.frame[4] - b * 2, DV.frame[5] - b * 2)
	end
	-- the phone button: bottom right while the phone is away (or the tablet's out)
	local btn = DV.button
	local bs = math.floor(64 * U.scale())
	local showBtn = o < 0.5
	btn:SetVisible(showBtn)
	if showBtn then
		local margin = math.floor(math.min(ScrW(), ScrH()) * 0.025)
		btn:SetSize(bs, bs)
		btn:SetPos(ScrW() - bs - margin * 2, ScrH() - bs - margin)
	end
	-- the keyboard: the device's while one of its text boxes is being typed in
	local focus = vgui.GetKeyboardFocus and vgui.GetKeyboardFocus()
	local inside = false
	local f = focus
	while IsValid(f) do if f == root then inside = true break end f = f:GetParent() end
	local wantKeys = inside or (SysTime() - (DV.keysAt or 0) < 0.4)
	if root.bobbaKeys ~= wantKeys then root.bobbaKeys = wantKeys root:SetKeyboardInputEnabled(wantKeys) end
	-- (the key that takes it out and puts it away)
	local ST = BOBBA.steering
	local key = ST and ST.key and ST.key("phone")
	if key and key > 0 then
		local down = input.IsKeyDown(key)
		if down and not DV.keyWas then DV.toggle() end
		DV.keyWas = down
	end
	-- (the eased places of items no longer drawn are forgotten)
	if math.random() < 0.02 then
		for k, p in pairs(DV.itemPos) do if SysTime() - (p.seen or 0) > 2 then DV.itemPos[k] = nil end end
	end
end)

-- another look chosen: the phone goes, or comes
BOBBA.events.on("uiStyleChanged", "bobba.device", function(st)
	if st ~= "phone" then removePanels() end
end)

-- the hotel's notifications go to the phone (with the phone's look)
local nitroNotify = U.notify
function U.notify(title, message, seconds)
	if DV.active() then
		return DV.notify({ title = title, text = U.plain and U.plain(message) or message })
	end
	return nitroNotify(title, message, seconds)
end

-- a fresh hotel: the saved layout for it
BOBBA.events.on("roomShown", "bobba.device.load", function()
	if not DV.layouts or DV.loadedFor ~= hotelKey() then DV.load() DV.loadedFor = hotelKey() end
end)
