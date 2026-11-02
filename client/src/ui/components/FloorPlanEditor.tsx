// Floor plan editor: paint floor tiles, heights and the door on a flat isometric grid.
// - "This room": a Bobba Club owner (or staff) reshapes the room they're in.
// - "Layouts" (staff): make shared layouts for the Create tab, free or Bobba Club only.
import { useEffect, useMemo, useRef, useState } from 'react';
import { floorPlanProblem, FLOORPLAN_LIMITS, tileCount, type FloorPlanLimits, type LayoutInfo } from '@bobba/shared';
import { actions } from '../actions.ts';
import { t } from '../i18n.ts';
import { setUi, useUi } from '../store.ts';
import { Window, type Tab } from './Window.tsx';

type Tool = 'floor' | 'erase' | 'door';
type Mode = 'room' | 'layouts';

const CANVAS_W = 600;
const CANVAS_H = 360;
const EMPTY_SIZE = 12;

/** Colours for floor heights, low (light) to high (dark). */
function heightColor(h: number, maxStep: number): string {
  const f = maxStep > 0 ? h / maxStep : 0;
  const light = 72 - f * 42;
  return `hsl(28 45% ${light}%)`;
}

interface Plan {
  cells: string[][];
  door: [number, number];
}

function planFrom(map: string[], door: [number, number]): Plan {
  return { cells: map.map((row) => [...row.toLowerCase()]), door };
}

function emptyPlan(): Plan {
  const cells = Array.from({ length: EMPTY_SIZE }, (_, y) => Array.from({ length: EMPTY_SIZE }, (_, x) => (x === 0 && y !== 2 ? 'x' : '0')));
  return { cells, door: [0, 2] };
}

export function FloorPlanEditor() {
  const me = useUi((s) => s.me);
  const room = useUi((s) => s.room);
  const layouts = useUi((s) => s.layouts);
  const staff = !!me?.staff;
  const club = !!me && me.clubUntil > Date.now();
  const ownRoom = !!room && room.id.startsWith('r:') && room.ownerId === me?.id;
  const canEditRoom = !!room && room.id.startsWith('r:') && (staff || (ownRoom && club));

  const tabs: Tab<Mode>[] = staff
    ? [
        { key: 'room', label: t('editor.tab.room') },
        { key: 'layouts', label: t('editor.tab.layouts') },
      ]
    : [{ key: 'room', label: t('editor.tab.room') }];
  const [mode, setMode] = useState<Mode>(canEditRoom || !staff ? 'room' : 'layouts');
  const limits: FloorPlanLimits = staff ? FLOORPLAN_LIMITS.staff : FLOORPLAN_LIMITS.club;

  useEffect(() => {
    if (staff) actions.loadLayouts();
  }, [staff]);

  const close = () => setUi({ editorOpen: false });

  return (
    <Window title={t('editor.title')} onClose={close} tabs={tabs.length > 1 ? tabs : undefined} activeTab={mode} onTab={setMode} width={CANVAS_W + 18}>
      {mode === 'room' ? (
        canEditRoom && room ? (
          <PlanEditor key={`room-${room.id}-${room.map.join('/')}`} start={planFrom(room.map, room.door)} limits={limits} footer={(plan) => <RoomFooter roomId={room.id} plan={plan} limits={limits} />} />
        ) : (
          <div className="nav-empty">{t('editor.not_own_room')}</div>
        )
      ) : (
        <LayoutsMode limits={limits} layouts={layouts} />
      )}
    </Window>
  );
}

function LayoutsMode({ layouts }: { limits: FloorPlanLimits; layouts: LayoutInfo[] }) {
  const [baseId, setBaseId] = useState<string>('');
  const base = layouts.find((l) => l.id === baseId);
  const start = base ? planFrom(base.map, base.door) : emptyPlan();
  return (
    <>
      <label className="ui-label" style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
        {t('editor.base')}
        <select className="ui-input" value={baseId} onChange={(e) => setBaseId(e.target.value)}>
          <option value="">{t('editor.new')}</option>
          {layouts.map((l) => (
            <option key={l.id} value={l.id}>
              {l.name}
              {l.club ? ` (${t('creator.club')})` : ''}
              {l.custom ? ` · ${t('creator.custom')}` : ''}
            </option>
          ))}
        </select>
      </label>
      <PlanEditor key={`layout-${baseId}`} start={start} limits={FLOORPLAN_LIMITS.staff} footer={(plan) => <LayoutFooter plan={plan} base={base} />} />
    </>
  );
}

function RoomFooter({ roomId, plan, limits }: { roomId: string; plan: Plan; limits: FloorPlanLimits }) {
  const map = plan.cells.map((r) => r.join(''));
  const problem = floorPlanProblem(map, plan.door, limits);
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
      <span style={{ flex: 1, fontSize: 11, color: '#444' }}>{t('editor.room_note')}</span>
      <button className="ui-btn good" type="button" disabled={!!problem} onClick={() => actions.saveRoomFloor(roomId, map, plan.door)}>
        {t('editor.save_room')}
      </button>
    </div>
  );
}

function LayoutFooter({ plan, base }: { plan: Plan; base: { id: string; name: string; club: boolean; custom: boolean } | undefined }) {
  const [name, setName] = useState(base?.custom ? base.name : '');
  const [club, setClub] = useState(base?.club ?? false);
  const map = plan.cells.map((r) => r.join(''));
  const problem = floorPlanProblem(map, plan.door, FLOORPLAN_LIMITS.staff);
  const ok = !problem && name.trim().length >= 2;
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
      <input className="ui-input" style={{ flex: '1 1 160px' }} value={name} maxLength={40} placeholder={t('editor.name')} onChange={(e) => setName(e.target.value)} />
      <label style={{ display: 'flex', gap: 4, alignItems: 'center' }}>
        <input type="checkbox" checked={club} onChange={(e) => setClub(e.target.checked)} />
        {t('editor.club')}
      </label>
      {base?.custom && (
        <>
          <button className="ui-btn" type="button" disabled={!ok} onClick={() => actions.saveLayout({ id: base.id, name, club, map, door: plan.door })}>
            {t('editor.update')}
          </button>
          <button className="ui-btn" style={{ background: 'var(--btn-close)' }} type="button" onClick={() => actions.deleteLayout(base.id)}>
            {t('editor.delete')}
          </button>
        </>
      )}
      <button className="ui-btn good" type="button" disabled={!ok} onClick={() => actions.saveLayout({ name, club, map, door: plan.door })}>
        {t('editor.save_new')}
      </button>
    </div>
  );
}

function PlanEditor({ start, limits, footer }: { start: Plan; limits: FloorPlanLimits; footer: (plan: Plan) => React.ReactNode }) {
  const [plan, setPlan] = useState<Plan>(start);
  const [tool, setTool] = useState<Tool>('floor');
  const [brush, setBrush] = useState(0);
  const [hover, setHover] = useState<[number, number] | null>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const painting = useRef(false);

  const h = plan.cells.length;
  const w = plan.cells[0]?.length ?? 0;
  const map = useMemo(() => plan.cells.map((r) => r.join('')), [plan]);
  const problem = floorPlanProblem(map, plan.door, limits);

  // Tile size and origin so the whole grid fits the canvas.
  const tw = Math.max(6, Math.min(48, Math.floor(Math.min((CANVAS_W - 20) / ((w + h) / 2), (CANVAS_H - 20) / ((w + h) / 4)))));
  const ox = CANVAS_W / 2 - ((w - h) * tw) / 4;
  const oy = (CANVAS_H - ((w + h) * tw) / 4) / 2;

  useEffect(() => {
    const ctx = canvas.current?.getContext('2d');
    if (!ctx) return;
    ctx.clearRect(0, 0, CANVAS_W, CANVAS_H);
    const diamond = (x: number, y: number) => {
      const cx = ox + ((x - y) * tw) / 2;
      const cy = oy + ((x + y) * tw) / 4;
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx + tw / 2, cy + tw / 4);
      ctx.lineTo(cx, cy + tw / 2);
      ctx.lineTo(cx - tw / 2, cy + tw / 4);
      ctx.closePath();
      return [cx, cy + tw / 4] as const;
    };
    ctx.font = `bold ${Math.max(8, Math.floor(tw / 4))}px sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const c = plan.cells[y]![x]!;
        const [mx, my] = diamond(x, y);
        if (c === 'x') {
          ctx.strokeStyle = 'rgba(0,0,0,0.18)';
          ctx.lineWidth = 1;
          ctx.stroke();
          continue;
        }
        const z = parseInt(c, 36);
        const isDoor = x === plan.door[0] && y === plan.door[1];
        ctx.fillStyle = isDoor ? '#1e7295' : heightColor(z, limits.maxStep);
        ctx.fill();
        ctx.strokeStyle = 'rgba(0,0,0,0.35)';
        ctx.stroke();
        if (tw >= 24 && z > 0) {
          ctx.fillStyle = '#fff';
          ctx.fillText(String(z), mx, my);
        }
      }
    }
    if (hover) {
      diamond(hover[0], hover[1]);
      ctx.strokeStyle = '#fff';
      ctx.lineWidth = 2;
      ctx.stroke();
    }
  }, [plan, hover, tw, ox, oy, w, h, limits.maxStep]);

  const cellAt = (e: React.PointerEvent): [number, number] | null => {
    const r = canvas.current!.getBoundingClientRect();
    const px = ((e.clientX - r.left) / r.width) * CANVAS_W;
    const py = ((e.clientY - r.top) / r.height) * CANVAS_H;
    const u = (px - ox) / (tw / 2);
    const v = (py - oy) / (tw / 4);
    const x = Math.floor((u + v) / 2);
    const y = Math.floor((v - u) / 2);
    return x >= 0 && y >= 0 && x < w && y < h ? [x, y] : null;
  };

  const apply = (cell: [number, number] | null) => {
    if (!cell) return;
    const [x, y] = cell;
    setPlan((p) => {
      const cells = p.cells.map((r) => [...r]);
      let door = p.door;
      if (tool === 'erase') cells[y]![x] = 'x';
      else if (tool === 'floor') cells[y]![x] = brush.toString(36);
      else {
        if (cells[y]![x] === 'x') cells[y]![x] = '0';
        door = [x, y];
      }
      return { cells, door };
    });
  };

  const resize = (nw: number, nh: number) => {
    nw = Math.min(Math.max(nw, 2), limits.maxWidth);
    nh = Math.min(Math.max(nh, 2), limits.maxHeight);
    setPlan((p) => ({
      cells: Array.from({ length: nh }, (_, y) => Array.from({ length: nw }, (_, x) => p.cells[y]?.[x] ?? 'x')),
      door: p.door,
    }));
  };

  const problemText = problem && t(`error.${problem}`, { w: limits.maxWidth, h: limits.maxHeight, step: limits.maxStep });

  return (
    <>
      <div style={{ display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' }}>
        {(['floor', 'erase', 'door'] as Tool[]).map((k) => (
          <button key={k} type="button" className="ui-btn" style={tool === k ? undefined : { background: '#7a8a96' }} onClick={() => setTool(k)}>
            {t(`editor.tool.${k}`)}
          </button>
        ))}
        <label style={{ display: 'flex', gap: 4, alignItems: 'center', marginLeft: 6 }}>
          {t('editor.height')}
          <input type="range" min={0} max={limits.maxStep} value={brush} onChange={(e) => { setBrush(Number(e.target.value)); setTool('floor'); }} />
          <span style={{ display: 'inline-block', width: 22, height: 14, borderRadius: 3, background: heightColor(brush, limits.maxStep), textAlign: 'center', color: '#fff', fontSize: 10, lineHeight: '14px' }}>{brush}</span>
        </label>
        <label style={{ display: 'flex', gap: 4, alignItems: 'center', marginLeft: 'auto' }}>
          {t('editor.size')}
          <input className="ui-input" style={{ width: 48, flex: 'none' }} type="number" min={2} max={limits.maxWidth} value={w} onChange={(e) => resize(Number(e.target.value), h)} />×
          <input className="ui-input" style={{ width: 48, flex: 'none' }} type="number" min={2} max={limits.maxHeight} value={h} onChange={(e) => resize(w, Number(e.target.value))} />
        </label>
      </div>
      <canvas
        ref={canvas}
        width={CANVAS_W}
        height={CANVAS_H}
        style={{ width: '100%', background: '#1c1c20', borderRadius: 4, touchAction: 'none', cursor: 'crosshair' }}
        onPointerDown={(e) => {
          painting.current = tool !== 'door';
          (e.target as HTMLElement).setPointerCapture(e.pointerId);
          apply(cellAt(e));
        }}
        onPointerMove={(e) => {
          const c = cellAt(e);
          setHover(c);
          if (painting.current) apply(c);
        }}
        onPointerUp={() => (painting.current = false)}
        onPointerLeave={() => setHover(null)}
      />
      <div style={{ display: 'flex', gap: 8, fontSize: 12 }}>
        <span>{t('editor.tiles', { tiles: tileCount(map) })}</span>
        <span style={{ color: '#555' }}>{t('editor.limits', { w: limits.maxWidth, h: limits.maxHeight, step: limits.maxStep })}</span>
        <span style={{ marginLeft: 'auto', fontWeight: 700, color: problem ? '#b3261e' : '#00800b' }}>{problemText ?? t('editor.ok')}</span>
      </div>
      {footer(plan)}
    </>
  );
}
