import { h } from './kit';
import { getWindow, toggleWindow } from './wm';
import { S, furniThumb } from './state';
import { openNavigator, openWardrobe, openHelp } from './windows';
import { openInventory, openCatalogue } from './shop';
import { drawFrame, loadLayers } from './avatarcanvas';

const svg = (inner: string) => `<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round">${inner}</svg>`;
const ICON = {
  home: svg('<path d="M3 11l9-8 9 8"/><path d="M5 10v10h5v-6h4v6h5V10"/>').replace('#fff', '#3c2a00'),
  cat: svg('<path d="M4 8l8-4 8 4v10l-8 4-8-4z"/><path d="M4 8l8 4 8-4M12 12v10"/>'),
  inv: svg('<rect x="4" y="9" width="16" height="11" rx="1"/><path d="M4 9l2-5h12l2 5"/><path d="M9 13h6"/>'),
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
  const cat = h('button', 'tb'); cat.innerHTML = ICON.cat + '<span>Catalogue</span>'; cat.onclick = () => toggleWindow('catalogue', openCatalogue);
  const inv = h('button', 'tb'); inv.innerHTML = ICON.inv + '<span>My stuff</span>'; inv.onclick = () => toggleWindow('inventory', openInventory);
  tb.append(home, rooms, cat, inv, me); ui.append(tb);
  const drawHead = async () => { if (S.me) drawFrame(head, await loadLayers(S.me.look, 'idle'), 0, 0, 2, [16, 2, 32, 32]); };
  S.listeners.add(drawHead); drawHead();
  const toast = h('div'); toast.id = 'toast'; toast.hidden = true; ui.append(toast);
  // coins + item card
  const coins = h('div'); coins.id = 'coins'; ui.append(coins);
  const card = h('div'); card.id = 'itemcard'; card.hidden = true; ui.append(card);
  const draw = () => {
    toast.textContent = S.reconnecting ? 'Connection lost. Reconnecting...' : toast.textContent; if (S.reconnecting) toast.hidden = false; else if (toast.textContent.startsWith('Connection lost')) toast.hidden = true;
    coins.innerHTML = `<b>${S.silver}</b> silver · <b>${S.gold}</b> gold`;
    const it = S.selected, d = it && S.defs[it.furni];
    if (!it || !d) { card.hidden = true; return; }
    card.hidden = false; card.replaceChildren();
    const cv = h('canvas'); cv.width = cv.height = 64; furniThumb(d.anim?.[0] ?? d.file, 64).then(c => cv.getContext('2d')!.drawImage(c, 0, 0));
    const bt = h('div', 'bt'); const b = (label: string, act: string, cls = '') => { const x = h('button', cls, label); x.type = 'button'; x.onclick = () => S.itemAction(act); bt.append(x); };
    if (d.seat) b('Sit here', 'sit');
    if (d.anim) b(it.state === 0 ? 'Switch off' : 'Switch on', 'use');
    if (S.edit) { b('Move', 'move'); b('Rotate', 'rotate'); b('Pick up', 'pickup', 'red'); }
    card.append(cv, h('div', 'nm', d.name), bt);
  };
  S.listeners.add(draw); draw();
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
  return {
    setRoom: (n: string) => { name.textContent = n; },
    toast: (t: string) => { toast.textContent = t; toast.hidden = false; setTimeout(() => { toast.hidden = true; }, 8000); },
    hasWindow: (id: string) => !!getWindow(id),
  };
}
