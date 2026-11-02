// Start-up: check the login, show the login screen if needed, then enter the hotel.
import { Application } from 'pixi.js';
import { FLOORPLAN_LIMITS, NAME_MAX, NAME_MIN, PROTOCOL_VERSION, ROOM_NAME_MIN } from '@bobba/shared';
import { getMe, post } from './api.ts';
import { hideScreens, showChooseName, showLogin } from './login.ts';
import { Connection, serverUrl } from './net.ts';
import { RoomView } from './room/RoomView.ts';
import { setActions } from './ui/actions.ts';
import { t } from './ui/i18n.ts';
import { getUi, setNavigator, setUi } from './ui/store.ts';
import { loadTheme } from './ui/theme.ts';
import { mountUi } from './ui/UiRoot.tsx';

const status = document.getElementById('status')!;

function setStatus(text: string | null): void {
  status.textContent = text ?? '';
  status.hidden = text === null;
}

/** Text for a server error code (with the numbers some messages need). */
function errorText(code: string): string {
  const limits = getUi().me?.staff ? FLOORPLAN_LIMITS.staff : FLOORPLAN_LIMITS.club;
  return t(`error.${code}`, {
    min: code === 'bad_room_name' ? ROOM_NAME_MIN : NAME_MIN,
    max: NAME_MAX,
    w: limits.maxWidth,
    h: limits.maxHeight,
    step: limits.maxStep,
  });
}

/** Text for a server "it worked" code. */
function infoText(code: string, vars?: Record<string, string | number>): string {
  return t(code.includes('.') ? code : `info.${code}`, vars);
}

async function main(): Promise<void> {
  await loadTheme();
  const params = new URLSearchParams(location.search);
  const loginFailed = params.get('login') === 'failed';
  if (params.has('login')) history.replaceState(null, '', location.pathname);

  for (;;) {
    const me = await getMe().catch(() => null);
    if (!me) {
      setStatus(t('status.unreachable'));
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
  setStatus(t('status.connecting'));
  conn.onOpen = () => conn.send({ t: 'hello', d: { protocol: PROTOCOL_VERSION } });
  conn.onClose = () => setStatus(t('status.reconnecting'));
  conn.on('welcome', (d) => {
    setStatus(null);
    setUi({ me: d.me });
  });
  conn.on('room', (d) => {
    room.enter(d);
    setUi({ room: { id: d.id, name: d.name, description: d.description, owner: d.owner, ownerId: d.ownerId, map: d.map, door: d.door } });
  });
  conn.on('userJoin', (d) => room.addUser(d));
  conn.on('userLeave', (d) => room.removeUser(d.id));
  conn.on('status', (d) => room.status(d));
  conn.on('chat', (d) => room.chat(d.id, d.text));
  conn.on('navigator', (d) => {
    const nav = getUi().navigator;
    // Only show the answer for the list that is open now.
    if (nav.tab === d.tab && nav.query === d.query) setNavigator({ rooms: d.rooms, loading: false });
  });
  conn.on('layouts', (d) => setUi({ layouts: d.layouts }));
  conn.on('layoutSaved', () => setUi({ notice: { text: infoText('layout_saved'), at: Date.now() } }));
  conn.on('me', (d) => setUi({ me: d }));
  conn.on('info', (d) => setUi({ notice: { text: infoText(d.code, d.vars), at: Date.now() } }));
  conn.on('roomCreated', () => setNavigator({ open: false, tab: 'mine' }));
  conn.on('error', (d) => {
    if (d.code === 'old_client') {
      setStatus(d.message);
      setTimeout(() => location.reload(), 1500);
    } else if (d.code === 'replaced') {
      conn.stop();
      setStatus(d.message);
    } else {
      setUi({ notice: { text: errorText(d.code), at: Date.now() } });
    }
  });
  conn.connect();

  room.onWalk = (x, y) => conn.send({ t: 'walk', d: { x, y } });
  // Development only: lets automated tests walk to a tile. Not in production builds.
  if (import.meta.env.DEV) Object.assign(window, { bobbaWalk: (x: number, y: number) => conn.send({ t: 'walk', d: { x, y } }) });

  setActions({
    chat: (text) => conn.send({ t: 'chat', d: { text } }),
    loadRooms: (tab, query) => conn.send({ t: 'navigator', d: { tab, query } }),
    loadLayouts: () => conn.send({ t: 'layouts', d: {} }),
    createRoom: (name, description, layout) => conn.send({ t: 'createRoom', d: { name, description, layout } }),
    goToRoom: (id) => conn.send({ t: 'goToRoom', d: { id } }),
    saveLayout: (plan) => conn.send({ t: 'saveLayout', d: plan }),
    deleteLayout: (id) => conn.send({ t: 'deleteLayout', d: { id } }),
    saveRoomFloor: (roomId, map, door) => conn.send({ t: 'saveRoomFloor', d: { roomId, map, door } }),
    logout: async () => {
      await post('/api/auth/logout');
      location.reload();
    },
  });
  mountUi(document.getElementById('ui')!);
}

void main();
