// A tiny declarative UI kit: describe a window's content as a tree, get DOM back plus references by id.
// Element types: col, row, text, button, input, select, tabs, list, grid, slot (an empty box for custom code).
export type Spec =
  | { t: 'col' | 'row'; children: Spec[]; fill?: boolean; cls?: string; id?: string }
  | { t: 'text'; text: string; cls?: string; id?: string; fill?: boolean }
  | { t: 'button'; label: string; action: string; kind?: 'blue' | 'green' | 'plain'; big?: boolean; id?: string; fill?: boolean }
  | { t: 'input'; id: string; placeholder?: string; max?: number; value?: string; action?: string; fill?: boolean }
  | { t: 'select'; id: string; options: [string, string][]; action?: string }
  | { t: 'tabs'; id: string; tabs: [string, string][]; action: string }
  | { t: 'list' | 'grid' | 'slot'; id: string; cls?: string; fill?: boolean };

export type Built = { root: HTMLElement; refs: Record<string, HTMLElement> };
export type Handlers = Record<string, (value?: string, ev?: Event) => void>;

export function h<K extends keyof HTMLElementTagNameMap>(tag: K, cls = '', text?: string): HTMLElementTagNameMap[K] {
  const e = document.createElement(tag); if (cls) e.className = cls; if (text !== undefined) e.textContent = text; return e;
}

export function build(spec: Spec, on: Handlers): Built {
  const refs: Record<string, HTMLElement> = {};
  const make = (s: Spec): HTMLElement => {
    let e: HTMLElement;
    switch (s.t) {
      case 'col': case 'row': e = h('div', 'k-' + s.t + (s.cls ? ' ' + s.cls : '')); s.children.forEach(c => e.append(make(c))); break;
      case 'text': e = h('p', 'k-text ' + (s.cls ?? ''), s.text); break;
      case 'button': {
        const b = h('button', 'k-btn' + (s.kind && s.kind !== 'plain' ? ' ' + s.kind : '') + (s.big ? ' big' : ''), s.label); b.type = 'button';
        b.onclick = ev => on[s.action]?.(undefined, ev); e = b; break;
      }
      case 'input': {
        const i = h('input', 'k-input'); i.placeholder = s.placeholder ?? ''; i.maxLength = s.max ?? 100; i.value = s.value ?? '';
        if (s.action) i.oninput = ev => on[s.action!]?.(i.value, ev); e = i; break;
      }
      case 'select': {
        const sel = h('select', 'k-select'); for (const [v, l] of s.options) { const o = h('option', '', l); o.value = v; sel.append(o); }
        if (s.action) sel.onchange = ev => on[s.action!]?.(sel.value, ev); e = sel; break;
      }
      case 'tabs': {
        e = h('div', 'k-tabs');
        for (const [id, label] of s.tabs) {
          const t = h('button', 'k-tab', label); t.type = 'button'; t.dataset.tab = id;
          t.onclick = ev => { e.querySelectorAll('.k-tab').forEach(x => x.classList.toggle('on', x === t)); on[s.action]?.(id, ev); };
          e.append(t);
        }
        break;
      }
      case 'list': e = h('div', 'k-list ' + (s.cls ?? '')); break;
      case 'grid': e = h('div', 'k-grid ' + (s.cls ?? '')); break;
      case 'slot': e = h('div', s.cls ?? ''); break;
    }
    if ('fill' in s && s.fill) e.classList.add('k-fill');
    if ('id' in s && s.id) refs[s.id] = e;
    return e;
  };
  return { root: make(spec), refs };
}

/** Select a tab programmatically (and run its action). */
export function selectTab(tabs: HTMLElement, id: string) { (tabs.querySelector(`[data-tab="${id}"]`) as HTMLElement | null)?.click(); }
