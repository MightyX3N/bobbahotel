// Staff: every furni, to put new ones in the room (until there is an inventory and catalogue).
// Pick one and a see-through copy follows the pointer until you click where it goes.
import { useEffect, useMemo, useRef, useState } from 'react';
import type { FurniDef } from '@bobba/shared';
import { furniDefs, furniThumb } from '../../room/furniAssets.ts';
import { actions } from '../actions.ts';
import { t } from '../i18n.ts';
import { setUi } from '../store.ts';
import { Window, type Tab } from './Window.tsx';

type Kind = 'floor' | 'wall';
const TABS: Tab<Kind>[] = [
  { key: 'floor', label: t('furni.floor') },
  { key: 'wall', label: t('furni.wall') },
];

export function FurniWindow() {
  const [defs, setDefs] = useState<FurniDef[]>([]);
  const [kind, setKind] = useState<Kind>('floor');
  const [query, setQuery] = useState('');
  useEffect(() => void furniDefs().then((d) => setDefs([...d.values()])), []);
  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return defs.filter((d) => d.kind === kind && (!q || d.name.toLowerCase().includes(q))).sort((a, b) => a.name.localeCompare(b.name));
  }, [defs, kind, query]);

  return (
    <Window title={t('furni.title')} onClose={() => setUi({ furniWindowOpen: false })} tabs={TABS} activeTab={kind} onTab={setKind} width={430} start={{ left: 440, bottom: 70 }}>
      <div className="nav-search">
        <input className="ui-input" value={query} placeholder={t('furni.search')} onChange={(e) => setQuery(e.target.value)} />
      </div>
      <div className="furni-grid">
        {shown.map((d) => (
          <button key={d.id} type="button" className="furni-cell" title={d.name} onClick={() => actions.placeFurni(d.id)}>
            <Thumb id={d.id} />
          </button>
        ))}
      </div>
      <div style={{ fontSize: 11, color: '#555' }}>{t('furni.count', { count: shown.length })}</div>
    </Window>
  );
}

const CELL = 52;
const images = new Map<string, Promise<HTMLImageElement>>();
function loadImage(url: string): Promise<HTMLImageElement> {
  let p = images.get(url);
  if (!p) {
    p = new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = url;
    });
    images.set(url, p);
  }
  return p;
}

/** A furni's picture, shrunk to fit its cell (pixels kept sharp). */
function Thumb({ id }: { id: string }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    let live = true;
    void furniThumb(id).then(async (thumb) => {
      if (!thumb || !live) return;
      const img = await loadImage(thumb.url).catch(() => null);
      const canvas = ref.current;
      if (!img || !canvas || !live) return;
      const scale = Math.min(1, CELL / thumb.w, CELL / thumb.h);
      const w = Math.max(1, Math.round(thumb.w * scale));
      const h = Math.max(1, Math.round(thumb.h * scale));
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d')!;
      ctx.imageSmoothingEnabled = scale < 1;
      if (thumb.flip) {
        ctx.translate(w, 0);
        ctx.scale(-1, 1);
      }
      ctx.drawImage(img, thumb.x, thumb.y, thumb.w, thumb.h, 0, 0, w, h);
    });
    return () => {
      live = false;
    };
  }, [id]);
  return <canvas ref={ref} width={1} height={1} />;
}
