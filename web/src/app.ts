// The website's HTTP routes. The game client itself (Nitro) and its assets are served by the web
// server (Caddy) next to this; the game runs on the Arcturus server.
import { randomBytes } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { Auth } from './auth.ts';
import type { Config } from './config.ts';
import { accountBySteamId, createAccount, nameTaken, setRank, setTicket, type Db } from './db.ts';
import { starterLook, validName } from './looks.ts';
import { homePage, loginPage, namePage } from './pages.ts';
import { adminRoutes } from './admin.ts';

export interface AppOptions {
  config: Config;
  db: Db;
  /** For tests: replaces the HTTP client used to check Steam logins. */
  fetch?: typeof fetch;
}

export function createApp({ config, db, fetch: fetchImpl }: AppOptions) {
  const auth = new Auth(db, { publicUrl: config.publicUrl, ...(fetchImpl ? { fetch: fetchImpl } : {}) });
  const isOwner = (steamId: string) => config.ownerSteamIds.has(steamId);
  const admin = adminRoutes({ config, db });

  return async function handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const url = new URL(req.url ?? '/', 'http://x');
    const route = `${req.method} ${url.pathname}`;
    const ip = clientIp(req);
    try {
      // The old version of the hotel installed a service worker; this one removes itself.
      if (route === 'GET /sw.js') return send(res, 200, OLD_WORKER_REMOVER, 'text/javascript');
      if (route === 'GET /health') return send(res, 200, JSON.stringify({ ok: true, version: config.version }), 'application/json');

      if (route === 'GET /auth/steam') return redirect(res, auth.steamLoginUrl());
      if (route === 'GET /auth/steam/return') {
        const steamId = await auth.verifySteam(url.searchParams);
        if (!steamId) return send(res, 200, loginPage('The Steam login did not work. Please try again.'));
        return redirect(res, '/', [await auth.start(steamId)]);
      }

      const steamId = await auth.steamId(req.headers.cookie);
      if (route === 'POST /logout') return redirect(res, '/', [await auth.end(req.headers.cookie)]);
      if (!steamId) {
        if (route === 'GET /') return send(res, 200, loginPage());
        return redirect(res, '/');
      }

      let account = await accountBySteamId(db, steamId);
      // Owners always have the top rank.
      if (account && isOwner(steamId) && account.rank < config.ownerRank) {
        await setRank(db, account.id, config.ownerRank);
        account = { ...account, rank: config.ownerRank };
      }

      if (!account) {
        if (route === 'POST /name') {
          const form = new URLSearchParams(await readBody(req));
          const name = (form.get('name') ?? '').trim();
          const gender = form.get('gender') === 'F' ? 'F' : 'M';
          if (!validName(name)) return send(res, 200, namePage({ error: 'That name is not allowed: use 3 to 15 letters, numbers, or - _ .', name, gender }));
          if (await nameTaken(db, name)) return send(res, 200, namePage({ error: 'Someone already has that name.', name, gender }));
          try {
            await createAccount(db, { steamId, name, gender, look: starterLook(gender), rank: isOwner(steamId) ? config.ownerRank : 1, ip });
          } catch (e) {
            if ((e as Error).message === 'name_taken') return send(res, 200, namePage({ error: 'Someone already has that name.', name, gender }));
            throw e;
          }
          return redirect(res, '/');
        }
        if (route === 'GET /') return send(res, 200, namePage());
        return redirect(res, '/');
      }

      if (route === 'GET /') return send(res, 200, homePage(account.username, account.rank >= config.ownerRank));
      if (route === 'GET /hotel') {
        const ticket = `bobba-${randomBytes(24).toString('hex')}`;
        await setTicket(db, account.id, ticket, ip);
        return redirect(res, `/client/?sso=${ticket}`);
      }
      if (url.pathname === '/admin' || url.pathname.startsWith('/admin/')) {
        if (account.rank < config.ownerRank) return redirect(res, '/');
        return await admin(req, res, url, account);
      }
      return send(res, 404, 'Not found', 'text/plain');
    } catch (e) {
      console.error(e);
      return send(res, 500, 'Something went wrong.', 'text/plain');
    }
  };
}

const OLD_WORKER_REMOVER = `self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil((async () => {
  for (const key of await caches.keys()) await caches.delete(key);
  await self.registration.unregister();
  for (const c of await self.clients.matchAll({ type: 'window' })) c.navigate(c.url);
})()));`;

export function send(res: ServerResponse, status: number, body: string, type = 'text/html; charset=utf-8', cookies: string[] = []): void {
  res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store', ...(cookies.length ? { 'Set-Cookie': cookies } : {}) });
  res.end(body);
}

export function redirect(res: ServerResponse, to: string, cookies: string[] = []): void {
  res.writeHead(303, { Location: to, 'Cache-Control': 'no-store', ...(cookies.length ? { 'Set-Cookie': cookies } : {}) });
  res.end();
}

export async function readBody(req: IncomingMessage, limit = 64 * 1024): Promise<string> {
  let size = 0;
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > limit) throw new Error('body too large');
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks).toString('utf8');
}

/** The player's address: Caddy passes it in X-Forwarded-For (the website only listens locally). */
function clientIp(req: IncomingMessage): string {
  const fwd = req.headers['x-forwarded-for'];
  const first = (Array.isArray(fwd) ? fwd[0] : fwd)?.split(',')[0]?.trim();
  return (first || req.socket.remoteAddress || '').slice(0, 45);
}
