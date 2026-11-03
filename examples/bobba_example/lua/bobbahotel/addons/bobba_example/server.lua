-- Server only: an addon's own table, made once.
BOBBA.store.migrate("bobba_example.001_visits", {
	"CREATE TABLE bobba_example_visits (steamid TEXT PRIMARY KEY, visits INTEGER NOT NULL)",
})
