// Website logins with Steam (OpenID 2.0). A login is a random token in an HttpOnly cookie; the
// database only keeps its hash.
import { createHash, randomBytes } from 'node:crypto';
import type { RowDataPacket } from 'mysql2/promise';
import type { Db } from './db.ts';

const COOKIE = 'bh_login';
const DAYS = 30;
const STEAM_OPENID = 'https://steamcommunity.com/openid/login';

export class Auth {
  private readonly db: Db;
  private readonly publicUrl: string;
  private readonly fetch: typeof fetch;

  constructor(db: Db, opts: { publicUrl: string; fetch?: typeof fetch }) {
    this.db = db;
    this.publicUrl = opts.publicUrl;
    this.fetch = opts.fetch ?? fetch;
  }

  /** Starts a login for a Steam account; returns the cookie header. */
  async start(steamId: string): Promise<string> {
    const token = randomBytes(32).toString('base64url');
    const now = Math.floor(Date.now() / 1000);
    await this.db.query('INSERT INTO bobba_sessions (token_hash, steam_id, created, expires) VALUES (?, ?, ?, ?)', [
      hash(token), steamId, now, now + DAYS * 86400,
    ]);
    return `${COOKIE}=${token}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${DAYS * 86400}${this.secure ? '; Secure' : ''}`;
  }

  /** The Steam ID logged in with this request's cookie, or null. */
  async steamId(cookieHeader: string | undefined): Promise<string | null> {
    const token = readCookie(cookieHeader, COOKIE);
    if (!token) return null;
    const [rows] = await this.db.query<RowDataPacket[]>('SELECT steam_id FROM bobba_sessions WHERE token_hash = ? AND expires > ?', [
      hash(token), Math.floor(Date.now() / 1000),
    ]);
    return (rows[0]?.steam_id as string | undefined) ?? null;
  }

  async end(cookieHeader: string | undefined): Promise<string> {
    const token = readCookie(cookieHeader, COOKIE);
    if (token) await this.db.query('DELETE FROM bobba_sessions WHERE token_hash = ?', [hash(token)]);
    return `${COOKIE}=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0${this.secure ? '; Secure' : ''}`;
  }

  async removeExpired(): Promise<void> {
    await this.db.query('DELETE FROM bobba_sessions WHERE expires < ?', [Math.floor(Date.now() / 1000)]);
  }

  private get secure(): boolean {
    return this.publicUrl.startsWith('https:');
  }

  get steamReturnUrl(): string {
    return `${this.publicUrl}/auth/steam/return`;
  }

  steamLoginUrl(): string {
    const q = new URLSearchParams({
      'openid.ns': 'http://specs.openid.net/auth/2.0',
      'openid.mode': 'checkid_setup',
      'openid.return_to': this.steamReturnUrl,
      'openid.realm': this.publicUrl,
      'openid.identity': 'http://specs.openid.net/auth/2.0/identifier_select',
      'openid.claimed_id': 'http://specs.openid.net/auth/2.0/identifier_select',
    });
    return `${STEAM_OPENID}?${q}`;
  }

  /** Asks Steam whether this login return is genuine. Returns the 17-digit Steam ID, or null. */
  async verifySteam(params: URLSearchParams): Promise<string | null> {
    const id = /^https:\/\/steamcommunity\.com\/openid\/id\/(\d{17})$/.exec(params.get('openid.claimed_id') ?? '')?.[1];
    if (!id || params.get('openid.mode') !== 'id_res') return null;
    if (params.get('openid.op_endpoint') !== STEAM_OPENID) return null;
    if (params.get('openid.return_to') !== this.steamReturnUrl) return null;
    const body = new URLSearchParams();
    for (const [k, v] of params) if (k.startsWith('openid.')) body.set(k, v);
    body.set('openid.mode', 'check_authentication');
    try {
      const res = await this.fetch(STEAM_OPENID, { method: 'POST', body, signal: AbortSignal.timeout(8000) });
      return /is_valid\s*:\s*true/.test(await res.text()) ? id : null;
    } catch {
      return null;
    }
  }
}

function hash(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export function readCookie(header: string | undefined, name: string): string | null {
  for (const part of (header ?? '').split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === name) return v.join('=') || null;
  }
  return null;
}
