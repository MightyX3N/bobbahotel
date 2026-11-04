-- Steering your avatar with keys or a controller, and the interact button (client). The server walks
-- you tile after tile while a direction is held (hotel/roomlive.lua: room.steer, room.interact).
--
-- Keys (Settings, "Movement keys"; bobba_setting_movekeys):
--   0  the arrow keys; typing goes into the chat as in Habbo (the default)
--   1  WASD and the arrow keys while the chat box is empty; once something is typed the letters are
--      the chat's. To start a message with w, a, s or d, press Enter first.
--   2  WASD and the arrow keys always; Enter (or T) opens the chat, Enter sends and closes it
-- Directions (bobba_setting_moveaxes): 0 as on the screen (up is up), 1 along the room's sides.
-- Interact: Space while the chat box is empty (and E with setting 2) uses what's highlighted next to
-- you: sit, lie down, switch, open a gift, an avatar's menu; Tab picks the next thing.
-- A controller (the desktop app; GMod through Steam Input) steers with BOBBA.steering.setPad(x, y).

BOBBA.steering = BOBBA.steering or {}
local S = BOBBA.steering
local P = BOBBA.platform
local R = BOBBA.room
local V = BOBBA.view

S.keysVar = CreateClientConVar("bobba_setting_movekeys", "0", true, false, "Movement keys: 0 arrows, 1 WASD while the chat is empty, 2 WASD (Enter to chat)")
S.axesVar = CreateClientConVar("bobba_setting_moveaxes", "0", true, false, "Movement directions: 0 as on the screen, 1 along the room's sides")

S.held = S.held or {}   -- from the chat box's key events: code -> direction
S.typing = S.typing or false -- (setting 1: Enter pressed on an empty box, letters are the chat's)
S.chatOpen = S.chatOpen or false -- (setting 2: the chat box has the keyboard)
S.cycle = S.cycle or 0
S.lastUsed = S.lastUsed or 0

local ARROWS = { [KEY_UP] = "up", [KEY_DOWN] = "down", [KEY_LEFT] = "left", [KEY_RIGHT] = "right" }
local WASD = { [KEY_W] = "up", [KEY_S] = "down", [KEY_A] = "left", [KEY_D] = "right" }
local LETTERS = { w = true, a = true, s = true, d = true, W = true, A = true, S = true, D = true }

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
		if WASD[code] then entry.steerDrop = true end
		S.lastUsed = SysTime()
		return true
	end
	if empty and not S.typing and code == KEY_SPACE then
		entry.steerDrop = true
		S.interact()
		return true
	end
	if empty and code == KEY_TAB then
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
		entry.steerDrop = false
		if LETTERS[ch] or ch == " " then return true end
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
	if math.abs(x) > 0.4 or math.abs(y) > 0.4 then S.lastUsed = SysTime() end
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
			-- (eight ways, by the stick's angle)
			local a = math.atan2(py, px)
			local k = math.floor(a / (math.pi / 4) + 0.5)
			sx, sy = math.Round(math.cos(k * math.pi / 4)), math.Round(math.sin(k * math.pi / 4))
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

function S.next() S.cycle = S.cycle + 1 S.lastUsed = SysTime() end

function S.interact()
	if V.mode ~= "room" then return end
	S.lastUsed = SysTime()
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
	-- setting 2: Enter or T opens the chat; clicking it does too
	if m == 2 and V.mode == "room" then
		if entry and entry:HasFocus() then S.chatOpen = true end
		if not S.chatOpen and not typingSomewhere() then
			local t = input.IsKeyDown(KEY_T)
			local down = input.IsKeyDown(KEY_ENTER) or t
			if down and not S.openWasDown then S.openChat(t and "t" or nil) end
			S.openWasDown = down
		end
		-- E (and Space) interacts, Tab picks the next thing
		if not typingSomewhere() then
			local e = input.IsKeyDown(KEY_E) or input.IsKeyDown(KEY_SPACE)
			if e and not S.eWasDown then S.interact() end
			S.eWasDown = e
			local tab = input.IsKeyDown(KEY_TAB)
			if tab and not S.tabWasDown then S.next() end
			S.tabWasDown = tab
		end
	elseif not typingSomewhere() and V.mode == "room" then
		local sp = input.IsKeyDown(KEY_SPACE)
		if sp and not S.eWasDown then S.interact() end
		S.eWasDown = sp
	end
	expireHeld()
	local dx, dy = 0, 0
	if S.allowed() then dx, dy = S.direction() end
	if dx ~= sent[1] or dy ~= sent[2] then
		sent = { dx, dy }
		if R.current then P.send("room.steer", { dx = dx, dy = dy }) end
		if dx ~= 0 or dy ~= 0 then S.lastUsed = SysTime() S.cycle = 0 end
	end
end)

-- the highlight: shown while steering is in use (or a controller is there), around what the
-- interact button would use
S.HIGHLIGHT_SECONDS = 10
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
	if not (S.padConnected or SysTime() - (S.lastUsed or 0) < S.HIGHLIGHT_SECONDS) then return end
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

-- a new room: nothing held
BOBBA.events.on("roomShown", "bobba.steering", function()
	S.held = {}
	sent = { 0, 0 }
	S.cycle = 0
end)
