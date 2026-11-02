// Everything drawn on top of the room: toolbar, windows, the room's name and notices.
import { useEffect } from 'react';
import { createRoot } from 'react-dom/client';
import { FloorPlanEditor } from './components/FloorPlanEditor.tsx';
import { Navigator } from './components/Navigator.tsx';
import { Toolbar } from './components/Toolbar.tsx';
import { t } from './i18n.ts';
import { setUi, useUi } from './store.ts';

function RoomChip() {
  const room = useUi((s) => s.room);
  if (!room) return null;
  return (
    <div className="room-chip">
      <b>{room.name}</b>
      <span>{room.owner ? t('room.by', { owner: room.owner }) : t('room.public')}</span>
    </div>
  );
}

function Notice() {
  const notice = useUi((s) => s.notice);
  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setUi({ notice: null }), 4000);
    return () => clearTimeout(timer);
  }, [notice]);
  return notice ? <div className="notice">{notice.text}</div> : null;
}

function Ui() {
  const navOpen = useUi((s) => s.navigator.open);
  const editorOpen = useUi((s) => s.editorOpen);
  return (
    <div className="ui-root">
      <RoomChip />
      {navOpen && <Navigator />}
      {editorOpen && <FloorPlanEditor />}
      <Notice />
      <Toolbar />
    </div>
  );
}

export function mountUi(el: HTMLElement): void {
  createRoot(el).render(<Ui />);
}
