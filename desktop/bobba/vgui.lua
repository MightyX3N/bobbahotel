-- GMod's panels (vgui): a tree of panels over the screen, drawn parent first, children over it,
-- windows made with MakePopup on top of everything (the one clicked last in front). Mouse and
-- keyboard go to the panel under the mouse / the one with the keyboard, as in GMod.

local utf8 = require("utf8")
local lg = love.graphics

return function(G)
	local S = G.drawState
	local classes = {}
	local orderCounter = 0
	local function nextOrder() orderCounter = orderCounter + 1 return orderCounter end

	local hovered, captured, focus, pressed

	-- --- the base panel -------------------------------------------------------------------------
	local Panel = {}
	Panel.__index = Panel
	classes.Panel = { meta = Panel, name = "Panel" }

	local function sortChildren(p)
		table.sort(p.children, function(a, b)
			if a.popup ~= b.popup then return not a.popup end
			if a.zpos ~= b.zpos then return a.zpos < b.zpos end
			return a.order < b.order
		end)
	end

	function Panel:IsValid() return not self.removed end
	function Panel:SetPos(x, y) self.x, self.y = math.floor(x or 0), math.floor(y or 0) end
	function Panel:GetPos() return self.x, self.y end
	function Panel:SetX(x) self.x = math.floor(x) end
	function Panel:SetY(y) self.y = math.floor(y) end
	function Panel:GetX() return self.x end
	function Panel:GetY() return self.y end
	function Panel:SetSize(w, h)
		w, h = math.max(0, math.floor(w or 0)), math.max(0, math.floor(h or 0))
		if w ~= self.w or h ~= self.h then self.w, self.h = w, h self.needLayout = true end
	end
	function Panel:GetSize() return self.w, self.h end
	function Panel:SetWide(w) self:SetSize(w, self.h) end
	function Panel:SetTall(h) self:SetSize(self.w, h) end
	Panel.SetWidth, Panel.SetHeight = Panel.SetWide, Panel.SetTall
	function Panel:GetWide() return self.w end
	function Panel:GetTall() return self.h end
	function Panel:SetBounds(x, y, w, h) self:SetPos(x, y) self:SetSize(w, h) end
	function Panel:GetBounds() return self.x, self.y, self.w, self.h end
	function Panel:Center()
		local pw, ph = self.parent and self.parent.w or ScrW(), self.parent and self.parent.h or ScrH()
		self:SetPos((pw - self.w) / 2, (ph - self.h) / 2)
	end
	function Panel:CenterHorizontal(f) local pw = self.parent and self.parent.w or ScrW() self.x = math.floor(pw * (f or 0.5) - self.w / 2) end
	function Panel:CenterVertical(f) local ph = self.parent and self.parent.h or ScrH() self.y = math.floor(ph * (f or 0.5) - self.h / 2) end
	function Panel:SetVisible(v) v = v and true or false if self.visible ~= v then self.visible = v if not v then G.vguiHidden(self) end end end
	function Panel:IsVisible() return self.visible end
	function Panel:Show() self:SetVisible(true) end
	function Panel:Hide() self:SetVisible(false) end
	function Panel:GetParent() return self.parent ~= G.world and self.parent or nil end
	function Panel:GetChildren() local t = {} for i, c in ipairs(self.children) do t[i] = c end return t end
	function Panel:ChildCount() return #self.children end
	function Panel:GetChild(i) return self.children[i + 1] end
	function Panel:SetParent(p)
		p = p or G.world
		if self.parent then
			for i, c in ipairs(self.parent.children) do if c == self then table.remove(self.parent.children, i) break end end
		end
		self.parent = p
		p.children[#p.children + 1] = self
		sortChildren(p)
	end
	function Panel:Add(class) return vgui.Create(class, self) end
	function Panel:MakePopup()
		self.popup = true
		self.mouseEnabled = true
		self.keyboardEnabled = true
		if self.parent ~= G.world then self:SetParent(G.world) end
		self:MoveToFront()
	end
	function Panel:IsPopup() return self.popup end
	function Panel:MoveToFront() self.order = nextOrder() if self.parent then sortChildren(self.parent) end end
	function Panel:MoveToBack() self.order = -nextOrder() if self.parent then sortChildren(self.parent) end end
	function Panel:SetZPos(z) self.zpos = z or 0 if self.parent then sortChildren(self.parent) end end
	function Panel:GetZPos() return self.zpos end
	function Panel:SetMouseInputEnabled(on) self.mouseEnabled = on and true or false end
	function Panel:IsMouseInputEnabled() return self.mouseEnabled end
	function Panel:SetKeyboardInputEnabled(on)
		self.keyboardEnabled = on and true or false
		if not on and focus and (focus == self or focus:HasParent(self)) then focus = nil end
	end
	function Panel:IsKeyboardInputEnabled() return self.keyboardEnabled end
	function Panel:HasParent(p)
		local q = self.parent
		while q do if q == p then return true end q = q.parent end
		return false
	end
	function Panel:IsHovered() return hovered == self end
	function Panel:IsChildHovered()
		return hovered ~= nil and hovered ~= self and hovered:HasParent(self)
	end
	function Panel:LocalToScreen(x, y)
		local p = self
		x, y = x or 0, y or 0
		while p and p ~= G.world do x, y = x + p.x, y + p.y p = p.parent end
		return x, y
	end
	function Panel:ScreenToLocal(x, y)
		local ox, oy = self:LocalToScreen(0, 0)
		return x - ox, y - oy
	end
	function Panel:CursorPos()
		local mx, my = love.mouse.getPosition()
		return self:ScreenToLocal(mx, my)
	end
	Panel.LocalCursorPos = Panel.CursorPos
	function Panel:MouseCapture(on)
		if on then captured = self elseif captured == self then captured = nil end
	end
	-- (a text box only gets the keyboard when its window lets it have it)
	function Panel:RequestFocus()
		local p = self
		while p and p ~= G.world do
			if p.popup and not p.keyboardEnabled then return end
			p = p.parent
		end
		if focus ~= self then
			local old = focus
			focus = self
			if old and not old.removed and old.OnFocusChanged then old:OnFocusChanged(false) end
			if self.OnFocusChanged then self:OnFocusChanged(true) end
		end
	end
	function Panel:KillFocus() if focus == self then focus = nil if self.OnFocusChanged then self:OnFocusChanged(false) end end end
	function Panel:HasFocus() return focus == self end
	function Panel:HasHierarchicalFocus() return focus ~= nil and (focus == self or focus:HasParent(self)) end
	function Panel:Dock(d) self.dock = d or NODOCK if self.parent then self.parent.needLayout = true end end
	function Panel:GetDock() return self.dock end
	function Panel:DockMargin(l, t, r, b) self.margin = { l or 0, t or 0, r or 0, b or 0 } if self.parent then self.parent.needLayout = true end end
	function Panel:DockPadding(l, t, r, b) self.padding = { l or 0, t or 0, r or 0, b or 0 } self.needLayout = true end
	function Panel:GetDockMargin() return unpack(self.margin) end
	function Panel:GetDockPadding() return unpack(self.padding) end
	function Panel:InvalidateLayout() self.needLayout = true end
	function Panel:InvalidateParent() if self.parent then self.parent.needLayout = true end end
	function Panel:InvalidateChildren() self.needLayout = true for _, c in ipairs(self.children) do c:InvalidateChildren() end end
	function Panel:SetPaintBackground(on) self.paintBackground = on and true or false end
	Panel.SetDrawBackground = Panel.SetPaintBackground
	function Panel:GetPaintBackground() return self.paintBackground end
	function Panel:SetAlpha(a) self.alpha = a end
	function Panel:GetAlpha() return self.alpha end
	function Panel:SetName(n) self.name = n end
	function Panel:GetName() return self.name or "" end
	function Panel:GetClassName() return self.className end
	function Panel:SetEnabled(on) self.enabled = on and true or false end
	function Panel:IsEnabled() return self.enabled end
	function Panel:SetDisabled(on) self.enabled = not on end
	function Panel:GetDisabled() return not self.enabled end
	function Panel:SetPaintedManually(on) self.manual = on and true or false end
	function Panel:PaintManual() if not self.manual then return end self.manual = false G.paintPanel(self, S.clip) self.manual = true end
	function Panel:NoClipping(on) self.noClip = on end
	function Panel:SetCursor() end
	function Panel:SetTooltip() end
	function Panel:SetSkin() end
	function Panel:SetFocusTopLevel() end
	function Panel:SetWorldClicker() end
	function Panel:SetSelectable() end
	function Panel:SetCookieName() end
	function Panel:SizeToChildren(w, h)
		local mw, mh = 0, 0
		for _, c in ipairs(self.children) do
			mw = math.max(mw, c.x + c.w + (c.margin[3] or 0))
			mh = math.max(mh, c.y + c.h + (c.margin[4] or 0))
		end
		self:SetSize(w and mw + self.padding[3] or self.w, h and mh + self.padding[4] or self.h)
	end
	function Panel:GetTable() return self end
	function Panel:Remove()
		if self.removed then return end
		self.removed = true
		for _, c in ipairs(self:GetChildren()) do c:Remove() end
		if self.OnRemove then pcall(self.OnRemove, self) end
		if self.parent then
			for i, c in ipairs(self.parent.children) do if c == self then table.remove(self.parent.children, i) break end end
		end
		if hovered == self then hovered = nil end
		if captured == self then captured = nil end
		if focus == self then focus = nil end
		if pressed == self then pressed = nil end
	end

	-- text on labels and buttons (GMod's Label): shown after the panel's Paint
	function Panel:SetText(t)
		t = tostring(t or "")
		if self.text ~= t then self.text = t self.wrapW = nil if self.autoStretch then self.needStretch = true end end
	end
	function Panel:GetText() return self.text or "" end
	function Panel:SetFont(f) self.font = f self.wrapW = nil end
	function Panel:GetFont() return self.font end
	function Panel:SetTextColor(c) self.textColor = c end
	function Panel:GetTextColor() return self.textColor end
	Panel.SetFGColor = Panel.SetTextColor
	function Panel:SetContentAlignment(a) self.align = a end
	function Panel:SetTextInset(x, y) self.inset = { x or 0, y or 0 } end
	function Panel:SetWrap(on) self.wrap = on and true or false self.wrapW = nil end
	function Panel:GetWrap() return self.wrap end
	function Panel:SetAutoStretchVertical(on) self.autoStretch = on and true or false self.needStretch = true end
	function Panel:SetExpensiveShadow() end
	-- the label's lines (wrapped to its width)
	function Panel:textLines()
		local text = self.text or ""
		if not self.wrap then return { text } end
		if self.wrapW == self.w and self.wrapped then return self.wrapped end
		local font = G.fontOf(self.font).font
		local lines = {}
		local maxW = math.max(1, self.w - (self.inset and self.inset[1] * 2 or 0))
		for para in (text .. "\n"):gmatch("(.-)\n") do
			local _, wrapped = font:getWrap(para, maxW)
			if #wrapped == 0 then wrapped = { "" } end
			for _, l in ipairs(wrapped) do lines[#lines + 1] = l end
		end
		self.wrapped, self.wrapW = lines, self.w
		return lines
	end
	function Panel:GetContentSize()
		local lines = self:textLines()
		local w = 0
		for _, l in ipairs(lines) do w = math.max(w, (G.textSize(l, self.font))) end
		return w, #lines * G.fontOf(self.font).font:getHeight()
	end
	function Panel:SizeToContents()
		local w, h = self:GetContentSize()
		self:SetSize(w + (self.inset and self.inset[1] * 2 or 0), h)
	end
	function Panel:SizeToContentsX(add) local w = self:GetContentSize() self:SetWide(w + (add or 0)) end
	function Panel:SizeToContentsY(add) local _, h = self:GetContentSize() self:SetTall(h + (add or 0)) end
	function Panel:drawLabel()
		if not self.text or self.text == "" then return end
		local c = self.textColor or Color(255, 255, 255)
		local lines = self:textLines()
		local font = self.font or "DermaDefault"
		local lh = G.fontOf(font).font:getHeight()
		local total = lh * #lines
		local a = self.align or (self.wrap and 7 or 4)
		local ix = self.inset and self.inset[1] or 0
		local iy = self.inset and self.inset[2] or 0
		-- (alignment like a numpad: 7 8 9 top, 4 5 6 middle, 1 2 3 bottom)
		local y
		if a >= 7 then y = iy elseif a >= 4 then y = (self.h - total) / 2 else y = self.h - total - iy end
		for i, line in ipairs(lines) do
			local w = G.textSize(line, font)
			local col = (a - 1) % 3
			local x = col == 0 and ix or (col == 1 and (self.w - w) / 2 or (self.w - w - ix))
			G.printText(line, font, math.floor(x), math.floor(y + (i - 1) * lh), { (c.r or 255) / 255, (c.g or 255) / 255, (c.b or 255) / 255, (c.a or 255) / 255 })
		end
	end

	-- --- classes ----------------------------------------------------------------------------------
	local function define(name, base, tbl)
		tbl = tbl or {}
		tbl.__index = tbl
		local baseMeta = classes[base] and classes[base].meta or Panel
		setmetatable(tbl, { __index = baseMeta })
		classes[name] = { meta = tbl, base = base, name = name }
		return tbl
	end

	define("EditablePanel", "Panel")
	define("DPanel", "Panel", {
		Init = function(self) self.paintBackground = true end,
		Paint = function(self, w, h)
			if not self.paintBackground then return end
			draw.RoundedBox(4, 0, 0, w, h, self.bgColor or Color(240, 240, 240, 255))
		end,
		SetBackgroundColor = function(self, c) self.bgColor = c end,
		GetBackgroundColor = function(self) return self.bgColor end,
	})
	define("DLabel", "Panel", {
		Init = function(self) self.mouseEnabled = false self.text = "Label" self.isLabel = true end,
		SetColor = function(self, c) self.textColor = c end,
		GetColor = function(self) return self.textColor end,
		SetDark = function(self, on) if on then self.textColor = Color(30, 30, 30) end end,
		SetBright = function(self, on) if on then self.textColor = Color(255, 255, 255) end end,
	})
	define("DButton", "DLabel", {
		Init = function(self)
			self.mouseEnabled = true
			self.text = "Button"
			self.align = 5
			self.textColor = Color(30, 30, 30)
			self:SetTall(22)
		end,
		Paint = function(self, w, h)
			draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and Color(230, 230, 230) or Color(210, 210, 210))
		end,
		IsDown = function(self) return self.down == true end,
		OnMousePressed = function(self, code)
			if not self.enabled then return end
			self.down = true
			self.downCode = code
			self:MouseCapture(true)
		end,
		OnMouseReleased = function(self, code)
			self:MouseCapture(false)
			if not self.down then return end
			self.down = false
			if not self.enabled then return end
			local mx, my = self:CursorPos()
			if mx < 0 or my < 0 or mx >= self.w or my >= self.h then return end
			if code == MOUSE_LEFT and self.DoClick then self:DoClick() end
			if code == MOUSE_RIGHT and self.DoRightClick then self:DoRightClick() end
			if code == MOUSE_MIDDLE and self.DoMiddleClick then self:DoMiddleClick() end
		end,
		SetImage = function() end,
		SetIcon = function() end,
		SetIsToggle = function() end,
	})
	define("DFrame", "EditablePanel", {
		Init = function(self) self.title = "" end,
		SetTitle = function(self, t) self.title = t end,
		ShowCloseButton = function() end,
		SetDraggable = function() end,
		SetSizable = function() end,
		Close = function(self) if self.OnClose then self:OnClose() end self:Remove() end,
		Paint = function(self, w, h)
			draw.RoundedBox(4, 0, 0, w, h, Color(60, 60, 70, 240))
			draw.SimpleText(self.title or "", "DermaDefault", 8, 4, color_white)
		end,
	})
	require("bobba.textentry")(G, define, Panel, function() return focus end)

	vgui = {}
	function vgui.Register(name, tbl, base)
		base = base or "Panel"
		tbl.__index = tbl
		local baseClass = classes[base]
		setmetatable(tbl, { __index = baseClass and baseClass.meta or Panel })
		tbl.BaseClass = baseClass and baseClass.meta or Panel
		classes[name] = { meta = tbl, base = base, name = name }
		return tbl
	end
	function vgui.RegisterTable(tbl, base) tbl.Base = base return tbl end
	function vgui.GetControlTable(name) return classes[name] and classes[name].meta end
	local function initChain(p, cls)
		if not cls then return end
		if cls.base then initChain(p, classes[cls.base]) end
		local init = rawget(cls.meta, "Init")
		if init then
			local ok, err = pcall(init, p)
			if not ok then ErrorNoHalt("[vgui " .. cls.name .. " Init] " .. tostring(err) .. "\n") end
		end
	end
	function vgui.Create(class, parent, name)
		local cls = classes[class]
		if not cls then
			ErrorNoHalt("vgui.Create: no panel called " .. tostring(class) .. "\n")
			return nil
		end
		local p = setmetatable({
			x = 0, y = 0, w = 64, h = 24, visible = true, children = {}, zpos = 0, order = nextOrder(),
			mouseEnabled = true, keyboardEnabled = false, popup = false, dock = NODOCK,
			margin = { 0, 0, 0, 0 }, padding = { 0, 0, 0, 0 }, enabled = true, paintBackground = true,
			className = class, name = name, needLayout = true,
		}, cls.meta)
		p:SetParent(parent or G.world)
		initChain(p, cls)
		return p
	end
	function vgui.CreateFromTable(tbl, parent, name)
		local n = "anon_" .. tostring(tbl)
		if not classes[n] then vgui.Register(n, tbl, tbl.Base or "Panel") end
		return vgui.Create(n, parent, name)
	end
	function vgui.GetKeyboardFocus() return focus end
	function vgui.GetHoveredPanel() return hovered end
	function vgui.GetWorldPanel() return G.world end
	function vgui.CursorVisible() return true end
	function vgui.IsHoveringWorld() return hovered == nil end
	function vgui.FocusedHasParent(p) return focus ~= nil and focus:HasParent(p) end
	GetHUDPanel = function() return G.world end

	G.world = setmetatable({ x = 0, y = 0, w = lg.getWidth(), h = lg.getHeight(), visible = true, children = {}, zpos = 0, order = 0,
		mouseEnabled = false, keyboardEnabled = false, popup = false, dock = NODOCK, margin = { 0, 0, 0, 0 }, padding = { 0, 0, 0, 0 },
		enabled = true, className = "GModBase", needLayout = false }, Panel)

	-- --- every frame: Think, layout ---------------------------------------------------------------
	function G.vguiHidden(p)
		if hovered and (hovered == p or hovered:HasParent(p)) then hovered = nil end
		if focus and (focus == p or focus:HasParent(p)) then focus = nil end
	end

	local function layout(p)
		if p.needLayout then
			p.needLayout = false
			if p.PerformLayout and p ~= G.world then
				local ok, err = pcall(p.PerformLayout, p, p.w, p.h)
				if not ok then ErrorNoHalt("[vgui PerformLayout] " .. tostring(err) .. "\n") end
			end
			-- docking: TOP/BOTTOM/LEFT/RIGHT in order, then FILL in what's left
			local l, t, r, b = p.padding[1], p.padding[2], p.w - p.padding[3], p.h - p.padding[4]
			local fills = {}
			for _, c in ipairs(p.children) do
				if c.visible and c.dock ~= NODOCK then
					local m = c.margin
					if c.dock == TOP then
						c:SetPos(l + m[1], t + m[2]) c:SetSize(r - l - m[1] - m[3], c.h)
						t = t + m[2] + c.h + m[4]
					elseif c.dock == BOTTOM then
						c:SetPos(l + m[1], b - m[4] - c.h) c:SetSize(r - l - m[1] - m[3], c.h)
						b = b - m[2] - c.h - m[4]
					elseif c.dock == LEFT then
						c:SetPos(l + m[1], t + m[2]) c:SetSize(c.w, b - t - m[2] - m[4])
						l = l + m[1] + c.w + m[3]
					elseif c.dock == RIGHT then
						c:SetPos(r - m[3] - c.w, t + m[2]) c:SetSize(c.w, b - t - m[2] - m[4])
						r = r - m[1] - c.w - m[3]
					elseif c.dock == FILL then
						fills[#fills + 1] = c
					end
				end
			end
			for _, c in ipairs(fills) do
				local m = c.margin
				c:SetPos(l + m[1], t + m[2])
				c:SetSize(r - l - m[1] - m[3], b - t - m[2] - m[4])
			end
		end
		for _, c in ipairs(p.children) do
			if c.autoStretch and c.wrap and (c.needStretch or c.wrapW ~= c.w) then
				c.needStretch = false
				local _, h = c:GetContentSize()
				if h ~= c.h then c:SetTall(h) p.needLayout = true end
			end
			if c.visible then layout(c) end
		end
	end

	local function think(p)
		for _, c in ipairs(p:GetChildren()) do
			if c.visible and not c.removed then
				if c.Think then
					local ok, err = pcall(c.Think, c)
					if not ok then ErrorNoHalt("[vgui Think] " .. tostring(err) .. "\n") end
				end
				if not c.removed then think(c) end
			end
		end
	end

	function G.vguiUpdate()
		G.world.w, G.world.h = lg.getWidth(), lg.getHeight()
		think(G.world)
		layout(G.world)
		G.updateHover()
	end

	-- --- drawing ------------------------------------------------------------------------------------
	local function paintPanel(p, clip)
		if not p.visible or p.removed or p.manual then return end
		local ax, ay = p:LocalToScreen(0, 0)
		local x0, y0, x1, y1 = ax, ay, ax + p.w, ay + p.h
		if clip and not p.noClip then
			x0, y0, x1, y1 = math.max(x0, clip[1]), math.max(y0, clip[2]), math.min(x1, clip[3]), math.min(y1, clip[4])
		end
		if x1 <= x0 or y1 <= y0 then return end
		local myClip = { x0, y0, x1, y1 }
		local function setup()
			S.clip = myClip
			G.applyScissor(x0, y0, x1, y1)
			lg.origin()
			lg.translate(ax, ay)
		end
		setup()
		S.alpha = (p.alpha or 255) / 255
		if p.Paint then
			local ok, err = pcall(p.Paint, p, p.w, p.h)
			if not ok then ErrorNoHalt("[vgui Paint " .. tostring(p.className) .. "] " .. tostring(err) .. "\n") end
			setup()
		end
		if p.isLabel then p:drawLabel() end
		S.alpha = 1
		for _, c in ipairs(p:GetChildren()) do paintPanel(c, myClip) end
		if p.PaintOver then
			setup()
			pcall(p.PaintOver, p, p.w, p.h)
		end
	end
	G.paintPanel = paintPanel

	function G.vguiDraw()
		for _, c in ipairs(G.world:GetChildren()) do paintPanel(c, { 0, 0, lg.getWidth(), lg.getHeight() }) end
		S.clip = nil
		lg.setScissor()
		lg.origin()
		lg.setColor(1, 1, 1, 1)
	end

	-- --- mouse --------------------------------------------------------------------------------------
	local function hit(p, mx, my, ox, oy)
		local list = p.children
		for i = #list, 1, -1 do
			local c = list[i]
			if c.visible and not c.removed then
				local cx, cy = ox + c.x, oy + c.y
				if mx >= cx and my >= cy and mx < cx + c.w and my < cy + c.h then
					local h = hit(c, mx, my, cx, cy)
					if h then return h end
					if c.mouseEnabled then return c end
				end
			end
		end
	end
	G.hitTest = function(mx, my) return hit(G.world, mx, my, 0, 0) end

	function G.updateHover()
		local mx, my = love.mouse.getPosition()
		local h = hit(G.world, mx, my, 0, 0)
		if h ~= hovered then
			local old = hovered
			hovered = h
			if old and not old.removed and old.OnCursorExited then pcall(old.OnCursorExited, old) end
			if h and h.OnCursorEntered then pcall(h.OnCursorEntered, h) end
		end
	end

	local BUTTON = { MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE, MOUSE_4, MOUSE_5 }
	function G.mousePressed(x, y, button)
		G.updateHover()
		local code = BUTTON[button]
		if not code then return end
		local target = captured or hovered
		if not target then
			if focus and not focus.removed then focus:KillFocus() end
			hook.Run("GUIMousePressed", code, Vector and Vector(0, 0, 0) or nil)
			return
		end
		-- the window clicked comes to the front
		local top = target
		while top.parent and top.parent ~= G.world do top = top.parent end
		if top.popup then top:MoveToFront() end
		if focus and focus ~= target and not target.isTextEntry then focus:KillFocus() end
		hook.Run("VGUIMousePressed", target, code)
		pressed = target
		if target.OnMousePressed then
			local ok, err = pcall(target.OnMousePressed, target, code)
			if not ok then ErrorNoHalt("[vgui OnMousePressed] " .. tostring(err) .. "\n") end
		end
	end

	function G.mouseReleased(x, y, button)
		local code = BUTTON[button]
		if not code then return end
		G.updateHover()
		local target = captured or hovered
		if target and target.OnMouseReleased then
			local ok, err = pcall(target.OnMouseReleased, target, code)
			if not ok then ErrorNoHalt("[vgui OnMouseReleased] " .. tostring(err) .. "\n") end
		end
		hook.Run("VGUIMouseReleased", target, code)
		pressed = nil
	end

	function G.mouseMoved(x, y)
		G.updateHover()
		local target = captured or hovered
		if target and target.OnCursorMoved then
			local lx, ly = target:ScreenToLocal(x, y)
			local ok, err = pcall(target.OnCursorMoved, target, lx, ly)
			if not ok then ErrorNoHalt("[vgui OnCursorMoved] " .. tostring(err) .. "\n") end
		end
	end

	-- (a panel that doesn't take the wheel passes it to the one it's in)
	function G.wheelMoved(dx, dy)
		G.updateHover()
		local p = hovered
		local delta = dy > 0 and 1 or (dy < 0 and -1 or 0)
		if delta == 0 then return end
		while p and p ~= G.world do
			if p.OnMouseWheeled then
				local ok, res = pcall(p.OnMouseWheeled, p, delta)
				if not ok then ErrorNoHalt("[vgui OnMouseWheeled] " .. tostring(res) .. "\n") break end
				if res then break end
			end
			p = p.parent
		end
	end

	-- --- keyboard ------------------------------------------------------------------------------------
	function G.keyPressed(key, isRepeat)
		local code = G.loveToCode[key]
		if focus and not focus.removed and focus.visible then
			if focus.isTextEntry then focus:keyTyped(key, code, isRepeat) return true end
			if code and focus.OnKeyCodePressed then pcall(focus.OnKeyCodePressed, focus, code) return true end
		end
		if code and not isRepeat then
			-- (to the window in front that takes the keyboard, else the game's binds)
			local p = hovered
			while p and p ~= G.world do
				if p.OnKeyCodePressed and p.keyboardEnabled then
					local ok, res = pcall(p.OnKeyCodePressed, p, code)
					if ok and res then return true end
				end
				p = p.parent
			end
		end
		return false
	end
	function G.keyReleased(key)
		local code = G.loveToCode[key]
		if code and focus and focus.OnKeyCodeReleased then pcall(focus.OnKeyCodeReleased, focus, code) end
	end
	function G.textInput(t)
		if focus and not focus.removed and focus.isTextEntry and focus.visible then focus:typeText(t) return true end
		return false
	end
	G.focus = function() return focus end
end
