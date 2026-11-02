import { build, h, selectTab, type Spec } from './kit';
import { createWindow, getWindow } from './wm';
import { S, changed, type RoomInfo } from './state';
import { drawFrame, drawLayout, loadLayers, pieceThumb, type Layers } from './avatarcanvas';
import { SLOTS, type Look } from '../avatar';

// ============================ Room browser ==========================================
export function openNavigator() {
  const spec: Spec = { t: 'col', fill: true, children: [
    { t: 'tabs', id: 'tabs', action: 'tab', tabs: [['pub', 'Public'], ['all', 'All rooms'], ['mine', 'My rooms']] },
    { t: 'row', id: 'search', children: [
      { t: 'select', id: 'field', action: 'filter', options: [['any', 'Anything'], ['name', 'Room name'], ['owner', 'Owner']] },
      { t: 'input', id: 'q', placeholder: 'Search rooms', fill: true, action: 'filter' }] },
    { t: 'list', id: 'list', fill: true },
    { t: 'text', id: 'detail', text: 'Pick a room to see what it is about.', cls: 'detail' },
    { t: 'row', children: [
      { t: 'button', label: 'Create room', action: 'create', kind: 'blue', big: true, fill: true },
      { t: 'button', label: 'Somewhere new', action: 'random', kind: 'green', big: true, fill: true }] },
  ] };
  let tab = 'pub', sel: string | null = null;
  const win = createWindow({ id: 'navigator', title: 'Room browser', w: 440, h: 620, onClose: () => S.listeners.delete(render) });
  const on = {
    tab: (v?: string) => { tab = v!; sel = null; render(); },
    filter: () => render(),
    create: () => openCreateRoom(),
    random: () => { const c = S.rooms.filter(r => r.id !== S.roomId && r.users < r.max); const busy = c.filter(r => r.users > 0); const p = busy.length ? busy : c; if (p.length) S.send({ t: 'join', room: p[Math.floor(Math.random() * p.length)].id }); },
  };
  const b = build(spec, on); b.root.style.flex = '1'; win.body.append(b.root);
  const field = b.refs.field as HTMLSelectElement, q = b.refs.q as HTMLInputElement;
  function render() {
    b.refs.search.style.display = tab === 'pub' ? 'none' : '';
    const term = q.value.trim().toLowerCase();
    const rows = S.rooms.filter(r => (tab === 'pub' ? r.pub : tab === 'mine' ? r.mine : !r.pub)).filter(r => {
      if (!term) return true;
      const inName = r.name.toLowerCase().includes(term), inOwner = r.owner.toLowerCase().includes(term);
      return field.value === 'name' ? inName : field.value === 'owner' ? inOwner : inName || inOwner;
    });
    const list = b.refs.list; list.replaceChildren();
    if (!rows.length) list.append(h('div', 'empty', tab === 'mine' ? 'You have no rooms yet.' : 'No rooms found.'));
    for (const r of rows) list.append(row(r));
    const s = S.rooms.find(r => r.id === sel);
    b.refs.detail.textContent = s ? `${s.name}${s.owner ? ' · by ' + s.owner : ''} · ${s.users}/${s.max} guests${s.desc ? ' — ' + s.desc : ''}` : 'Pick a room to see what it is about.';
  }
  function row(r: RoomInfo) {
    const e = h('div', 'rr' + (r.id === sel ? ' sel' : ''));
    const f = r.users / r.max, c = h('span', 'cnt ' + (r.users === 0 ? '' : f >= 1 ? 'full' : f >= .5 ? 'mid' : 'low'), String(r.users));
    const n = h('span', 'nm', r.name); n.title = r.name;
    e.append(c, n); if (r.owner && !r.pub) e.append(h('span', 'ow', r.owner)); e.append(h('span', 'inf', 'i'));
    e.onclick = () => { sel = r.id; render(); };
    e.ondblclick = () => S.send({ t: 'join', room: r.id });
    e.querySelector('.inf')!.addEventListener('click', ev => { ev.stopPropagation(); S.send({ t: 'join', room: r.id }); });
    return e;
  }
  S.listeners.add(render);
  selectTab(b.refs.tabs, 'pub');
  return win;
}

// ============================ Create a room =========================================
export function openCreateRoom() {
  const spec: Spec = { t: 'col', fill: true, children: [
    { t: 'text', text: 'Pick a layout for your room.' },
    { t: 'row', fill: true, children: [
      { t: 'grid', id: 'grid', fill: true },
      { t: 'col', cls: 'cr-side', children: [
        { t: 'slot', id: 'pv' },
        { t: 'text', id: 'info', text: '', cls: 'k-muted' },
        { t: 'text', text: 'Room name', cls: 'k-b' }, { t: 'input', id: 'name', max: 30 },
        { t: 'text', text: 'Description', cls: 'k-b' }, { t: 'input', id: 'desc', max: 100, placeholder: 'What is your room about?' }] }] },
    { t: 'row', children: [{ t: 'text', id: 'err', text: '', cls: 'k-fill', }, { t: 'button', label: 'Cancel', action: 'cancel' }, { t: 'button', label: 'Create room', action: 'ok', kind: 'green' }] },
  ] };
  const win = createWindow({ id: 'createroom', title: 'Create a room', w: 660, h: 560 });
  const b = build(spec, {
    cancel: () => win.close(),
    ok: () => { if (!pick) return; S.send({ t: 'create_room', name: (b.refs.name as HTMLInputElement).value, desc: (b.refs.desc as HTMLInputElement).value, layout: pick }); win.close(); getWindow('navigator')?.close(); },
  });
  b.root.style.flex = '1'; b.refs.grid.style.maxHeight = '380px'; (b.root.querySelector('.cr-side') as HTMLElement).style.cssText = 'width:200px;flex:none';
  win.body.append(b.root);
  (b.refs.name as HTMLInputElement).value = (S.me?.name ?? 'My') + "'s room";
  const pv = h('canvas'); pv.width = 200; pv.height = 130; pv.style.cssText = 'background:#1a1a1a;border-radius:4px;width:200px'; b.refs.pv.append(pv);
  let pick = '';
  const cards = new Map<string, HTMLElement>();
  const choose = (id: string) => {
    pick = id; cards.forEach((c, k) => c.classList.toggle('on', k === id));
    const l = S.layouts.find(x => x.id === id)!; drawLayout(pv, l.map, l.door); b.refs.info.textContent = `${l.name} · ${l.tiles} tiles · up to ${l.max} guests`;
  };
  for (const l of S.layouts) {
    const c = h('div', 'lay'); const cv = h('canvas'); cv.width = 86; cv.height = 56; drawLayout(cv, l.map, l.door);
    c.append(cv, h('div', '', `${l.tiles} tiles`)); c.title = l.name; c.onclick = () => choose(l.id); cards.set(l.id, c); b.refs.grid.append(c);
  }
  if (S.layouts.length) choose(S.layouts[0].id);
  return win;
}

// ============================ Change your look ======================================
export function openWardrobe() {
  if (!S.me) return;
  let look: Look = { ...S.me.look }, tab = 'body', row = 0;
  const spec: Spec = { t: 'col', fill: true, children: [
    { t: 'row', fill: true, children: [
      { t: 'col', fill: true, children: [
        { t: 'tabs', id: 'tabs', action: 'tab', tabs: [['body', 'Body'], ['hair', 'Hair'], ['top', 'Shirt'], ['bottom', 'Pants'], ['shoes', 'Shoes']] },
        { t: 'row', id: 'sex', children: [{ t: 'button', label: 'Boy', action: 'boy' }, { t: 'button', label: 'Girl', action: 'girl' }] },
        { t: 'grid', id: 'grid', fill: true }] },
      { t: 'col', cls: 'pv', children: [{ t: 'slot', id: 'pv' }, { t: 'row', children: [{ t: 'button', label: '◀', action: 'left' }, { t: 'button', label: '▶', action: 'right' }] }] }] },
    { t: 'row', children: [{ t: 'button', label: 'Close', action: 'close' }, { t: 'text', text: '', cls: 'k-fill' }, { t: 'button', label: 'Save changes', action: 'save', kind: 'green' }] },
  ] };
  const win = createWindow({ id: 'wardrobe', title: 'Change your look', theme: 'dark', w: 640, h: 540, onClose: () => clearInterval(timer) });
  const b = build(spec, {
    tab: (v?: string) => { tab = v!; render(); },
    boy: () => { look = { ...look, sex: 'm' }; render(); }, girl: () => { look = { ...look, sex: 'f' }; render(); },
    left: () => { row = (row + 3) % 4; }, right: () => { row = (row + 1) % 4; },
    close: () => win.close(), save: () => { S.send({ t: 'look', look }); if (S.me) S.me.look = { ...look }; changed(); win.close(); },
  });
  b.root.style.flex = '1'; win.body.append(b.root);
  (b.root.querySelector('.pv') as HTMLElement).style.cssText = 'width:200px;flex:none;align-items:center';
  const pv = h('canvas'); pv.style.cssText = 'image-rendering:pixelated;background:radial-gradient(ellipse at 50% 90%,#8a8a8a 0,#8a8a8a 17%,#555 18%);border-radius:6px'; b.refs.pv.append(pv);
  let layers: Layers = [], frame = 0;
  const reload = async () => { layers = await loadLayers(look, 'idle'); };
  const timer = setInterval(() => { frame = (frame + 1) % 8; if (layers.length) drawFrame(pv, layers, row, frame, 3); }, 1000 / 6);
  async function render() {
    b.refs.sex.style.display = tab === 'body' ? '' : 'none';
    b.refs.sex.querySelectorAll('button').forEach((x, i) => x.style.outline = (i === 0) === (look.sex === 'm') ? '2px solid #f0a526' : '');
    const grid = b.refs.grid; grid.replaceChildren(); grid.style.background = '#fff';
    const count = tab === 'body' ? 4 : SLOTS.find(s => s[0] === tab)![1];
    for (let n = 1; n <= count; n++) {
      const cur = (look as any)[tab === 'body' ? 'body' : tab] === n;
      const btn = h('button', 'th' + (cur ? ' on' : '')); btn.type = 'button';
      btn.onclick = () => { (look as any)[tab] = n; render(); };
      grid.append(btn); pieceThumb(look, tab, n).then(c => btn.append(c));
    }
    await reload();
  }
  selectTab(b.refs.tabs, 'body');
  return win;
}

export function openHelp() {
  const win = createWindow({ id: 'help', title: 'Help', w: 360 });
  const b = build({ t: 'col', children: [
    { t: 'text', text: 'Click the floor to walk. Type in the bar at the bottom to chat.', cls: '' },
    { t: 'text', text: 'Rooms opens the room browser: pick a public room, visit someone else\'s, or create your own.', cls: '' },
    { t: 'text', text: 'Me lets you change your look.', cls: '' },
    { t: 'button', label: 'Close', action: 'x' }] }, { x: () => win.close() });
  win.body.append(b.root); return win;
}
