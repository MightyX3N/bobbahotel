// Hotel accounts.
import { lookSchema, randomLook, type Look } from '@bobba/shared';
import type { Db } from './db.ts';

export interface User {
  id: number;
  name: string;
  look: Look;
  guest: boolean;
  steamId: string | null;
  /** Bobba Club runs until this time (ms); 0 = never had it. */
  clubUntil: number;
}

/** Guests that haven't been seen for this long are removed (and their name freed). */
const GUEST_LIFETIME_MS = 7 * 24 * 3600 * 1000;

interface Row {
  id: number;
  name: string;
  look: string;
  guest: number;
  steam_id: string | null;
  club_until: number;
}

const COLUMNS = 'id, name, look, guest, steam_id, club_until';

export class Users {
  private readonly db: Db;
  constructor(db: Db) {
    this.db = db;
  }

  byId(id: number): User | null {
    const row = this.db.prepare(`SELECT ${COLUMNS} FROM users WHERE id = ?`).get(id) as Row | undefined;
    return row ? toUser(row, this.db) : null;
  }

  bySteamId(steamId: string): User[] {
    const rows = this.db.prepare(`SELECT ${COLUMNS} FROM users WHERE steam_id = ? ORDER BY id`).all(steamId) as unknown as Row[];
    return rows.map((r) => toUser(r, this.db));
  }

  nameTaken(name: string): boolean {
    return this.db.prepare('SELECT 1 FROM users WHERE name = ?').get(name) !== undefined;
  }

  /** Creates an account. Throws "name_taken" if the name is in use. */
  create(input: { name: string; steamId?: string; guest?: boolean }, now = Date.now()): User {
    const look = randomLook();
    try {
      const result = this.db
        .prepare('INSERT INTO users (steam_id, name, look, guest, created, last_seen) VALUES (?, ?, ?, ?, ?, ?)')
        .run(input.steamId ?? null, input.name, JSON.stringify(look), input.guest ? 1 : 0, now, now);
      return { id: Number(result.lastInsertRowid), name: input.name, look, guest: !!input.guest, steamId: input.steamId ?? null, clubUntil: 0 };
    } catch (err) {
      if (String(err).includes('UNIQUE')) throw new Error('name_taken');
      throw err;
    }
  }

  byName(name: string): User | null {
    const row = this.db.prepare(`SELECT ${COLUMNS} FROM users WHERE name = ?`).get(name) as Row | undefined;
    return row ? toUser(row, this.db) : null;
  }

  /** Adds Bobba Club days (counting from now, or from the current end if Club is still running). */
  addClubDays(id: number, days: number, now = Date.now()): number {
    const row = this.db.prepare('SELECT club_until FROM users WHERE id = ?').get(id) as { club_until: number } | undefined;
    if (!row) throw new Error('no such user');
    // Adding counts on from the current end while Club is running; taking away never goes below now.
    const until = Math.max(Math.max(row.club_until, now) + days * 86_400_000, days < 0 ? now : 0);
    this.db.prepare('UPDATE users SET club_until = ? WHERE id = ?').run(until, id);
    return until;
  }

  touch(id: number, now = Date.now()): void {
    this.db.prepare('UPDATE users SET last_seen = ? WHERE id = ?').run(now, id);
  }

  removeStaleGuests(now = Date.now()): number {
    return Number(this.db.prepare('DELETE FROM users WHERE guest = 1 AND last_seen < ?').run(now - GUEST_LIFETIME_MS).changes);
  }
}

function toUser(row: Row, db: Db): User {
  const parsed = lookSchema.safeParse(JSON.parse(row.look));
  let look: Look;
  if (parsed.success) look = parsed.data;
  else {
    // A look that no longer fits the parts (e.g. after a sprite pack change): give a new one and keep it.
    look = randomLook();
    db.prepare('UPDATE users SET look = ? WHERE id = ?').run(JSON.stringify(look), row.id);
  }
  return {
    id: row.id,
    name: row.name,
    look,
    guest: row.guest === 1,
    steamId: row.steam_id,
    clubUntil: row.club_until,
  };
}
