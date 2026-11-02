// Logins: Steam (OpenID 2.0) and guests. A login is a random token in an HttpOnly cookie; the
// database only stores its hash. A Steam login without a hotel account yet is a session with a
// steam_id and no user_id until the player picks a name.
import { createHash, randomBytes } from 'node:crypto';
import type { Db } from './db.ts';

const COOKIE = 'bh_session';
const SESSION_DAYS = 30;
const STEAM_OPENID = 'https://steamcommunity.com/openid/login';

export interface Session {
  tokenHash: string;
  userId: number | null;
  steamId: string | null;
}

export type Fetch = typeof fetch;

export class Auth {
  private readonly db: Db;
  private readonly publicUrl: string;
  private readonly fetch: Fetch;

  constructor(db: Db, opts: { publicUrl: string; fetch?: Fetch }) {
    this.db = db;
    this.publicUrl = opts.publicUrl;
    this.fetch = opts.fetch ?? fetch;
  }

  /** Starts a session and returns its token (for the cookie). */
  start(input: { userId?: number; steamId?: string }, now = Date.now()): string {
    const token = randomBytes(32).toString('base64url');
    this.db
      .prepare('INSERT INTO sessions (token_hash, user_id, steam_id, created, expires) VALUES (?, ?, ?, ?, ?)')
      .run(hash(token), input.userId ?? null, input.steamId ?? null, now, now + SESSION_DAYS * 864e5);
    return token;
  }

  fromCookie(cookieHeader: string | undefined, now = Date.now()): Session | null {
    const token = readCookie(cookieHeader, COOKIE);
    if (!token) return null;
    const row = this.db
      .prepare('SELECT token_hash, user_id, steam_id, expires FROM sessions WHERE token_hash = ?')
      .get(hash(token)) as { token_hash: string; user_id: number | null; steam_id: string | null; expires: number } | undefined;
    if (!row || row.expires < now) return null;
    return { tokenHash: row.token_hash, userId: row.user_id, steamId: row.steam_id };
  }

  bindUser(session: Session, userId: number): void {
    this.db.prepare('UPDATE sessions SET user_id = ? WHERE token_hash = ?').run(userId, session.tokenHash);
  }

  end(session: Session): void {
    this.db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(session.tokenHash);
  }

  removeExpired(now = Date.now()): void {
    this.db.prepare('DELETE FROM sessions WHERE expires < ?').run(now);
  }

  cookie(token: string): string {
    return `${COOKIE}=${token}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${SESSION_DAYS * 86400}${this.secure ? '; Secure' : ''}`;
  }

  clearCookie(): string {
    return `${COOKIE}=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0${this.secure ? '; Secure' : ''}`;
  }

  private get secure(): boolean {
    return this.publicUrl.startsWith('https:');
  }

  // ---- Steam ----

  get steamReturnUrl(): string {
    return `${this.publicUrl}/api/auth/steam/return`;
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

function readCookie(header: string | undefined, name: string): string | null {
  for (const part of (header ?? '').split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === name) return v.join('=') || null;
  }
  return null;
}
