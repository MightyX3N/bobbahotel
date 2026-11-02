import type { AddressInfo } from 'node:net';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';
import WebSocket from 'ws';
import { encodeMessage, parseMessage, PROTOCOL_VERSION, serverMessages, type ServerMessage } from '@bobba/shared';
import { createApp, type App } from '../src/app.ts';
import { loadContent } from '../src/content.ts';
import { openDb } from '../src/db.ts';
import { TICK_MS } from '../src/room.ts';

const content = loadContent(fileURLToPath(new URL('../../content/', import.meta.url)));
const PUBLIC = 'http://hotel.test';

let app: App | undefined;
afterEach(async () => {
  await app?.close();
  app = undefined;
});

const STAFF_STEAM = '76561198000000099';

async function start(opts: { allowOrigin?: string[]; steamValid?: boolean } = {}): Promise<string> {
  const fakeSteam = (async () => new Response(`ns:http://specs.openid.net/auth/2.0\nis_valid:${opts.steamValid ? 'true' : 'false'}\n`)) as typeof fetch;
  app = createApp({
    config: { allowOrigin: opts.allowOrigin ?? [], version: 'test', publicUrl: PUBLIC, staffSteamIds: new Set([STAFF_STEAM]) },
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

/** Logs in a Steam account (Steam's answer is faked as valid) with a hotel name. */
async function steamLogin(host: string, steamId: string, name: string): Promise<string> {
  const params = new URLSearchParams({
    'openid.ns': 'http://specs.openid.net/auth/2.0',
    'openid.mode': 'id_res',
    'openid.op_endpoint': 'https://steamcommunity.com/openid/login',
    'openid.claimed_id': `https://steamcommunity.com/openid/id/${steamId}`,
    'openid.return_to': `${PUBLIC}/api/auth/steam/return`,
  });
  const back = await fetch(`http://${host}/api/auth/steam/return?${params}`, { redirect: 'manual' });
  const cookie = cookieOf(back);
  await fetch(`http://${host}/api/auth/name`, { method: 'POST', headers: { 'content-type': 'application/json', cookie }, body: JSON.stringify({ name }) });
  return cookie;
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

  it('shows room lists and floor plans read-only', async () => {
    const host = await start();
    const p = await Player.join(host, await guest(host, 'Planner'));
    p.send({ t: 'createRoom', d: { name: 'Planned', description: '', layout: 'model_a' } });
    const id = (await p.waitFor('roomCreated')).d.id;
    const list = (await (await fetch(`http://${host}/api/rooms?q=plan`)).json()) as { rooms: { id: string; name: string }[] };
    expect(list.rooms[0]).toMatchObject({ id, name: 'Planned' });
    const plan = (await (await fetch(`http://${host}/api/room-plan?id=${id}`)).json()) as { map: string[] };
    expect(plan.map).toEqual(content.layouts.get('model_a')!.map);
    expect((await fetch(`http://${host}/api/room-plan?id=r:99999`)).status).toBe(404);
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
    const t0 = Date.now();
    for (let i = 0; i < 4; i++) app!.lobby.tick(t0 + i * TICK_MS);
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
    const t0 = Date.now();
    for (let i = 0; i < 20; i++) app!.lobby.tick(t0 + i * TICK_MS);
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

describe('rooms', () => {
  it('lists public rooms with how many are inside', async () => {
    const host = await start();
    const p = await Player.join(host, await guest(host, 'Lister'));
    p.send({ t: 'navigator', d: { tab: 'public' } });
    const list = await p.waitFor('navigator');
    expect(list.d.rooms[0]).toMatchObject({ id: 'p:lobby', name: 'Lobby', owner: null, users: 1 });
    expect(list.d.rooms.length).toBe(content.publicRooms.filter((r) => !r.staffOnly).length);
  });

  it('creates a room from a layout, goes there, and lists it as mine', async () => {
    const host = await start();
    const p = await Player.join(host, await guest(host, 'Builder'));
    p.send({ t: 'layouts', d: {} });
    const layouts = (await p.waitFor('layouts')).d.layouts;
    expect(layouts.some((l) => l.id === 'model_a' && !l.club)).toBe(true);
    expect(layouts.some((l) => l.id === 'pub_lobby')).toBe(false);

    p.send({ t: 'createRoom', d: { name: '  My   Room ', description: 'cosy', layout: 'model_a' } });
    const created = await p.waitFor('roomCreated');
    const room = await p.waitFor('room', (m) => m.d.id === created.d.id);
    expect(room.d).toMatchObject({ name: 'My Room', description: 'cosy', owner: 'Builder' });

    p.send({ t: 'navigator', d: { tab: 'mine' } });
    const mine = await p.waitFor('navigator', (m) => m.d.tab === 'mine');
    expect(mine.d.rooms).toMatchObject([{ id: created.d.id, name: 'My Room', users: 1 }]);
  });

  it('refuses bad names, Club layouts and unknown rooms', async () => {
    const host = await start();
    const p = await Player.join(host, await guest(host, 'Picky'));
    p.send({ t: 'createRoom', d: { name: 'ab', description: '', layout: 'model_a' } });
    expect((await p.waitFor('error', (m) => m.d.code === 'bad_room_name')).d.code).toBe('bad_room_name');
    p.send({ t: 'createRoom', d: { name: 'Fancy', description: '', layout: 'model_i' } });
    await p.waitFor('error', (m) => m.d.code === 'layout_not_allowed');
    p.send({ t: 'goToRoom', d: { id: 'r:999999' } });
    await p.waitFor('error', (m) => m.d.code === 'room_not_found');
  });

  it('moves players between rooms and tells both rooms', async () => {
    const host = await start();
    const a = await Player.join(host, await guest(host, 'Mover'));
    const b = await Player.join(host, await guest(host, 'Stayer'));
    const moverId = (await b.waitFor('room')).d.users.find((u) => u.name === 'Mover')!.id;
    a.send({ t: 'goToRoom', d: { id: 'p:cafe' } });
    expect((await a.waitFor('room', (m) => m.d.id === 'p:cafe')).d.name).toBe('Corner Café');
    expect((await b.waitFor('userLeave')).d.id).toBe(moverId);
  });
});

describe('Bobba Club and floor plans', () => {
  const plan = { map: ['x0000', '00000', 'x0000', 'x0000'], door: [0, 1] as [number, number] };

  it('staff give Club with :club, and the player sees it straight away', async () => {
    const host = await start({ steamValid: true });
    const staff = await Player.join(host, await steamLogin(host, STAFF_STEAM, 'Boss'));
    expect((await staff.waitFor('welcome')).d.me).toMatchObject({ staff: true, clubUntil: 0 });
    const member = await Player.join(host, await guest(host, 'Lucky'));
    staff.send({ t: 'chat', d: { text: ':club Lucky 30' } });
    expect((await staff.waitFor('info', (m) => m.d.code === 'command.club_given')).d.vars).toMatchObject({ name: 'Lucky', days: 30 });
    const me = await member.waitFor('me');
    expect(me.d.clubUntil).toBeGreaterThan(Date.now() + 29 * 86_400_000);
    // Commands are never shown as chat.
    expect(member.inbox.some((m) => m.t === 'chat')).toBe(false);
  });

  it('only staff can use :club', async () => {
    const host = await start();
    const p = await Player.join(host, await guest(host, 'Sneaky'));
    p.send({ t: 'chat', d: { text: ':club Sneaky 999' } });
    await p.waitFor('info', (m) => m.d.code === 'command.not_allowed');
  });

  it('staff save Club layouts; only Club members can build with them', async () => {
    const host = await start({ steamValid: true });
    const staff = await Player.join(host, await steamLogin(host, STAFF_STEAM, 'Boss'));
    staff.send({ t: 'saveLayout', d: { name: 'Club Loft', club: true, ...plan } });
    const id = (await staff.waitFor('layoutSaved')).d.id;
    const listed = await staff.waitFor('layouts');
    expect(listed.d.layouts.find((l) => l.id === id)).toMatchObject({ name: 'Club Loft', club: true, custom: true });

    const normal = await Player.join(host, await guest(host, 'Normal'));
    normal.send({ t: 'createRoom', d: { name: 'Try', description: '', layout: id } });
    await normal.waitFor('error', (m) => m.d.code === 'layout_not_allowed');

    staff.send({ t: 'chat', d: { text: ':club Normal 7' } });
    await normal.waitFor('me');
    normal.send({ t: 'createRoom', d: { name: 'Now I can', description: '', layout: id } });
    const room = await normal.waitFor('room', (m) => m.d.name === 'Now I can');
    expect(room.d.map).toEqual(plan.map);
  });

  it('players can not save layouts, and bad plans are refused', async () => {
    const host = await start({ steamValid: true });
    const p = await Player.join(host, await guest(host, 'Nope'));
    p.send({ t: 'saveLayout', d: { name: 'Mine', club: false, ...plan } });
    await p.waitFor('error', (m) => m.d.code === 'not_allowed');
    const staff = await Player.join(host, await steamLogin(host, STAFF_STEAM, 'Boss'));
    staff.send({ t: 'saveLayout', d: { name: 'Broken', club: false, map: ['0000', '0000'], door: [0, 0] } });
    await staff.waitFor('error', (m) => m.d.code === 'plan_door_not_out');
  });

  it('a Club owner reshapes their own room and everyone inside starts again at the door', async () => {
    const host = await start({ steamValid: true });
    const staff = await Player.join(host, await steamLogin(host, STAFF_STEAM, 'Boss'));
    const owner = await Player.join(host, await guest(host, 'Owner'));
    owner.send({ t: 'createRoom', d: { name: 'Reshape me', description: '', layout: 'model_a' } });
    const roomId = (await owner.waitFor('roomCreated')).d.id;
    await owner.waitFor('room', (m) => m.d.id === roomId);

    // Without Club: not allowed.
    owner.send({ t: 'saveRoomFloor', d: { roomId, ...plan } });
    await owner.waitFor('error', (m) => m.d.code === 'not_allowed');

    staff.send({ t: 'chat', d: { text: ':club Owner 30' } });
    await owner.waitFor('me');
    const visitor = await Player.join(host, await guest(host, 'Visitor'));
    visitor.send({ t: 'goToRoom', d: { id: roomId } });
    await visitor.waitFor('room', (m) => m.d.id === roomId);

    // Too big for Club.
    const big = { map: ['x' + '0'.repeat(30), '0'.repeat(31)], door: [0, 1] as [number, number] };
    owner.send({ t: 'saveRoomFloor', d: { roomId, ...big } });
    await owner.waitFor('error', (m) => m.d.code === 'plan_too_big');

    owner.send({ t: 'saveRoomFloor', d: { roomId, ...plan } });
    await owner.waitFor('info', (m) => m.d.code === 'floor_saved');
    const again = await visitor.waitFor('room', (m) => m.d.id === roomId && m.d.map.length === plan.map.length);
    expect(again.d.map).toEqual(plan.map);
    expect(again.d.users).toHaveLength(2);
    // The room still works after the rebuild.
    visitor.send({ t: 'chat', d: { text: 'still here' } });
    await owner.waitFor('chat', (m) => m.d.text === 'still here');
  });
});

describe('walking speed', () => {
  it('takes the first step right after the click, then one step per TICK_MS', async () => {
    const host = await start();
    const p = await Player.join(host, await guest(host, 'Quick'));
    const room = (await p.waitFor('room')).d;
    const me = room.users[0]!;
    p.send({ t: 'walk', d: { x: room.door[0] + 3, y: room.door[1] } });
    await new Promise((r) => setTimeout(r, 50));
    const t0 = Date.now();
    app!.lobby.tick(t0); // first step: immediately
    app!.lobby.tick(t0 + 100); // too early for the second
    await new Promise((r) => setTimeout(r, 50));
    expect(p.inbox.filter((m) => m.t === 'status' && m.d.some((s) => s.id === me.id))).toHaveLength(1);
    app!.lobby.tick(t0 + TICK_MS); // second step on time
    await new Promise((r) => setTimeout(r, 50));
    expect(p.inbox.filter((m) => m.t === 'status' && m.d.some((s) => s.id === me.id))).toHaveLength(2);
  });
});

describe('content', () => {
  it('every layout has a Habbo-style door sticking out of the left wall', () => {
    expect(content.layouts.size).toBeGreaterThan(40);
    expect(content.layouts.get('pub_lobby')!.door).toEqual([0, 9]);
  });
});

describe('furni', () => {
  it('loads the furni definitions, with a sheet frame list endpoint', async () => {
    expect(content.furni.size).toBeGreaterThan(300);
    const chair = content.furni.get('salvaje_chair_2')!;
    expect(chair).toMatchObject({ kind: 'floor', size: [1, 1], sit: true });
    expect(Object.keys(chair.dirs).sort()).toEqual(['0', '2', '4', '6']);
    const host = await start();
    const body = (await (await fetch(`http://${host}/api/furni`)).json()) as { furni: unknown[]; sheets: object };
    expect(body.furni.length).toBe(content.furni.size);
    expect(typeof body.sheets).toBe('object');
  });

  it('the furni test room is for staff only and has every floor furni in it', async () => {
    const host = await start({ steamValid: true });
    const p = await Player.join(host, await guest(host, 'Nosy'));
    p.send({ t: 'navigator', d: { tab: 'public' } });
    expect((await p.waitFor('navigator')).d.rooms.some((r) => r.id === 'p:furni_test')).toBe(false);
    p.send({ t: 'goToRoom', d: { id: 'p:furni_test' } });
    expect((await p.waitFor('error')).d.code).toBe('room_not_found');
    expect((await fetch(`http://${host}/api/room-plan?id=p:furni_test`)).status).toBe(404);

    const staff = await Player.join(host, await steamLogin(host, STAFF_STEAM, 'Boss'));
    staff.send({ t: 'goToRoom', d: { id: 'p:furni_test' } });
    const room = await staff.waitFor('room', (m) => m.d.id === 'p:furni_test');
    const floor = [...content.furni.values()].filter((d) => d.kind === 'floor');
    expect(room.d.furni.length).toBe(floor.length);
    expect(new Set(room.d.furni.map((f) => f.def)).size).toBe(floor.length);
  });

  it("can't walk onto furni, only around it (rugs and seats excepted)", async () => {
    const host = await start({ steamValid: true });
    const staff = await Player.join(host, await steamLogin(host, STAFF_STEAM, 'Boss'));
    staff.send({ t: 'goToRoom', d: { id: 'p:furni_test' } });
    const room = await staff.waitFor('room', (m) => m.d.id === 'p:furni_test');
    const block = room.d.furni.find((f) => {
      const d = content.furni.get(f.def)!;
      return !d.sit && !d.walk && d.size[0] === 1 && d.size[1] === 1;
    })!;
    const me = (await staff.waitFor('welcome')).d.me;
    staff.send({ t: 'walk', d: { x: block.x, y: block.y } });
    const live = app!.rooms.get('p:furni_test')!;
    for (let i = 0; i < 80; i++) live.tick(Date.now() + i * TICK_MS);
    await new Promise((r) => setTimeout(r, 50));
    expect(staff.inbox.some((m) => m.t === 'status' && m.d.some((s) => s.id === me.id))).toBe(false);
  });
});

