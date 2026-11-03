-- GMod's DTextEntry: a text box with a caret, selecting, copy and paste, one line or several.
-- Like GMod: OnKeyCodeTyped(code) sees every key first (true = it's dealt with), AllowInput(char)
-- true keeps a character out, OnEnter on Enter (one line), OnValueChange as it's typed when
-- SetUpdateOnType(true).

local utf8 = require("utf8")
local lg = love.graphics

return function(G, define, Panel, getFocus)
	local function chars(s)
		local t = {}
		for _, c in utf8.codes(s) do t[#t + 1] = utf8.char(c) end
		return t
	end
	local function len(s) return utf8.len(s) or #s end
	-- the bytes before character n (0 = none)
	local function byteAt(s, n)
		if n <= 0 then return 0 end
		local o = utf8.offset(s, n + 1)
		return (o or (#s + 1)) - 1
	end
	local function sub(s, a, b) -- characters a+1 .. b
		return s:sub(byteAt(s, a) + 1, byteAt(s, b))
	end

	local E = define("DTextEntry", "Panel", {})
	function E:Init()
		self.isTextEntry = true
		self.value = ""
		self.caret = 0
		self.sel = nil
		self.font = "DermaDefault"
		self.placeholder = ""
		self.multiline = false
		self.updateOnType = false
		self.editable = true
		self.scrollX = 0
		self.scrollY = 0
		self.enterAllowed = true
		self.blinkAt = love.timer.getTime()
		self.mouseEnabled = true
		self.keyboardEnabled = true
		self:SetSize(100, 20)
	end
	function E:GetValue() return self.value end
	E.GetText = E.GetValue
	function E:SetText(t)
		self.value = tostring(t or "")
		local n = len(self.value)
		if self.caret > n then self.caret = n end
		self.sel = nil
	end
	function E:SetValue(t)
		self:SetText(t)
		if self.OnValueChange then self:OnValueChange(self.value) end
	end
	function E:GetCaretPos() return self.caret end
	function E:SetCaretPos(n) self.caret = math.max(0, math.min(len(self.value), math.floor(n or 0))) self.sel = nil end
	function E:SetMultiline(on) self.multiline = on and true or false end
	function E:IsMultiline() return self.multiline end
	E.GetMultiline = E.IsMultiline
	function E:SetPlaceholderText(t) self.placeholder = tostring(t or "") end
	function E:GetPlaceholderText() return self.placeholder end
	function E:SetPlaceholderColor(c) self.placeholderColor = c end
	function E:SetUpdateOnType(on) self.updateOnType = on and true or false end
	function E:GetUpdateOnType() return self.updateOnType end
	function E:SetEditable(on) self.editable = on and true or false end
	function E:IsEditable() return self.editable end
	function E:SetNumeric(on) self.numeric = on and true or false end
	function E:GetNumeric() return self.numeric end
	function E:SetEnterAllowed(on) self.enterAllowed = on and true or false end
	function E:GetEnterAllowed() return self.enterAllowed end
	function E:SetMaximumCharCount(n) self.maxChars = n end
	function E:SetHighlightColor(c) self.highlightColor = c end
	function E:SetCursorColor(c) self.cursorColor = c end
	function E:SetHistoryEnabled() end
	function E:SetDrawLanguageID() end
	function E:SetDrawBorder() end
	function E:SetTabbingDisabled() end
	function E:SetVerticalScrollbarEnabled() end
	function E:SelectAllText() self.sel = 0 self.caret = len(self.value) end
	function E:SelectAllOnFocus() self.selectAllOnFocus = true end
	function E:GetSelectedText()
		if not self.sel or self.sel == self.caret then return "" end
		local a, b = math.min(self.sel, self.caret), math.max(self.sel, self.caret)
		return sub(self.value, a, b)
	end
	function E:IsEditing() return getFocus() == self end
	function E:OnFocusChanged(gained)
		if gained then
			self.blinkAt = love.timer.getTime()
			if self.selectAllOnFocus then self:SelectAllText() end
			if self.OnGetFocus then self:OnGetFocus() end
		else
			self.sel = nil
			if self.OnLoseFocus then self:OnLoseFocus() end
		end
	end

	-- after the text changed
	function E:changed()
		self.blinkAt = love.timer.getTime()
		if self.OnChange then self:OnChange() end
		if self.OnTextChanged then self:OnTextChanged() end
		if self.updateOnType and self.OnValueChange then self:OnValueChange(self.value) end
	end

	local function deleteSelection(self)
		if not self.sel or self.sel == self.caret then self.sel = nil return false end
		local a, b = math.min(self.sel, self.caret), math.max(self.sel, self.caret)
		self.value = sub(self.value, 0, a) .. sub(self.value, b, len(self.value))
		self.caret = a
		self.sel = nil
		return true
	end

	function E:insert(text)
		if not self.editable then return end
		local changed = deleteSelection(self)
		for _, ch in ipairs(chars(text)) do
			local blocked = false
			if ch == "\n" and not self.multiline then blocked = true end
			if self.numeric and not ch:match("[%d%.%-]") then blocked = true end
			if self.maxChars and len(self.value) >= self.maxChars then blocked = true end
			if not blocked and self.AllowInput and self:AllowInput(ch) == true then blocked = true end
			if not blocked then
				self.value = sub(self.value, 0, self.caret) .. ch .. sub(self.value, self.caret, len(self.value))
				self.caret = self.caret + 1
				changed = true
			end
		end
		if changed then self:changed() end
	end
	function E:typeText(t) self:insert(t) end

	-- (GMod's own: Enter gives OnEnter and lets go of the keyboard)
	function E:OnKeyCodeTyped(code)
		if (code == KEY_ENTER or code == KEY_PAD_ENTER) and not self.multiline and self.enterAllowed then
			self:KillFocus()
			if self.OnEnter then self:OnEnter(self.value) end
			return true
		end
	end

	local function wordLeft(s, n)
		local cs = chars(s)
		while n > 0 and cs[n]:match("%s") do n = n - 1 end
		while n > 0 and not cs[n]:match("%s") do n = n - 1 end
		return n
	end
	local function wordRight(s, n)
		local cs = chars(s)
		local m = #cs
		while n < m and not cs[n + 1]:match("%s") do n = n + 1 end
		while n < m and cs[n + 1]:match("%s") do n = n + 1 end
		return n
	end

	function E:keyTyped(key, code, isRepeat)
		if code and self.OnKeyCodeTyped then
			local ok, res = pcall(self.OnKeyCodeTyped, self, code)
			if not ok then ErrorNoHalt("[DTextEntry OnKeyCodeTyped] " .. tostring(res) .. "\n") end
			if ok and res then return end
			if self.removed or getFocus() ~= self then return end
		end
		local ctrl = love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
		local shift = love.keyboard.isDown("lshift", "rshift")
		local n = len(self.value)
		local function move(to)
			if shift then self.sel = self.sel or self.caret else self.sel = nil end
			self.caret = math.max(0, math.min(n, to))
			self.blinkAt = love.timer.getTime()
		end
		if key == "backspace" then
			if not self.editable then return end
			if not deleteSelection(self) then
				if self.caret == 0 then return end
				local from = ctrl and wordLeft(self.value, self.caret) or self.caret - 1
				self.value = sub(self.value, 0, from) .. sub(self.value, self.caret, n)
				self.caret = from
			end
			self:changed()
		elseif key == "delete" then
			if not self.editable then return end
			if not deleteSelection(self) then
				if self.caret >= n then return end
				local to = ctrl and wordRight(self.value, self.caret) or self.caret + 1
				self.value = sub(self.value, 0, self.caret) .. sub(self.value, to, n)
			end
			self:changed()
		elseif key == "left" then
			if not shift and self.sel and self.sel ~= self.caret then move(math.min(self.sel, self.caret)) return end
			move(ctrl and wordLeft(self.value, self.caret) or self.caret - 1)
		elseif key == "right" then
			if not shift and self.sel and self.sel ~= self.caret then move(math.max(self.sel, self.caret)) return end
			move(ctrl and wordRight(self.value, self.caret) or self.caret + 1)
		elseif key == "home" then
			move(self.multiline and self:lineStart() or 0)
		elseif key == "end" then
			move(self.multiline and self:lineEnd() or n)
		elseif key == "up" or key == "down" then
			if self.multiline then
				local lines = self:layout()
				local li = self:caretLine(lines)
				local target = lines[li + (key == "up" and -1 or 1)]
				if target then
					local x = self:caretX(lines[li])
					move(self:charAtX(target, x))
				else
					move(key == "up" and 0 or n)
				end
			end
		elseif key == "return" or key == "kpenter" then
			if self.multiline then self:insert("\n") end
		elseif key == "tab" then
			-- (nothing: GMod moves to the next box; there's no order of boxes here)
		elseif ctrl and key == "a" then
			self.sel = 0
			self.caret = n
		elseif ctrl and key == "c" then
			local t = self:GetSelectedText()
			if t ~= "" then love.system.setClipboardText(t) end
		elseif ctrl and key == "x" then
			local t = self:GetSelectedText()
			if t ~= "" and self.editable then
				love.system.setClipboardText(t)
				deleteSelection(self)
				self:changed()
			end
		elseif ctrl and key == "v" then
			local t = love.system.getClipboardText() or ""
			if not self.multiline then t = t:gsub("[\r\n]+", " ") else t = t:gsub("\r", "") end
			if t ~= "" then self:insert(t) end
		end
	end

	-- --- where the characters are ------------------------------------------------------------------
	local function font(self) return G.fontOf(self.font).font end

	-- the lines: { start = characters before it, text = ... } (one line unless multiline; long
	-- lines wrap at a space, or anywhere when a word is too long)
	function E:layout()
		local f = font(self)
		if self.layoutFor == self.value and self.layoutW == self.w and self.layoutFont == self.font then return self.lines end
		local lines = {}
		if not self.multiline then
			lines[1] = { start = 0, text = self.value }
		else
			local maxW = math.max(10, self.w - 6)
			local cs = chars(self.value)
			local start, cur, w, lastSpace = 0, {}, 0, nil
			local i = 1
			while i <= #cs do
				local ch = cs[i]
				if ch == "\n" then
					lines[#lines + 1] = { start = start, text = table.concat(cur), nl = true }
					start, cur, w, lastSpace = i, {}, 0, nil
				else
					local cw = f:getWidth(ch)
					if w + cw > maxW and #cur > 0 then
						if lastSpace and lastSpace < #cur then
							local keep = {}
							for k = 1, lastSpace do keep[k] = cur[k] end
							local rest = {}
							for k = lastSpace + 1, #cur do rest[#rest + 1] = cur[k] end
							lines[#lines + 1] = { start = start, text = table.concat(keep) }
							start = start + lastSpace
							cur = rest
							w = f:getWidth(table.concat(rest))
						else
							lines[#lines + 1] = { start = start, text = table.concat(cur) }
							start = start + #cur
							cur, w = {}, 0
						end
						lastSpace = nil
					end
					cur[#cur + 1] = ch
					w = w + cw
					if ch == " " then lastSpace = #cur end
				end
				i = i + 1
			end
			lines[#lines + 1] = { start = start, text = table.concat(cur) }
		end
		self.lines, self.layoutFor, self.layoutW, self.layoutFont = lines, self.value, self.w, self.font
		return lines
	end
	function E:caretLine(lines)
		lines = lines or self:layout()
		for i = #lines, 1, -1 do
			if self.caret >= lines[i].start then return i end
		end
		return 1
	end
	function E:caretX(line, at)
		at = at or self.caret
		return font(self):getWidth(sub(line.text, 0, math.max(0, math.min(len(line.text), at - line.start))))
	end
	function E:charAtX(line, x)
		local f = font(self)
		local best, bestD = line.start, math.huge
		local n = len(line.text)
		for i = 0, n do
			local d = math.abs(f:getWidth(sub(line.text, 0, i)) - x)
			if d < bestD then best, bestD = line.start + i, d end
		end
		return best
	end
	function E:lineStart() local lines = self:layout() return lines[self:caretLine(lines)].start end
	function E:lineEnd() local lines = self:layout() local l = lines[self:caretLine(lines)] return l.start + len(l.text) end

	local PAD_X, PAD_Y = 2, 1
	-- the character under a point in the box
	function E:charAt(mx, my)
		local lines = self:layout()
		local lh = font(self):getHeight()
		local li = 1
		if self.multiline then li = math.max(1, math.min(#lines, math.floor((my - PAD_Y + self.scrollY) / lh) + 1)) end
		return self:charAtX(lines[li], mx - PAD_X + self.scrollX)
	end

	function E:OnMousePressed(code)
		if code ~= MOUSE_LEFT then return end
		self:RequestFocus()
		local mx, my = self:CursorPos()
		local at = self:charAt(mx, my)
		local now = love.timer.getTime()
		if self.lastClick and now - self.lastClick < 0.35 then
			-- (double click: the word)
			self.sel = wordLeft(self.value, at)
			self.caret = wordRight(self.value, at)
			self.lastClick = nil
			return
		end
		self.lastClick = now
		self.caret = at
		self.sel = nil
		if love.keyboard.isDown("lshift", "rshift") then self.sel = self.sel or at end
		self.dragging = true
		self:MouseCapture(true)
		self.blinkAt = now
	end
	function E:OnMouseReleased()
		self.dragging = false
		self:MouseCapture(false)
	end
	function E:OnCursorMoved(x, y)
		if not self.dragging then return end
		local at = self:charAt(x, y)
		if at ~= self.caret then
			self.sel = self.sel or self.caret
			self.caret = at
		end
	end

	-- GMod's TextEntry drawing: the text, the selection behind it, the blinking caret
	function E:DrawTextEntryText(textCol, highCol, caretCol)
		local f = font(self)
		local lh = f:getHeight()
		local lines = self:layout()
		local focused = getFocus() == self
		local li = self:caretLine(lines)
		local cx = self:caretX(lines[li])
		-- keep the caret in sight
		if not self.multiline then
			local room = self.w - PAD_X * 2 - 2
			if cx - self.scrollX > room then self.scrollX = cx - room end
			if cx - self.scrollX < 0 then self.scrollX = cx end
			if self.scrollX > 0 and f:getWidth(self.value) - self.scrollX < room then self.scrollX = math.max(0, f:getWidth(self.value) - room) end
		else
			local cy = (li - 1) * lh
			if cy - self.scrollY > self.h - lh - PAD_Y * 2 then self.scrollY = cy - (self.h - lh - PAD_Y * 2) end
			if cy - self.scrollY < 0 then self.scrollY = cy end
		end
		local y0 = self.multiline and (PAD_Y - self.scrollY) or math.floor((self.h - lh) / 2)
		local x0 = PAD_X - self.scrollX
		local tc = textCol or self.textColor or Color(0, 0, 0)
		-- selection
		if self.sel and self.sel ~= self.caret then
			local a, b = math.min(self.sel, self.caret), math.max(self.sel, self.caret)
			local hc = highCol or self.highlightColor or Color(70, 140, 220)
			lg.setColor(hc.r / 255, hc.g / 255, hc.b / 255, (hc.a or 255) / 255 * 0.6)
			for i, l in ipairs(lines) do
				local ls, le = l.start, l.start + len(l.text)
				local sa, sb = math.max(a, ls), math.min(b, le)
				if sb > sa then
					local xa, xb = self:caretX(l, sa), self:caretX(l, sb)
					lg.rectangle("fill", x0 + xa, y0 + (i - 1) * lh, xb - xa, lh)
				end
			end
		end
		local font = self.font
		for i, l in ipairs(lines) do
			local y = y0 + (i - 1) * lh
			if y + lh >= 0 and y <= self.h then
				G.printText(l.text, font, math.floor(x0), math.floor(y), { tc.r / 255, tc.g / 255, tc.b / 255, (tc.a or 255) / 255 })
			end
		end
		if focused and self.editable and ((love.timer.getTime() - self.blinkAt) % 1) < 0.5 then
			local cc = caretCol or self.cursorColor or tc
			lg.setColor(cc.r / 255, cc.g / 255, cc.b / 255, (cc.a or 255) / 255)
			lg.rectangle("fill", math.floor(x0 + cx), math.floor(y0 + (li - 1) * lh), 1, lh)
		end
	end

	function E:Paint(w, h)
		if self.paintBackground then
			draw.RoundedBox(3, 0, 0, w, h, Color(255, 255, 255))
		end
		self:DrawTextEntryText(self.textColor or Color(0, 0, 0), Color(70, 140, 220), Color(0, 0, 0))
		if self.value == "" and self.placeholder ~= "" then
			draw.SimpleText(self.placeholder, self.font, PAD_X, self.multiline and PAD_Y or h / 2, self.placeholderColor or Color(128, 128, 128), TEXT_ALIGN_LEFT, self.multiline and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
		end
	end
	E.SetFont = Panel.SetFont
end
