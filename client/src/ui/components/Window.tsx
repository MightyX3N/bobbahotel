// A window: header with title and close button, optional tabs, and a body. Drag it by the header.
// Windows open next to the toolbar (bottom-left), like Habbo, and stay inside the screen.
import { useEffect, useRef, useState, type ReactNode } from 'react';

export interface Tab<K extends string> {
  key: K;
  label: string;
}

interface Props<K extends string> {
  title: string;
  onClose: () => void;
  tabs?: Tab<K>[];
  activeTab?: K;
  onTab?: (key: K) => void;
  width?: number;
  /** Where it first opens, from the bottom-left corner above the toolbar. */
  start?: { left: number; bottom: number };
  children: ReactNode;
}

export function Window<K extends string>({ title, onClose, tabs, activeTab, onTab, width = 400, start = { left: 12, bottom: 70 }, children }: Props<K>) {
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ x: number; y: number } | null>(null);

  // First placement: measure the window and put it above the toolbar on the left.
  useEffect(() => {
    const el = ref.current;
    if (!el || pos) return;
    setPos({ x: start.left, y: Math.max(8, window.innerHeight - start.bottom - el.offsetHeight) });
  }, [pos, start.left, start.bottom]);

  const onPointerDown = (e: React.PointerEvent) => {
    if ((e.target as HTMLElement).closest('button') || !pos) return;
    const el = ref.current!;
    const dx = e.clientX - pos.x;
    const dy = e.clientY - pos.y;
    const move = (ev: PointerEvent) => {
      const x = Math.min(Math.max(ev.clientX - dx, 0), window.innerWidth - el.offsetWidth);
      const y = Math.min(Math.max(ev.clientY - dy, 0), window.innerHeight - 40);
      setPos({ x, y });
    };
    const up = () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  };

  return (
    <div
      ref={ref}
      className="win"
      style={{ width, left: pos?.x ?? -9999, top: pos?.y ?? -9999 }}
      // Scrolling over a window must never zoom or scroll the room behind it.
      onWheel={(e) => e.stopPropagation()}
    >
      <div className="win-header" onPointerDown={onPointerDown}>
        {title}
        <button className="win-close" type="button" aria-label="Close" onClick={onClose}>
          ✕
        </button>
      </div>
      {tabs && (
        <div className="win-tabs" role="tablist">
          {tabs.map((tab) => (
            <button
              key={tab.key}
              type="button"
              role="tab"
              aria-selected={tab.key === activeTab}
              className={`win-tab${tab.key === activeTab ? ' active' : ''}`}
              onClick={() => onTab?.(tab.key)}
            >
              {tab.label}
            </button>
          ))}
        </div>
      )}
      <div className="win-body">{children}</div>
    </div>
  );
}
