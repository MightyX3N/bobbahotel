// The toolbar along the bottom: window buttons on the left, the chat input in the middle.
import { useEffect, useRef } from 'react';
import { CHAT_MAX, clubDaysLeft } from '@bobba/shared';
import { actions } from '../actions.ts';
import { t } from '../i18n.ts';
import { getUi, setNavigator, setUi, useUi } from '../store.ts';
import { FloorPlanIcon, LogoutIcon, NavigatorIcon } from './Icons.tsx';

export function Toolbar() {
  const navOpen = useUi((s) => s.navigator.open);
  const editorOpen = useUi((s) => s.editorOpen);
  const me = useUi((s) => s.me);
  const clubDays = me ? clubDaysLeft(me.clubUntil) : 0;
  // Staff always get the floor plan editor; Bobba Club members for their own rooms.
  const showEditor = !!me && (me.staff || clubDays > 0);
  const input = useRef<HTMLInputElement>(null);

  // Typing anywhere goes to the chat, like Habbo (unless you're typing in another field).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const el = document.activeElement;
      const typing = el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement;
      if (!typing && e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) input.current?.focus();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const toggleNavigator = () => {
    const nav = getUi().navigator;
    if (nav.open) return setNavigator({ open: false });
    setNavigator({ open: true, loading: nav.tab !== 'create' });
    if (nav.tab === 'create') actions.loadLayouts();
    else actions.loadRooms(nav.tab, nav.query);
  };

  return (
    <div className="toolbar" onWheel={(e) => e.stopPropagation()}>
      <div className="toolbar-icons">
        <button type="button" className={`toolbar-btn${navOpen ? ' active' : ''}`} title={t('toolbar.navigator')} onClick={toggleNavigator}>
          <NavigatorIcon />
        </button>
        {showEditor && (
          <button type="button" className={`toolbar-btn${editorOpen ? ' active' : ''}`} title={t('toolbar.floorplan')} onClick={() => setUi({ editorOpen: !editorOpen })}>
            <FloorPlanIcon />
          </button>
        )}
      </div>
      <form
        className="toolbar-chat"
        onSubmit={(e) => {
          e.preventDefault();
          const text = input.current!.value.trim();
          if (text) actions.chat(text);
          input.current!.value = '';
        }}
      >
        <input ref={input} maxLength={CHAT_MAX} placeholder={t('chat.placeholder')} aria-label={t('chat.placeholder')} autoComplete="off" />
      </form>
      <div className="toolbar-right">
        {clubDays > 0 && (
          <div className="club-badge" title={t('club.badge')}>
            <b>{t('club.badge')}</b>
            <span>{clubDays === 1 ? t('club.day') : t('club.days', { days: clubDays })}</span>
          </div>
        )}
        <button type="button" className="toolbar-btn" title={t('toolbar.logout')} onClick={() => actions.logout()}>
          <LogoutIcon />
        </button>
      </div>
    </div>
  );
}
