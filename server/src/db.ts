// The database. Tables are created and upgraded by numbered migrations: add new ones at the end,
// never edit one that has already run on the live server.
import { DatabaseSync } from 'node:sqlite';

const MIGRATIONS: string[] = [
  // 1: accounts and logins
  `CREATE TABLE users (
     id INTEGER PRIMARY KEY,
     steam_id TEXT,
     name TEXT NOT NULL UNIQUE COLLATE NOCASE,
     look TEXT NOT NULL,
     guest INTEGER NOT NULL DEFAULT 0,
     created INTEGER NOT NULL,
     last_seen INTEGER NOT NULL
   );
   CREATE INDEX users_steam ON users(steam_id);
   CREATE TABLE sessions (
     token_hash TEXT PRIMARY KEY,
     user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
     steam_id TEXT,
     created INTEGER NOT NULL,
     expires INTEGER NOT NULL
   );`,
];

export type Db = DatabaseSync;

export function openDb(file: string): Db {
  const db = new DatabaseSync(file);
  db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
  migrate(db);
  return db;
}

function migrate(db: Db): void {
  const current = (db.prepare('PRAGMA user_version').get() as { user_version: number }).user_version;
  for (let v = current; v < MIGRATIONS.length; v++) {
    db.exec('BEGIN');
    try {
      db.exec(MIGRATIONS[v]!);
      db.exec(`PRAGMA user_version = ${v + 1}`);
      db.exec('COMMIT');
    } catch (err) {
      db.exec('ROLLBACK');
      throw err;
    }
  }
}
