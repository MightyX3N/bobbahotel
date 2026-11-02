import type { AddressInfo } from 'node:net';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';
import WebSocket from 'ws';
import { encodeMessage, parseMessage, PROTOCOL_VERSION, serverMessages, type ServerMessage } from '@bobba/shared';
import { createApp, type App } from '../src/app.ts';
import { loadContent } from '../src/content.ts';
import { openDb } from '../src/db.ts';

const content = loadContent(fileURLToPath(new URL('../../content/', import.meta.url)));
const PUBLIC = 'http://hotel.test';

let app: App | undefined;
afterEach(async () => {
  await app?.close();
  app = undefined;
});

async function start(opts: { allowOrigin?: string[]; steamValid?: boolean } = {}): Promise<string> {
  const fakeSteam = (async () => new Response(`ns:http://specs.openid.net/auth/2.0\nis_valid:${opts.steamValid ? 'true' : 'false'}\n`)) as typeof fetch;
  app = createApp({
    config: { allowOrigin: opts.allowOrigin ?? [], version: 'test', publicUrl: PUBLIC },
    db: openDb(':memory:'),
    content,
    fetch: fakeSteam,
    manualTicks: true,
  });
  await new Promise<void>((resolve) => app!.server.listen(0, '127.0.0.1', resolve));
  return `127.0.0.1:${(app.server.address() as AddressInfo).port}`;
}

const cookieOf = (res: Response) => (res.headers.get('set-cookie') ?? '').split(';')[0]!;

async function guest(host: string, name: string): Promise<string> {
  const res = await fetch(`http://${host}/api/auth/guest`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name }),
  });
  expect(res.status).toBe(200);
  return cookieOf(res);
}

/** A connected player that collects every message it receives. */
class Player {
  readonly inbox: ServerMessage[] = [];
  private waiters: (() => void)[] = [];
  readonly ws: WebSocket;
  constructor(ws: WebSocket) {
    this.ws = ws;
    ws.on('message', (data) => {
      const m = parseMessage(serverMessages, data.toString());
      if (!m) throw new Error(`bad server message ${data}`);
      this.inbox.push(m);
      for (const w of this.waiters.splice(0)) w();
    });
  }
  static async join(host: string, cookie: string): Promise<Player> {
    const ws = new WebSocket(`ws://${host}/ws`, { headers: { cookie } });
    const p = new Player(ws);
    await new Promise((resolve, reject) => {
      ws.once('open', resolve);
      ws.once('error', reject);
    });
    ws.send(encodeMessage({ t: 'hello', d: { protocol: PROTOCOL_VERSION } }));
    await p.waitFor('room');
    return p;
  }
  async waitFor<T extends ServerMessage['t']>(t: T, pred: (m: Extract<ServerMessage, { t: T }>) => boolean = () => true) {
    for (;;) {
      const found = this.inbox.find((m) => m.t === t && pred(m as Extract<ServerMessage, { t: T }>));
      if (found) return found as Extract<ServerMessage, { t: T }>;
      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`timed out waiting for ${t}`)), 2000);
        this.waiters.push(() => {
          clearTimeout(timer);
          resolve();
        });
      });
    }
  }
  send(m: Parameters<typeof encodeMessage>[0]) {
    this.ws.send(encodeMessage(m));
  }
}

describe('http', () => {
  it('answers the health check', async () => {
    const host = await start();
    const res = await fetch(`http://${host}/api/health`);
    expect(await res.json()).toEqual({ ok: true, version: 'test', protocol: PROTOCOL_VERSION });
  });

  it('logs in a guest and remembers them', async () => {
    const host = await start();
    expect(await (await fetch(`http://${host}/api/me`)).json()).toEqual({ state: 'out' });
    const cookie = await guest(host, 'Bobbafan');
    expect(cookie).toMatch(/^bh_session=/);
    const me = await (await fetch(`http://${host}/api/me`, { headers: { cookie } })).json();
    expect(me).toMatchObject({ state: 'in', user: { name: 'Bobbafan', guest: true } });
  });

  it('refuses taken and bad names', async () => {
    const host = await start();
    await guest(host, 'Taken');
    const post = (name: string) =>
      fetch(`http://${host}/api/auth/guest`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name }) });
    expect(await (await post('taken')).json()).toEqual({ error: 'name_taken' });
    expect(await (await post('a b c')).json()).toEqual({ error: 'bad_characters' });
  });

  it('refuses logins posted from other sites', async () => {
    const host = await start({ allowOrigin: ['https://hotel.playbobba.com'] });
    const res = await fetch(`http://${host}/api/auth/guest`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', origin: 'https://evil.example' },
      body: JSON.stringify({ name: 'Sneaky' }),
    });
    expect(res.status).toBe(403);
  });

  it('sends Steam players to Steam and back, then asks for a name', async () => {
    const host = await start({ steamValid: true });
    const go = await fetch(`http://${host}/api/auth/steam`, { redirect: 'manual' });
    expect(go.headers.get('location')).toContain('steamcommunity.com/openid/login');

    const params = new URLSearchParams({
      'openid.ns': 'http://specs.openid.net/auth/2.0',
      'openid.mode': 'id_res',
      'openid.op_endpoint': 'https://steamcommunity.com/openid/login',
      'openid.claimed_id': 'https://steamcommunity.com/openid/id/76561198000000001',
      'openid.identity': 'https://steamcommunity.com/openid/id/76561198000000001',
      'openid.return_to': `${PUBLIC}/api/auth/steam/return`,
      'openid.sig': 'x',
    });
    const back = await fetch(`http://${host}/api/auth/steam/return?${params}`, { redirect: 'manual' });
    expect(back.headers.get('location')).toBe('/');
    const cookie = cookieOf(back);
    expect(await (await fetch(`http://${host}/api/me`, { headers: { cookie } })).json()).toEqual({ state: 'name' });

    const named = await fetch(`http://${host}/api/auth/name`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', cookie },
      body: JSON.stringify({ name: 'SteamGuy' }),
    });
    expect(named.status).toBe(200);
    expect(await (await fetch(`http://${host}/api/me`, { headers: { cookie } })).json()).toMatchObject({ state: 'in', user: { name: 'SteamGuy', guest: false } });

    // Next time the same Steam account goes straight in.
    const again = await fetch(`http://${host}/api/auth/steam/return?${params}`, { redirect: 'manual' });
    expect(await (await fetch(`http://${host}/api/me`, { headers: { cookie: cookieOf(again) } })).json()).toMatchObject({ state: 'in' });
  });

  it('rejects Steam returns that Steam does not confirm', async () => {
    const host = await start({ steamValid: false });
    const params = new URLSearchParams({
      'openid.mode': 'id_res',
      'openid.op_endpoint': 'https://steamcommunity.com/openid/login',
      'openid.claimed_id': 'https://steamcommunity.com/openid/id/76561198000000001',
      'openid.return_to': `${PUBLIC}/api/auth/steam/return`,
    });
    const back = await fetch(`http://${host}/api/auth/steam/return?${params}`, { redirect: 'manual' });
    expect(back.headers.get('location')).toBe('/?login=failed');
    expect(back.headers.get('set-cookie')).toBeNull();
  });
});

describe('hotel', () => {
  it('only lets logged-in players connect', async () => {
    const host = await start();
    await expect(
      new Promise((resolve, reject) => {
        const ws = new WebSocket(`ws://${host}/ws`);
        ws.once('open', resolve);
        ws.once('error', reject);
      }),
    ).rejects.toThrow(/401/);
  });

  it('puts players in the lobby where they see each other walk and chat', async () => {
    const host = await start();
    const alice = await Player.join(host, await guest(host, 'Alice'));
    const room = await alice.waitFor('room');
    expect(room.d.name).toBe('Lobby');
    expect(room.d.users.map((u) => u.name)).toEqual(['Alice']);

    const bob = await Player.join(host, await guest(host, 'Bob'));
    expect((await bob.waitFor('room')).d.users.map((u) => u.name).sort()).toEqual(['Alice', 'Bob']);
    const joined = await alice.waitFor('userJoin');
    expect(joined.d.name).toBe('Bob');

    // Bob walks three tiles to the right; one step per tick, then a stop.
    const [dx, dy] = room.d.door;
    bob.send({ t: 'walk', d: { x: dx + 3, y: dy } });
    await new Promise((r) => setTimeout(r, 50));
    for (let i = 0; i < 4; i++) app!.lobby.tick();
    const steps = await alice.waitFor('status', (m) => m.d.some((s) => s.id === joined.d.id && !s.moving));
    expect(steps.d.find((s) => s.id === joined.d.id)).toMatchObject({ x: dx + 3, y: dy, moving: false });

    bob.send({ t: 'chat', d: { text: '  hello   there  ' } });
    const said = await alice.waitFor('chat');
    expect(said.d).toEqual({ id: joined.d.id, text: 'hello there' });

    bob.ws.close();
    expect((await alice.waitFor('userLeave')).d.id).toBe(joined.d.id);
  });

  it('walks up the raised part of the lobby one step at a time', async () => {
    const host = await start();
    const p = await Player.join(host, await guest(host, 'Climber'));
    const me = (await p.waitFor('room')).d.users[0]!;
    p.send({ t: 'walk', d: { x: 1, y: 0 } });
    await new Promise((r) => setTimeout(r, 50));
    for (let i = 0; i < 20; i++) app!.lobby.tick();
    const last = await p.waitFor('status', (m) => m.d.some((s) => s.id === me.id && s.x === 1 && s.y === 0 && !s.moving));
    expect(last.d[0]!.z).toBe(1);
  });

  it('limits chat spam', async () => {
    const host = await start();
    const p = await Player.join(host, await guest(host, 'Spammer'));
    for (let i = 0; i < 10; i++) p.send({ t: 'chat', d: { text: `msg ${i}` } });
    await new Promise((r) => setTimeout(r, 100));
    expect(p.inbox.filter((m) => m.t === 'chat')).toHaveLength(5);
  });

  it('replaces an older connection of the same account', async () => {
    const host = await start();
    const cookie = await guest(host, 'Twice');
    const first = await Player.join(host, cookie);
    await Player.join(host, cookie);
    expect((await first.waitFor('error')).d.code).toBe('replaced');
    expect(app!.lobby.count).toBe(1);
  });
});

describe('content', () => {
  it('every layout has a Habbo-style door sticking out of the left wall', () => {
    expect(content.layouts.size).toBeGreaterThan(40);
    expect(content.layouts.get('pub_lobby')!.door).toEqual([0, 9]);
  });
});
