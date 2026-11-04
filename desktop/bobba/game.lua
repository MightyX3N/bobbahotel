-- Playing: the hotel's server on its thread, the game (the gamemode's client files) here, and the
-- console (F1). Game.start(opts), then Love's events go to Game.update / Game.draw / Game.*.

local FS = require("bobba.fs")
local HTTP = require("bobba.http")
local Console = require("bobba.console")
local Pad = require("bobba.gamepad")

local Game = {}
local toGame = love.thread.getChannel("bobba_to_game")
local toServer = love.thread.getChannel("bobba_to_server")
local G
local state = "starting" -- starting, loading, playing, failed, stopping
local why
local serverThread
local startedAt

function Game.start(opts)
	Game.opts = opts
	toGame:clear()
	toServer:clear()
	startedAt = love.timer.getTime()
	FS.mkdirs(opts.save)
	Console.init(opts.log)
	Console.add("Playing as " .. tostring(opts.playerName) .. " (" .. tostring(opts.playerKey) .. ")\n")
	HTTP.startWorkers(os.getenv("BOBBA_DESKTOP_FAKE_HTTP"))

	serverThread = love.thread.newThread("bobba/server.lua")
	serverThread:start({ garrysmod = opts.garrysmod, save = opts.save, database = opts.database, playerKey = opts.playerKey, playerName = opts.playerName })

	G = require("bobba.gmod")({
		server = false,
		garrysmod = opts.garrysmod,
		save = opts.save,
		player = { key = opts.playerKey, name = opts.playerName },
		transport = function(s) toServer:push(s) end,
		console = Console.add,
	})
	require("bobba.gmod_client")(G)
	G.consoleOpen = Console.isOpen
	-- back to the start page
	concommand.Add("disconnect", function() love.event.quit("restart") end)
	concommand.Add("quit", function() love.event.quit() end)
	Console.run = function(line) G.console(line) end
	Console.names = G.commandNames
	state = "loading"
	Game.G = G
end

local function loadClient()
	G.runFile(Game.opts.garrysmod .. "/gamemodes/bobbahotel/gamemode/cl_init.lua", "bobbahotel/gamemode/cl_init.lua")
	hook.Run("Initialize")
	-- the "me" menu's leave button: back to the start page
	if BOBBA.hud and BOBBA.hud.actions then
		BOBBA.hud.actions.leaveHotel = function() love.event.quit("restart") end
	end
end

local function serverMessages()
	while true do
		local msg = toGame:pop()
		if not msg then break end
		local k = msg:sub(1, 1)
		if k == "S" then
			-- the player is in: the game has "loaded" (GMod's InitPostEntity)
			G.player.valid = true
			hook.Run("InitPostEntity")
			Game.spawnedAt = love.timer.getTime()
			-- (a room picked on the start page: once the hotel has put you in its first one)
			-- (Manage on the start page: the hotel's Manage screen once it's in)
			if Game.opts.manage then timer.Simple(1, function() G.console("bobba_manage") end) end
			if Game.opts.enterRoom then
				local id = Game.opts.enterRoom
				timer.Simple(1.5, function() G.console("bobba_room " .. id) end)
			end
		elseif k == "E" then
			state, why = "failed", msg:sub(2)
			Console.add("The hotel's server stopped: " .. why .. "\n", { r = 255, g = 90, b = 90 })
		elseif k == "X" then
			Game.serverStopped = true
		else
			G.incoming(msg)
		end
	end
end

function Game.update(dt)
	if not G then return end
	if state == "loading" then
		-- (one frame of "starting" first, then the gamemode loads)
		if love.timer.getTime() - startedAt > 0.05 then
			loadClient()
			state = "playing"
		end
		return
	end
	serverMessages()
	G.tick(dt)
	-- (a controller: walking, the pointer, the wheels)
	if not Console.isOpen() then pcall(Pad.update, dt, G) end
	G.vguiUpdate()
	if serverThread and serverThread:getError() then
		local err = serverThread:getError()
		serverThread = nil
		state, why = "failed", err
		Console.add("The hotel's server stopped: " .. tostring(err) .. "\n", { r = 255, g = 90, b = 90 })
		Console.open = true
	end
end

function Game.draw()
	local lg = love.graphics
	if not G or state == "loading" then
		lg.clear(0.05, 0.11, 0.17)
		lg.setColor(1, 1, 1)
		lg.printf("Starting the hotel...", 0, lg.getHeight() / 2 - 10, lg.getWidth(), "center")
		return
	end
	-- (GMod's world isn't drawn while the room view is up: it clears to its colour)
	lg.clear(0, 0, 0)
	hook.Run("RenderScene")
	hook.Run("PreDrawHUD")
	hook.Run("HUDPaint")
	hook.Run("PostDrawHUD")
	G.vguiDraw()
	hook.Run("DrawOverlay")
	lg.origin()
	lg.setScissor()
	hook.Run("PostRender")
	lg.origin()
	lg.setScissor()
	Game.snapshot()
	Pad.draw()
	if state == "failed" then
		lg.setColor(0, 0, 0, 0.7)
		lg.rectangle("fill", 0, 0, lg.getWidth(), 60)
		lg.setColor(1, 0.5, 0.5)
		lg.printf("The hotel's server stopped. F1 shows the console.", 10, 10, lg.getWidth() - 20, "left")
		lg.setColor(1, 1, 1)
		lg.printf(tostring(why), 10, 30, lg.getWidth() - 20, "left")
	end
	Console.draw()
end

-- your avatar for the start page: drawn by the game itself now and then, saved as avatar.png
local snapUnit, snapAt, snapFigure
function Game.snapshot()
	local R = BOBBA and BOBBA.room
	if not (R and R.figureDrawer and R.you and R.units and Game.spawnedAt) then return end
	local u = R.units[R.you]
	if not u then return end
	local figure = u.figure or ""
	local now = love.timer.getTime()
	if snapFigure == figure and now - (snapAt or 0) < 30 then return end
	if now - Game.spawnedAt < 3 or (snapAt and now - snapAt < 2) then return end
	snapAt = now
	snapUnit = snapUnit or { id = "desktop_snapshot", name = "" }
	snapUnit.figure = u.figure
	snapUnit.gender = u.gender
	local lg = love.graphics
	local canvas = lg.newCanvas(128, 200)
	lg.setCanvas(canvas)
	lg.clear(0, 0, 0, 0)
	lg.origin()
	local ok, drew = pcall(R.figureDrawer, snapUnit, { x = 0, y = 0, z = 0, sx = 64, sy = 184, k = 1, dir = 2, posture = "std", now = SysTime(), talk = false })
	lg.setCanvas()
	if ok and drew then
		-- (only once something was drawn: the clothes may still be loading)
		-- (cut to what's drawn)
		local data = canvas:newImageData()
		local x0, y0, x1, y1 = 128, 200, -1, -1
		for y = 0, 199 do
			for x = 0, 127 do
				local _, _, _, a = data:getPixel(x, y)
				if a > 0 then
					if x < x0 then x0 = x end
					if x > x1 then x1 = x end
					if y < y0 then y0 = y end
					if y > y1 then y1 = y end
				end
			end
		end
		if x1 >= x0 then
			local w, h = x1 - x0 + 1, y1 - y0 + 1
			local cut = love.image.newImageData(w, h)
			cut:paste(data, 0, 0, x0, y0, w, h)
			FS.write(Game.opts.save .. "/avatar.png", cut:encode("png"):getString())
			snapFigure = figure
		end
	end
end

function Game.mousepressed(x, y, b) if G and state == "playing" and not Console.isOpen() then G.mousePressed(x, y, b) end end
function Game.mousereleased(x, y, b) if G and state == "playing" then G.mouseReleased(x, y, b) end end
function Game.mousemoved(x, y) if G and state == "playing" then G.mouseMoved(x, y) end end
function Game.wheelmoved(dx, dy)
	if Console.isOpen() then Console.wheel(dy) return end
	if G and state == "playing" then G.wheelMoved(dx, dy) end
end
function Game.keypressed(key, scancode, isRepeat)
	if key == "f11" then
		local Win, Settings = require("bobba.window"), require("bobba.settings")
		Win.toggle()
		local st = Settings.load()
		st.fullscreen = Win.full()
		Settings.save(st)
		return
	end
	if key == "f1" or (key == "`" and Console.isOpen()) then Console.toggle() return end
	if Console.isOpen() then Console.key(key) return end
	if G and state == "playing" then G.keyPressed(key, isRepeat) end
end
function Game.keyreleased(key) if G and state == "playing" then G.keyReleased(key) end end
function Game.textinput(t)
	if Console.isOpen() then Console.text(t) return end
	if G and state == "playing" then G.textInput(t) end
end
function Game.resize(w, h)
	if G and state == "playing" then hook.Run("OnScreenSizeChanged", G.world.w, G.world.h) end
end

-- stopping: the server saves and stops (waits a little for it)
function Game.stop()
	if not G then return end
	toServer:push("Q")
	local t0 = love.timer.getTime()
	while serverThread and serverThread:isRunning() and love.timer.getTime() - t0 < 5 do
		love.timer.sleep(0.02)
	end
	HTTP.stopWorkers()
	Console.close()
end

return Game
