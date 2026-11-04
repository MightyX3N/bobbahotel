-- Steering your avatar with keys or a controller, and the interact button (client). The server walks
-- you tile after tile while a direction is held (hotel/roomlive.lua: room.steer, room.interact).
--
-- Keys (Settings, "Movement keys"; bobba_setting_movekeys):
--   0  the arrow keys; typing goes into the chat as in Habbo (the default)
--   1  WASD and the arrow keys while the chat box is empty; once something is typed the letters are
--      the chat's. To start a message with w, a, s or d, press Enter first.
--   2  WASD and the arrow keys always; Enter (or T) opens the chat, Enter sends and closes it
-- Directions (bobba_setting_moveaxes): 0 as on the screen (up is up), 1 along the room's sides.
-- Interact: a key (Space unless changed; also E with setting 2) uses what's highlighted next to you:
-- sit, lie down, switch, open a gift, an avatar's menu; another (Tab) picks the next thing. With more
-- than one thing near, a list over your avatar shows them. The keys and the controller's buttons are
-- chosen in Settings > Keys and controller (S.KEYS, S.PAD; bobba_key_* / bobba_pad_*).
-- A controller (the desktop app; GMod through Steam Input) steers with BOBBA.steering.setPad(x, y).

BOBBA.steering = BOBBA.steering or {}
local S = BOBBA.steering
local P = BOBBA.platform
local R = BOBBA.room
local V = BOBBA.view

S.keysVar = CreateClientConVar("bobba_setting_movekeys", "0", true, false, "Movement keys: 0 arrows, 1 WASD while the chat is empty, 2 WASD (Enter to chat)")
S.axesVar = CreateClientConVar("bobba_setting_moveaxes", "0", true, false, "Movement directions: 0 as on the screen, 1 along the room's sides")

-- the keys and controller buttons for each action (chosen in Settings; the defaults here)
S.KEYS = {
	{ id = "use", default = KEY_SPACE, label = { "bobba.controls.use", "Use what's next to you" } },
	{ id = "next", default = KEY_TAB, label = { "bobba.controls.next", "Pick the next thing" } },
	{ id = "chat", default = KEY_T, label = { "bobba.controls.chat", "Open the chat (WASD, Enter to chat)" } },
}
S.PAD = {
	{ id = "use", default = "a", label = { "bobba.controls.use", "Use what's next to you" } },
	{ id = "next", default = "leftshoulder", label = { "bobba.controls.next", "Pick the next thing" } },
	{ id = "rotate", default = "rightshoulder", label = { "bobba.controls.rotate", "Turn furni" } },
	{ id = "click", default = "x", label = { "bobba.controls.click", "Click" } },
	{ id = "rightclick", default = "b", label = { "bobba.controls.rightclick", "Right-click" } },
	{ id = "menu", default = "y", label = { "bobba.controls.menu", "Menu wheel (hold)" } },
	{ id = "say", default = "back", label = { "bobba.controls.say", "Quick messages (hold)" } },
	{ id = "chat", default = "start", label = { "bobba.controls.padchat", "Chat" } },
}
for _, k in ipairs(S.KEYS) do k.var = CreateClientConVar("bobba_key_" .. k.id, tostring(k.default), true, false) end
for _, k in ipairs(S.PAD) do k.var = CreateClientConVar("bobba_pad_" .. k.id, k.default, true, false) end
function S.key(id)
	for _, k in ipairs(S.KEYS) do if k.id == id then return k.var:GetInt() end end
end
function S.padButton(id)
	for _, k in ipairs(S.PAD) do if k.id == id then return k.var:GetString() end end
end

-- a binding being chosen: { kind = "key" / "pad", id } (the next key or button pressed is it)
function S.startCapture(kind, id) S.capture = { kind = kind, id = id, at = SysTime() } end
-- sets it; another action that had that key gets this one's old key (no two on one key)
function S.bind(kind, id, value)
	local list = kind == "key" and S.KEYS or S.PAD
	local this
	for _, k in ipairs(list) do if k.id == id then this = k end end
	if not this then return end
	local old = this.var:GetString()
	for _, k in ipairs(list) do
		if k ~= this and k.var:GetString() == tostring(value) then RunConsoleCommand(k.var:GetName(), old) end
	end
	RunConsoleCommand(this.var:GetName(), tostring(value))
	S.capture = nil
end
function S.resetBindings(kind)
	for _, k in ipairs(kind == "key" and S.KEYS or S.PAD) do RunConsoleCommand(k.var:GetName(), tostring(k.default)) end
end

-- names to show
local PAD_NAMES = { a = "A", b = "B", x = "X", y = "Y", leftshoulder = "LB", rightshoulder = "RB", back = "View / Back",
	start = "Menu / Start", leftstick = "Left stick", rightstick = "Right stick", guide = "Guide", dpup = "D-pad up",
	dpdown = "D-pad down", dpleft = "D-pad left", dpright = "D-pad right", triggerleft = "LT", triggerright = "RT" }
function S.padName(b) return PAD_NAMES[b] or tostring(b) end
function S.keyName(code)
	local n = input.GetKeyName and input.GetKeyName(code) or nil
	if not n or n == "" then return "?" end
	n = tostring(n):gsub("_", " ")
	return n:sub(1, 1):upper() .. n:sub(2):lower()
end

S.held = S.held or {}   -- from the chat box's key events: code -> direction
S.typing = S.typing or false -- (setting 1: Enter pressed on an empty box, letters are the chat's)
S.chatOpen = S.chatOpen or false -- (setting 2: the chat box has the keyboard)
S.cycle = S.cycle or 0
S.lastUsed = S.lastUsed or 0
-- what was used last: "keys", "pad" or "mouse" (the list and the highlight follow it: the keys' or the
-- controller's names in the hint, and nothing after a mouse click)
S.device = S.device or "mouse"
function S.setDevice(d)
	S.device = d
	if d ~= "mouse" then S.lastUsed = SysTime() end
end

local ARROWS = { [KEY_UP] = "up", [KEY_DOWN] = "down", [KEY_LEFT] = "left", [KEY_RIGHT] = "right" }
local WASD = { [KEY_W] = "up", [KEY_S] = "down", [KEY_A] = "left", [KEY_D] = "right" }

function S.mode() return math.Clamp(S.keysVar:GetInt(), 0, 2) end

-- the room's own setting (rooms can be for clicking only or steering only)
function S.roomMovement()
	local a = R.current and R.current.access
	return a and tonumber(a.movement) or 0
end
function S.allowed() return V.mode == "room" and R.current ~= nil and S.roomMovement() ~= 1 end

-- does this key steer now? (empty: the chat box has nothing typed)
local function steersFor(code, empty)
	if ARROWS[code] then return ARROWS[code] end
	local m = S.mode()
	if WASD[code] and (m == 2 or (m == 1 and empty and not S.typing)) then return WASD[code] end
	return nil
end

-- the chat box's keys (it has the keyboard; GMod doesn't see keys then): true = dealt with
function S.keyTyped(entry, code)
	local empty = (entry:GetValue() or "") == ""
	local m = S.mode()
	-- (a key being chosen in Settings)
	if S.capture and S.capture.kind == "key" then
		S.bind("key", S.capture.id, code)
		entry.steerDrop = SysTime() + 0.15
		return true
	end
	if (code == KEY_ENTER or code == KEY_PAD_ENTER) and empty then
		if m == 1 and not S.typing then S.typing = true return true end
		if m == 2 then S.closeChat() return true end
	end
	-- (setting 2: the box has the keyboard only while chatting, so no steering from it)
	if m == 2 then return false end
	-- (the arrow keys move the caret once something is typed)
	local dir = empty and S.allowed() and steersFor(code, true)
	if dir then
		S.held[code] = dir
		S.heldAt = SysTime()
		if WASD[code] then entry.steerDrop = SysTime() + 0.15 end
		S.setDevice("keys")
		return true
	end
	if empty and not S.typing and code == S.key("use") then
		entry.steerDrop = SysTime() + 0.15
		S.interact()
		return true
	end
	if empty and not S.typing and code == S.key("next") then
		entry.steerDrop = SysTime() + 0.15
		S.next()
		return true
	end
	return false
end

function S.keyReleased(code)
	S.releaseSeen = true
	S.held[code] = nil
end

-- (in case a text box never says a key was let go: until one has, keys count as let go when the
-- key's repeats stop coming)
S.REPEAT_TIMEOUT = 1.1
local function expireHeld()
	if S.releaseSeen or not next(S.held) then return end
	if SysTime() - (S.heldAt or 0) > S.REPEAT_TIMEOUT then S.held = {} end
end

-- a letter the key above dealt with isn't typed
function S.blockChar(entry, ch)
	local sw = S.swallow
	if sw then
		S.swallow = nil
		if SysTime() < sw.untilT and ch:lower() == sw.ch then return true end
	end
	if entry.steerDrop then
		local drop = entry.steerDrop
		entry.steerDrop = nil
		if SysTime() < drop then return true end
	end
	return false
end

-- setting 2: the chat box only has the keyboard while it's open
function S.chatWanted() return S.mode() ~= 2 or S.chatOpen end
function S.openChat(key)
	S.chatOpen = true
	S.held = {}
	-- (the T that opened it isn't typed into it)
	if key then S.swallow = { ch = key, untilT = SysTime() + 0.3 } end
end
function S.closeChat()
	S.chatOpen = false
	local f = R.chatState and R.chatState.input
	if IsValid(f) and IsValid(f.entry) then f.entry:KillFocus() end
end

-- what the empty chat box says (nil: Habbo's own "Click here to chat...")
function S.placeholder()
	local m = S.mode()
	if m == 1 and S.typing then return BOBBA.ui.text("bobba.chatinput.typing", "Type your message...") end
	if m == 2 and not S.chatOpen then return BOBBA.ui.text("bobba.chatinput.enter", "Press Enter to chat...") end
	return nil
end

-- a controller's stick (x right, y down, -1 .. 1), or nil
function S.setPad(x, y)
	if not x then S.pad = nil return end
	S.pad = { x, y }
	if math.abs(x) > 0.4 or math.abs(y) > 0.4 then S.setDevice("pad") end
end

-- --- the direction now ------------------------------------------------------------------------------
local function sign(v) if v > 0.25 then return 1 elseif v < -0.25 then return -1 end return 0 end

-- a direction on the screen (sx right, sy down) as a step on the tiles
function S.toTiles(sx, sy)
	if S.axesVar:GetInt() == 1 then return sign(sx), sign(sy) end
	-- (a tile right is right-down on the screen, a tile down is left-down)
	return sign((sx + sy) / 2), sign((sy - sx) / 2)
end

local function typingSomewhere()
	local f = vgui.GetKeyboardFocus and vgui.GetKeyboardFocus()
	return IsValid(f) and f.GetCaretPos ~= nil
end

function S.direction()
	local sx, sy = 0, 0
	local dirs = {}
	for _, d in pairs(S.held) do dirs[d] = true end
	-- (nothing typing: the keys themselves; e.g. setting 2, or while a furni is placed)
	if not typingSomewhere() then
		for code, d in pairs(ARROWS) do if input.IsKeyDown(code) then dirs[d] = true end end
		if S.mode() >= 1 then
			for code, d in pairs(WASD) do if input.IsKeyDown(code) then dirs[d] = true end end
		end
	end
	if dirs.up then sy = sy - 1 end
	if dirs.down then sy = sy + 1 end
	if dirs.left then sx = sx - 1 end
	if dirs.right then sx = sx + 1 end
	if sx == 0 and sy == 0 and S.pad then
		local px, py = S.pad[1], S.pad[2]
		if px * px + py * py > 0.4 * 0.4 then
			-- (eight ways, by the stick's angle; the way it's going is kept until the stick is clearly
			-- in another one, so a stick between two doesn't flick back and forth)
			local a = math.atan2(py, px)
			local k = math.floor(a / (math.pi / 4) + 0.5) % 8
			local was = S.padSector
			if was and was ~= k then
				local d = math.abs(((a - was * math.pi / 4) + math.pi) % (2 * math.pi) - math.pi)
				if d < math.rad(30) then k = was end
			end
			S.padSector = k
			local c, sn = math.cos(k * math.pi / 4), math.sin(k * math.pi / 4)
			sx = c > 0.5 and 1 or (c < -0.5 and -1 or 0)
			sy = sn > 0.5 and 1 or (sn < -0.5 and -1 or 0)
		else
			S.padSector = nil
		end
	end
	if sx == 0 and sy == 0 then return 0, 0 end
	return S.toTiles(sx, sy)
end

-- --- what the interact button uses ------------------------------------------------------------------
local function me()
	local u = R.units and R.you and R.units[R.you]
	if not u then return nil end
	local t = u.to or u.from
	return u, math.floor(t.x + 0.5), math.floor(t.y + 0.5)
end

local AHEAD = { [0] = { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } }

local function footprint(it, fi)
	local w, l = fi.width or 1, fi.length or 1
	if it.dir == 2 or it.dir == 6 then w, l = l, w end
	local out = {}
	for i = 0, w - 1 do for j = 0, l - 1 do out[#out + 1] = { x = it.x + i, y = it.y + j } end end
	return out
end

-- something you can do something with (not a plain table or rug)
local function usable(fi)
	if fi.sit or fi.lay or fi.paint then return not fi.paint end
	if fi.category == "present" or fi.category == "gate" or fi.category == "teleport" then return true end
	return fi.logic ~= nil and fi.logic ~= "furniture_basic" and fi.logic ~= ""
end

-- the things next to you, best first: { kind = "item" / "unit", id, tiles = { {x, y, z} } }
function S.candidates()
	local u, x, y = me()
	if not u then return {} end
	local a = AHEAD[u.dir or 2] or { 0, 0 }
	local fx, fy = x + a[1], y + a[2]
	local list = {}
	for _, it in pairs(R.items or {}) do
		local fi = R.furniInfo and R.furniInfo(it.kind)
		if fi and usable(fi) then
			local score
			local tiles = {}
			if fi.wall or it.wall then
				local d = math.max(math.abs(it.x - x), math.abs(it.y - y))
				if d <= 2 then score = 3 + d end
				tiles[1] = { x = it.x, y = it.y, z = 0, wall = true }
			else
				for _, t in ipairs(footprint(it, fi)) do
					tiles[#tiles + 1] = { x = t.x, y = t.y, z = it.z or 0 }
					local d = math.max(math.abs(t.x - x), math.abs(t.y - y))
					local s
					if d == 0 then s = 0 elseif t.x == fx and t.y == fy then s = 1 elseif d == 1 then s = 2 end
					if s and (not score or s < score) then score = s end
				end
			end
			if score then list[#list + 1] = { kind = "item", id = it.id, score = score, tiles = tiles, item = it } end
		end
	end
	for id, o in pairs(R.units or {}) do
		if id ~= R.you then
			local t = o.to or o.from
			local ox, oy = math.floor(t.x + 0.5), math.floor(t.y + 0.5)
			local d = math.max(math.abs(ox - x), math.abs(oy - y))
			if d <= 1 then
				list[#list + 1] = { kind = "unit", id = id, score = (ox == fx and oy == fy) and 1.5 or 2.5, tiles = { { x = ox, y = oy, z = t.z or 0 } } }
			end
		end
	end
	table.sort(list, function(p, q)
		if p.score ~= q.score then return p.score < q.score end
		return tostring(p.kind) .. p.id < tostring(q.kind) .. q.id
	end)
	return list
end

function S.target()
	local list = S.candidates()
	if #list == 0 then return nil end
	return list[(S.cycle % #list) + 1]
end

function S.next(device)
	S.cycle = S.cycle + 1
	S.setDevice(device or "keys")
end

function S.interact(device)
	if V.mode ~= "room" then return end
	S.setDevice(device or "keys")
	local t = S.target()
	if not t then return end
	if t.kind == "unit" then
		R.selected = nil
		R.selectedUnit = t.id
		if BOBBA.roomWindows and BOBBA.roomWindows.selectUnit then BOBBA.roomWindows.selectUnit(t.id) end
		if R.updateInfo then R.updateInfo() end
		return
	end
	R.selected = t.id
	if R.updateInfo then R.updateInfo() end
	-- (furni that open a window instead: a trophy, a toner)
	local fi = R.furniInfo and R.furniInfo(t.item.kind)
	if not (fi and (fi.sit or fi.lay)) and R.widgets and R.widgets.open and R.widgets.open(t.item) then return end
	P.send("room.interact", { id = t.id })
end

-- --- each frame: tell the server the direction; the highlight -------------------------------------
local sent = { 0, 0 }
hook.Add("Think", "bobba.steering", function()
	-- (setting 1: typing ends when the box is empty again)
	local f = R.chatState and R.chatState.input
	local entry = IsValid(f) and f.entry or nil
	if entry then
		local text = entry:GetValue() or ""
		if text ~= "" then S.hadText = true elseif S.hadText then S.hadText = false S.typing = false end
		-- (the box lost the keyboard: its keys can't be held any more)
		if not entry:HasFocus() then S.held = {} end
	end
	-- (switched to setting 2: the chat starts closed)
	local m = S.mode()
	if m ~= S.lastMode then
		S.lastMode = m
		S.typing = false
		if m == 2 then S.closeChat() else S.chatOpen = false end
	end
	-- (a key being chosen in Settings, while no text box has the keyboard)
	if S.capture and S.capture.kind == "key" and not typingSomewhere() then
		S.capDown = S.capDown or {}
		for code = 1, 160 do
			local d = input.IsKeyDown(code)
			if d and not S.capDown[code] and SysTime() - S.capture.at > 0.2 then S.bind("key", S.capture.id, code) break end
			S.capDown[code] = d
		end
	end
	local function edge(name, down)
		S.was = S.was or {}
		local e = down and not S.was[name]
		S.was[name] = down
		return e
	end
	-- setting 2: Enter or the chat key opens the chat; clicking it does too
	if m == 2 and V.mode == "room" then
		if entry and entry:HasFocus() then S.chatOpen = true end
		if not S.chatOpen and not typingSomewhere() and not S.capture then
			local ck = input.IsKeyDown(S.key("chat"))
			if edge("chat", input.IsKeyDown(KEY_ENTER) or ck) then
				local n = S.keyName(S.key("chat")):lower()
				S.openChat(ck and #n == 1 and n or nil)
			end
		end
	end
	-- (no text box has the keyboard: the use and next keys; E uses too with setting 2)
	if V.mode == "room" and not typingSomewhere() and not S.capture then
		if edge("use", input.IsKeyDown(S.key("use")) or (m == 2 and input.IsKeyDown(KEY_E))) then S.interact() end
		if edge("next", input.IsKeyDown(S.key("next"))) then S.next() end
	end
	expireHeld()
	local dx, dy = 0, 0
	if S.allowed() then dx, dy = S.direction() end
	if dx ~= sent[1] or dy ~= sent[2] then
		sent = { dx, dy }
		if R.current then P.send("room.steer", { dx = dx, dy = dy }) end
		if dx ~= 0 or dy ~= 0 then
			-- (by the stick, or by keys)
			local stick = S.pad and (math.abs(S.pad[1]) > 0.4 or math.abs(S.pad[2]) > 0.4)
			if not stick then S.setDevice("keys") end
			S.cycle = 0
		end
	end
end)

-- the highlight: shown while steering is in use (or a controller is there), around what the
-- interact button would use
S.HIGHLIGHT_SECONDS = 10
-- shown while a controller is what's used, or for a while after keys; never after a mouse click
function S.showing()
	if S.device == "mouse" then return false end
	if S.device == "pad" and S.padConnected then return true end
	return SysTime() - (S.lastUsed or 0) < S.HIGHLIGHT_SECONDS
end
-- (clicking the room: the mouse is what's used)
BOBBA.events.on("roomClick", "bobba.steering.mouse", function() S.setDevice("mouse") end)
local function tileOutline(x, y, z, c)
	local pts = {}
	for _, k in ipairs({ { -0.5, -0.5 }, { 0.5, -0.5 }, { 0.5, 0.5 }, { -0.5, 0.5 } }) do
		local sx, sy = V.project(x + k[1], y + k[2], z)
		if not sx then return end
		pts[#pts + 1] = { sx, sy }
	end
	surface.SetDrawColor(c)
	for i = 1, 4 do
		local a, b = pts[i], pts[i % 4 + 1]
		for o = 0, 1 do surface.DrawLine(a[1], a[2] + o, b[1], b[2] + o) end
	end
end
function V.drawOverlay()
	if not S.showing() then return end
	local t = S.target()
	if not t then return end
	local a = 150 + 90 * math.sin(SysTime() * 5)
	local c = Color(255, 255, 255, math.floor(a))
	for _, tile in ipairs(t.tiles) do
		if tile.wall then
			local sx, sy = V.project(tile.x, tile.y, 2)
			if sx then
				draw.NoTexture()
				surface.SetDrawColor(c)
				surface.DrawPoly(V.clockwise({ { x = sx - 6, y = sy - 10 }, { x = sx + 6, y = sy - 10 }, { x = sx, y = sy - 2 } }))
			end
		else
			tileOutline(tile.x, tile.y, tile.z, c)
		end
	end
end

-- the list over your avatar when more than one thing is near: their names, the one the use key
-- would use marked, and which keys use and pick (the controller's when it was used last)
local function nameOf(t)
	if t.kind == "unit" then
		local o = R.units and R.units[t.id]
		return o and o.name or "?"
	end
	local fi = R.furniInfo and R.furniInfo(t.item.kind)
	return (fi and fi.name and fi.name ~= "") and fi.name or t.item.kind
end
S.LIST_MAX = 6
function V.drawOverlayTop()
	if not S.showing() then return end
	local list = S.candidates()
	if #list < 2 then return end
	local u = R.units and R.you and R.units[R.you]
	if not u then return end
	local x, y, z = R.unitPosition(u)
	local sx, sy, k = V.project(x, y, z)
	if not sx then return end
	local U = BOBBA.ui
	local sc = U.scale()
	local font, bold = U.font(12.6), U.font(12.6, true)
	local cur = (S.cycle % #list) + 1
	local pad = S.device == "pad"
	local useK = pad and S.padName(S.padButton("use")) or S.keyName(S.key("use"))
	local nextK = pad and S.padName(S.padButton("next")) or S.keyName(S.key("next"))
	local hint = string.format("%s: %s   %s: %s", useK, U.text("bobba.controls.short.use", "use"), nextK, U.text("bobba.controls.short.next", "next"))
	local rows = {}
	local first = math.max(1, math.min(cur - 2, #list - S.LIST_MAX + 1))
	for i = first, math.min(#list, first + S.LIST_MAX - 1) do rows[#rows + 1] = { i = i, text = nameOf(list[i]) } end
	surface.SetFont(bold)
	local w = surface.GetTextSize(hint)
	for _, r in ipairs(rows) do w = math.max(w, surface.GetTextSize(r.text) + 14 * sc) end
	local rh = math.floor(17 * sc)
	w = w + math.floor(16 * sc)
	local h = #rows * rh + rh + math.floor(10 * sc)
	local bx = math.floor(sx - w / 2)
	local by = math.floor(sy - 120 * k - h)
	draw.RoundedBox(math.floor(6 * sc), bx, by, w, h, Color(28, 28, 32, 235))
	local ty = by + math.floor(5 * sc)
	for _, r in ipairs(rows) do
		local on = r.i == cur
		if on then
			draw.RoundedBox(math.floor(3 * sc), bx + math.floor(3 * sc), ty, w - math.floor(6 * sc), rh, Color(45, 171, 194, 220))
			draw.SimpleText(">", bold, bx + math.floor(7 * sc), ty + rh / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		draw.SimpleText(r.text, on and bold or font, bx + math.floor(18 * sc), ty + rh / 2, on and color_white or Color(220, 220, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		ty = ty + rh
	end
	draw.SimpleText(hint, font, bx + w / 2, ty + rh / 2, Color(160, 160, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- bobba_steer_debug 1: what the stick and keys say, and the direction sent (top left)
local debugVar = CreateClientConVar("bobba_steer_debug", "0", false, false, "Show the stick's values and the walking direction")
hook.Add("DrawOverlay", "bobba.steering.debug", function()
	if not debugVar:GetBool() then return end
	local dx, dy = S.direction()
	local lines = {
		string.format("stick %s", S.pad and string.format("%.2f, %.2f", S.pad[1], S.pad[2]) or "none"),
		string.format("sector %s   tiles %d, %d   sent %d, %d", tostring(S.padSector), dx, dy, sent[1], sent[2]),
		string.format("device %s   directions %s   keys %d", S.device, S.axesVar:GetInt() == 1 and "room" or "screen", S.mode()),
	}
	for i, l in ipairs(lines) do draw.SimpleTextOutlined(l, "DermaDefault", 60, 60 + i * 16, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black) end
end)

-- a new room: nothing held
BOBBA.events.on("roomShown", "bobba.steering", function()
	S.held = {}
	sent = { 0, 0 }
	S.cycle = 0
end)
