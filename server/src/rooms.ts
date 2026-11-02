// All rooms: the public rooms from content, and guest rooms players create (saved in the
// database). A room is loaded when someone goes there and unloaded once it has been empty a while.
import { cleanChat, ROOM_DESC_MAX, ROOM_NAME_MAX, ROOM_NAME_MIN, type LayoutInfo, type NavigatorTab, type RoomInfo } from '@bobba/shared';
import type { Content } from './content.ts';
import type { Db } from './db.ts';
import { Room } from './room.ts';

/** Most rooms one player can own. */
export const MAX_ROOMS_PER_USER = 25;
/** Users per guest room unless the layout says otherwise. */
const DEFAULT_MAX_USERS = 25;
/** Most rooms in one navigator list. */
const LIST_LIMIT = 50;
/** An empty room stays loaded this long (so quick re-entries don't reload it). */
const UNLOAD_AFTER_MS = 60_000;

interface RoomRow {
  id: number;
  owner_id: number;
  owner_name: string;
  name: string;
  description: string;
  layout: string;
}

export type CreateResult = { ok: true; id: string } | { ok: false; error: 'bad_room_name' | 'too_many_rooms' | 'layout_not_allowed' };

export class Rooms {
  private readonly db: Db;
  private readonly content: Content;
  private readonly autoTick: boolean;
  private readonly active = new Map<string, Room>();
  private readonly unloadTimers = new Map<string, ReturnType<typeof setTimeout>>();

  constructor(db: Db, content: Content, opts: { autoTick?: boolean } = {}) {
    this.db = db;
    this.content = content;
    this.autoTick = opts.autoTick ?? true;
  }

  /** The room players start in. */
  get lobbyId(): string {
    const first = this.content.publicRooms[0];
    if (!first) throw new Error('rooms.json has no public rooms');
    return `p:${first.id}`;
  }

  /** A room by id, loading it if needed; null if it doesn't exist. */
  get(id: string): Room | null {
    const loaded = this.active.get(id);
    if (loaded) {
      this.cancelUnload(id);
      return loaded;
    }
    const room = this.load(id);
    if (room) this.active.set(id, room);
    return room;
  }

  /** Call when someone left a room: an empty room is unloaded after a while. */
  left(room: Room): void {
    if (room.count > 0 || this.unloadTimers.has(room.id)) return;
    const timer = setTimeout(() => {
      this.unloadTimers.delete(room.id);
      if (room.count === 0) {
        room.stop();
        this.active.delete(room.id);
      }
    }, UNLOAD_AFTER_MS);
    timer.unref();
    this.unloadTimers.set(room.id, timer);
  }

  /** Layouts a player can build a room from. Club layouts are listed (marked) but not usable yet. */
  layouts(): LayoutInfo[] {
    const out: LayoutInfo[] = [];
    for (const l of this.content.layouts.values()) {
      if (l.access === 'admin') continue;
      out.push({ id: l.id, name: l.name, map: l.map, door: l.door, maxUsers: l.maxUsers ?? DEFAULT_MAX_USERS, club: l.access === 'club' });
    }
    return out;
  }

  create(ownerId: number, rawName: string, rawDescription: string, layoutId: string, now = Date.now()): CreateResult {
    const name = cleanChat(rawName).slice(0, ROOM_NAME_MAX);
    const description = cleanChat(rawDescription).slice(0, ROOM_DESC_MAX);
    if (name.length < ROOM_NAME_MIN) return { ok: false, error: 'bad_room_name' };
    const layout = this.content.layouts.get(layoutId);
    // Bobba Club layouts open up once Club exists.
    if (!layout || (layout.access ?? 'free') !== 'free') return { ok: false, error: 'layout_not_allowed' };
    const owned = (this.db.prepare('SELECT COUNT(*) AS n FROM rooms WHERE owner_id = ?').get(ownerId) as { n: number }).n;
    if (owned >= MAX_ROOMS_PER_USER) return { ok: false, error: 'too_many_rooms' };
    const result = this.db
      .prepare('INSERT INTO rooms (owner_id, name, description, layout, created) VALUES (?, ?, ?, ?, ?)')
      .run(ownerId, name, description, layoutId, now);
    return { ok: true, id: `r:${Number(result.lastInsertRowid)}` };
  }

  list(tab: NavigatorTab, query: string, userId: number): RoomInfo[] {
    const q = query.trim().toLowerCase();
    if (tab === 'public') {
      return this.content.publicRooms
        .map((p) => this.publicInfo(p.id, p.name, p.description ?? '', p.layout.maxUsers ?? DEFAULT_MAX_USERS))
        .filter((r) => !q || r.name.toLowerCase().includes(q));
    }
    const where = tab === 'mine' ? 'WHERE r.owner_id = ?' : 'WHERE 1 = 1';
    const params: (string | number)[] = tab === 'mine' ? [userId] : [];
    const search = q ? ' AND (lower(r.name) LIKE ? OR lower(u.name) LIKE ?)' : '';
    if (q) params.push(`%${q}%`, `%${q}%`);
    const rows = this.db
      .prepare(`SELECT r.id, r.owner_id, u.name AS owner_name, r.name, r.description, r.layout FROM rooms r JOIN users u ON u.id = r.owner_id ${where}${search} ORDER BY r.id DESC LIMIT 500`)
      .all(...params) as unknown as RoomRow[];
    const infos = rows.map((r) => this.guestInfo(r));
    // Busy rooms first (like Habbo), newest first among equals.
    if (tab === 'all') infos.sort((a, b) => b.users - a.users);
    return infos.slice(0, LIST_LIMIT);
  }

  stopAll(): void {
    for (const t of this.unloadTimers.values()) clearTimeout(t);
    this.unloadTimers.clear();
    for (const r of this.active.values()) r.stop();
    this.active.clear();
  }

  private cancelUnload(id: string): void {
    clearTimeout(this.unloadTimers.get(id));
    this.unloadTimers.delete(id);
  }

  private load(id: string): Room | null {
    const [kind, key] = id.split(':');
    if (kind === 'p') {
      const p = this.content.publicRooms.find((r) => r.id === key);
      if (!p) return null;
      return new Room(id, { name: p.name, description: p.description ?? '', owner: null, ownerId: null, maxUsers: p.layout.maxUsers ?? DEFAULT_MAX_USERS }, p.layout, { autoTick: this.autoTick });
    }
    if (kind === 'r' && key && /^\d+$/.test(key)) {
      const row = this.db
        .prepare('SELECT r.id, r.owner_id, u.name AS owner_name, r.name, r.description, r.layout FROM rooms r JOIN users u ON u.id = r.owner_id WHERE r.id = ?')
        .get(Number(key)) as RoomRow | undefined;
      const layout = row && this.content.layouts.get(row.layout);
      if (!row || !layout) return null;
      return new Room(
        id,
        { name: row.name, description: row.description, owner: row.owner_name, ownerId: row.owner_id, maxUsers: layout.maxUsers ?? DEFAULT_MAX_USERS },
        layout,
        { autoTick: this.autoTick },
      );
    }
    return null;
  }

  private publicInfo(key: string, name: string, description: string, maxUsers: number): RoomInfo {
    const id = `p:${key}`;
    return { id, name, description, owner: null, users: this.active.get(id)?.count ?? 0, maxUsers };
  }

  private guestInfo(r: RoomRow): RoomInfo {
    const id = `r:${r.id}`;
    const layout = this.content.layouts.get(r.layout);
    return { id, name: r.name, description: r.description, owner: r.owner_name, users: this.active.get(id)?.count ?? 0, maxUsers: layout?.maxUsers ?? DEFAULT_MAX_USERS };
  }
}
