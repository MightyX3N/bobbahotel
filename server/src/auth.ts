import type { DatabaseSync } from 'node:sqlite';
import { randomBytes } from 'node:crypto';

export const PUBLIC_URL = (process.env.PUBLIC_URL ?? 'http://localhost:8080').replace(/\/$/, '');
const SECURE = PUBLIC_URL.startsWith('https');
const COOKIE_DOMAIN = process.env.COOKIE_DOMAIN; // e.g. .playbobba.com to share the login with the website
const DAYS = 30;
export const STAFF = new Set((process.env.STAFF_STEAMIDS ?? '').split(',').map(s => s.trim()).filter(Boolean));

let db: DatabaseSync;
export function initAuth(d: DatabaseSync) {
  db = d;
  db.exec('CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, steamid TEXT NOT NULL, created INTEGER NOT NULL)');
  db.prepare('DELETE FROM sessions WHERE created < ?').run(Date.now() - DAYS * 864e5);
}

export const safeNext = (n: string | null) => (n && /^\/[^/\\]/.test(n) || n === '/' ? n! : '/');

export function steamLoginUrl(next: string) {
  const ret = `${PUBLIC_URL}/auth/steam/return?next=${encodeURIComponent(next)}`;
  const q = new URLSearchParams({
    'openid.ns': 'http://specs.openid.net/auth/2.0', 'openid.mode': 'checkid_setup',
    'openid.return_to': ret, 'openid.realm': PUBLIC_URL,
    'openid.identity': 'http://specs.openid.net/auth/2.0/identifier_select',
    'openid.claimed_id': 'http://specs.openid.net/auth/2.0/identifier_select',
  });
  return 'https://steamcommunity.com/openid/login?' + q;
}

/** Ask Steam whether this return is genuine. Returns the 17-digit Steam ID or null. */
export async function verifySteam(params: URLSearchParams): Promise<string | null> {
  const m = /^https:\/\/steamcommunity\.com\/openid\/id\/(\d{17})$/.exec(params.get('openid.claimed_id') ?? '');
  if (!m || params.get('openid.mode') !== 'id_res') return null;
  // the return_to Steam signed must be our own endpoint
  if (!(params.get('openid.return_to') ?? '').startsWith(`${PUBLIC_URL}/auth/steam/return`)) return null;
  const body = new URLSearchParams();
  for (const [k, v] of params) if (k.startsWith('openid.')) body.set(k, v);
  body.set('openid.mode', 'check_authentication');
  try {
    const r = await fetch('https://steamcommunity.com/openid/login', { method: 'POST', body, signal: AbortSignal.timeout(8000) });
    return /is_valid\s*:\s*true/.test(await r.text()) ? m[1] : null;
  } catch { return null; }
}

export function makeSession(steamid: string) {
  const token = randomBytes(24).toString('hex');
  db.prepare('INSERT INTO sessions(token, steamid, created) VALUES(?,?,?)').run(token, steamid, Date.now());
  return token;
}
export function cookieFor(token: string, clear = false) {
  return `bh_session=${clear ? '' : token}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${clear ? 0 : DAYS * 86400}` +
    (SECURE ? '; Secure' : '') + (COOKIE_DOMAIN ? `; Domain=${COOKIE_DOMAIN}` : '');
}
export function sessionToken(cookieHeader: string | undefined) {
  return /(?:^|;\s*)bh_session=([0-9a-f]{48})/.exec(cookieHeader ?? '')?.[1] ?? null;
}
export function steamidFromCookie(cookieHeader: string | undefined): string | null {
  const t = sessionToken(cookieHeader); if (!t) return null;
  const r = db.prepare('SELECT steamid, created FROM sessions WHERE token = ?').get(t) as any;
  return r && r.created > Date.now() - DAYS * 864e5 ? r.steamid : null;
}
export function endSession(cookieHeader: string | undefined) {
  const t = sessionToken(cookieHeader); if (t) db.prepare('DELETE FROM sessions WHERE token = ?').run(t);
}
