-- Moving your avatar freely with keys or a controller, and the interact button (client). Your own
-- avatar moves here at once, in exactly the way pushed (a stick: any angle; keys: 8 ways), keeping off
-- walls and furni; the server is told where it is (room.move) and checks it (hotel/roomlive.lua).
-- Let go, and it eases onto the middle of its tile. Clicking still walks Habbo's way, tile by tile.
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
-- A controller (the desktop app; GMod through Steam Input) moves it with BOBBA.steering.setPad(x, y).

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
local function typingSomewhere()
	local f = vgui.GetKeyboardFocus and vgui.GetKeyboardFocus()
	return IsValid(f) and f.GetCaretPos ~= nil
end

-- where the keys or the stick point on the screen (x right, y down; length 1), or nil
function S.vector()
	local dirs = {}
	for _, d in pairs(S.held) do dirs[d] = true end
	-- (nothing typing: the keys themselves; e.g. setting 2, or while a furni is placed)
	if not typingSomewhere() then
		for code, d in pairs(ARROWS) do if input.IsKeyDown(code) then dirs[d] = true end end
		if S.mode() >= 1 then
			for code, d in pairs(WASD) do if input.IsKeyDown(code) then dirs[d] = true end end
		end
	end
	local sx, sy = 0, 0
	if dirs.up then sy = sy - 1 end
	if dirs.down then sy = sy + 1 end
	if dirs.left then sx = sx - 1 end
	if dirs.right then sx = sx + 1 end
	if sx ~= 0 or sy ~= 0 then
		local l = math.sqrt(sx * sx + sy * sy)
		return sx / l, sy / l, "keys"
	end
	-- the stick: any angle (it starts once pushed a third of the way, stops nearly back in the middle)
	if S.pad then
		local px, py = S.pad[1], S.pad[2]
		local m = math.sqrt(px * px + py * py)
		if m > (S.padMoving and 0.25 or 0.35) then
			S.padMoving = true
			return px / m, py / m, "pad"
		end
		S.padMoving = false
	end
	return nil
end

-- a direction on the screen as one along the floor (tile units, length 1). As isometric games do:
-- up is straight up the screen, and a diagonal (up-right, ...) goes along the floor's edges (which
-- are flatter than 45 degrees on the screen); in between, in between.
function S.toTiles(sx, sy)
	local x, y
	if S.axesVar:GetInt() == 1 then
		x, y = sx, sy
	else
		x, y = (sx + sy) / 2, (sy - sx) / 2
	end
	local l = math.sqrt(x * x + y * y)
	if l < 1e-6 then return 0, 0 end
	return x / l, y / l
end

-- the nearest of the avatar's 8 directions to a way along the floor (0 = y - 1, 2 = x + 1, ...)
local DIRS = { ["0,-1"] = 0, ["1,-1"] = 1, ["1,0"] = 2, ["1,1"] = 3, ["0,1"] = 4, ["-1,1"] = 5, ["-1,0"] = 6, ["-1,-1"] = 7 }
function S.dirFor(x, y)
	local k = math.floor(math.atan2(y, x) / (math.pi / 4) + 0.5)
	local c, sn = math.cos(k * math.pi / 4), math.sin(k * math.pi / 4)
	local dx = c > 0.5 and 1 or (c < -0.5 and -1 or 0)
	local dy = sn > 0.5 and 1 or (sn < -0.5 and -1 or 0)
	return DIRS[dx .. "," .. dy]
end

-- --- the floor, as far as this game knows it (the server has the last word: hotel/roomlive.lua) --------
S.SPEED = 2        -- tiles a second (Habbo's walk: a tile in half a second)
S.RADIUS = 0.2     -- how near a wall or furni its middle may come
S.SEND_EVERY = 1 / 15
local floor = { rows = nil, heightmap = nil, blocked = {}, at = 0 }
local function tileHeight(x, y)
	local row = floor.rows and floor.rows[y + 1]
	local c = row and row:sub(x + 1, x + 1) or ""
	if c == "" or c == "x" or c == "X" then return nil end
	return tonumber(c, 36)
end
local function refreshFloor()
	local c = R.current
	if not c then floor.rows = nil return end
	if floor.heightmap ~= c.heightmap then
		floor.heightmap = c.heightmap
		floor.rows = {}
		for row in (tostring(c.heightmap or "") .. "\r"):gmatch("(.-)\r") do floor.rows[#floor.rows + 1] = row end
	end
	if SysTime() - floor.at < 0.25 then return end
	floor.at = SysTime()
	local blocked = {}
	for _, it in pairs(R.items or {}) do
		local fi = R.furniInfo and R.furniInfo(it.kind)
		if fi and not fi.wall and not it.wall then
			-- (as the server has it: a teleport or a one-way gate is only gone into by using it, a gate
			-- only when open)
			local open = fi.walk or fi.sit or fi.lay
			if fi.category == "gate" then open = tonumber(it.state) == 1 end
			if fi.category == "teleport" or fi.logic == "furniture_one_way_door" then open = false end
			if not open then
				local w, l = fi.width or 1, fi.length or 1
				if it.dir == 2 or it.dir == 6 then w, l = l, w end
				for i = 0, w - 1 do for j = 0, l - 1 do blocked[(it.x + i) .. "," .. (it.y + j)] = true end end
			end
		end
	end
	floor.blocked = blocked
end
local function round(v) return math.floor(v + 0.5) end
local function tileOk(x, y, fromH)
	local h = tileHeight(x, y)
	if not h then return false end
	if floor.blocked[x .. "," .. y] then return false end
	local d = R.current and R.current.door
	if d and d.x == x and d.y == y then return false end
	if fromH and h - fromH > 1.1 then return false end
	return true
end
-- the floor's height at a point, sloping between tiles one can step between (stairs: up and down
-- the steps as walking does, not jumping at a tile's edge); a drop too high to step stays flat
function S.floorZ(x, y)
	refreshFloor()
	local h0 = tileHeight(round(x), round(y))
	if not h0 then return nil end
	local x0, y0 = math.floor(x), math.floor(y)
	local fx, fy = x - x0, y - y0
	local function h(tx, ty)
		local v = tileHeight(tx, ty)
		if not v or math.abs(v - h0) > 1.1 or floor.blocked[tx .. "," .. ty] then return h0 end
		return v
	end
	local a = h(x0, y0) + (h(x0 + 1, y0) - h(x0, y0)) * fx
	local b = h(x0, y0 + 1) + (h(x0 + 1, y0 + 1) - h(x0, y0 + 1)) * fx
	return a + (b - a) * fy
end

-- may its middle be at x, y (coming from the tile it's on)?
function S.spotOk(x, y, fromX, fromY)
	local fh = tileHeight(fromX, fromY)
	local tx, ty = round(x), round(y)
	if (tx ~= fromX or ty ~= fromY) and not tileOk(tx, ty, fh) then return false end
	local Rr = S.RADIUS
	for _, c in ipairs({ { -Rr, -Rr }, { Rr, -Rr }, { -Rr, Rr }, { Rr, Rr } }) do
		local cx, cy = round(x + c[1]), round(y + c[2])
		if (cx ~= tx or cy ~= ty) and (cx ~= fromX or cy ~= fromY) and not tileOk(cx, cy, fh) then return false end
	end
	return true
end

-- --- what the interact button uses ------------------------------------------------------------------
local function me()
	local u = R.units and R.you and R.units[R.you]
	if not u then return nil end
	local t = u.freePos or u.to or u.from
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
		-- (the chat box got the keyboard: opened only by a click on it; GMod hands the keyboard to it by
		-- itself when another window closes, which mustn't open the chat)
		if entry and entry:HasFocus() and not S.chatOpen then
			if SysTime() - (S.chatClickAt or 0) < 0.5 then S.chatOpen = true else entry:KillFocus() end
		end
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
	S.moveFrame(math.min(RealFrameTime(), 0.1))
end)

-- --- moving your own avatar: at once, here; the server is told where it is ---------------------------
-- S.free: { x, y, z } while moving (the avatar is drawn there: room.lua's position)
function S.stopFree(u)
	if not S.free then return end
	P.send("room.move", { x = S.free.x, y = S.free.y, dir = u and u.dir or nil, stop = true })
	if u then u.freeMoving = false u.freeStopAt = SysTime() end
	S.free = nil
end
-- going through a teleport: no moving until it has let you out (the server says: room.busy)
P.receive("room.busy", function(_, data)
	S.busy = data.on and SysTime() or nil
	if data.on and S.free then
		local u = R.units and R.you and R.units[R.you]
		S.free = nil
		if u then u.freePos, u.freeMoving = nil, nil end
	end
end)

function S.moveFrame(dt)
	local u = R.units and R.you and R.units[R.you]
	local sx, sy, via
	-- (busy: going through a teleport; at most 8 s, in case the word that it's over got lost)
	if S.busy and SysTime() - S.busy > 8 then S.busy = nil end
	if S.allowed() and u and not S.busy then sx, sy, via = S.vector() end
	if not sx then
		S.stopFree(u)
		-- (the server didn't say where it eased to: drawn on its tile again)
		if u and u.freePos and not u.freeMoving and SysTime() - (u.freeStopAt or 0) > 1 then u.freePos = nil end
		return
	end
	if via == "keys" then S.setDevice("keys") end
	S.cycle = 0
	refreshFloor()
	local vx, vy = S.toTiles(sx, sy)
	if not S.free then
		-- (on the door: one step into the room first, straight, as Habbo walks out of a door)
		local t = u.to or u.from
		local d = R.current and R.current.door
		local onDoor = d and round(t.x) == d.x and round(t.y) == d.y
		-- (and until that step off it is walked)
		local leaving = d and u.to and round(u.from.x) == d.x and round(u.from.y) == d.y and SysTime() - u.started < (u.dur or 0.5)
		if leaving then return end
		if onDoor then
			if not u.to and SysTime() - (S.doorStepAt or 0) > 0.6 then
				S.doorStepAt = SysTime()
				local fx, fy = d.x, d.y
				local dd = d.dir or 2
				if dd == 2 then fx = fx + 1 elseif dd == 4 then fy = fy + 1 elseif dd == 6 then fx = fx - 1 elseif dd == 0 then fy = fy - 1 end
				P.send("room.walk", { x = fx, y = fy })
			end
			return
		end
		-- from where it's drawn now (walking a step, sitting: from its tile)
		local x, y, z = R.unitPosition(u)
		if u.posture == "sit" or u.posture == "lay" then x, y = (u.to or u.from).x, (u.to or u.from).y end
		S.free = { x = x, y = y, z = (u.to or u.from).z or 0 }
		S.sentAt = 0
	end
	local f = S.free
	local tx, ty = round(f.x), round(f.y)
	local step = S.SPEED * dt
	local nx, ny = f.x + vx * step, f.y + vy * step
	-- into a wall or furni: along it
	if not S.spotOk(nx, ny, tx, ty) then
		if math.abs(vx) > 0.05 and S.spotOk(f.x + vx * step, f.y, tx, ty) then nx, ny = f.x + vx * step, f.y
		elseif math.abs(vy) > 0.05 and S.spotOk(f.x, f.y + vy * step, tx, ty) then nx, ny = f.x, f.y + vy * step
		else nx, ny = f.x, f.y end
	end
	f.x, f.y = nx, ny
	f.z = S.floorZ(nx, ny) or f.z
	u.dir = S.dirFor(vx, vy) or u.dir
	u.posture, u.height = nil, nil
	u.freePos, u.freeMoving = f, true
	if SysTime() - (S.sentAt or 0) >= S.SEND_EVERY then
		S.sentAt = SysTime()
		P.send("room.move", { x = f.x, y = f.y, dir = u.dir })
	end
end

-- (a click on the chat box: setting 2 opens the chat then)
hook.Add("VGUIMousePressed", "bobba.steering.chat", function(panel)
	local f = R.chatState and R.chatState.input
	if IsValid(f) and IsValid(panel) and (panel == f or panel == f.entry) then S.chatClickAt = SysTime() end
end)

-- the server didn't take a move (too fast, into something): back to where it says
P.receive("room.unit.pos", function(_, data)
	if S.free then S.free.x, S.free.y, S.free.z = data.x, data.y, data.z or S.free.z end
	local u = R.units and R.you and R.units[R.you]
	if u and u.freePos and not S.free then u.freePos = nil end
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
	local sx, sy = S.vector()
	local vx, vy = 0, 0
	if sx then vx, vy = S.toTiles(sx, sy) end
	local lines = {
		string.format("stick %s", S.pad and string.format("%.2f, %.2f", S.pad[1], S.pad[2]) or "none"),
		string.format("screen %s   floor %.2f, %.2f   at %s", sx and string.format("%.2f, %.2f", sx, sy) or "-", vx, vy, S.free and string.format("%.2f, %.2f", S.free.x, S.free.y) or "-"),
		string.format("device %s   directions %s   keys %d", S.device, S.axesVar:GetInt() == 1 and "room" or "screen", S.mode()),
	}
	for i, l in ipairs(lines) do draw.SimpleTextOutlined(l, "DermaDefault", 60, 60 + i * 16, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black) end
end)

-- a new room: nothing held
BOBBA.events.on("roomShown", "bobba.steering", function()
	S.held = {}
	S.free = nil
	S.cycle = 0
end)
