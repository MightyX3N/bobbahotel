-- Saving, on the server. GMod gives every server SQLite (sv.db), so nothing has to be installed.
-- Tables are created and changed through migrations: each runs once, in order, and is remembered.
--
--   BOBBA.store.migrate("core.001_settings", { "CREATE TABLE ...", "CREATE INDEX ..." })
--   BOBBA.store.query("SELECT * FROM bobbahotel_settings WHERE k = ?", { "lobby" })  --> list of rows
--   BOBBA.store.setting("lobby", "0")          BOBBA.store.setSetting("lobby", "12")
--
-- sv.db is shared by every gamemode and addon on the server, so every table needs a name nobody
-- else uses. The core's tables start with "bobbahotel_"; an addon starts its tables and migration
-- names with its own id (e.g. table "mywired_boxes", migration "mywired.001_boxes").

BOBBA.store = BOBBA.store or {}
local store = BOBBA.store

local function db()
	local d = BOBBA.platform.db
	if not d then error("this side has no database (only the server saves)", 3) end
	return d
end

-- Runs SQL with ? placeholders. Returns the rows (a list of tables, maybe empty). Errors on bad SQL.
function store.query(sqlText, params)
	local d = db()
	local bound = BOBBA.util.bindSql(sqlText, params, d.quote)
	local rows, err = d.query(bound)
	if rows == false then error("SQL failed: " .. tostring(err) .. "\n  in: " .. bound, 2) end
	return rows or {}
end

function store.row(sqlText, params)
	return store.query(sqlText, params)[1]
end

-- Runs fn() inside one transaction: all of it is saved, or (if fn errors) none of it. One inside
-- another is part of the outer one (SQLite has no transaction in a transaction).
store.depth = store.depth or 0
function store.transaction(fn)
	local d = db()
	if store.depth > 0 then
		store.depth = store.depth + 1
		local ok, err = pcall(fn)
		store.depth = store.depth - 1
		if not ok then error(err, 2) end
		return true
	end
	d.query("BEGIN")
	store.depth = 1
	local ok, err = pcall(fn)
	store.depth = 0
	if ok then
		d.query("COMMIT")
		return true
	end
	d.query("ROLLBACK")
	error(err, 2)
end

local function ensureMigrations()
	if store.ready then return end
	store.query("CREATE TABLE IF NOT EXISTS bobbahotel_migrations (id TEXT PRIMARY KEY, applied INTEGER NOT NULL)")
	store.ready = true
end

-- Applies a migration once. Returns true if it ran now, false if it had run before.
function store.migrate(id, statements)
	assert(type(id) == "string" and type(statements) == "table", "store.migrate(id, { sql, ... })")
	ensureMigrations()
	if store.row("SELECT id FROM bobbahotel_migrations WHERE id = ?", { id }) then return false end
	store.transaction(function()
		for _, s in ipairs(statements) do store.query(s) end
		store.query("INSERT INTO bobbahotel_migrations (id, applied) VALUES (?, ?)", { id, math.floor(BOBBA.platform.time()) })
	end)
	BOBBA.info("database: applied %s", id)
	return true
end

-- Hotel settings (strings): name, lobby room, ... Changed through the admin menu later.
-- Rows come back the way GMod's SQLite gives them: every value as text, NULLs left out.
-- Turn numbers back with tonumber().

function store.setting(key, default)
	local r = store.row("SELECT v FROM bobbahotel_settings WHERE k = ?", { key })
	if r then return r.v end
	return default
end

function store.setSetting(key, value)
	store.query("INSERT OR REPLACE INTO bobbahotel_settings (k, v) VALUES (?, ?)", { key, tostring(value) })
	BOBBA.events.emit("settingChanged", key, tostring(value))
end

function store.init()
	store.migrate("core.001_settings", {
		"CREATE TABLE bobbahotel_settings (k TEXT PRIMARY KEY, v TEXT NOT NULL)",
	})
end
