-- The new player's tutorial (client): a small panel at the top left while in a room, the step
-- to do now with the steps' dots; it moves on by itself when the step is done (hotel/tutorial.lua).
-- "Skip" ends it. Done: a notification with the reward.

BOBBA.tutorialPanel = BOBBA.tutorialPanel or {}
local TP = BOBBA.tutorialPanel
local U = BOBBA.ui
local P = BOBBA.platform
local V = BOBBA.view
local T = function(key, fallback, vars) return U.text(key, fallback, vars) end

TP.TEXTS = {
	walk = { "bobba.tutorial.walk", "Walk around: click the floor where you want to go (or use the arrow keys)." },
	gift = { "bobba.tutorial.gift", "There's a gift for you in your room. Click it and open it." },
	move = { "bobba.tutorial.move", "Make the room yours: click a furni and move it or turn it." },
	chat = { "bobba.tutorial.chat", "Say hi! Type something in the chat at the bottom and press Enter." },
}

local W = 260
local WHITE, MUTED = Color(255, 255, 255), Color(255, 255, 255, 150)

local function lines(d)
	local st = TP.state
	local t = TP.TEXTS[st.name or ""] or { "", "" }
	return d:wrap(T(t[1], t[2]), 12.6, W - 24)
end

local function height(d)
	return 12 + 18 + 6 + #lines(d) * 18 + 8 + 14 + 12
end

local function draw(w, d)
	local st = TP.state
	if not st then return end
	local H = d.height
	d:darkBox(0, 0, W, H, 6)
	local x, y = 12, 12
	d:text(T("bobba.tutorial.title", "Welcome to the hotel!"), 14.4, x, y, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
	-- skip (right)
	local sk = T("bobba.tutorial.skip", "Skip")
	local sw = d:textWidth(sk, 11)
	local hover = d:click(W - 12 - sw, y, sw, 16, function() P.send("tutorial.skip", {}) TP.state = nil end)
	d:text(sk, 11, W - 12, y + 2, hover and WHITE or MUTED, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
	y = y + 18 + 6
	for _, l in ipairs(lines(d)) do
		d:text(l, 12.6, x, y, WHITE)
		y = y + 18
	end
	y = y + 8
	-- the steps: a dot each (done ones filled), and "2 / 4"
	for i = 1, st.steps or 4 do
		local cx = x + 5 + (i - 1) * 16
		if i < st.step then d:circle(cx, y + 6, 5, Color(78, 190, 92))
		elseif i == st.step then d:circle(cx, y + 6, 5, WHITE)
		else d:circle(cx, y + 6, 5, Color(255, 255, 255, 60)) end
	end
	local reward = tonumber(st.reward) or 0
	local right = (st.step .. " / " .. (st.steps or 4))
	if reward > 0 then right = T("bobba.tutorial.reward", "Reward: %credits% credits", { credits = tostring(reward) }) .. "   " .. right end
	d:text(right, 11, W - 12, y + 6, MUTED, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

U.hud("tutorial", function(sw, sh)
	if not TP.state or V.mode ~= "room" then return nil end
	-- (its height from its text: measured with the HUD's own drawing scale)
	local h = TP.lastH or 110
	return 10, 70, W, h
end, function(w, d)
	TP.lastH = height(d)
	draw(w, d)
end)

P.receive("tutorial.step", function(_, data)
	TP.state = data
	if data.done then TP.state = nil end
end)

P.receive("tutorial.done", function(_, data)
	local had = TP.state ~= nil
	TP.state = nil
	local reward = tonumber(data.reward) or 0
	if reward > 0 then
		U.notify(T("bobba.tutorial.done.title", "Well done!"), T("bobba.tutorial.done", "That's the basics. Here are %credits% credits to start with.", { credits = tostring(reward) }), 8)
	elseif had then
		U.notify(T("bobba.tutorial.title", "Welcome to the hotel!"), T("bobba.tutorial.skipped", "Have fun!"), 4)
	end
end)
