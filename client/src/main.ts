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

/** Phones and tablets: installable as an app (see public/sw.js), and no page zooming while playing. */
function setUpDevice(): void {
  if ('serviceWorker' in navigator && import.meta.env.PROD) {
    window.addEventListener('load', () => void navigator.serviceWorker.register('/sw.js').catch(() => {}));
  }
  // iPhone/iPad: pinching the page would zoom the whole page instead of the room.
  document.addEventListener('gesturestart', (e) => e.preventDefault());
  // iPhone/iPad: after typing, the keyboard can leave the page scrolled; put it back.
  document.addEventListener('focusout', () => {
    if (window.scrollY !== 0 || window.scrollX !== 0) window.scrollTo(0, 0);
  });
}

async function main(): Promise<void> {
  setUpDevice();
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
  /** Who may do what with furni here: staff anywhere, owners in their own rooms. */
  const updateRights = () => {
    const { me, room: r } = getUi();
    const staff = !!me?.staff;
    room.setRights({ edit: staff || (!!me && r?.ownerId === me.id), place: staff });
  };
  conn.on('welcome', (d) => {
    setStatus(null);
    setUi({ me: d.me });
    updateRights();
  });
  conn.on('room', (d) => {
    setUi({ room: { id: d.id, name: d.name, description: d.description, owner: d.owner, ownerId: d.ownerId, map: d.map, door: d.door } });
    updateRights();
    room.enter(d);
  });
  conn.on('furniAdd', (d) => room.addFurni(d));
  conn.on('furniMove', (d) => room.moveFurni(d));
  conn.on('furniRemove', (d) => room.removeFurni(d.uid));
  conn.on('userJoin', (d) => room.addUser(d));
  conn.on('userLeave', (d) => room.removeUser(d.id));
  conn.on('status', (d) => room.status(d));
  conn.on('chat', (d) => room.chat(d.id, d.text));
  conn.on('furniState', (d) => room.furniState(d.uid, d.state));
  conn.on('navigator', (d) => {
    const nav = getUi().navigator;
    // Only show the answer for the list that is open now.
    if (nav.tab === d.tab && nav.query === d.query) setNavigator({ rooms: d.rooms, loading: false });
  });
  conn.on('layouts', (d) => setUi({ layouts: d.layouts }));
  conn.on('layoutSaved', () => setUi({ notice: { text: infoText('layout_saved'), at: Date.now() } }));
  conn.on('me', (d) => {
    setUi({ me: d });
    updateRights();
  });
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
  room.onUseFurni = (uid) => conn.send({ t: 'useFurni', d: { uid } });
  room.onSelectFurni = (f) => {
    const states = f ? Math.max(1, ...Object.values(f.def.dirs).map((d) => ('states' in d ? d.states.length : 1))) : 0;
    setUi({ selectedFurni: f && { uid: f.uid, name: f.def.name, states, state: f.state, wall: f.def.kind === 'wall' } });
  };
  room.onPlacing = (def) => setUi({ placing: def && { name: def.name, wall: def.kind === 'wall' } });
  room.onPlaceFurni = (def, f) => conn.send({ t: 'placeFurni', d: { def, ...f } });
  room.onMoveFurni = (uid, f) => conn.send({ t: 'moveFurni', d: { uid, ...f } });
  // Development only: lets automated tests walk to a tile. Not in production builds.
  if (import.meta.env.DEV) Object.assign(window, { bobbaRoom: room, bobbaConn: conn, bobbaWalk: (x: number, y: number) => conn.send({ t: 'walk', d: { x, y } }) });

  setActions({
    chat: (text) => conn.send({ t: 'chat', d: { text } }),
    loadRooms: (tab, query) => conn.send({ t: 'navigator', d: { tab, query } }),
    loadLayouts: () => conn.send({ t: 'layouts', d: {} }),
    createRoom: (name, description, layout) => conn.send({ t: 'createRoom', d: { name, description, layout } }),
    goToRoom: (id) => conn.send({ t: 'goToRoom', d: { id } }),
    saveLayout: (plan) => conn.send({ t: 'saveLayout', d: plan }),
    deleteLayout: (id) => conn.send({ t: 'deleteLayout', d: { id } }),
    saveRoomFloor: (roomId, map, door) => conn.send({ t: 'saveRoomFloor', d: { roomId, map, door } }),
    zoom: () => room.toggleZoom(),
    placeFurni: (def) => room.startPlacing(def),
    moveFurni: (uid) => room.startMoving(uid),
    rotateFurni: () => room.rotatePlacing(),
    pickUpFurni: (uid) => conn.send({ t: 'pickUpFurni', d: { uid } }),
    useFurni: (uid) => conn.send({ t: 'useFurni', d: { uid } }),
    cancelPlacing: () => room.cancelPlacing(),
    logout: async () => {
      await post('/api/auth/logout');
      location.reload();
    },
  });
  mountUi(document.getElementById('ui')!);
}

void main();
