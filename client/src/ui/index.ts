import { buildHud } from './hud';
import { S, changed, type RoomInfo, type LayoutInfo } from './state';
import type { Look } from '../avatar';
import './ui.css';

let hud: ReturnType<typeof buildHud> | null = null;

export function initUI(o: { http: string; send: (m: object) => void; logout: () => void; me: { id: number; name: string; look: Look; steam: boolean } }) {
  S.http = o.http; S.send = o.send; S.logout = o.logout; S.me = o.me;
  hud = buildHud(text => S.send({ t: 'chat', text }));
}
export function hideUI() { document.getElementById('ui')?.replaceChildren(); hud = null; }

/** Feed server messages to the UI. */
export function uiHandle(m: any) {
  if (!hud) return;
  switch (m.t) {
    case 'rooms': S.rooms = m.rooms as RoomInfo[]; changed(); break;
    case 'layouts': S.layouts = m.layouts as LayoutInfo[]; break;
    case 'room': S.roomId = m.id; S.edit = !!m.edit; S.selected = null; hud.setRoom(m.name); changed(); break;
    case 'balance': S.silver = m.silver; S.gold = m.gold; changed(); break;
    case 'inventory': S.inv = m.items; changed(); break;
    case 'inv_add': S.inv.push(...m.items); changed(); break;
    case 'inv_remove': S.inv = S.inv.filter(i => i.id !== m.id); changed(); break;
    case 'bought': hud.toast(m.count > 1 ? `Bought ${m.count} pieces. They are in My stuff.` : 'Bought! It is in My stuff.'); break;
    case 'look': if (S.me && m.id === S.me.id) { S.me.look = m.look; changed(); } break;
    case 'announce': hud.toast(m.text); break;
    case 'error': hud.toast(m.msg); break;
  }
}
