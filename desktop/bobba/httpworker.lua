-- A download thread: takes "id \0 reply channel \0 url" from the bobba_http channel, downloads it
-- and puts "id \0 code \0 body" (code 0: it failed, the body says why) on the reply channel.
-- Windows downloads through WinHTTP (what Windows itself uses, with the system's certificates and
-- proxy); elsewhere through curl.

require("love.thread")
local ffi = require("ffi")
local requests = love.thread.getChannel("bobba_http")

local USER_AGENT = "Valve/Steam HTTP Client 1.0 (4000)" -- (what GMod's http.Fetch says it is)

-- tests: answers from files instead of the internet (BOBBA_DESKTOP_FAKE_HTTP = a Lua file that
-- returns function(url) -> code, body)
local fake = ...
if fake and fake ~= "" then
	local f = io.open(fake, "rb")
	local src = f and f:read("*a")
	if f then f:close() end
	fake = src and loadstring(src, "@" .. fake)()
else
	fake = nil
end

local get

if fake then
	get = fake
elseif ffi.os == "Windows" then
	ffi.cdef [[
	void* WinHttpOpen(const uint16_t* agent, uint32_t access, const uint16_t* proxy, const uint16_t* bypass, uint32_t flags);
	void* WinHttpConnect(void* session, const uint16_t* host, uint16_t port, uint32_t reserved);
	void* WinHttpOpenRequest(void* connect, const uint16_t* verb, const uint16_t* path, const uint16_t* version, const uint16_t* referrer, const uint16_t** types, uint32_t flags);
	int WinHttpSendRequest(void* request, const uint16_t* headers, uint32_t headersLength, void* optional, uint32_t optionalLength, uint32_t total, uintptr_t context);
	int WinHttpReceiveResponse(void* request, void* reserved);
	int WinHttpQueryHeaders(void* request, uint32_t level, const uint16_t* name, void* buffer, uint32_t* length, uint32_t* index);
	int WinHttpQueryDataAvailable(void* request, uint32_t* available);
	int WinHttpReadData(void* request, void* buffer, uint32_t toRead, uint32_t* read);
	int WinHttpCloseHandle(void* handle);
	int WinHttpSetTimeouts(void* handle, int resolve, int connect, int send, int receive);
	int WinHttpSetOption(void* handle, uint32_t option, void* buffer, uint32_t length);
	uint32_t GetLastError(void);
	int MultiByteToWideChar(uint32_t page, uint32_t flags, const char* s, int n, uint16_t* out, int size);
	]]
	local W = ffi.load("winhttp")
	local C = ffi.C
	local function wide(s)
		local n = C.MultiByteToWideChar(65001, 0, s, #s, nil, 0)
		local buf = ffi.new("uint16_t[?]", n + 1)
		C.MultiByteToWideChar(65001, 0, s, #s, buf, n)
		buf[n] = 0
		return buf
	end
	-- (automatic proxy needs Windows 8.1; older ones take the default)
	local session = W.WinHttpOpen(wide(USER_AGENT), 4, nil, nil, 0)
	if session == nil then session = W.WinHttpOpen(wide(USER_AGENT), 0, nil, nil, 0) end
	if session ~= nil then
		W.WinHttpSetTimeouts(session, 15000, 15000, 30000, 60000)
		-- gzip and deflate (WINHTTP_OPTION_DECOMPRESSION, Windows 8.1)
		local flags = ffi.new("uint32_t[1]", 3)
		W.WinHttpSetOption(session, 118, flags, 4)
	end

	local function curl(url)
		local p = io.popen('curl.exe -sL --max-time 120 -A "' .. USER_AGENT .. '" -w "\n%{http_code}" "' .. url:gsub('"', "%%22") .. '"', "rb")
		if not p then return 0, "WinHTTP and curl didn't start" end
		local out = p:read("*a")
		p:close()
		local body, code = out:match("^(.*)\n(%d+)$")
		if not body then return 0, "curl failed" end
		return tonumber(code), body
	end
	get = function(url)
		if session == nil then return curl(url) end
		local scheme, host, port, path = url:match("^(%a+)://([^/:]+):?(%d*)(.*)$")
		if not scheme then return 0, "not a web address: " .. url end
		scheme = scheme:lower()
		port = tonumber(port) or (scheme == "https" and 443 or 80)
		if path == "" then path = "/" end
		local connect = W.WinHttpConnect(session, wide(host), port, 0)
		if connect == nil then return 0, "can't reach " .. host .. " (" .. C.GetLastError() .. ")" end
		local req = W.WinHttpOpenRequest(connect, wide("GET"), wide(path), nil, nil, nil, scheme == "https" and 0x00800000 or 0)
		if req == nil then W.WinHttpCloseHandle(connect) return 0, "request failed (" .. C.GetLastError() .. ")" end
		local function done(code, body)
			W.WinHttpCloseHandle(req)
			W.WinHttpCloseHandle(connect)
			return code, body
		end
		if W.WinHttpSendRequest(req, nil, 0, nil, 0, 0, 0) == 0 then return done(0, "couldn't send (" .. C.GetLastError() .. ")") end
		if W.WinHttpReceiveResponse(req, nil) == 0 then return done(0, "no answer (" .. C.GetLastError() .. ")") end
		local status = ffi.new("uint32_t[1]")
		local size = ffi.new("uint32_t[1]", 4)
		-- WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER
		W.WinHttpQueryHeaders(req, 19 + 0x20000000, nil, status, size, nil)
		local parts = {}
		local avail = ffi.new("uint32_t[1]")
		local got = ffi.new("uint32_t[1]")
		local cap = 0
		local buf
		while true do
			if W.WinHttpQueryDataAvailable(req, avail) == 0 then return done(0, "download cut off (" .. C.GetLastError() .. ")") end
			local n = avail[0]
			if n == 0 then break end
			if n > cap then cap = n buf = ffi.new("uint8_t[?]", cap) end
			if W.WinHttpReadData(req, buf, n, got) == 0 then return done(0, "download cut off (" .. C.GetLastError() .. ")") end
			if got[0] == 0 then break end
			parts[#parts + 1] = ffi.string(buf, got[0])
		end
		return done(status[0], table.concat(parts))
	end
else
	get = function(url)
		local p = io.popen("curl -sL --max-time 120 -A '" .. USER_AGENT .. "' -w '\\n%{http_code}' '" .. url:gsub("'", "%%27") .. "'", "r")
		if not p then return 0, "curl didn't start" end
		local out = p:read("*a")
		p:close()
		local body, code = out:match("^(.*)\n(%d+)$")
		if not body then return 0, "curl failed" end
		return tonumber(code), body
	end
end

while true do
	local req = requests:demand()
	if req == "quit" then requests:push("quit") break end
	local id, reply, url = req:match("^(%d+)%z([^%z]+)%z(.*)$")
	if id then
		local ok, code, body = pcall(get, url)
		if not ok then code, body = 0, tostring(code) end
		love.thread.getChannel(reply):push(id .. "\0" .. tostring(code or 0) .. "\0" .. (body or ""))
	end
end
