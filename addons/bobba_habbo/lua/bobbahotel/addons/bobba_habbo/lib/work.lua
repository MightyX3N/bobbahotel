-- Long work without freezing the game: a job is a function run as a coroutine, a few milliseconds
-- each frame, until it is done. Inside a job, H.yield() hands the frame back when its time is up.
-- Where the platform has no timers (tests, previews) a job simply runs to the end at once, and so
-- does every job while the game is still loading (behind the loading screen nobody sees a freeze,
-- and the avatars are ready when the room shows).
--
-- H.httpGet waits until the game has loaded (GMod can't reach the internet before that).
--
--   BOBBA.habbo.work(function() ... H.yield() ... end)
--   BOBBA.habbo.work(fn, true)   -- a job that can wait (chat bubbles, editor icons): it only gets
--     time when no other job wants it, so it never holds up the avatars, furni or room

local H = BOBBA.habbo
local P = BOBBA.platform

H.WORK_BUDGET = 0.004 -- seconds of work per frame

local jobs = {}
local started = 0

local function now()
	return P.clock and P.clock() or os.clock()
end

-- in a job: give the frame back when this frame's time is used up
function H.yield()
	local co, main = coroutine.running()
	if not co or main or not jobs[co] then return end
	if now() - started >= H.WORK_BUDGET then coroutine.yield() end
end

local function step()
	started = now()
	-- the jobs that can wait only run when no other job is waiting
	local urgent = false
	for _, kind in pairs(jobs) do if kind ~= "low" then urgent = true break end end
	for co, kind in pairs(jobs) do
		if not (urgent and kind == "low") then
			local ok, err = coroutine.resume(co)
			if not ok then
				jobs[co] = nil
				print("[Bobba] Habbo: " .. tostring(err))
			elseif coroutine.status(co) == "dead" then
				jobs[co] = nil
			end
			if now() - started >= H.WORK_BUDGET then break end
		end
	end
	if next(jobs) == nil and P.stop then P.stop("habbo.work") end
end

-- the game is loading until GMod's InitPostEntity (on GMod's client; elsewhere it never is)
H.loadingGame = (CLIENT == true) and (LocalPlayer == nil or not IsValid(LocalPlayer()))
local afterLoad = {}
if H.loadingGame and hook then
	hook.Add("InitPostEntity", "bobba.habbo.loaded", function()
		H.loadingGame = false
		local list = afterLoad
		afterLoad = {}
		for _, fn in ipairs(list) do fn() end
	end)
end

function H.httpGet(url, ok, fail)
	if H.loadingGame then
		afterLoad[#afterLoad + 1] = function() P.httpGet(url, ok, fail) end
		return
	end
	P.httpGet(url, ok, fail)
end

function H.work(fn, canWait)
	if not P.every then fn() return end
	-- (while the game loads, only what can't wait runs, all at once: it's behind the loading screen)
	if H.loadingGame and not canWait then fn() return end
	local co = coroutine.create(fn)
	jobs[co] = canWait and "low" or true
	P.every("habbo.work", 0, step)
end
