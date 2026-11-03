-- Bobba Hotel core. Everything under hotel/ is plain Lua: no GMod functions, no GMod-only syntax
-- (no !=, &&, ||, //, continue). It reaches the outside world only through BOBBA.platform, so the
-- same files can later run outside GMod (the custom server).

BOBBA = BOBBA or {}
BOBBA.VERSION = "0.1.0"

local function platform()
	local p = BOBBA.platform
	if not p then error("Bobba Hotel: no platform loaded", 2) end
	return p
end

function BOBBA.log(level, fmt, ...)
	local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
	platform().log(level, msg)
end

function BOBBA.info(fmt, ...) BOBBA.log("info", fmt, ...) end
function BOBBA.warn(fmt, ...) BOBBA.log("warn", fmt, ...) end
function BOBBA.err(fmt, ...) BOBBA.log("error", fmt, ...) end

-- Calls fn(...) and logs instead of breaking when it fails. Addon code goes through this, so one
-- broken addon can't stop the hotel from loading.
function BOBBA.safe(what, fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then
		BOBBA.err("%s failed: %s", what, tostring(res))
		return false, res
	end
	return true, res
end
