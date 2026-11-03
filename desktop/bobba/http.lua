-- Downloads without waiting: HTTP.get(url, done(code, body)); HTTP.poll() (every frame) calls back
-- the ones that finished. The downloading is done by a few threads (httpworker.lua) shared by the
-- game and its server.

require("love.thread")
local HTTP = {}
local WORKERS = 6

local requests = love.thread.getChannel("bobba_http")
local replyName, replies
local pending, nextId = {}, 0

-- the main program starts the threads once; every Lua state that downloads calls HTTP.init(name)
function HTTP.startWorkers(fakeFile)
	for _ = 1, WORKERS do
		local t = love.thread.newThread("bobba/httpworker.lua")
		t:start(fakeFile or "")
		HTTP.threads = HTTP.threads or {}
		HTTP.threads[#HTTP.threads + 1] = t
	end
end

function HTTP.stopWorkers()
	requests:clear()
	requests:push("quit")
end

function HTTP.init(name)
	replyName = "bobba_http_reply_" .. name
	replies = love.thread.getChannel(replyName)
	replies:clear()
end

function HTTP.get(url, done)
	nextId = nextId + 1
	pending[nextId] = done
	requests:push(nextId .. "\0" .. replyName .. "\0" .. url)
end

function HTTP.poll()
	if not replies then return end
	while true do
		local msg = replies:pop()
		if not msg then break end
		local a = msg:find("\0", 1, true)
		local b = msg:find("\0", a + 1, true)
		local id, code, body = tonumber(msg:sub(1, a - 1)), tonumber(msg:sub(a + 1, b - 1)), msg:sub(b + 1)
		local done = pending[id]
		pending[id] = nil
		if done then
			local ok, err = pcall(done, code, body)
			if not ok then print("[Desktop] download callback: " .. tostring(err)) end
		end
	end
end

return HTTP
