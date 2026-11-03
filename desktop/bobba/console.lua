-- The console (F1): what the game and its server print, and a line to type commands in (Tab
-- completes). Everything printed also goes to a log file.

local FS = require("bobba.fs")
local lg = love.graphics
local Console = {}
local lines = {} -- { text, color }
local MAX = 2000
local open = false
local typed, history, histAt = "", {}, 0
local scroll = 0
local logPath
local errors = 0
local font

function Console.init(log)
	logPath = log
	if logPath then
		FS.mkdirs(FS.parent(logPath))
		FS.write(logPath, "Bobba Hotel Desktop " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
	end
end

local partial = ""
function Console.add(text, color)
	text = tostring(text)
	io.write(text)
	if logPath then FS.write(logPath, text, true) end
	if color and color.r == 255 and color.g == 90 then errors = errors + 1 end
	partial = partial .. text
	while true do
		local nl = partial:find("\n", 1, true)
		if not nl then break end
		lines[#lines + 1] = { partial:sub(1, nl - 1), color }
		partial = partial:sub(nl + 1)
	end
	while #lines > MAX do table.remove(lines, 1) end
end

function Console.isOpen() return open end
function Console.toggle() open = not open scroll = 0 errors = 0 end
function Console.close() open = false end
function Console.wheel(dy) scroll = math.max(0, math.min(#lines - 1, scroll + dy * 3)) end

function Console.key(key)
	if key == "escape" then open = false return end
	if key == "return" or key == "kpenter" then
		local line = typed
		typed = ""
		if line:match("%S") then
			Console.add("] " .. line .. "\n", { r = 200, g = 200, b = 200 })
			history[#history + 1] = line
			histAt = #history + 1
			if Console.run then Console.run(line) end
		end
		scroll = 0
	elseif key == "backspace" then
		typed = typed:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
	elseif key == "up" then
		histAt = math.max(1, histAt - 1)
		typed = history[histAt] or typed
	elseif key == "down" then
		histAt = math.min(#history + 1, histAt + 1)
		typed = history[histAt] or ""
	elseif key == "tab" and Console.names then
		for _, n in ipairs(Console.names()) do
			if n:sub(1, #typed) == typed:lower() and #typed > 0 then typed = n .. " " break end
		end
	elseif key == "v" and love.keyboard.isDown("lctrl", "rctrl") then
		typed = typed .. (love.system.getClipboardText() or ""):gsub("[\r\n]", " ")
	end
end
function Console.text(t)
	if t == "`" then return end
	typed = typed .. t
end

function Console.draw()
	if not font then font = lg.newFont(13) end
	lg.origin()
	lg.setScissor()
	if not open then
		if errors > 0 then
			lg.setFont(font)
			local t = errors .. " error" .. (errors == 1 and "" or "s") .. " (F1: console)"
			local w = font:getWidth(t) + 16
			lg.setColor(0.6, 0.1, 0.1, 0.85)
			lg.rectangle("fill", lg.getWidth() - w - 8, 8, w, 22, 4)
			lg.setColor(1, 1, 1)
			lg.print(t, lg.getWidth() - w, 12)
		end
		return
	end
	local W, H = lg.getWidth(), math.floor(lg.getHeight() * 0.6)
	lg.setColor(0.07, 0.08, 0.1, 0.94)
	lg.rectangle("fill", 0, 0, W, H)
	lg.setFont(font)
	local lh = font:getHeight() + 2
	local y = H - 30 - lh
	local i = #lines - math.floor(scroll)
	while y > -lh and i >= 1 do
		local l = lines[i]
		local c = l[2]
		if c then lg.setColor(c.r / 255, c.g / 255, c.b / 255) else lg.setColor(0.88, 0.88, 0.88) end
		lg.print(l[1], 8, y)
		y = y - lh
		i = i - 1
	end
	lg.setColor(0.15, 0.17, 0.2)
	lg.rectangle("fill", 0, H - 26, W, 26)
	lg.setColor(1, 1, 1)
	local caret = (love.timer.getTime() % 1 < 0.5) and "_" or ""
	lg.print("> " .. typed .. caret, 8, H - 21)
end

return Console
