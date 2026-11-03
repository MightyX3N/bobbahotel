-- Bobba Hotel Desktop: the website-style start page (bobba/launcher.lua), then the hotel itself
-- (bobba/game.lua: the gamemode from your garrysmod folder, run through a copy of GMod's Lua
-- functions, with its server on a thread of its own).

local Settings = require("bobba.settings")
local FS = require("bobba.fs")
local Game = require("bobba.game")
local Launcher

local mode -- "launcher" or "game"
local settings

local function current() return mode == "game" and Game or Launcher end

-- what Game.start needs to play the hotel on this computer
local function playOptions()
	local save = Settings.folder() .. "/hotels/local"
	return {
		garrysmod = settings.garrysmod,
		save = save,
		database = "hotel.db",
		playerKey = settings.playerKey,
		playerName = settings.playerName,
		-- (the console's log, where it can be read along with the game's own files)
		log = settings.garrysmod and (settings.garrysmod .. "/data/bobba_temp/desktop_console.log") or nil,
	}
end

local function play(roomId)
	settings.lastPlayed = os.time()
	Settings.save(settings)
	mode = "game"
	if Launcher and Launcher.leave then Launcher.leave() end
	local opts = playOptions()
	opts.enterRoom = roomId
	Game.start(opts)
end

function love.load(args)
	love.keyboard.setKeyRepeat(true)
	settings = Settings.load()
	-- who you are: the Steam account signed in on this computer (a name can be set in Settings)
	if not settings.playerKey then
		local ST = require("bobba.steam")
		local key, name = ST.account()
		settings.playerKey = key or ("local_" .. string.format("%08x", love.math.random(0, 0x7fffffff)))
		settings.playerName = settings.playerName or name or os.getenv("USERNAME") or os.getenv("USER") or "Player"
		Settings.save(settings)
	end
	local direct = os.getenv("BOBBA_DESKTOP_PLAY")
	for _, a in ipairs(args or {}) do if a == "--play" then direct = "1" end end
	if os.getenv("BOBBA_DESKTOP_GARRYSMOD") then settings.garrysmod = os.getenv("BOBBA_DESKTOP_GARRYSMOD") end
	Launcher = require("bobba.launcher")
	if settings.fullscreen then require("bobba.window").set(true) end
	if direct and settings.garrysmod then
		play()
	else
		mode = "launcher"
		Launcher.start(settings, { play = play, save = function() Settings.save(settings) end, options = playOptions })
	end
	-- tests: a script that clicks and takes pictures (BOBBA_DESKTOP_TEST)
	local test = os.getenv("BOBBA_DESKTOP_TEST")
	if test then
		local fn = assert(loadstring(assert(FS.read(test)), "@" .. test))
		TEST = coroutine.create(fn)
		TEST_API = { game = Game, launcher = Launcher, settings = settings, play = play, mode = function() return mode end }
	end
end

function love.update(dt)
	if TEST and coroutine.status(TEST) ~= "dead" then
		local ok, err = coroutine.resume(TEST, TEST_API, dt)
		if not ok then print("TEST FAILED: " .. tostring(err)) love.event.quit(1) end
	end
	local m = current()
	if m and m.update then m.update(dt) end
end

function love.draw()
	local m = current()
	if m and m.draw then m.draw() end
end

for _, name in ipairs({ "mousepressed", "mousereleased", "mousemoved", "wheelmoved", "keypressed", "keyreleased", "textinput", "resize", "filedropped", "directorydropped" }) do
	love[name] = function(...)
		local m = current()
		if m and m[name] then m[name](...) end
	end
end

function love.quit()
	if mode == "game" then Game.stop() end
	return false
end
