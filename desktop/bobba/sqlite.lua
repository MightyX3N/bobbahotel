-- SQLite through the copy Windows itself has (winsqlite3.dll, Windows 10 and later), or the
-- system's libsqlite3 elsewhere. Answers like GMod's sql.Query: a list of rows with every value as
-- text (NULLs left out), nil when there are no rows, false on an error (SQ.lastError says why).

local ffi = require("ffi")
ffi.cdef [[
	typedef struct sqlite3 sqlite3;
	typedef struct sqlite3_stmt sqlite3_stmt;
	int sqlite3_open_v2(const char* filename, sqlite3** db, int flags, const char* vfs);
	int sqlite3_close_v2(sqlite3* db);
	int sqlite3_prepare_v2(sqlite3* db, const char* sql, int n, sqlite3_stmt** stmt, const char** tail);
	int sqlite3_step(sqlite3_stmt* stmt);
	int sqlite3_finalize(sqlite3_stmt* stmt);
	int sqlite3_column_count(sqlite3_stmt* stmt);
	const char* sqlite3_column_name(sqlite3_stmt* stmt, int i);
	int sqlite3_column_type(sqlite3_stmt* stmt, int i);
	const unsigned char* sqlite3_column_text(sqlite3_stmt* stmt, int i);
	int sqlite3_column_bytes(sqlite3_stmt* stmt, int i);
	const char* sqlite3_errmsg(sqlite3* db);
	int sqlite3_busy_timeout(sqlite3* db, int ms);
]]

local lib
for _, name in ipairs(ffi.os == "Windows" and { "winsqlite3", "sqlite3" } or { "sqlite3", "libsqlite3.so.0" }) do
	local ok, l = pcall(ffi.load, name)
	if ok then lib = l break end
end

local SQ = {}
SQ.available = lib ~= nil

local ROW, DONE, NULL = 100, 101, 5

-- opens (making it when it isn't there) a database file; returns a db or nil, why
function SQ.open(path)
	if not lib then return nil, "SQLite isn't on this computer" end
	local p = ffi.new("sqlite3*[1]")
	local rc = lib.sqlite3_open_v2(path, p, 0x02 + 0x04, nil) -- READWRITE | CREATE
	if rc ~= 0 then return nil, "can't open " .. path .. " (" .. rc .. ")" end
	local db = { handle = p[0], lastError = "" }
	lib.sqlite3_busy_timeout(db.handle, 3000)
	return setmetatable(db, { __index = SQ })
end

function SQ:close()
	if self.handle then lib.sqlite3_close_v2(self.handle) self.handle = nil end
end

-- runs every statement in s; the rows of the last one that gave rows
function SQ:query(s)
	local rows
	local tail = ffi.new("const char*[1]")
	local stmt = ffi.new("sqlite3_stmt*[1]")
	local buf = ffi.new("char[?]", #s + 1, s)
	local at = buf
	local finish = buf + #s
	while at < finish do
		local rc = lib.sqlite3_prepare_v2(self.handle, at, finish - at, stmt, tail)
		if rc ~= 0 then
			self.lastError = ffi.string(lib.sqlite3_errmsg(self.handle))
			return false
		end
		at = tail[0]
		local st = stmt[0]
		if st == nil then break end -- (only spaces or a comment left)
		local cols, names = lib.sqlite3_column_count(st), {}
		for i = 0, cols - 1 do names[i] = ffi.string(lib.sqlite3_column_name(st, i)) end
		local got = {}
		while true do
			rc = lib.sqlite3_step(st)
			if rc == ROW then
				local r = {}
				for i = 0, cols - 1 do
					if lib.sqlite3_column_type(st, i) ~= NULL then
						local t = lib.sqlite3_column_text(st, i)
						r[names[i]] = ffi.string(t, lib.sqlite3_column_bytes(st, i))
					end
				end
				got[#got + 1] = r
			elseif rc == DONE then
				break
			else
				self.lastError = ffi.string(lib.sqlite3_errmsg(self.handle))
				lib.sqlite3_finalize(st)
				return false
			end
		end
		lib.sqlite3_finalize(st)
		if cols > 0 then rows = got end
	end
	if rows and #rows == 0 then return nil end
	return rows
end

-- a string as an SQL literal ('it''s'), like GMod's sql.SQLStr
function SQ.quote(s, noQuotes)
	s = tostring(s):gsub("'", "''")
	local cut = s:find("\0", 1, true)
	if cut then s = s:sub(1, cut - 1) end
	if noQuotes then return s end
	return "'" .. s .. "'"
end

return SQ
