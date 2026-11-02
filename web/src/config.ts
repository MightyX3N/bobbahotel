// Website settings from environment variables. On the VPS they are in /etc/bobbahotel/env.
import { readFileSync } from 'node:fs';

export interface Config {
  port: number;
  host: string;
  /** The address players use, e.g. https://hotel.playbobba.com (Steam sends logins back here). */
  publicUrl: string;
  db: { host: string; port: number; user: string; password: string; database: string };
  /** Steam IDs of the owners: their accounts get the top rank. */
  ownerSteamIds: Set<string>;
  /** Rank given to owners (Arcturus permissions table). */
  ownerRank: number;
  /** Arcturus remote control (RCON), for telling a running server about changes. */
  rcon: { host: string; port: number };
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
  return {
    port: Number(env.PORT ?? 8080),
    host: env.HOST ?? '127.0.0.1',
    publicUrl: (env.PUBLIC_URL ?? 'http://localhost:8080').replace(/\/$/, ''),
    db: {
      host: env.DB_HOST ?? '127.0.0.1',
      port: Number(env.DB_PORT ?? 3306),
      user: env.DB_USER ?? 'arcturus',
      password: env.DB_PASSWORD ?? 'arcturus',
      database: env.DB_NAME ?? 'arcturus',
    },
    ownerSteamIds: new Set((env.STAFF_STEAMIDS ?? '').split(',').map((s) => s.trim()).filter(Boolean)),
    ownerRank: Number(env.OWNER_RANK ?? 7),
    rcon: { host: env.RCON_HOST ?? '127.0.0.1', port: Number(env.RCON_PORT ?? 30001) },
    version: readVersion(),
  };
}
