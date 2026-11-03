-- Files anywhere on the computer (Love's own love.filesystem only sees the game and its save
-- folder): reading, writing, listing folders and making them. Windows through its own functions
-- (paths are UTF-8 here and wide inside, so folders with any letters work); elsewhere POSIX.

local ffi = require("ffi")
local bit = require("bit")
local FS = {}
FS.windows = ffi.os == "Windows"

if FS.windows then
	ffi.cdef [[
	typedef struct { uint32_t lo, hi; } BOBBA_FILETIME;
	typedef struct {
		uint32_t attributes;
		BOBBA_FILETIME created, accessed, written;
		uint32_t sizeHigh, sizeLow, reserved0, reserved1;
		uint16_t name[260];
		uint16_t alternate[14];
	} BOBBA_FIND_DATA;
	void* FindFirstFileW(const uint16_t* pattern, BOBBA_FIND_DATA* data);
	int FindNextFileW(void* handle, BOBBA_FIND_DATA* data);
	int FindClose(void* handle);
	int CreateDirectoryW(const uint16_t* path, void* security);
	uint32_t GetFileAttributesW(const uint16_t* path);
	int MultiByteToWideChar(uint32_t page, uint32_t flags, const char* s, int n, uint16_t* out, int size);
	int WideCharToMultiByte(uint32_t page, uint32_t flags, const uint16_t* s, int n, char* out, int size, const char* def, int* used);
	void* _wfopen(const uint16_t* path, const uint16_t* mode);
	]]
end
ffi.cdef [[
	size_t fread(void* buf, size_t size, size_t n, void* f);
	size_t fwrite(const void* buf, size_t size, size_t n, void* f);
	int fclose(void* f);
	int fseek(void* f, long off, int whence);
	long ftell(void* f);
]]

local C = ffi.C
local INVALID = ffi.cast("void*", -1)
-- (the C library's wide-name fopen; if it can't be found, Lua's own io.open is used)
local wideFiles = FS.windows and pcall(function() return C._wfopen and C.fread and C.fwrite and C.fclose and C.fseek and C.ftell end)

-- UTF-8 <-> UTF-16 (Windows)
local function wide(s)
	local n = C.MultiByteToWideChar(65001, 0, s, #s, nil, 0)
	local buf = ffi.new("uint16_t[?]", n + 1)
	C.MultiByteToWideChar(65001, 0, s, #s, buf, n)
	buf[n] = 0
	return buf
end
local function narrow(w)
	local n = C.WideCharToMultiByte(65001, 0, w, -1, nil, 0, nil, nil)
	if n <= 1 then return "" end
	local buf = ffi.new("char[?]", n)
	C.WideCharToMultiByte(65001, 0, w, -1, buf, n, nil, nil)
	return ffi.string(buf, n - 1)
end
FS.wide, FS.narrow = wide, narrow

-- one way of writing paths: forward slashes, no slash at the end
function FS.clean(p)
	p = tostring(p or ""):gsub("\\", "/")
	if #p > 1 and not p:match("^%a:/$") then p = p:gsub("/+$", "") end
	return p
end

function FS.join(a, b)
	if a == "" then return b end
	return FS.clean(a) .. "/" .. b
end

-- the folder a path is in
function FS.parent(p)
	return (FS.clean(p):match("^(.*)/[^/]*$"))
end

local function open(path, mode)
	if FS.windows then
		local f = C._wfopen(wide(path), wide(mode))
		if f == nil then return nil end
		return f
	end
	local f = io.open(path, mode)
	return f
end

-- the whole file, or nil
function FS.read(path)
	if wideFiles then
		local f = open(path, "rb")
		if not f then return nil end
		C.fseek(f, 0, 2)
		local size = C.ftell(f)
		C.fseek(f, 0, 0)
		local data = ""
		if size > 0 then
			local buf = ffi.new("uint8_t[?]", size)
			local got = C.fread(buf, 1, size, f)
			data = ffi.string(buf, got)
		end
		C.fclose(f)
		return data
	end
	local f = io.open(path, "rb")
	if not f then return nil end
	local data = f:read("*a")
	f:close()
	return data
end

-- writes (or with append = true adds to) a file; the folder must be there (FS.mkdirs)
function FS.write(path, data, append)
	if wideFiles then
		local f = open(path, append and "ab" or "wb")
		if not f then return false end
		if #data > 0 then C.fwrite(data, 1, #data, f) end
		C.fclose(f)
		return true
	end
	local f = io.open(path, append and "ab" or "wb")
	if not f then return false end
	f:write(data)
	f:close()
	return true
end

-- "file", "dir" or nil
if FS.windows then
	function FS.kind(path)
		local a = C.GetFileAttributesW(wide(path))
		if a == 0xFFFFFFFF then return nil end
		return bit.band(a, 0x10) ~= 0 and "dir" or "file"
	end
else
	ffi.cdef [[
	void* opendir(const char* name);
	int closedir(void* d);
	typedef struct { uint64_t ino; int64_t off; uint16_t reclen; uint8_t type; char name[256]; } BOBBA_DIRENT;
	BOBBA_DIRENT* readdir(void* d);
	int mkdir(const char* path, uint32_t mode);
	]]
	function FS.kind(path)
		local d = C.opendir(path)
		if d ~= nil then C.closedir(d) return "dir" end
		local f = io.open(path, "rb")
		if f then f:close() return "file" end
		return nil
	end
end

function FS.exists(path) return FS.kind(path) ~= nil end
function FS.isDir(path) return FS.kind(path) == "dir" end

-- what's in a folder: files, folders (names, sorted)
function FS.list(dir)
	local files, dirs = {}, {}
	if FS.windows then
		local data = ffi.new("BOBBA_FIND_DATA")
		local h = C.FindFirstFileW(wide(FS.clean(dir) .. "/*"), data)
		if h == INVALID then return files, dirs end
		repeat
			local name = narrow(data.name)
			if name ~= "." and name ~= ".." then
				if bit.band(data.attributes, 0x10) ~= 0 then dirs[#dirs + 1] = name else files[#files + 1] = name end
			end
		until C.FindNextFileW(h, data) == 0
		C.FindClose(h)
	else
		local d = C.opendir(dir)
		if d == nil then return files, dirs end
		while true do
			local e = C.readdir(d)
			if e == nil then break end
			local name = ffi.string(e.name)
			if name ~= "." and name ~= ".." then
				local kind = e.type == 4 and "dir" or (e.type == 8 and "file" or FS.kind(dir .. "/" .. name))
				if kind == "dir" then dirs[#dirs + 1] = name else files[#files + 1] = name end
			end
		end
		C.closedir(d)
	end
	table.sort(files)
	table.sort(dirs)
	return files, dirs
end

-- makes a folder and the ones it's in
function FS.mkdirs(path)
	path = FS.clean(path)
	if path == "" or FS.isDir(path) then return true end
	local up = FS.parent(path)
	if up and up ~= path and not up:match("^%a:$") and up ~= "" then FS.mkdirs(up) end
	if FS.windows then C.CreateDirectoryW(wide(path), nil) else C.mkdir(path, tonumber("755", 8)) end
	return FS.isDir(path)
end

-- a glob like GMod's file.Find ("*", "*.lua", "name*"): Lua pattern
function FS.globPattern(glob)
	return "^" .. glob:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
end

return FS
