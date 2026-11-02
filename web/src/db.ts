// The hotel database (Arcturus' MariaDB) plus the website's own two tables:
//   bobba_steam     which hotel account belongs to which Steam account
//   bobba_sessions  website logins (only a hash of each login token is kept)
import mysql from 'mysql2/promise';
import type { Config } from './config.ts';

export type Db = mysql.Pool;

export async function openDb(config: Config): Promise<Db> {
  const db = mysql.createPool({ ...config.db, connectionLimit: 4, charset: 'utf8mb4', timezone: 'Z' });
  await db.query(`CREATE TABLE IF NOT EXISTS bobba_steam (
    steam_id VARCHAR(20) NOT NULL PRIMARY KEY,
    user_id INT NOT NULL UNIQUE,
    created INT NOT NULL
  )`);
  await db.query(`CREATE TABLE IF NOT EXISTS bobba_sessions (
    token_hash CHAR(64) NOT NULL PRIMARY KEY,
    steam_id VARCHAR(20) NOT NULL,
    created INT NOT NULL,
    expires INT NOT NULL,
    KEY expires (expires)
  )`);
  return db;
}

export interface Account {
  id: number;
  username: string;
  look: string;
  gender: 'M' | 'F';
  rank: number;
}

export async function accountBySteamId(db: Db, steamId: string): Promise<Account | null> {
  const [rows] = await db.query<mysql.RowDataPacket[]>(
    'SELECT u.id, u.username, u.look, u.gender, u.`rank` FROM bobba_steam s JOIN users u ON u.id = s.user_id WHERE s.steam_id = ?',
    [steamId],
  );
  return (rows[0] as Account | undefined) ?? null;
}

export async function nameTaken(db: Db, name: string): Promise<boolean> {
  const [rows] = await db.query<mysql.RowDataPacket[]>('SELECT 1 FROM users WHERE username = ?', [name]);
  return rows.length > 0;
}

/** Creates a hotel account for a Steam account. Throws 'name_taken' if the name is gone. */
export async function createAccount(
  db: Db,
  input: { steamId: string; name: string; look: string; gender: 'M' | 'F'; rank: number; ip: string },
): Promise<number> {
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();
    const now = Math.floor(Date.now() / 1000);
    let id: number;
    try {
      const [res] = await conn.query<mysql.ResultSetHeader>(
        `INSERT INTO users (username, real_name, password, mail, account_created, last_login, motto, look, gender, \`rank\`, credits, pixels, points, ip_register, ip_current, home_room)
         VALUES (?, '', '', NULL, ?, 0, '', ?, ?, ?, ?, 0, 0, ?, ?, ?)`,
        [input.name, now, input.look, input.gender, input.rank, STARTING.credits, input.ip, input.ip, WELCOME_ROOM],
      );
      id = res.insertId;
    } catch (e) {
      if ((e as { code?: string }).code === 'ER_DUP_ENTRY') throw new Error('name_taken');
      throw e;
    }
    await conn.query('INSERT INTO bobba_steam (steam_id, user_id, created) VALUES (?, ?, ?)', [input.steamId, id, now]);
    await conn.query('INSERT INTO users_currency (user_id, type, amount) VALUES (?, 0, ?), (?, 5, ?)', [
      id, STARTING.duckets, id, STARTING.diamonds,
    ]);
    await conn.commit();
    return id;
  } catch (e) {
    await conn.rollback();
    throw e;
  } finally {
    conn.release();
  }
}

/** The public room new players go into first (sql/lobby.sql). */
export const WELCOME_ROOM = 100;

/** What a new player starts with. */
export const STARTING = { credits: 1000, duckets: 200, diamonds: 0 };

/** A one-time login ticket for the game client (Arcturus clears it when it's used). */
export async function setTicket(db: Db, userId: number, ticket: string, ip: string): Promise<void> {
  await db.query('UPDATE users SET auth_ticket = ?, ip_current = ? WHERE id = ?', [ticket, ip, userId]);
}

export async function setRank(db: Db, userId: number, rank: number): Promise<void> {
  await db.query('UPDATE users SET `rank` = ? WHERE id = ?', [rank, userId]);
}
