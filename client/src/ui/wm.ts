// Window manager: draggable windows with a title bar, a close button and remembered positions.
export type WinDef = { id: string; title: string; theme?: 'light' | 'dark'; w: number; h?: number; x?: number; y?: number; onClose?: () => void };
export type Win = { id: string; el: HTMLElement; body: HTMLElement; setTitle(t: string): void; close(): void; focus(): void };

const layer = () => document.getElementById('ui')!;
const open = new Map<string, Win>();
let topZ = 10;

const saved = (id: string): { x: number; y: number } | null => { try { return JSON.parse(localStorage.getItem('bh_win:' + id) ?? 'null'); } catch { return null; } };
const save = (id: string, x: number, y: number) => { try { localStorage.setItem('bh_win:' + id, JSON.stringify({ x, y })); } catch { /* storage may be blocked */ } };

export function getWindow(id: string) { return open.get(id); }
export function toggleWindow(id: string, make: () => Win) { const w = open.get(id); if (w) w.close(); else make(); }

export function createWindow(d: WinDef): Win {
  const old = open.get(d.id); if (old) { old.focus(); return old; }
  const el = document.createElement('div'); el.className = `win ${d.theme ?? 'light'}`; el.dataset.win = d.id;
  const vw = window.innerWidth, vh = window.innerHeight;
  const w = Math.min(d.w, vw - 8); el.style.width = w + 'px'; if (d.h) el.style.maxHeight = d.h + 'px';
  const title = document.createElement('div'); title.className = 'win-title';
  const tText = document.createElement('span'); tText.textContent = d.title;
  const x = document.createElement('button'); x.className = 'win-close'; x.textContent = '✕'; x.setAttribute('aria-label', 'Close');
  title.append(tText, x);
  const body = document.createElement('div'); body.className = 'win-body';
  el.append(title, body); layer().append(el);
  const sp = saved(d.id);
  const clamp = (px: number, py: number) => ({ x: Math.max(4, Math.min(px, window.innerWidth - 60)), y: Math.max(4, Math.min(py, window.innerHeight - 40)) });
  const pos = clamp(sp?.x ?? d.x ?? (vw - w) / 2, sp?.y ?? d.y ?? Math.max(10, (vh - (d.h ?? 520)) / 2 - 20));
  el.style.left = pos.x + 'px'; el.style.top = pos.y + 'px';
  const win: Win = {
    id: d.id, el, body,
    setTitle: t => { tText.textContent = t; },
    focus: () => { el.style.zIndex = String(++topZ); },
    close: () => { open.delete(d.id); el.remove(); d.onClose?.(); },
  };
  win.focus(); open.set(d.id, win);
  x.onclick = () => win.close();
  el.addEventListener('pointerdown', () => win.focus());
  title.addEventListener('pointerdown', e => {
    if (e.target === x) return;
    const sx = e.clientX - el.offsetLeft, sy = e.clientY - el.offsetTop;
    title.setPointerCapture(e.pointerId); title.style.cursor = 'grabbing';
    const move = (m: PointerEvent) => { const p = clamp(m.clientX - sx, m.clientY - sy); el.style.left = p.x + 'px'; el.style.top = p.y + 'px'; };
    const up = () => { title.removeEventListener('pointermove', move); title.removeEventListener('pointerup', up); title.style.cursor = ''; save(d.id, el.offsetLeft, el.offsetTop); };
    title.addEventListener('pointermove', move); title.addEventListener('pointerup', up);
  });
  return win;
}
