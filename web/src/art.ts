// Art packs uploaded on the admin pages: zip files of pictures for sprites/ (the licensed packs,
// never in git). The website can't write files on the server (its service is locked down), so an
// upload is kept in the database; the next deploy (deploy/deploy.sh, `node web/src/art.ts apply`)
// unpacks it into the sprites folder and builds the hotel's pictures from it.
//
// A zip holds pack folders at its top: furni/, tiles/, cozy/, casino/, cats/, cars/, city/,
// space/ (or one folder around those, which is skipped). Only pictures and small text files are
// taken, and nothing outside those folders.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { inflateRawSync } from 'node:zlib';
import type { RowDataPacket } from 'mysql2/promise';
import type { Db } from './db.ts';

export const PACK_FOLDERS = ['furni', 'tiles', 'cozy', 'casino', 'cats', 'cars', 'city', 'space'];
const FILE_TYPES = /\.(png|json|txt)$/i;
/** Uploads are kept in pieces this big (MariaDB's default packet limit is 16 MB). */
const CHUNK = 4 * 1024 * 1024;
// (the website may use at most 200 MB of memory)
export const MAX_UPLOAD = 60 * 1024 * 1024;

export interface ZipEntry {
  name: string;
  /** Where it goes in the sprites folder ("casino/poker_table.png"), or null if it isn't taken. */
  target: string | null;
  read: () => Buffer;
}

/** The files in a zip (from its central directory). Throws 'not_a_zip' if it isn't one. */
export function readZip(zip: Buffer): ZipEntry[] {
  // The end of central directory record: the last 22+ bytes, signature 0x06054b50.
  let end = -1;
  for (let i = zip.length - 22; i >= Math.max(0, zip.length - 22 - 65535); i--) {
    if (zip.readUInt32LE(i) === 0x06054b50) { end = i; break; }
  }
  if (end < 0) throw new Error('not_a_zip');
  const count = zip.readUInt16LE(end + 10);
  let p = zip.readUInt32LE(end + 16);
  const names: { name: string; method: number; size: number; local: number }[] = [];
  for (let i = 0; i < count; i++) {
    if (p + 46 > zip.length || zip.readUInt32LE(p) !== 0x02014b50) throw new Error('not_a_zip');
    const method = zip.readUInt16LE(p + 10);
    const size = zip.readUInt32LE(p + 20);
    const nameLen = zip.readUInt16LE(p + 28), extraLen = zip.readUInt16LE(p + 30), commentLen = zip.readUInt16LE(p + 32);
    const local = zip.readUInt32LE(p + 42);
    names.push({ name: zip.toString('utf8', p + 46, p + 46 + nameLen), method, size, local });
    p += 46 + nameLen + extraLen + commentLen;
  }
  // One folder around the pack folders (e.g. "bobba-new-packs/casino/...") is skipped.
  const tops = new Set(names.map((n) => n.name.split('/')[0]));
  const wrapped = tops.size === 1 && !PACK_FOLDERS.includes([...tops][0] ?? '');
  return names.map(({ name, method, size, local }) => {
    const path = wrapped ? name.split('/').slice(1).join('/') : name;
    return {
      name,
      target: safeTarget(path),
      read: () => {
        if (zip.readUInt32LE(local) !== 0x04034b50) throw new Error('not_a_zip');
        const start = local + 30 + zip.readUInt16LE(local + 26) + zip.readUInt16LE(local + 28);
        const data = zip.subarray(start, start + size);
        if (method === 0) return Buffer.from(data);
        if (method === 8) return inflateRawSync(data);
        throw new Error('unsupported_zip');
      },
    };
  });
}

/** "casino/x.png" -> itself; anything outside the pack folders, odd paths or other files -> null. */
export function safeTarget(path: string): string | null {
  if (path.endsWith('/') || !FILE_TYPES.test(path) || path.includes('\\')) return null;
  const parts = path.split('/');
  if (parts.length < 2 || !PACK_FOLDERS.includes(parts[0] ?? '')) return null;
  if (parts.some((s) => s === '' || s === '.' || s === '..' || s.startsWith('.') || s.startsWith('__MACOSX'))) return null;
  return parts.join('/');
}

async function tables(db: Db): Promise<void> {
  await db.query(`CREATE TABLE IF NOT EXISTS bobba_art_packs (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    size INT NOT NULL,
    files INT NOT NULL,
    folders VARCHAR(200) NOT NULL,
    uploaded INT NOT NULL,
    uploaded_by VARCHAR(50) NOT NULL,
    applied INT NULL
  )`);
  await db.query(`CREATE TABLE IF NOT EXISTS bobba_art_chunks (
    pack_id INT NOT NULL,
    n INT NOT NULL,
    data MEDIUMBLOB NOT NULL,
    PRIMARY KEY (pack_id, n)
  )`);
}

/** Checks and keeps an uploaded zip. Returns what it holds, or throws a message for the admin. */
export async function storePack(db: Db, name: string, zip: Buffer, by: string): Promise<{ files: number; folders: string[] }> {
  let entries: ZipEntry[];
  try {
    entries = readZip(zip);
  } catch {
    throw new Error('That is not a zip file.');
  }
  const taken = entries.filter((e) => e.target);
  if (!taken.length) throw new Error(`No pictures in it. The zip should have folders named ${PACK_FOLDERS.join(', ')} with the pictures inside.`);
  const folders = [...new Set(taken.map((e) => e.target!.split('/')[0]!))].sort();
  await tables(db);
  const [res] = await db.query<import('mysql2/promise').ResultSetHeader>(
    'INSERT INTO bobba_art_packs (name, size, files, folders, uploaded, uploaded_by) VALUES (?, ?, ?, ?, ?, ?)',
    [name.slice(0, 200), zip.length, taken.length, folders.join(', '), Math.floor(Date.now() / 1000), by],
  );
  for (let i = 0, n = 0; i < zip.length; i += CHUNK, n++) {
    await db.query('INSERT INTO bobba_art_chunks (pack_id, n, data) VALUES (?, ?, ?)', [res.insertId, n, zip.subarray(i, i + CHUNK)]);
  }
  return { files: taken.length, folders };
}

export interface PackRow { id: number; name: string; size: number; files: number; folders: string; uploaded: number; uploaded_by: string; applied: number | null }

export async function listPacks(db: Db): Promise<PackRow[]> {
  await tables(db);
  const [rows] = await db.query<RowDataPacket[]>('SELECT id, name, size, files, folders, uploaded, uploaded_by, applied FROM bobba_art_packs ORDER BY id DESC LIMIT 50');
  return rows as PackRow[];
}

export async function deletePack(db: Db, id: number): Promise<void> {
  await tables(db);
  await db.query('DELETE FROM bobba_art_chunks WHERE pack_id = ? AND pack_id IN (SELECT id FROM bobba_art_packs WHERE applied IS NULL)', [id]);
  await db.query('DELETE FROM bobba_art_packs WHERE id = ? AND applied IS NULL', [id]);
}

/** Unpacks every upload not unpacked yet into the sprites folder (oldest first). For deploys. */
export async function applyPacks(db: Db, spritesDir: string, log = console.log): Promise<number> {
  await tables(db);
  const [packs] = await db.query<RowDataPacket[]>('SELECT id, name FROM bobba_art_packs WHERE applied IS NULL ORDER BY id');
  for (const pack of packs) {
    const [chunks] = await db.query<RowDataPacket[]>('SELECT data FROM bobba_art_chunks WHERE pack_id = ? ORDER BY n', [pack.id]);
    const zip = Buffer.concat(chunks.map((c) => c.data as Buffer));
    let files = 0;
    for (const e of readZip(zip)) {
      if (!e.target) continue;
      const to = join(spritesDir, e.target);
      mkdirSync(dirname(to), { recursive: true });
      writeFileSync(to, e.read());
      files++;
    }
    await db.query('UPDATE bobba_art_packs SET applied = ? WHERE id = ?', [Math.floor(Date.now() / 1000), pack.id]);
    // The pictures are in the sprites folder now; the copy in the database isn't needed.
    await db.query('DELETE FROM bobba_art_chunks WHERE pack_id = ?', [pack.id]);
    log(`  ${pack.name}: ${files} pictures`);
  }
  return packs.length;
}

// `node web/src/art.ts apply <sprites dir>` (deploy/deploy.sh), with the database settings in the
// environment like the website.
if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href && process.argv[2] === 'apply') {
  const { loadConfig } = await import('./config.ts');
  const { openDb } = await import('./db.ts');
  const db = await openDb(loadConfig());
  try {
    const n = await applyPacks(db, process.argv[3] ?? 'sprites');
    if (!n) console.log('  no new uploads');
  } finally {
    await db.end();
  }
}
