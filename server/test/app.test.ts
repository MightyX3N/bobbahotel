import type { AddressInfo } from 'node:net';
import { afterEach, describe, expect, it } from 'vitest';
import WebSocket from 'ws';
import { encodeMessage, parseMessage, PROTOCOL_VERSION, serverMessages, type ServerMessage } from '@bobba/shared';
import { createApp, type App } from '../src/app.ts';

let app: App | undefined;
afterEach(async () => {
  await app?.close();
  app = undefined;
});

async function start(allowOrigin: string[] = []): Promise<string> {
  app = createApp({ allowOrigin, version: 'test' });
  await new Promise<void>((resolve) => app!.server.listen(0, '127.0.0.1', resolve));
  const { port } = app.server.address() as AddressInfo;
  return `127.0.0.1:${port}`;
}

function nextMessage(ws: WebSocket): Promise<ServerMessage> {
  return new Promise((resolve, reject) => {
    ws.once('message', (data) => {
      const message = parseMessage(serverMessages, data.toString());
      message ? resolve(message) : reject(new Error(`bad server message: ${data}`));
    });
    ws.once('error', reject);
  });
}

function open(url: string, origin?: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url, origin ? { origin } : {});
    ws.once('open', () => resolve(ws));
    ws.once('error', reject);
  });
}

describe('server', () => {
  it('answers the health check', async () => {
    const host = await start();
    const res = await fetch(`http://${host}/api/health`);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, version: 'test', protocol: PROTOCOL_VERSION });
  });

  it('welcomes a client that says hello', async () => {
    const ws = await open(`ws://${await start()}/ws`);
    const reply = nextMessage(ws);
    ws.send(encodeMessage({ t: 'hello', d: { protocol: PROTOCOL_VERSION } }));
    expect(await reply).toEqual({ t: 'welcome', d: { server: 'test', protocol: PROTOCOL_VERSION } });
    ws.close();
  });

  it('rejects malformed messages', async () => {
    const ws = await open(`ws://${await start()}/ws`);
    const reply = nextMessage(ws);
    ws.send('{"t":"hello","d":{"protocol":"x"}}');
    expect((await reply).t).toBe('error');
    ws.close();
  });

  it('tells an outdated client to reload', async () => {
    const ws = await open(`ws://${await start()}/ws`);
    const reply = nextMessage(ws);
    ws.send(encodeMessage({ t: 'hello', d: { protocol: PROTOCOL_VERSION + 1 } }));
    expect(await reply).toMatchObject({ t: 'error', d: { code: 'old_client' } });
  });

  it('refuses WebSocket connections from other sites', async () => {
    const host = await start(['https://hotel.playbobba.com']);
    await expect(open(`ws://${host}/ws`, 'https://evil.example')).rejects.toThrow();
    const ok = await open(`ws://${host}/ws`, 'https://hotel.playbobba.com');
    ok.close();
  });
});
