// Admin pages (owners only): find players and give them club, currency or a rank; edit catalogue
// prices. Moderation itself (mutes, bans, reports) happens in the game's Mod Tools.
//
// Changes go to a running server through RCON when the player is online, and straight into the
// database otherwise (the server reads it on their next login).
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { RowDataPacket } from 'mysql2/promise';
import type { Config } from './config.ts';
import type { Account, Db } from './db.ts';
import { esc, layout } from './pages.ts';
import { rcon, RCON } from './rcon.ts';
import { readBody, redirect, send } from './app.ts';

const CURRENCIES: Record<string, string> = { credits: 'Credits', '0': 'Duckets', '5': 'Diamonds' };

export function adminRoutes({ config, db }: { config: Config; db: Db }) {
  const q = async <T = RowDataPacket>(sql: string, args: unknown[] = []) => (await db.query<RowDataPacket[]>(sql, args))[0] as T[];

  const page = (title: string, body: string, note?: string) =>
    layout(`${title} - Bobba Hotel admin`, `
<div class="card">
  <div class="row" style="margin:0 0 12px"><a href="/admin">Players</a> · <a href="/admin/catalogue">Catalogue</a> · <a href="/admin/staff">Staff</a> · <a href="/">Back to the hotel</a></div>
  <h1>${esc(title)}</h1>
  ${note ? `<div class="error" style="background:#e3f6dd;border-color:#8bc480">${esc(note)}</div>` : ''}
  ${body}
</div>
<style>table{border-collapse:collapse;width:100%;font-size:14px}td,th{border-bottom:1px solid #d6e0e5;padding:5px 6px;text-align:left}
input[type=number]{width:90px;padding:4px}select,input{font:inherit}form.inline{display:inline}</style>`);

  async function players(url: URL): Promise<string> {
    const term = (url.searchParams.get('q') ?? '').trim();
    const rows = term
      ? await q('SELECT id, username, `rank`, online, last_online FROM users WHERE username LIKE ? ORDER BY username LIMIT 50', [`%${term}%`])
      : await q('SELECT id, username, `rank`, online, last_online FROM users ORDER BY last_online DESC LIMIT 50');
    const [counts] = await q<{ total: number; online: number }>("SELECT COUNT(*) total, SUM(online = '1') online FROM users");
    return `<p>${counts?.total ?? 0} players, ${counts?.online ?? 0} online now.</p>
<form method="get" action="/admin" class="row"><input type="text" name="q" value="${esc(term)}" placeholder="Name"><button class="btn small">Search</button></form>
<table><tr><th>Name</th><th>Rank</th><th>Online</th><th>Last seen</th></tr>
${rows.map((r) => `<tr><td><a href="/admin/player?id=${r.id}">${esc(String(r.username))}</a></td><td>${r.rank}</td><td>${r.online === '1' ? 'yes' : ''}</td><td>${r.last_online ? new Date(Number(r.last_online) * 1000).toISOString().slice(0, 16).replace('T', ' ') : ''}</td></tr>`).join('')}
</table>`;
  }

  async function player(id: number): Promise<string | null> {
    const [u] = await q('SELECT id, username, `rank`, credits, online, account_created, look FROM users WHERE id = ?', [id]);
    if (!u) return null;
    const cur = await q('SELECT type, amount FROM users_currency WHERE user_id = ?', [id]);
    const amount = (t: number) => Number(cur.find((c) => Number(c.type) === t)?.amount ?? 0);
    const [club] = await q('SELECT timestamp_start + duration AS ends FROM users_subscriptions WHERE user_id = ? AND subscription_type = ? AND active = 1 ORDER BY ends DESC LIMIT 1', [id, 'HABBO_CLUB']);
    const clubEnds = club && Number(club.ends) * 1000 > Date.now() ? new Date(Number(club.ends) * 1000).toISOString().slice(0, 10) : null;
    const ranks = await q('SELECT id, rank_name FROM permissions ORDER BY id');
    const [steam] = await q('SELECT steam_id FROM bobba_steam WHERE user_id = ?', [id]);
    return `<table>
<tr><th>Name</th><td>${esc(String(u.username))} ${u.online === '1' ? '(online)' : ''}</td></tr>
<tr><th>Steam</th><td>${steam ? `<a href="https://steamcommunity.com/profiles/${esc(String(steam.steam_id))}">${esc(String(steam.steam_id))}</a>` : '-'}</td></tr>
<tr><th>Joined</th><td>${new Date(Number(u.account_created) * 1000).toISOString().slice(0, 10)}</td></tr>
<tr><th>Credits / Duckets / Diamonds</th><td>${u.credits} / ${amount(0)} / ${amount(5)}</td></tr>
<tr><th>Bobba Club</th><td>${clubEnds ? `until ${clubEnds}` : 'no'}</td></tr>
</table>
<h2 style="font-size:17px;margin-top:20px">Give Bobba Club</h2>
<form method="post" action="/admin/player/club" class="row"><input type="hidden" name="id" value="${u.id}">
  <input type="number" name="days" value="31" min="1" max="3650"> days <button class="btn small">Give</button></form>
<h2 style="font-size:17px;margin-top:20px">Give currency</h2>
<form method="post" action="/admin/player/currency" class="row"><input type="hidden" name="id" value="${u.id}">
  <input type="number" name="amount" value="100" min="-1000000" max="1000000">
  <select name="type">${Object.entries(CURRENCIES).map(([k, v]) => `<option value="${k}">${v}</option>`).join('')}</select>
  <button class="btn small">Give</button> <span class="muted">(negative takes away)</span></form>
<h2 style="font-size:17px;margin-top:20px">Rank</h2>
<form method="post" action="/admin/player/rank" class="row"><input type="hidden" name="id" value="${u.id}">
  <select name="rank">${ranks.map((r) => `<option value="${r.id}"${Number(r.id) === Number(u.rank) ? ' selected' : ''}>${r.id}: ${esc(String(r.rank_name))}</option>`).join('')}</select>
  <button class="btn small">Set</button></form>`;
  }

  async function catalogue(url: URL): Promise<string> {
    const pages = await q("SELECT id, caption FROM catalog_pages WHERE page_layout LIKE 'default%' AND parent_id <> -1 ORDER BY order_num, id");
    const pageId = Number(url.searchParams.get('page') ?? pages[0]?.id ?? 0);
    const items = await q(
      'SELECT ci.id, ci.cost_credits, ci.cost_points, ci.points_type, ib.public_name FROM catalog_items ci JOIN items_base ib ON ib.id = ci.item_ids WHERE ci.page_id = ? ORDER BY ci.order_number, ci.id',
      [pageId],
    );
    return `<div class="row" style="flex-wrap:wrap;gap:6px">${pages.map((p) => `<a ${Number(p.id) === pageId ? 'style="font-weight:700"' : ''} href="/admin/catalogue?page=${p.id}">${esc(String(p.caption))}</a>`).join(' · ')}</div>
<form method="post" action="/admin/catalogue"><input type="hidden" name="page" value="${pageId}">
<table><tr><th>Furni</th><th>Credits</th><th>Points</th><th>Points type</th></tr>
${items.map((i) => `<tr><td>${esc(String(i.public_name))}</td>
<td><input type="number" min="0" name="c${i.id}" value="${i.cost_credits}"></td>
<td><input type="number" min="0" name="p${i.id}" value="${i.cost_points}"></td>
<td><select name="t${i.id}">${[['0', 'Duckets'], ['5', 'Diamonds']].map(([v, n]) => `<option value="${v}"${String(i.points_type) === v ? ' selected' : ''}>${n}</option>`).join('')}</select></td></tr>`).join('')}
</table><div class="row"><button class="btn">Save prices</button></div></form>`;
  }

  async function staff(): Promise<string> {
    const rows = await q('SELECT u.id, u.username, u.`rank`, p.rank_name FROM users u JOIN permissions p ON p.id = u.`rank` WHERE u.`rank` > 1 ORDER BY u.`rank` DESC, u.username');
    return `<table><tr><th>Name</th><th>Rank</th></tr>${rows.map((r) => `<tr><td><a href="/admin/player?id=${r.id}">${esc(String(r.username))}</a></td><td>${r.rank}: ${esc(String(r.rank_name))}</td></tr>`).join('')}</table>
<p class="muted">Give someone a rank from their player page. What each rank may do is set in the permissions table.</p>`;
  }

  /** Sends an RCON message; if the player is offline, runs `offline` on the database instead. */
  async function apply(key: string, data: object, offline: () => Promise<unknown>): Promise<string> {
    const r = await rcon(config.rcon, key, data);
    if (r?.status === RCON.OK) return 'Done.';
    await offline();
    return r ? 'Done (the player is offline; they get it when they log in).' : 'Done in the database (the game server did not answer).';
  }

  return async function handle(req: IncomingMessage, res: ServerResponse, url: URL, me: Account): Promise<void> {
    if (req.method === 'POST') {
      // Forms only from our own pages.
      const origin = req.headers.origin;
      if (origin && origin !== config.publicUrl) return send(res, 403, 'Forbidden', 'text/plain');
      const f = new URLSearchParams(await readBody(req));
      const id = Number(f.get('id'));
      const back = (note: string) => redirect(res, `/admin/player?id=${id}&note=${encodeURIComponent(note)}`);
      switch (url.pathname) {
        case '/admin/player/club': {
          const days = Math.max(1, Math.min(3650, Number(f.get('days')) || 0));
          const note = await apply('modifysubscription', { user_id: id, type: 'HABBO_CLUB', action: 'add', duration: days * 86400 }, async () => {
            const now = Math.floor(Date.now() / 1000);
            const [cur] = await q('SELECT id, timestamp_start + duration AS ends FROM users_subscriptions WHERE user_id = ? AND subscription_type = ? AND active = 1 ORDER BY ends DESC LIMIT 1', [id, 'HABBO_CLUB']);
            if (cur && Number(cur.ends) > now) await db.query('UPDATE users_subscriptions SET duration = duration + ? WHERE id = ?', [days * 86400, cur.id]);
            else await db.query("INSERT INTO users_subscriptions (user_id, subscription_type, timestamp_start, duration, active) VALUES (?, 'HABBO_CLUB', ?, ?, 1)", [id, now, days * 86400]);
          });
          console.log(`admin ${me.username}: club +${days}d for user ${id}`);
          return back(note);
        }
        case '/admin/player/currency': {
          const amount = Math.trunc(Number(f.get('amount')) || 0);
          const type = f.get('type') ?? 'credits';
          const note =
            type === 'credits'
              ? await apply('givecredits', { user_id: id, credits: amount }, () => db.query('UPDATE users SET credits = GREATEST(0, credits + ?) WHERE id = ?', [amount, id]))
              : await apply('givepoints', { user_id: id, points: amount, type: Number(type) }, () =>
                  db.query('INSERT INTO users_currency (user_id, type, amount) VALUES (?, ?, GREATEST(0, ?)) ON DUPLICATE KEY UPDATE amount = GREATEST(0, amount + ?)', [id, Number(type), amount, amount]),
                );
          console.log(`admin ${me.username}: ${amount} ${CURRENCIES[type] ?? type} for user ${id}`);
          return back(note);
        }
        case '/admin/player/rank': {
          const rank = Number(f.get('rank'));
          const note = await apply('setrank', { user_id: id, rank }, () => db.query('UPDATE users SET `rank` = ? WHERE id = ?', [rank, id]));
          console.log(`admin ${me.username}: rank ${rank} for user ${id}`);
          return back(note);
        }
        case '/admin/catalogue': {
          const pageId = Number(f.get('page'));
          for (const [k, v] of f) {
            const m = /^c(\d+)$/.exec(k);
            if (!m) continue;
            const itemId = Number(m[1]);
            await db.query('UPDATE catalog_items SET cost_credits = ?, cost_points = ?, points_type = ? WHERE id = ? AND page_id = ?', [
              Math.max(0, Number(v) || 0), Math.max(0, Number(f.get(`p${itemId}`)) || 0), Number(f.get(`t${itemId}`)) === 5 ? 5 : 0, itemId, pageId,
            ]);
          }
          const r = await rcon(config.rcon, 'updatecatalog', {});
          return redirect(res, `/admin/catalogue?page=${pageId}&note=${encodeURIComponent(r ? 'Saved. The catalogue in the game is updated.' : 'Saved. The game server did not answer; it picks the prices up when it restarts.')}`);
        }
      }
      return send(res, 404, 'Not found', 'text/plain');
    }

    const note = url.searchParams.get('note') ?? undefined;
    switch (url.pathname) {
      case '/admin':
        return send(res, 200, page('Players', await players(url), note));
      case '/admin/player': {
        const body = await player(Number(url.searchParams.get('id')));
        return body ? send(res, 200, page('Player', body, note)) : send(res, 404, page('Player', '<p>No such player.</p>'));
      }
      case '/admin/catalogue':
        return send(res, 200, page('Catalogue prices', await catalogue(url), note));
      case '/admin/staff':
        return send(res, 200, page('Staff', await staff(), note));
    }
    return send(res, 404, 'Not found', 'text/plain');
  };
}
