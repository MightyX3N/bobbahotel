// The navigator: room lists (public rooms, all rooms, my rooms), search, and creating a room.
import { useEffect, useState } from 'react';
import { ROOM_DESC_MAX, ROOM_NAME_MAX, ROOM_NAME_MIN, tileCount, type NavigatorTab, type RoomInfo } from '@bobba/shared';
import { actions } from '../actions.ts';
import { t } from '../i18n.ts';
import { setNavigator, useUi } from '../store.ts';
import { PersonIcon } from './Icons.tsx';
import { LayoutPreview } from './LayoutPreview.tsx';
import { Window, type Tab } from './Window.tsx';

type NavTab = NavigatorTab | 'create';

const TABS: Tab<NavTab>[] = [
  { key: 'public', label: t('navigator.tab.public') },
  { key: 'all', label: t('navigator.tab.all') },
  { key: 'mine', label: t('navigator.tab.mine') },
  { key: 'create', label: t('navigator.tab.create') },
];

export function Navigator() {
  const nav = useUi((s) => s.navigator);
  const close = () => setNavigator({ open: false });

  const openTab = (tab: NavTab) => {
    setNavigator({ tab, query: '', loading: tab !== 'create', rooms: tab === nav.tab ? nav.rooms : [] });
    if (tab === 'create') actions.loadLayouts();
    else actions.loadRooms(tab, '');
  };

  return (
    <Window title={nav.tab === 'create' ? t('creator.title') : t('navigator.title')} onClose={close} tabs={TABS} activeTab={nav.tab} onTab={openTab} width={420}>
      {nav.tab === 'create' ? <RoomCreator /> : <RoomList tab={nav.tab} />}
    </Window>
  );
}

/** How often an open room list refreshes, so user counts stay current. */
const REFRESH_MS = 5000;

function RoomList({ tab }: { tab: NavigatorTab }) {
  const { rooms, loading, query } = useUi((s) => s.navigator);
  const current = useUi((s) => s.room?.id);
  const [text, setText] = useState(query);
  useEffect(() => setText(query), [query, tab]);
  // Keep the list (and its user counts) up to date while it's open.
  useEffect(() => {
    const timer = setInterval(() => actions.loadRooms(tab, query), REFRESH_MS);
    return () => clearInterval(timer);
  }, [tab, query]);
  // Also refresh right after moving to another room (its count changed).
  useEffect(() => {
    if (current) actions.loadRooms(tab, query);
  }, [current]); // eslint-disable-line react-hooks/exhaustive-deps

  const search = (e: React.FormEvent) => {
    e.preventDefault();
    setNavigator({ query: text, loading: true });
    actions.loadRooms(tab, text);
  };

  return (
    <>
      <form className="nav-search" onSubmit={search}>
        <input className="ui-input" value={text} maxLength={40} placeholder={t('navigator.search.placeholder')} onChange={(e) => setText(e.target.value)} />
        <button className="ui-btn" type="submit">
          {t('navigator.search.button')}
        </button>
      </form>
      <div className="nav-list" style={{ height: 300 }}>
        {loading && rooms.length === 0 ? (
          <div className="nav-empty">{t('navigator.loading')}</div>
        ) : rooms.length === 0 ? (
          <div className="nav-empty">{t(`navigator.empty.${tab}`)}</div>
        ) : (
          rooms.map((r) => <RoomRow key={r.id} room={r} current={r.id === current} />)
        )}
      </div>
    </>
  );
}

function RoomRow({ room, current }: { room: RoomInfo; current: boolean }) {
  const fill = room.users / Math.max(1, room.maxUsers);
  const level = room.users === 0 ? '' : fill < 0.5 ? 'low' : fill < 0.9 ? 'mid' : 'high';
  return (
    <button
      type="button"
      className={`nav-row${current ? ' current' : ''}`}
      title={[room.description, t('navigator.users', { users: room.users, max: room.maxUsers })].filter(Boolean).join('\n')}
      onClick={() => actions.goToRoom(room.id)}
    >
      <span className={`nav-badge ${level}`}>
        <PersonIcon /> {room.users}
      </span>
      <span className="nav-name">{room.name}</span>
      {room.owner && <span className="nav-owner">{t('navigator.owner', { owner: room.owner })}</span>}
    </button>
  );
}

function RoomCreator() {
  const layouts = useUi((s) => s.layouts);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [layout, setLayout] = useState<string | null>(null);
  const chosen = layout ?? layouts.find((l) => !l.club)?.id ?? null;
  const ok = name.trim().length >= ROOM_NAME_MIN && chosen !== null;

  const create = (e: React.FormEvent) => {
    e.preventDefault();
    if (ok && chosen) actions.createRoom(name.trim(), description.trim(), chosen);
  };

  return (
    <form onSubmit={create} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <label className="ui-label">
        {t('creator.name')}
        <input className="ui-input" style={{ display: 'block', width: '100%', boxSizing: 'border-box', marginTop: 3 }} value={name} maxLength={ROOM_NAME_MAX} placeholder={t('creator.name_placeholder')} onChange={(e) => setName(e.target.value)} />
      </label>
      <label className="ui-label">
        {t('creator.description')}
        <textarea className="ui-input" rows={2} style={{ display: 'block', width: '100%', boxSizing: 'border-box', marginTop: 3 }} value={description} maxLength={ROOM_DESC_MAX} placeholder={t('creator.description_placeholder')} onChange={(e) => setDescription(e.target.value)} />
      </label>
      <div className="ui-label">{t('creator.layout')}</div>
      <div className="creator-grid">
        {layouts.length === 0 && <div className="nav-empty">{t('navigator.loading')}</div>}
        {layouts.map((l) => (
          <button key={l.id} type="button" disabled={l.club} title={l.name} className={`creator-layout${l.id === chosen ? ' selected' : ''}`} onClick={() => setLayout(l.id)}>
            <LayoutPreview map={l.map} door={l.door} />
            <span>{t('creator.tiles', { tiles: tileCount(l.map) })}</span>
            {l.club && <span className="creator-club">{t('creator.club')}</span>}
          </button>
        ))}
      </div>
      <button className="ui-btn good" type="submit" disabled={!ok}>
        {t('creator.create')}
      </button>
    </form>
  );
}
