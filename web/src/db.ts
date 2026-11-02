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
    const room = await createStarterRoom(conn, id, input.name);
    await conn.query('UPDATE users SET home_room = ? WHERE id = ?', [room, id]);
    await conn.commit();
    return id;
  } catch (e) {
    await conn.rollback();
    throw e;
  } finally {
    conn.release();
  }
}

type Conn = mysql.PoolConnection;

/** Furni ids by name (items_base.item_name). */
async function furniIds(conn: Conn, names: string[]): Promise<Map<string, number>> {
  const [rows] = await conn.query<mysql.RowDataPacket[]>('SELECT id, item_name FROM items_base WHERE item_name IN (?)', [names]);
  return new Map(rows.map((r) => [r.item_name as string, r.id as number]));
}

/**
 * Every new player gets their own room, furnished like Habbo's starter rooms, with a welcome gift
 * in it to open. Returns the room's id.
 */
async function createStarterRoom(conn: Conn, userId: number, name: string): Promise<number> {
  const [res] = await conn.query<mysql.ResultSetHeader>(
    `INSERT INTO rooms (owner_id, owner_name, name, description, model, state, users_max, paper_floor, paper_wall, paper_landscape, thickness_wall, wall_height, thickness_floor, moodlight_data, tags, is_public, category)
     VALUES (?, ?, ?, '', ?, 'open', 25, '0.0', '0.0', '0.0', 0, -1, 0, '', '', '0', 1)`,
    [userId, name, `${name}'s room`, STARTER_ROOM.model],
  );
  const roomId = res.insertId;
  const names = [...STARTER_ROOM.furni.map((f) => f.name), ...STARTER_ROOM.gift.contents, STARTER_ROOM.gift.name];
  const ids = await furniIds(conn, names);
  const rows = STARTER_ROOM.furni.filter((f) => ids.has(f.name));
  if (rows.length) {
    await conn.query('INSERT INTO items (user_id, room_id, item_id, wall_pos, x, y, z, rot, extra_data) VALUES ?', [
      rows.map((f) => [userId, roomId, ids.get(f.name), f.wall ?? '', f.x ?? 0, f.y ?? 0, 0, f.rot ?? 0, '0']),
    ]);
  }
  // The gift: its furni are kept with no owner until it's opened (as Arcturus does for gifts).
  const giftId = ids.get(STARTER_ROOM.gift.name);
  const inside: number[] = [];
  for (const furni of STARTER_ROOM.gift.contents) {
    const base = ids.get(furni);
    if (!base) continue;
    const [r] = await conn.query<mysql.ResultSetHeader>(
      "INSERT INTO items (user_id, room_id, item_id, wall_pos, x, y, z, rot, extra_data) VALUES (0, 0, ?, '', 0, 0, 0, 0, '0')",
      [base],
    );
    inside.push(r.insertId);
  }
  if (giftId && inside.length) {
    // Arcturus' gift data: count, the furni ids, colour, ribbon, show sender, message, sender, look.
    const data = [inside.length, ...inside, 0, 0, 1, STARTER_ROOM.gift.message, 'Bobba', HOTEL_LOOK].join('\t');
    const [x, y] = STARTER_ROOM.gift.at;
    await conn.query("INSERT INTO items (user_id, room_id, item_id, wall_pos, x, y, z, rot, extra_data) VALUES (?, ?, ?, '', ?, ?, 0, 0, ?)", [
      userId, roomId, giftId, x, y, data,
    ]);
  }
  return roomId;
}

/** The look of the hotel's own account (user 1, "Bobba"), who the welcome gift is from. */
const HOTEL_LOOK = 'hd-101.hr-101.ch-101.lg-101.sh-101';

/**
 * A new player's room: Habbo's small starter layout (model_c: 6x6 tiles, x 5-10 and y 5-10, the
 * door on the left at 4,7; its back wall is at y 4, its left wall at x 4), some furni, and a gift.
 */
export const STARTER_ROOM = {
  model: 'model_c',
  furni: [
    { name: 'bobba_bed_g_4', x: 9, y: 5, rot: 0 },
    { name: 'bobba_plant_2', x: 5, y: 5, rot: 0 },
    { name: 'bobba_sofa_1', x: 6, y: 5, rot: 4 },
    { name: 'bobba_lamp_10', x: 7, y: 5, rot: 0 },
    { name: 'bobba_carpet_14', x: 6, y: 7, rot: 0 },
    { name: 'bobba_smalltable_5', x: 6, y: 7, rot: 2 },
    { name: 'bobba_window_8', wall: ':w=6,4 l=10,34 r' },
  ] as { name: string; x?: number; y?: number; rot?: number; wall?: string }[],
  gift: {
    name: 'bobba_gift',
    at: [8, 8] as [number, number],
    contents: ['bobba_lava_lamp', 'bobba_plant_3', 'bobba_picture_modern_1'],
    message: 'Welcome to Bobba Hotel! Here is something for your new room.',
  },
};

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
