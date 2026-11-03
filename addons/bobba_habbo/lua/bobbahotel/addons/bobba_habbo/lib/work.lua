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
-- ... and while the hotel's loading screen or the avatar editor is open (a lower frame rate there is
-- better than waiting)
H.WORK_BUDGET_BUSY = 0.030
local function budget()
	if BOBBA.loading and BOBBA.loading.active then return H.WORK_BUDGET_BUSY end
	if BOBBA.ui and BOBBA.ui.windows and BOBBA.ui.windows["avatar-editor"] then return H.WORK_BUDGET_BUSY end
	return H.WORK_BUDGET
end

local jobs = {}
local started = 0

local function now()
	return P.clock and P.clock() or os.clock()
end

-- in a job: give the frame back when this frame's time is used up
function H.yield()
	local co, main = coroutine.running()
	if not co or main or not jobs[co] then return end
	if now() - started >= budget() then coroutine.yield() end
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
			if now() - started >= budget() then break end
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

-- Downloads: at most H.DOWNLOADS at once (like a browser), the rest wait their turn
H.DOWNLOADS = 6
local active, queue = 0, {}
local function nextDownload()
	while active < H.DOWNLOADS and #queue > 0 do
		local d = table.remove(queue, 1)
		active = active + 1
		local finished = false
		local function finish()
			if finished then return false end
			finished = true
			active = active - 1
			nextDownload()
			return true
		end
		P.httpGet(d.url, function(body) if finish() then d.ok(body) end end, function(why) if finish() then d.fail(why) end end)
	end
end

-- canWait: behind every other download (fetching ahead, like the editor's clothes)
function H.httpGet(url, ok, fail, canWait)
	local d = { url = url, ok = ok, fail = fail, low = canWait }
	if H.loadingGame then
		afterLoad[#afterLoad + 1] = function() H.httpGet(url, ok, fail, d.low) end
		return d
	end
	if canWait then
		queue[#queue + 1] = d
	else
		-- (in front of the ones that can wait)
		local at = #queue + 1
		for i, q in ipairs(queue) do if q.low then at = i break end end
		table.insert(queue, at, d)
	end
	nextDownload()
	return d
end

-- a download that could wait is wanted now after all (something needs it on screen)
function H.hurryDownload(d)
	if not d or not d.low then return end
	d.low = false
	for i, q in ipairs(queue) do
		if q == d then
			table.remove(queue, i)
			local at = #queue + 1
			for j, q2 in ipairs(queue) do if q2.low then at = j break end end
			table.insert(queue, at, d)
			return
		end
	end
end

function H.work(fn, canWait)
	if not P.every then fn() return end
	-- (while the game loads, only what can't wait runs, all at once: it's behind the loading screen)
	if H.loadingGame and not canWait then fn() return end
	local co = coroutine.create(fn)
	jobs[co] = canWait and "low" or true
	P.every("habbo.work", 0, step)
	return co
end

-- a job that could wait is wanted now after all
function H.hurryWork(co)
	if co and jobs[co] == "low" then jobs[co] = true end
end
