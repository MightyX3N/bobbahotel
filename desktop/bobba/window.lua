-- Full screen as a borderless window the size of the screen ("windowed full screen"): alt-tab and
-- other windows work as normal, nothing is minimised. Win.set(true/false), Win.toggle(), Win.full().
local Win = {}
local full = false
local before -- the window as it was: w, h, x, y, display

local function windowFlags(extra)
	local f = { resizable = true, minwidth = 1024, minheight = 640, vsync = 1, highdpi = false }
	for k, v in pairs(extra or {}) do f[k] = v end
	return f
end

function Win.full() return full end

function Win.set(on)
	if on == full then return end
	local w, h = love.graphics.getDimensions()
	if on then
		local x, y, display = love.window.getPosition()
		before = { w = w, h = h, x = x, y = y, display = display }
		local dw, dh = love.window.getDesktopDimensions(display)
		love.window.setMode(dw, dh, windowFlags({ borderless = true, resizable = false, display = display, x = 0, y = 0 }))
		love.window.setPosition(0, 0, display)
	else
		local b = before or { w = 1280, h = 760 }
		love.window.setMode(b.w, b.h, windowFlags({ borderless = false, display = b.display, x = b.x, y = b.y }))
		if b.x then love.window.setPosition(b.x, b.y, b.display) end
	end
	full = on
	if love.resize then love.resize(love.graphics.getDimensions()) end
end

function Win.toggle() Win.set(not full) end

return Win
