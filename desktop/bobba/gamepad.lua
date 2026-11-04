-- A controller (Xbox, PlayStation, the Steam Deck's own) in the desktop app. The gamemode's
-- steering (client/steering.lua) does the walking; this turns the controller into it and into the
-- mouse:
--   left stick / d-pad   walk (tile after tile while held)
--   A                    interact: sit, lie down, switch, open a gift, an avatar's menu
--   LB                   pick the next thing to interact with
--   RB                   turn the furni being placed (or the one selected)
--   right stick          move the mouse pointer;  X  click,  B  right-click
--   Y (hold)             the menu wheel: navigator, inventory, catalogue, ... (let go to choose)
--   Back / View (hold)   the quick-message wheel (let go to say it)
--   Start / Menu         chat: the chat box, and the Steam Deck's on-screen keyboard
local Pad = {}

Pad.DEAD = 0.25
Pad.CURSOR_SPEED = 1400 -- pixels a second at full tilt

local wheel -- the open wheel: { kind = "menu" / "say", items, chosen }
local down = {}
local clickHeld = false

local function stick(js, ax, ay)
	local x, y = js:getGamepadAxis(ax), js:getGamepadAxis(ay)
	if x * x + y * y < Pad.DEAD * Pad.DEAD then return 0, 0 end
	return x, y
end

local function action(name)
	local HUD = BOBBA and BOBBA.hud
	local fn = HUD and HUD.actions and HUD.actions[name]
	if fn then pcall(fn) end
end

local function T(key, fallback)
	local U = BOBBA and BOBBA.ui
	return U and U.text and U.text(key, fallback) or fallback
end

local function menuItems()
	return {
		{ T("toolbar.icon.label.navigator", "Navigator"), function() action("navigator") end },
		{ T("toolbar.icon.label.inventory", "Inventory"), function() action("inventory") end },
		{ T("toolbar.icon.label.catalog", "Catalogue"), function() action("catalog") end },
		{ T("toolbar.icon.label.friends", "Friends"), function() action("friends") end },
		{ T("widget.memenu.settings.title", "Settings"), function() action("settings") end },
		{ T("toolbar.icon.label.exitroom", "Hotel view"), function() action("hotelView") end },
		{ T("navigator.myrooms", "My rooms"), function() action("myRooms") end },
		{ T("bobba.pad.chat", "Chat"), function() Pad.chat() end },
	}
end

Pad.PHRASES = { "Hi!", "o/", "Yes", "No", "lol", "Thanks!", "brb", "Bye!" }
local function sayItems()
	local out = {}
	for _, p in ipairs(Pad.PHRASES) do
		out[#out + 1] = { p, function()
			local C = BOBBA and BOBBA.room and BOBBA.room.chatState
			if C and C.send then pcall(C.send, p, false) end
		end }
	end
	return out
end

-- the chat box, with the Steam Deck's keyboard (on a PC without Steam's keyboard nothing opens)
function Pad.chat()
	local S = BOBBA and BOBBA.steering
	if S then S.openChat() end
	local C = BOBBA and BOBBA.room and BOBBA.room.chatState
	local f = C and C.input
	if f and IsValid(f) and IsValid(f.entry) then f.entry:RequestFocus() end
	pcall(love.system.openURL, "steam://open/keyboard")
end

function Pad.find()
	if not love.joystick then return nil end
	if Pad.fake then return Pad.fake end
	for _, js in ipairs(love.joystick.getJoysticks()) do
		if js:isGamepad() and js:isConnected() then return js end
	end
end

-- each frame while playing (G: the GMod world's input functions, vgui.lua)
function Pad.update(dt, G)
	local S = BOBBA and BOBBA.steering
	local js = Pad.find()
	if S then S.padConnected = js ~= nil end
	if not js then
		if S and S.pad then S.setPad(nil) end
		down = {}
		wheel = nil
		return
	end
	local function pressed(b)
		local now = js:isGamepadDown(b)
		local was = down[b]
		down[b] = now
		return now and not was, (not now) and was, now
	end
	-- walking: the left stick, or the d-pad
	local lx, ly = stick(js, "leftx", "lefty")
	local dx = (js:isGamepadDown("dpright") and 1 or 0) - (js:isGamepadDown("dpleft") and 1 or 0)
	local dy = (js:isGamepadDown("dpdown") and 1 or 0) - (js:isGamepadDown("dpup") and 1 or 0)
	if dx ~= 0 or dy ~= 0 then lx, ly = dx, dy end
	-- (with a wheel open the stick chooses in it instead)
	if wheel then
		if lx * lx + ly * ly > 0.5 * 0.5 then
			local a = math.atan2(ly, lx)
			local n = #wheel.items
			wheel.chosen = (math.floor(((a + math.pi / 2) % (2 * math.pi)) / (2 * math.pi) * n + 0.5) % n) + 1
		end
		if S then S.setPad(0, 0) end
	elseif S then
		S.setPad(lx, ly)
	end
	-- the pointer: the right stick
	local rx, ry = stick(js, "rightx", "righty")
	if rx ~= 0 or ry ~= 0 then
		local mx, my = love.mouse.getPosition()
		local sp = Pad.CURSOR_SPEED * dt
		local nx = math.max(0, math.min(love.graphics.getWidth() - 1, mx + rx * math.abs(rx) * sp))
		local ny = math.max(0, math.min(love.graphics.getHeight() - 1, my + ry * math.abs(ry) * sp))
		love.mouse.setPosition(nx, ny)
		G.mouseMoved(nx, ny)
	end
	local mx, my = love.mouse.getPosition()
	-- X: the left mouse button (held while held: dragging works); B: the right one
	local xDown, xUp = pressed("x")
	if xDown then G.mousePressed(mx, my, 1) clickHeld = true end
	if xUp and clickHeld then G.mouseReleased(mx, my, 1) clickHeld = false end
	local bDown, bUp = pressed("b")
	if bDown then G.mousePressed(mx, my, 2) end
	if bUp then G.mouseReleased(mx, my, 2) end
	-- A: interact; LB: the next thing; RB: turn
	if pressed("a") and S and not wheel then S.interact() end
	if pressed("leftshoulder") and S then S.next() end
	if pressed("rightshoulder") then
		local R = BOBBA and BOBBA.room
		if R and R.pressR then pcall(R.pressR) end
	end
	if pressed("start") then Pad.chat() end
	-- the wheels: held open, chosen when let go
	for _, w in ipairs({ { "y", "menu", menuItems }, { "back", "say", sayItems } }) do
		local press, release = pressed(w[1])
		if press and not wheel then wheel = { kind = w[2], button = w[1], items = w[3]() } end
		if release and wheel and wheel.button == w[1] then
			local item = wheel.chosen and wheel.items[wheel.chosen]
			wheel = nil
			if item then pcall(item[2]) end
		end
	end
end

function Pad.wheel() return wheel end

-- the wheel, over everything
function Pad.draw()
	if not wheel then return end
	local lg = love.graphics
	local W, H = lg.getDimensions()
	local s = math.max(1, math.floor(H / 1080 * 4 + 0.5) / 4)
	local cx, cy = W / 2, H / 2
	local R0 = 150 * s
	lg.setColor(0, 0, 0, 0.45)
	lg.rectangle("fill", 0, 0, W, H)
	lg.setColor(0.06, 0.12, 0.17, 0.92)
	lg.circle("fill", cx, cy, R0 + 70 * s)
	lg.setColor(1, 1, 1, 0.15)
	lg.setLineWidth(2 * s)
	lg.circle("line", cx, cy, R0 + 70 * s)
	local font = lg.getFont()
	local n = #wheel.items
	for i, item in ipairs(wheel.items) do
		local a = (i - 1) / n * 2 * math.pi - math.pi / 2
		local x, y = cx + math.cos(a) * R0, cy + math.sin(a) * R0
		local chosen = wheel.chosen == i
		local bw, bh = font:getWidth(item[1]) * s + 28 * s, 30 * s
		if chosen then lg.setColor(0.18, 0.67, 0.76, 1) else lg.setColor(1, 1, 1, 0.12) end
		lg.rectangle("fill", x - bw / 2, y - bh / 2, bw, bh, 8 * s, 8 * s)
		lg.setColor(1, 1, 1, 1)
		lg.print(item[1], x - font:getWidth(item[1]) * s / 2, y - font:getHeight() * s / 2, 0, s, s)
	end
	local title = wheel.kind == "menu" and T("bobba.pad.menu", "Menu") or T("bobba.pad.say", "Say")
	lg.setColor(1, 1, 1, 0.8)
	lg.print(title, cx - font:getWidth(title) * s / 2, cy - font:getHeight() * s / 2, 0, s, s)
	lg.setColor(1, 1, 1, 1)
end

return Pad
