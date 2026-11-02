// Start-up: check the login, show the login screen if needed, then enter the hotel.
import { Application } from 'pixi.js';
import { PROTOCOL_VERSION } from '@bobba/shared';
import { getMe, post } from './api.ts';
import { hideScreens, showChooseName, showLogin } from './login.ts';
import { Connection, serverUrl } from './net.ts';
import { RoomView } from './room/RoomView.ts';

const status = document.getElementById('status')!;
const chatbar = document.getElementById('chatbar') as HTMLFormElement;
const chatInput = document.getElementById('chat') as HTMLInputElement;
const logout = document.getElementById('logout') as HTMLButtonElement;

function setStatus(text: string | null): void {
  status.textContent = text ?? '';
  status.hidden = text === null;
}

async function main(): Promise<void> {
  const params = new URLSearchParams(location.search);
  const loginFailed = params.get('login') === 'failed';
  if (params.has('login')) history.replaceState(null, '', location.pathname);

  for (;;) {
    const me = await getMe().catch(() => null);
    if (!me) {
      setStatus('Can’t reach the hotel. Retrying…');
      await new Promise((r) => setTimeout(r, 3000));
      continue;
    }
    setStatus(null);
    if (me.state === 'in') break;
    if (me.state === 'name') await showChooseName();
    else await showLogin(loginFailed);
  }
  hideScreens();
  await enterHotel();
}

async function enterHotel(): Promise<void> {
  const app = new Application();
  await app.init({ resizeTo: window, background: 0x000000, antialias: false, autoDensity: true, resolution: window.devicePixelRatio || 1 });
  document.getElementById('game')!.appendChild(app.canvas);
  const room = new RoomView(app);

  const conn = new Connection(serverUrl());
  setStatus('Checking in…');
  conn.onOpen = () => conn.send({ t: 'hello', d: { protocol: PROTOCOL_VERSION } });
  conn.onClose = () => setStatus('Connection lost. Reconnecting…');
  conn.on('welcome', () => setStatus(null));
  conn.on('room', (d) => room.enter(d));
  conn.on('userJoin', (d) => room.addUser(d));
  conn.on('userLeave', (d) => room.removeUser(d.id));
  conn.on('status', (d) => room.status(d));
  conn.on('chat', (d) => room.chat(d.id, d.text));
  conn.on('error', (d) => {
    if (d.code === 'old_client') {
      setStatus(d.message);
      setTimeout(() => location.reload(), 1500);
    } else if (d.code === 'replaced') {
      conn.stop();
      setStatus(d.message);
    }
  });
  conn.connect();

  room.onWalk = (x, y) => conn.send({ t: 'walk', d: { x, y } });
  // Development only: lets automated tests walk to a tile. Not in production builds.
  if (import.meta.env.DEV) Object.assign(window, { bobbaWalk: (x: number, y: number) => conn.send({ t: 'walk', d: { x, y } }) });

  chatbar.hidden = false;
  logout.hidden = false;
  chatbar.addEventListener('submit', (e) => {
    e.preventDefault();
    const text = chatInput.value.trim();
    if (text) conn.send({ t: 'chat', d: { text } });
    chatInput.value = '';
  });
  // Typing anywhere goes to the chat, like in Habbo.
  window.addEventListener('keydown', (e) => {
    if (document.activeElement !== chatInput && e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) chatInput.focus();
  });
  logout.addEventListener('click', async () => {
    await post('/api/auth/logout');
    location.reload();
  });
}

void main();
