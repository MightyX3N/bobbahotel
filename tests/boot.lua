-- Loads the core the way GMod does, with the test platform in place of platform/gmod.lua.
local function run(path)
	local f = assert(loadfile(path))
	return f()
end
local files = run(GM_ROOT .. "/hotel/files.lua")
for _, f in ipairs(files) do
	if f == "PLATFORM" then run(TEST_ROOT .. "/platform_test.lua") else run(GM_ROOT .. "/" .. f) end
end
BOBBA.store.init()

-- tiny helpers for the tests
function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
function lastLog()
	local l = BOBBA.platform.logs
	return l[#l] and l[#l].msg or ""
end
