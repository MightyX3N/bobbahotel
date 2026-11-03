-- The desktop's own settings (where Garry's Mod is, your name), in its save folder as JSON.
local JSON = require("bobba.json")
local S = {}
local FILE = "settings.json"

function S.load()
	local text = love.filesystem.read(FILE)
	local t = text and JSON.decode(text)
	return type(t) == "table" and t or {}
end

function S.save(t)
	love.filesystem.write(FILE, JSON.encode(t))
end

-- the desktop's folder on the computer (the hotels' databases are in it)
function S.folder()
	return (love.filesystem.getSaveDirectory():gsub("\\", "/"))
end

return S
