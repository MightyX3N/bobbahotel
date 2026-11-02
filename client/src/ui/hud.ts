import { h } from './kit';
import { getWindow, toggleWindow } from './wm';
import { S } from './state';
import { openNavigator, openWardrobe, openHelp } from './windows';
import { drawFrame, loadLayers } from './avatarcanvas';

const svg = (inner: string) => `<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round">${inner}</svg>`;
const ICON = {
  home: svg('<path d="M3 11l9-8 9 8"/><path d="M5 10v10h5v-6h4v6h5V10"/>').replace('#fff', '#3c2a00'),
  rooms: svg('<rect x="5" y="3" width="14" height="18" rx="1"/><circle cx="15.5" cy="12.5" r=".9" fill="#fff"/>'),
};

export function buildHud(onChat: (text: string) => void) {
  const ui = document.getElementById('ui')!; ui.replaceChildren();
  // left toolbar
  const tb = h('div'); tb.id = 'toolbar';
  const home = h('button', 'tb home'); home.innerHTML = ICON.home; home.title = 'Back to the Lobby'; home.onclick = () => S.send({ t: 'join', room: 'pub:lobby' });
  const rooms = h('button', 'tb'); rooms.innerHTML = ICON.rooms + '<span>Rooms</span>'; rooms.onclick = () => toggleWindow('navigator', openNavigator);
  const me = h('button', 'tb'); me.title = 'Change your look'; me.onclick = () => toggleWindow('wardrobe', () => openWardrobe()!);
  const head = h('canvas'); me.append(head, h('span', '', 'Me'));
  tb.append(home, rooms, me); ui.append(tb);
  const drawHead = async () => { if (S.me) drawFrame(head, await loadLayers(S.me.look, 'idle'), 0, 0, 2, [16, 2, 32, 32]); };
  S.listeners.add(drawHead); drawHead();
  // top right
  const tr = h('div'); tr.id = 'topright';
  const help = h('button', 'hb', 'Help'); help.onclick = () => toggleWindow('help', openHelp);
  const out = h('button', 'hb', 'Log out'); out.onclick = () => S.logout();
  tr.append(help, out); ui.append(tr);
  // bottom bar: room name + chat
  const bar = h('div'); bar.id = 'bar';
  const name = h('span'); name.id = 'roomname';
  const say = h('input'); say.id = 'say'; say.placeholder = 'Click here to chat'; say.maxLength = 100; say.autocomplete = 'off';
  say.onkeydown = e => { if (e.key !== 'Enter') return; if (say.value.trim()) onChat(say.value); say.value = ''; };
  bar.append(name, say); ui.append(bar);
  const toast = h('div'); toast.id = 'toast'; toast.hidden = true; ui.append(toast);
  return {
    setRoom: (n: string) => { name.textContent = n; },
    toast: (t: string) => { toast.textContent = t; toast.hidden = false; setTimeout(() => { toast.hidden = true; }, 8000); },
    hasWindow: (id: string) => !!getWindow(id),
  };
}
