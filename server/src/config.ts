// Server settings come from environment variables. On the VPS they are in /etc/bobbahotel/env.
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export interface Config {
  port: number;
  host: string;
  /** The address players use, e.g. https://hotel.playbobba.com. Used for the Steam login return. */
  publicUrl: string;
  /** Allowed browser origins for the WebSocket and login requests. Empty = allow any (local development). */
  allowOrigin: string[];
  /** SQLite database file (":memory:" for tests). */
  dbFile: string;
  /** Folder with rooms.json and other content. */
  contentDir: string;
  /** Licensed pictures (never in git). */
  spritesDir: string;
  /** Where the server writes what it builds (furni sprite sheets): next to the database by default. */
  buildDir: string;
  /** Steam IDs of staff (admins). */
  staffSteamIds: Set<string>;
  /** The git commit this server was built from ("dev" when run from a checkout). */
  version: string;
}

function readVersion(): string {
  try {
    return readFileSync(new URL('../../VERSION', import.meta.url), 'utf8').trim() || 'dev';
  } catch {
    return 'dev';
  }
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const port = Number(env.PORT ?? 8080);
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error(`Bad PORT: ${env.PORT}`);
  return {
    port,
    host: env.HOST ?? '127.0.0.1',
    publicUrl: (env.PUBLIC_URL ?? 'http://localhost:5173').replace(/\/$/, ''),
    allowOrigin: (env.ALLOW_ORIGIN ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
    dbFile: env.DB_FILE ?? 'hotel.db',
    contentDir: env.CONTENT_DIR ?? fileURLToPath(new URL('../../content/', import.meta.url)),
    spritesDir: env.SPRITES_DIR ?? fileURLToPath(new URL('../../sprites/', import.meta.url)),
    buildDir: env.BUILD_DIR ?? join(dirname(resolve(env.DB_FILE ?? 'hotel.db')), 'built'),
    staffSteamIds: new Set((env.STAFF_STEAMIDS ?? '').split(',').map((s) => s.trim()).filter(Boolean)),
    version: readVersion(),
  };
}
