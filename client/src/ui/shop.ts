import { build, h, type Spec } from './kit';
import { createWindow, getWindow } from './wm';
import { S, furniThumb, type Page, type InvItem } from './state';

const sellable = (id: string) => { const d = S.defs[id]; return !!d && !d.wall; };

// ============================ My stuff (inventory) ===================================
export function openInventory() {
  let sel = '';
  const spec: Spec = { t: 'col', fill: true, children: [
    { t: 'grid', id: 'grid', fill: true },
    { t: 'text', id: 'info', text: 'Nothing selected.', cls: 'detail' },
    { t: 'row', children: [{ t: 'text', id: 'count', text: '', cls: 'k-fill k-muted' }, { t: 'button', label: 'Place in room', action: 'place', kind: 'green', id: 'placeBtn' }] },
  ] };
  const win = createWindow({ id: 'inventory', title: 'My stuff', w: 460, h: 520, onClose: () => S.listeners.delete(render) });
  const b = build(spec, { place: () => { if (!S.edit) { const r = S.rooms.find(x => x.mine); if (r) S.send({ t: 'join', room: r.id }); return; } const it = S.inv.find(i => i.furni === sel); if (it) S.startPlace(it.id); } });
  b.root.style.cssText = 'height:400px'; b.refs.grid.style.minHeight = '0'; win.body.append(b.root);
  function render() {
    const groups = new Map<string, InvItem[]>();
    for (const i of S.inv) { if (!groups.has(i.furni)) groups.set(i.furni, []); groups.get(i.furni)!.push(i); }
    if (sel && !groups.has(sel)) sel = '';
    const grid = b.refs.grid; grid.replaceChildren();
    if (!groups.size) grid.append(h('div', 'empty', 'Your inventory is empty. Visit the Catalogue to buy furniture.'));
    for (const [f, list] of [...groups].sort((a, c) => (S.defs[a[0]]?.name ?? '').localeCompare(S.defs[c[0]]?.name ?? ''))) {
      const d = S.defs[f]; if (!d) continue;
      const cell = h('button', 'pc' + (f === sel ? ' on' : '')); cell.type = 'button'; cell.title = d.name;
      const cv = h('canvas'); cv.width = cv.height = 52; furniThumb(d.anim?.[0] ?? d.file, 52).then(c => cv.getContext('2d')!.drawImage(c, 0, 0)); cell.append(cv);
      if (list.length > 1) cell.append(h('span', 'pcn', String(list.length)));
      cell.onclick = () => { sel = f; render(); };
      grid.append(cell);
    }
    const d = S.defs[sel];
    b.refs.info.textContent = d ? d.name : 'Nothing selected.';
    b.refs.count.textContent = S.inv.length ? `${S.inv.length} piece${S.inv.length === 1 ? '' : 's'}` : '';
    const pb = b.refs.placeBtn as HTMLButtonElement; pb.disabled = S.edit && !d;
    pb.textContent = S.edit ? 'Place in room' : 'Go to my room to place';
  }
  S.listeners.add(render); render();
  return win;
}

// ============================ Catalogue ==============================================
export function openCatalogue() {
  const pages = S.pages;
  const kids = (id: string | null) => pages.filter(p => p.parent === id).sort((a, c) => a.order - c.order);
  const pieces = (p: Page) => Object.keys(S.defs).filter(id => sellable(id) && S.defs[id].pages.includes(p.id)).sort((a, c) => S.defs[a].name.localeCompare(S.defs[c].name));
  const hasStuff = (p: Page): boolean => p.kind === 'bundle' ? true : p.kind === 'folder' ? kids(p.id).some(hasStuff) : p.kind === 'page' && pieces(p).length > 0;
  const roots = kids(null).filter(hasStuff);
  let page: Page | null = null, pick: { id: string; bundle: boolean } | null = null;
  const spec: Spec = { t: 'row', fill: true, children: [
    { t: 'list', id: 'tree', cls: 'cat-tree' },
    { t: 'col', fill: true, children: [
      { t: 'text', id: 'title', text: '', cls: 'k-b cat-title' }, { t: 'text', id: 'desc', text: '', cls: 'k-muted' },
      { t: 'grid', id: 'grid', fill: true },
      { t: 'col', id: 'buy', cls: 'cat-buy', children: [
        { t: 'text', id: 'bname', text: 'Click something to see its price.', cls: 'k-b' }, { t: 'text', id: 'bsub', text: '', cls: 'k-muted' },
        { t: 'row', children: [{ t: 'text', id: 'bal', text: '', cls: 'k-fill k-muted' }, { t: 'button', label: 'Buy', action: 'buy', kind: 'green', id: 'buyBtn' }] }] }] }] };
  const win = createWindow({ id: 'catalogue', title: 'Catalogue', w: 700, h: 560, onClose: () => S.listeners.delete(bal) });
  const b = build(spec, { buy: () => { if (pick) S.send({ t: 'buy', furni: pick.id }); } });
  b.root.style.cssText = 'height:470px;align-items:stretch'; win.body.append(b.root);
  b.refs.tree.style.cssText = 'flex:none;width:190px;align-self:stretch;min-height:0'; b.refs.grid.style.minHeight = '0'; (b.refs.grid.parentElement as HTMLElement).style.alignSelf = 'stretch';
  const bal = () => { b.refs.bal.textContent = `You have ${S.silver} silver`; (b.refs.buyBtn as HTMLButtonElement).disabled = !pick; };
  const price = () => pick ? (pick.bundle ? pages.find(p => p.id === pick!.id)?.price ?? 0 : S.defs[pick.id].price) : 0;

  function drawTree() {
    b.refs.tree.replaceChildren();
    const add = (p: Page, depth: number) => {
      const row = h('div', 'ct' + (page?.id === p.id ? ' sel' : '') + (p.kind === 'folder' ? ' fold' : ''));
      row.style.paddingLeft = 8 + depth * 14 + 'px';
      const ic = h('canvas'); ic.width = ic.height = 24; row.append(ic, h('span', '', p.title));
      const icon = p.icon && S.defs[p.icon]; if (icon) furniThumb(icon.anim?.[0] ?? icon.file, 24).then(c => ic.getContext('2d')!.drawImage(c, 0, 0));
      row.onclick = () => { go(p); };
      b.refs.tree.append(row);
      if (p.kind === 'folder') for (const c of kids(p.id).filter(c => c.kind !== 'bundle' && hasStuff(c))) add(c, depth + 1);
    };
    for (const p of roots) add(p, 0);
  }
  function go(p: Page) {
    page = p; pick = null; drawTree();
    b.refs.title.textContent = p.title; b.refs.desc.textContent = p.desc;
    const grid = b.refs.grid; grid.replaceChildren();
    const tile = (id: string, name: string, icon: string, cost: number, bundle: boolean) => {
      const t = h('button', 'pt'); t.type = 'button'; t.title = name;
      const cv = h('canvas'); cv.width = cv.height = 56; furniThumb(icon, 56).then(c => cv.getContext('2d')!.drawImage(c, 0, 0));
      t.append(cv, h('span', 'pp', cost + ' silver'));
      t.onclick = () => { pick = { id, bundle }; grid.querySelectorAll('.pt').forEach(x => x.classList.toggle('on', x === t)); show(); };
      grid.append(t);
    };
    if (p.kind === 'folder') {
      const bundles = kids(p.id).filter(c => c.kind === 'bundle');
      if (bundles.length) for (const c of bundles) { const ic = c.icon && S.defs[c.icon]; tile(c.id, c.title, ic ? ic.anim?.[0] ?? ic.file : '', c.price ?? 0, true); }
      else grid.append(h('div', 'empty', 'Pick a page on the left.'));
    } else for (const id of pieces(p)) { const d = S.defs[id]; tile(id, d.name, d.anim?.[0] ?? d.file, d.price, false); }
    show();
  }
  function show() {
    if (!pick) { b.refs.bname.textContent = 'Click something to see its price.'; b.refs.bsub.textContent = ''; bal(); return; }
    if (pick.bundle) {
      const p = pages.find(x => x.id === pick!.id)!;
      b.refs.bname.textContent = `${p.title} - ${p.price} silver`;
      b.refs.bsub.textContent = (p.items ?? []).map(([f, n]) => `${n > 1 ? n + '× ' : ''}${S.defs[f]?.name ?? f}`).join(', ');
    } else { const d = S.defs[pick.id]; b.refs.bname.textContent = `${d.name} - ${d.price} silver`; b.refs.bsub.textContent = d.seat ? 'You can sit on it.' : d.stack ? 'Other things can stand on it.' : d.stairs ? 'You can walk up it.' : d.flat ? 'You can walk over it.' : d.anim ? 'Double-click it to switch it on and off.' : ''; }
    bal();
  }
  S.listeners.add(bal);
  if (roots.length) go(roots.find(r => r.id === 'indoor') ? kids('indoor').find(hasStuff) ?? roots[0] : roots[0]); else b.refs.desc.textContent = 'The catalogue is empty right now.';
  return win;
}
export const isOpen = (id: string) => !!getWindow(id);
