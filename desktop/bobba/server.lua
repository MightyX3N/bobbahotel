-- The hotel's server, on its own thread (its own Lua, like a GMod listen server): it loads the
-- gamemode's init.lua with SERVER = true and talks to the game through two channels.
--   to the game:  N net message, P console text, S the player is in, E it failed to start
--   from the game: N net message, C console line, Q quit

require("love.filesystem")
require("love.timer")
require("love.thread")
require("love.data")

local args = ...
local toGame = love.thread.getChannel("bobba_to_game")
local toServer = love.thread.getChannel("bobba_to_server")

local function console(text, color)
	toGame:push("P" .. text)
end

local ok, err = pcall(function()
	local G = require("bobba.gmod")({
		server = true,
		garrysmod = args.garrysmod,
		save = args.save,
		database = args.database,
		player = { key = args.playerKey, name = args.playerName },
		transport = function(s) toGame:push(s) end,
		console = console,
	})

	G.runFile(args.garrysmod .. "/gamemodes/bobbahotel/gamemode/init.lua", "bobbahotel/gamemode/init.lua")
	hook.Run("Initialize")
	hook.Run("InitPostEntity")

	-- the player joins
	G.player.valid = true
	hook.Run("PlayerConnect", G.player:Nick(), "loopback")
	hook.Run("PlayerAuthed", G.player, G.player:SteamID(), G.player:UserID())
	hook.Run("PlayerInitialSpawn", G.player)
	hook.Run("PlayerSpawn", G.player)
	toGame:push("S")

	local TICK = 1 / 66
	local last = love.timer.getTime()
	while true do
		local quit = false
		while true do
			local msg = toServer:pop()
			if not msg then break end
			if msg == "Q" then quit = true break end
			G.incoming(msg)
		end
		if quit then break end
		local now = love.timer.getTime()
		G.tick(now - last)
		last = now
		local spare = TICK - (love.timer.getTime() - now)
		if spare > 0 then love.timer.sleep(spare) end
	end

	-- leaving: what the hotel does when someone leaves and the server stops
	hook.Run("PlayerDisconnected", G.player)
	G.player.valid = false
	hook.Run("ShutDown")
	if G.db then G.db:close() end
	toGame:push("X")
end)

if not ok then
	io.write("[server] failed: " .. tostring(err) .. "\n")
	toGame:push("E" .. tostring(err))
end
