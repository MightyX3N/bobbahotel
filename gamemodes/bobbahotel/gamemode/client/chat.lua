-- Talking (client): the chat input at the bottom of the screen and the speech bubbles over the room,
-- the way Nitro shows them (nitro-react's ChatWidget, free flow: a new bubble appears over the one
-- talking, older bubbles it would cover are pushed up, and every 6 seconds all bubbles move up 15
-- pixels until they leave the top). Habbo's bubble pictures come from an addon (R.chatSkin, e.g.
-- bobba_habbo); without one the bubbles are drawn plain.
--
-- Typing goes straight into the chat (like Habbo); Enter says it, Shift+Enter shouts it,
-- ":shout text", ":whisper name text" (or ":tell name text").
--
--   BOBBA.room.chatSkin = function(style) return skin end   -- nil: the plain bubble
--     skin = { base = img, color = img (optional), pointer = img, slice = { x, y, w, h },
--              colorXY = { x, y }, faceXY = { x, y }, pointerY, margins = { left, top, right, bottom },
--              textColor = 0xRRGGBB, anonymous (no face, no name) }
--     img = { path, width, height, texWidth, texHeight }
--   BOBBA.room.figureHeadDrawer = function(unit, cx, cy) ... end   -- the head in the bubble
--   BOBBA.room.figureColor = function(unit) return 0xRRGGBB end      -- its shirt colour

BOBBA.room = BOBBA.room or { units = {} }
local R = BOBBA.room
local V = BOBBA.view
local P = BOBBA.platform

local C = R.chatState or { bubbles = {}, nextId = 1 }
R.chatState = C

-- Sizes are Habbo's pixels; everything is drawn C.SCALE times as big: the screen's size (V.uiScale,
-- the size rooms open at). Like Nitro, it stays that size when the room is zoomed.
-- (its own copy of the rule too: GMod's live reload can load this file before the new view.lua)
function C.scaleFor(h)
	if V.uiScale then return V.uiScale(h) end
	return math.max(1, math.floor(h / 720))
end
C.MAX_LENGTH = 100
C.SCROLL_EVERY = 6        -- seconds (nitro-react: normal scroll speed)
C.SCROLL_BY = 15          -- pixels
C.AREA = 0.40             -- the top 40% of the screen (chat.viewer.height.percentage)
-- A new bubble starts at the bottom of that area (Nitro), or higher, over the head of whoever talks
-- when they stand higher up: it never covers them. (A standing Habbo avatar is about 100 pixels
-- tall from its feet to the top of its head.)
C.HEAD_HEIGHT = 100
C.HEAD_GAP = 4
C.MAX_WIDTH = 350         -- a normal bubble's widest (RoomChatSettings.CHAT_BUBBLE_WIDTH_NORMAL)
-- nitro-react's ChatWidgetView.scss: .chat-bubble { font-size: 14px; min-height: 26px; border-image
-- outset 2px at the top }, .chat-content { margin-left: 27px; padding: 5px 6px 5px 4px; line-height: 1 },
-- the name's margin-right .25rem, .pointer { bottom: -5px }, .user-image: the head at half size,
-- in the middle of a 45 x 65 box at (-9.25, -15)
C.FONT_SIZE = 14
C.LINE_H = 14
C.PAD = { 31, 5, 6, 5 }   -- left (27 + 4), top, right, bottom
C.MIN_H = 26
C.OUTSET_TOP = 2
C.NAME_GAP = 4
C.HEAD = { 13.25, 17.5 }
C.COLOR_W = 30
-- Nitro's "Ubuntu" is Ubuntu Condensed (see ui.lua). GMod's font size is the whole height of its
-- letters (ascent + descent: 1.121 of the font's size in CSS); line-height 1 puts that height's
-- middle in the middle of a 14 pixel line
C.FONT = "Ubuntu Condensed"
C.UBUNTU_CELL = 1.121

local S, IS, FONT_PX, TEXT_TOP, LINE_H, INPUT_W, INPUT_H, F
local made = {}
local INPUT_TEXT_PX = 14.4
local function fonts()
	if not made[F.chat] then
		made[F.chat] = true
		surface.CreateFont(F.chat, { font = C.FONT, size = FONT_PX, weight = 500, antialias = true, extended = true })
		surface.CreateFont(F.bold, { font = C.FONT, size = FONT_PX, weight = 800, antialias = true, extended = true })
		surface.CreateFont(F.italic, { font = C.FONT, size = FONT_PX, weight = 500, italic = true, antialias = true, extended = true })
		surface.CreateFont(F.input, { font = C.FONT, size = math.floor(INPUT_TEXT_PX * C.UBUNTU_CELL * IS + 0.5), weight = 500, antialias = true, extended = true })
	end
	return F
end
-- (sets the sizes for the screen; again when the game's resolution changes)
-- the input is part of the toolbar: it has the UI's size (BOBBA.ui.scale), not the room's
function C.inputScaleFor(h)
	if BOBBA.ui and BOBBA.ui.scale then return BOBBA.ui.scale(h) end
	return math.max(1, math.floor(h / 1080 * 4 + 0.5) / 4)
end
function C.setScale(scale, inputScale)
	S = scale
	IS = inputScale or C.inputScaleFor(ScrH())
	C.SCALE, R.chatScale = S, S
	FONT_PX = math.floor(C.FONT_SIZE * C.UBUNTU_CELL * S + 0.5)
	TEXT_TOP = -(C.UBUNTU_CELL - 1) / 2 * C.FONT_SIZE * S
	LINE_H = C.LINE_H * S
	INPUT_W, INPUT_H = 420 * IS, 32 * IS
	-- (the size in the names: GMod keeps a font's first size until the game restarts, so a new size
	-- needs a new name)
	-- (made when first used, not now: right after a game start the hotel's font file isn't ready yet
	-- while this file loads, and GMod would fall back to Tahoma for the whole session)
	F = { chat = "BobbaChatU" .. FONT_PX, bold = "BobbaChatUBold" .. FONT_PX, italic = "BobbaChatUItalic" .. FONT_PX, input = "BobbaChatUIn" .. IS }
	-- bubbles already up keep their size; the input is made again at the new size
	if IsValid(C.input) then C.input:Remove() C.input = nil end
end
C.setScale(C.scaleFor(ScrH()))
hook.Add("OnScreenSizeChanged", "bobba.chat", function() C.setScale(C.scaleFor(ScrH())) end)

-- bubbles made and drawn at another size while fn runs (the chat history window: the UI's size,
-- not the room's)
function C.atScale(scale, fn)
	local saved = { S, FONT_PX, TEXT_TOP, LINE_H, F, C.SCALE, R.chatScale }
	S = scale
	C.SCALE, R.chatScale = S, S
	FONT_PX = math.floor(C.FONT_SIZE * C.UBUNTU_CELL * S + 0.5)
	TEXT_TOP = -(C.UBUNTU_CELL - 1) / 2 * C.FONT_SIZE * S
	LINE_H = C.LINE_H * S
	F = { chat = "BobbaChatU" .. FONT_PX, bold = "BobbaChatUBold" .. FONT_PX, italic = "BobbaChatUItalic" .. FONT_PX, input = saved[5].input }
	local ok, err = pcall(fn)
	S, FONT_PX, TEXT_TOP, LINE_H, F, C.SCALE, R.chatScale = saved[1], saved[2], saved[3], saved[4], saved[5], saved[6], saved[7]
	if not ok then ErrorNoHalt("[Bobba] chat: " .. tostring(err) .. "\n") end
end

-- --- sending --------------------------------------------------------------------------------------
-- nitro-react's ChatInputView.sendChatValue
function C.send(value, shift)
	if not value or value == "" then return "" end
	local kind = shift and "shout" or "talk"
	local parts = {}
	-- (split at each space, like value.split(' '): two spaces stay two spaces)
	for w in (value .. " "):gmatch("(.-) ") do parts[#parts + 1] = w end
	local to, keep = nil, ""
	local first = (parts[1] or ""):lower()
	if first == ":whisper" or first == ":tell" then
		kind = "whisper"
		to = parts[2]
		keep = parts[1] .. " " .. (to or "") .. " "
		table.remove(parts, 1)
		table.remove(parts, 1)
	elseif first == ":shout" then
		kind = "shout"
		table.remove(parts, 1)
	elseif first == ":speak" then
		kind = "talk"
		table.remove(parts, 1)
	end
	local text = table.concat(parts, " ")
	if text ~= "" and utf8.len(text) and utf8.len(text) <= C.MAX_LENGTH then
		P.send("room.chat", { text = text, kind = kind, to = to })
	end
	-- a whisper keeps the whisper part, ready for the next one
	return keep
end

-- --- the bubbles ----------------------------------------------------------------------------------
local function measure(font, text)
	surface.SetFont(font)
	return surface.GetTextSize(text)
end

-- the words of "name: text" in lines no wider than maxW: { { { text, font }, ... }, ... }
-- (nitro-react: .chat-bubble { word-break: break-word }: a word too long for a whole line is
-- broken between its letters, starting in the room left on the line it's on)
local function wrap(name, text, kind, maxW)
	fonts()
	local msgFont = (kind == "shout") and F.bold or ((kind == "whisper") and F.italic or F.chat)
	local words = {}
	if name then words[#words + 1] = { name .. ": ", F.bold, name = true, gap = C.NAME_GAP * S } end
	for w in text:gmatch("%S+") do words[#words + 1] = { w .. " ", msgFont } end
	local lines, line, lineW = {}, {}, 0
	local maxLine = 0
	-- a line's width without the space after its last word
	local function finish()
		local last = line[#line]
		local w = lineW
		if last and last[1]:sub(-1) == " " then w = w - measure(last[2], " ") end
		if w > maxLine then maxLine = w end
		lines[#lines + 1] = line
		line, lineW = {}, 0
	end
	local function put(textPart, font, width, isName)
		line[#line + 1] = { textPart, font, x = lineW, name = isName }
		lineW = lineW + width
	end
	for _, w in ipairs(words) do
		local ww = measure(w[2], w[1]) + (w.gap or 0)
		local bare = measure(w[2], (w[1]:gsub(" $", ""))) + (w.gap or 0)
		if bare <= maxW then
			if lineW > 0 and lineW + bare > maxW then finish() end
			put(w[1], w[2], ww, w.name)
		else
			-- too long for any line: letter by letter, as much as fits on each line
			local piece = ""
			for ch in w[1]:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
				local try = piece .. ch
				if ch ~= " " and lineW + measure(w[2], try) > maxW and (piece ~= "" or lineW > 0) then
					if piece ~= "" then put(piece, w[2], measure(w[2], piece), w.name) end
					finish()
					piece = ch
				else
					piece = try
				end
			end
			if piece ~= "" then put(piece, w[2], measure(w[2], piece), w.name) end
		end
	end
	if #line > 0 then finish() end
	return lines, math.max(1, maxLine)
end


-- a bubble's look and size (not where it is): u's name and colour, its text, at most maxW wide
function C.makeBubble(u, text, kind, style, maxW)
	local skin = R.chatSkin and R.chatSkin(style or 0) or nil
	local anonymous = skin and skin.anonymous
	local m = C.PAD
	local lines, textW = wrap((not anonymous) and (u and u.name or "?") or nil, text, kind, ((maxW or C.MAX_WIDTH) - m[1] - m[3]) * S)
	local w = (m[1] + m[3]) * S + textW
	local h = math.max(C.MIN_H * S, (m[2] + m[4]) * S + #lines * LINE_H)
	return {
		unit = u and u.id, name = u and u.name, text = text, kind = kind, style = style or 0, skin = skin,
		lines = lines, width = math.floor(w + 0.5), height = h,
		color = (u and R.figureColor) and R.figureColor(u) or 0xC8C8C8,
	}
end

-- The chat history (nitro-react's ChatHistoryView): every message and room since the game started,
-- the last 100 (chat.history.max.items)
C.history = C.history or {}
C.HISTORY_MAX = 100
function C.addHistory(entry)
	entry.time = os.date("%H:%M")
	C.history[#C.history + 1] = entry
	while #C.history > C.HISTORY_MAX do table.remove(C.history, 1) end
	BOBBA.events.emit("chatHistory", entry)
end

-- a new bubble: its size, and where it starts (over the one talking, at the bottom of the chat area)
local function addBubble(u, text, kind, style)
	C.addHistory({ type = "chat", unit = u and u.id, name = u and u.name, text = text, kind = kind, style = style or 0,
		color = (u and R.figureColor) and R.figureColor(u) or 0xC8C8C8 })
	local skin = R.chatSkin and R.chatSkin(style or 0) or nil
	local anonymous = skin and skin.anonymous
	local m = C.PAD
	local lines, textW = wrap((not anonymous) and (u.name or "?") or nil, text, kind, (C.MAX_WIDTH - m[1] - m[3]) * S)
	local w = (m[1] + m[3]) * S + textW
	local h = math.max(C.MIN_H * S, (m[2] + m[4]) * S + #lines * LINE_H)
	local sx = ScrW() / 2
	local bottom = math.floor(ScrH() * C.AREA)
	if u then
		local x, y, z = R.unitPosition(u)
		local px, py, k = V.project(x, y, z)
		if px then
			sx = px
			local head = py - (C.HEAD_HEIGHT + C.HEAD_GAP) * k
			if head < bottom then bottom = math.floor(head) end
		end
	end
	local b = {
		id = C.nextId, unit = u and u.id, name = u and u.name, text = text, kind = kind, style = style or 0, skin = skin,
		lines = lines, width = math.floor(w + 0.5), height = h,
		left = math.floor(sx - w / 2), top = bottom - h, drawTop = nil, born = SysTime(),
		color = (u and R.figureColor) and R.figureColor(u) or 0xC8C8C8, panX = V.panX or 0,
	}
	C.nextId = C.nextId + 1
	C.bubbles[#C.bubbles + 1] = b
	-- ChatWidgetView.makeRoom (free flow): push up whatever the new one covers
	b.skipMovement = true
	C.pushUp(b, 0, { [b] = true })
	C.removeHidden()
end

-- DoChatsOverlap
local function overlap(a, b, addTop)
	return not ((a.left + a.width < b.left) or (a.left > b.left + b.width) or (a.top + a.height < b.top + addTop) or (a.top > b.top + addTop + b.height))
end

-- ChatWidgetView.checkOverlappingChats
function C.pushUp(chat, moved, done)
	local index
	for i, b in ipairs(C.bubbles) do if b == chat then index = i end end
	if not index then return end
	for i = index - 1, 1, -1 do
		local c = C.bubbles[i]
		if c and c ~= chat and not done[c] and not ((c.top + c.height) - moved > chat.top + chat.height) then
			if overlap(chat, c, -moved) then
				local amount = math.abs((c.top + c.height) - chat.top)
				done[c] = true
				c.top = c.top - amount
				c.skipMovement = true
				C.pushUp(c, amount, done)
			end
		end
	end
end

function C.removeHidden()
	local keep = {}
	for _, b in ipairs(C.bubbles) do
		if b.top > -b.height * 2 then keep[#keep + 1] = b end
	end
	C.bubbles = keep
end

local function moveAllUp(amount)
	amount = amount * S
	for _, b in ipairs(C.bubbles) do
		if b.skipMovement then b.skipMovement = false else b.top = b.top - amount end
	end
	C.removeHidden()
end

-- --- drawing ----------------------------------------------------------------------------------------
local mats = {}
local function mat(path)
	local m = mats[path]
	if not m then m = P.dataMaterial(path, "noclamp") mats[path] = m end
	return m
end

-- part of a picture (sx, sy, sw, sh in its pixels) into a rectangle on screen
local function blit(img, sx, sy, sw, sh, x, y, w, h)
	if sw <= 0 or sh <= 0 or w <= 0 or h <= 0 then return end
	surface.DrawTexturedRectUV(x, y, w, h, sx / img.texWidth, sy / img.texHeight, (sx + sw) / img.texWidth, (sy + sh) / img.texHeight)
end

-- a picture cut in nine (its corners kept, its middle stretched) over x, y, w, h
local function nineSlice(img, slice, x, y, w, h)
	surface.SetMaterial(mat(img.path))
	local cols = { { 0, slice[1] }, { slice[1], slice[3] }, { slice[1] + slice[3], img.width - slice[1] - slice[3] } }
	local rows = { { 0, slice[2] }, { slice[2], slice[4] }, { slice[2] + slice[4], img.height - slice[2] - slice[4] } }
	local dw = { cols[1][2] * S, w - (cols[1][2] + cols[3][2]) * S, cols[3][2] * S }
	local dh = { rows[1][2] * S, h - (rows[1][2] + rows[3][2]) * S, rows[3][2] * S }
	local dy = y
	for r = 1, 3 do
		local dx = x
		for c = 1, 3 do
			blit(img, cols[c][1], rows[r][1], cols[c][2], rows[r][2], dx, dy, dw[c], dh[r])
			dx = dx + dw[c]
		end
		dy = dy + dh[r]
	end
end

local function rgb(c) return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256 end

local function drawLines(b, x, y, textColor)
	local tr, tg, tb = rgb(textColor)
	for i, line in ipairs(b.lines) do
		for _, w in ipairs(line) do
			local r, g, bl = tr, tg, tb
			if b.kind == "whisper" and not w.name then r, g, bl = 0x59, 0x59, 0x59 end
			draw.SimpleText(w[1], w[2], x + w.x, math.floor(y + TEXT_TOP + (i - 1) * LINE_H + 0.5), Color(r, g, bl), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		end
	end
end

local function drawBubble(b, x, y)
	local s = b.skin
	local w, h = b.width, b.height
	local u = b.unit and R.units[b.unit]
	if s then
		render.PushFilterMag(TEXFILTER.POINT)
		render.PushFilterMin(TEXFILTER.POINT)
		surface.SetDrawColor(255, 255, 255, 255)
		-- the picture reaches 2 pixels above the bubble (border-image-outset)
		local oy, oh = y - C.OUTSET_TOP * S, h + C.OUTSET_TOP * S
		nineSlice(s.base, s.slice, x, oy, w, oh)
		if s.color then
			local r, g, bl = rgb(b.color)
			surface.SetDrawColor(r, g, bl, 255)
			-- the colour part keeps its width, stretches with the bubble's height
			surface.SetMaterial(mat(s.color.path))
			local top, bottom = s.slice[2], s.color.height - s.slice[2] - s.slice[4]
			local cx, cy = x + (s.colorXY and s.colorXY[1] or 0) * S, oy + (s.colorXY and s.colorXY[2] or 0) * S
			local cw = s.color.width * S
			blit(s.color, 0, 0, s.color.width, top, cx, cy, cw, top * S)
			blit(s.color, 0, top, s.color.width, s.slice[4], cx, cy + top * S, cw, oh - (top + bottom) * S)
			blit(s.color, 0, top + s.slice[4], s.color.width, bottom, cx, cy + oh - bottom * S, cw, bottom * S)
		end
		surface.SetDrawColor(255, 255, 255, 255)
		if s.pointer then
			surface.SetMaterial(mat(s.pointer.path))
			local py = y + h - S
			local pw = s.pointer.width * S
			blit(s.pointer, 0, 0, s.pointer.width, s.pointer.height, x + math.floor((w - pw) / 2 / S) * S, py, pw, s.pointer.height * S)
		end
		render.PopFilterMin()
		render.PopFilterMag()
		-- the head where Habbo's style puts the face (faceXY: level with the arrow), not Nitro's
		-- lower spot
		if not s.anonymous and u and R.figureHeadDrawer then
			local face = s.faceXY or C.HEAD
			pcall(R.figureHeadDrawer, u, x + face[1] * S, y + face[2] * S)
		end
		drawLines(b, x + C.PAD[1] * S, y + C.PAD[2] * S, s.textColor or 0)
		return
	end
	-- plain: a white rounded bubble with a dark edge, the colour part on the left, a little pointer
	draw.RoundedBox(8, x - S, y - S, w + 2 * S, h + 2 * S, Color(30, 30, 30))
	draw.RoundedBox(7, x, y, w, h, Color(250, 250, 250))
	local r, g, bl = rgb(b.color)
	draw.RoundedBoxEx(7, x, y, C.COLOR_W * S, h, Color(r, g, bl), true, false, true, false)
	draw.NoTexture()
	surface.SetDrawColor(250, 250, 250, 255)
	surface.DrawPoly({ { x = x + w / 2 - 5 * S, y = y + h }, { x = x + w / 2 + 5 * S, y = y + h }, { x = x + w / 2, y = y + h + 6 * S } })
	if u and R.figureHeadDrawer then pcall(R.figureHeadDrawer, u, x + C.HEAD[1] * S, y + C.HEAD[2] * S) end
	drawLines(b, x + C.PAD[1] * S, y + C.PAD[2] * S, 0)
end

C.drawBubble = drawBubble

-- every frame, over the room
function C.draw()
	if V.mode ~= "room" then return end
	local now = SysTime()
	C.lastScroll = C.lastScroll or now
	while now - C.lastScroll >= C.SCROLL_EVERY do
		C.lastScroll = C.lastScroll + C.SCROLL_EVERY
		moveAllUp(C.SCROLL_BY)
	end
	-- the room dragged sideways: the bubbles go with it (nitro-react RoomDragEvent)
	local panX = V.panX or 0
	local dt = math.min(RealFrameTime(), 0.1)
	for _, b in ipairs(C.bubbles) do
		if b.panX ~= panX then b.left = b.left + (panX - b.panX) b.panX = panX end
		-- (CSS: top moves over 0.2 s)
		if not b.drawTop then b.drawTop = b.top end
		b.drawTop = b.drawTop + (b.top - b.drawTop) * math.min(1, dt / 0.2 * 3)
		if math.abs(b.drawTop - b.top) < 0.5 then b.drawTop = b.top end
		drawBubble(b, math.floor(b.left), math.floor(b.drawTop))
	end
end

P.receive("room.chat", function(_, data)
	local u = R.units[data.unit]
	if not u then return end
	-- Nitro: the avatar talks for (length / 10) seconds
	u.talkUntil = SysTime() + #data.text / 10
	addBubble(u, data.text, data.kind, data.style)
end)

P.receive("room.chat.flood", function(_, data)
	C.floodUntil = SysTime() + (tonumber(data.seconds) or 10)
end)

-- a new room: no bubbles from the last one (and the history says which room it is)
BOBBA.events.on("roomShown", "bobba.chat.clear", function(data)
	C.bubbles = {}
	if data and data.name then C.addHistory({ type = "room", name = data.name }) end
end)

-- --- the input ------------------------------------------------------------------------------------

-- nitro-react's ChatInputView, in the toolbar (hud.lua says where): 40 high, a 2px black border with
-- 8px corners, #EDEDED with a white line along the top, the text 14.4px with 12 to its left, Habbo's
-- chat-styles icon 10 from the right; as wide as what's typed (at least 173 for the text)
local function createInput()
	if IsValid(C.input) then return C.input end
	local frame = vgui.Create("EditablePanel")
	frame:SetSize(INPUT_W, INPUT_H)
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(true)
	frame:SetMouseInputEnabled(true)
	frame.Paint = function(self, w, h)
		draw.RoundedBox(math.floor(8 * IS), 0, 0, w, h, Color(0, 0, 0, 255))
		draw.RoundedBox(math.floor(6 * IS), math.floor(2 * IS), math.floor(2 * IS), w - math.floor(4 * IS), h - math.floor(4 * IS), Color(237, 237, 237, 255))
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawRect(math.floor(2 * IS) + math.floor(4 * IS), math.floor(3 * IS), w - math.floor(4 * IS) - math.floor(8 * IS), math.floor(5 * IS))
		local U = BOBBA.ui
		local ic = U and U.icon and U.icon("chat-styles")
		if ic and ic.material then
			local iw, ih = math.floor(ic.width * IS + 0.5), math.floor(ic.height * IS + 0.5)
			render.PushFilterMag(TEXFILTER.POINT)
			render.PushFilterMin(TEXFILTER.POINT)
			surface.SetMaterial(ic.material)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawTexturedRectUV(w - math.floor((2 + 10) * IS) - iw, math.floor((h - ih) / 2), iw, ih, 0, 0, ic.u, ic.v)
			render.PopFilterMin()
			render.PopFilterMag()
		end
	end
	fonts()
	local entry = vgui.Create("DTextEntry", frame)
	entry:Dock(FILL)
	entry:DockMargin(math.floor(14 * IS), math.floor(10 * IS), math.floor((2 + 10 + 17 + 10) * IS), math.floor(10 * IS))
	entry:SetFont(F.input)
	entry:SetPaintBackground(false)
	entry:SetPlaceholderText(BOBBA.ui and BOBBA.ui.text and BOBBA.ui.text("widgets.chatinput.default", "Click here to chat...") or "Click here to chat...")
	entry:SetUpdateOnType(true)
	entry.AllowInput = function(self, ch)
		if self.dropNextR then
			self.dropNextR = false
			if ch == "r" or ch == "R" then return true end
		end
		-- at most 100 characters
		local t = self:GetValue() or ""
		return (utf8.len(t) or #t) >= C.MAX_LENGTH
	end
	entry.OnKeyCodeTyped = function(self, code)
		if code == KEY_ENTER or code == KEY_PAD_ENTER then
			if C.floodUntil and SysTime() < C.floodUntil then return true end
			local keep = C.send(self:GetValue(), input.IsShiftDown())
			self:SetText(keep)
			self:SetCaretPos(#keep)
			return true
		end
		-- turning the furni being placed (when there's nothing typed)
		if code == KEY_R and (self:GetValue() or "") == "" and (R.turnedAt or 0) < SysTime() - 0.2 and R.pressR and R.pressR() then
			-- (and the "r" isn't typed)
			self.dropNextR = true
			return true
		end
	end
	entry.Paint = function(self, w, h)
		if C.floodUntil and SysTime() < C.floodUntil then
			-- (Text variant="danger")
			draw.SimpleText(string.format("Please wait %d seconds...", math.ceil(C.floodUntil - SysTime())), F.input, 0, h / 2, Color(220, 53, 69), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			return
		end
		self:DrawTextEntryText(Color(0, 0, 0), Color(80, 140, 230), Color(0, 0, 0))
		if (self:GetValue() or "") == "" then
			-- (the browser's placeholder grey)
			draw.SimpleText(self:GetPlaceholderText(), F.input, 2, h / 2, Color(117, 117, 117), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	frame.entry = entry
	C.input = frame
	return frame
end

-- the input sits in the toolbar while a room is shown, and keeps the keyboard (so typing anywhere goes
-- into it, like Habbo) unless something else wants it
hook.Add("Think", "bobba.chat", function()
	local show = V.mode == "room" and V.room ~= nil and not (BOBBA.loading and BOBBA.loading.active)
	if not show then
		if IsValid(C.input) then C.input:SetVisible(false) end
		return
	end
	-- (the UI's size can change: bobba_ui_scale)
	local want = C.inputScaleFor(ScrH())
	if want ~= IS then C.setScale(S, want) end
	local f = createInput()
	f:SetVisible(true)
	-- as wide as what's typed (the ::after copy of it plus two spaces)
	surface.SetFont(F.input)
	local tw = surface.GetTextSize((f.entry:GetValue() or "") .. "  ") / IS
	local x, y, w, h
	if BOBBA.hud and BOBBA.hud.chatInput then
		x, y, w, h = BOBBA.hud.chatInput(ScrW() / IS, ScrH() / IS, tw)
	else
		w, h = 2 + 10 + math.max(173, tw) + 10 + 17 + 10 + 2, 40
		x, y = (ScrW() / IS - w) / 2, ScrH() / IS - h - 14
	end
	local X, Y = math.floor(x * IS + 0.5), math.floor(y * IS + 0.5)
	local W, H = math.floor((x + w) * IS + 0.5) - X, math.floor((y + h) * IS + 0.5) - Y
	if f:GetWide() ~= W or f:GetTall() ~= H then f:SetSize(W, H) end
	f:SetPos(X, Y)
	-- while a furni is being placed the input lets go of the keyboard, so R turns it (GMod doesn't
	-- see keys while a text box has them); afterwards it takes it back
	if R.placing then
		if f.hasKeyboard ~= false then
			f.hasKeyboard = false
			f:SetKeyboardInputEnabled(false)
			f.entry:KillFocus()
		end
		return
	end
	if f.hasKeyboard == false then
		f.hasKeyboard = true
		f:SetKeyboardInputEnabled(true)
	end
	local focus = vgui.GetKeyboardFocus()
	if not gui.IsGameUIVisible() and not gui.IsConsoleVisible() and (focus == nil or focus == f or focus == V.panel) then
		f.entry:RequestFocus()
	end
end)

-- GMod's own chat key would open GMod's chat box over the room: in a room, typing is the hotel's chat
hook.Add("PlayerBindPress", "bobba.chat", function(_, bind)
	if V.mode == "room" and bind and bind:find("messagemode", 1, true) then return true end
end)
