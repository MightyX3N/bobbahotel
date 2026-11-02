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
    case 'room': S.roomId = m.id; hud.setRoom(m.name); break;
    case 'look': if (S.me && m.id === S.me.id) { S.me.look = m.look; changed(); } break;
    case 'announce': hud.toast(m.text); break;
    case 'error': hud.toast(m.msg); break;
  }
}
