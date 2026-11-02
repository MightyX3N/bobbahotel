// All rooms: the public rooms from content, and guest rooms players create (saved in the
// database). A room is loaded when someone goes there and unloaded once it has been empty a while.
import {
  cleanChat,
  floorPlanProblem,
  FLOORPLAN_LIMITS,
  ROOM_DESC_MAX,
  ROOM_NAME_MAX,
  ROOM_NAME_MIN,
  type FloorPlanLimits,
  type FloorPlanProblem,
  type Layout,
  type LayoutInfo,
  type NavigatorTab,
  type RoomInfo,
} from '@bobba/shared';
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
  /** The room's own floor plan (JSON {map, door}) made in the editor, or null. */
  floor: string | null;
}

interface LayoutRow {
  id: string;
  name: string;
  map: string;
  door_x: number;
  door_y: number;
  access: string;
}

const ROOM_COLUMNS = 'r.id, r.owner_id, u.name AS owner_name, r.name, r.description, r.layout, r.floor';

/** Who is asking, for rules about Club layouts and floor plans. */
export interface Asker {
  id: number;
  staff: boolean;
  club: boolean;
}

export type SaveLayoutResult = { ok: true; id: string } | { ok: false; error: FloorPlanProblem | 'bad_layout_name' | 'not_allowed' };
export type SaveFloorResult = { ok: true; room: Room | null } | { ok: false; error: FloorPlanProblem | 'not_allowed' | 'room_not_found' };

export type CreateResult = { ok: true; id: string } | { ok: false; error: 'bad_room_name' | 'too_many_rooms' | 'layout_not_allowed' };

const LAYOUT_NAME_MAX = 40;

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

  /** A layout by id: built-in (content) or made in the editor. */
  layout(id: string): Layout | null {
    const builtIn = this.content.layouts.get(id);
    if (builtIn) return builtIn;
    const row = this.db.prepare('SELECT id, name, map, door_x, door_y, access FROM layouts WHERE id = ?').get(id) as LayoutRow | undefined;
    return row ? fromLayoutRow(row) : null;
  }

  /** Layouts a room can be built from: anyone's, and Bobba Club ones (marked). */
  layouts(): LayoutInfo[] {
    const info = (l: Layout, custom: boolean): LayoutInfo => ({
      id: l.id,
      name: l.name,
      map: l.map,
      door: l.door,
      maxUsers: l.maxUsers ?? DEFAULT_MAX_USERS,
      club: l.access === 'club',
      custom,
    });
    const out: LayoutInfo[] = [];
    for (const l of this.content.layouts.values()) if (l.access !== 'admin') out.push(info(l, false));
    const rows = this.db.prepare('SELECT id, name, map, door_x, door_y, access FROM layouts ORDER BY created').all() as unknown as LayoutRow[];
    for (const r of rows) out.push(info(fromLayoutRow(r), true));
    return out;
  }

  /** Staff: save a layout made in the editor (new, or replace a custom one). */
  saveLayout(asker: Asker, plan: { id?: string | undefined; name: string; map: string[]; door: [number, number]; club: boolean }, now = Date.now()): SaveLayoutResult {
    if (!asker.staff) return { ok: false, error: 'not_allowed' };
    const name = cleanChat(plan.name).slice(0, LAYOUT_NAME_MAX);
    if (name.length < 2) return { ok: false, error: 'bad_layout_name' };
    const problem = floorPlanProblem(plan.map, plan.door, FLOORPLAN_LIMITS.staff);
    if (problem) return { ok: false, error: problem };
    const access = plan.club ? 'club' : 'free';
    const existing = plan.id && this.db.prepare('SELECT id FROM layouts WHERE id = ?').get(plan.id);
    if (existing && plan.id) {
      this.db.prepare('UPDATE layouts SET name = ?, map = ?, door_x = ?, door_y = ?, access = ? WHERE id = ?').run(name, JSON.stringify(plan.map), plan.door[0], plan.door[1], access, plan.id);
      return { ok: true, id: plan.id };
    }
    const n = (this.db.prepare("SELECT COUNT(*) AS n FROM layouts").get() as { n: number }).n;
    let id = `custom_${n + 1}`;
    while (this.layout(id)) id = `custom_${Number(id.split('_')[1]) + 1}`;
    this.db
      .prepare('INSERT INTO layouts (id, name, map, door_x, door_y, access, created_by, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
      .run(id, name, JSON.stringify(plan.map), plan.door[0], plan.door[1], access, asker.id, now);
    return { ok: true, id };
  }

  /** Staff: remove a layout made in the editor. Rooms built on it keep their shape. */
  deleteLayout(asker: Asker, id: string): boolean {
    if (!asker.staff) return false;
    const layout = this.layout(id);
    if (!layout || this.content.layouts.has(id)) return false;
    this.db
      .prepare('UPDATE rooms SET floor = ? WHERE layout = ? AND floor IS NULL')
      .run(JSON.stringify({ map: layout.map, door: layout.door }), id);
    this.db.prepare('DELETE FROM layouts WHERE id = ?').run(id);
    return true;
  }

  /**
   * Give a guest room its own floor plan: its owner with Bobba Club (within the Club limits) or
   * staff (any size). A loaded room is rebuilt and everyone in it starts again at the door; the
   * new room is returned so callers can point players at it.
   */
  saveRoomFloor(asker: Asker, roomId: string, map: string[], door: [number, number]): SaveFloorResult {
    const key = /^r:(\d+)$/.exec(roomId)?.[1];
    const row = key ? (this.db.prepare('SELECT owner_id FROM rooms WHERE id = ?').get(Number(key)) as { owner_id: number } | undefined) : undefined;
    if (!row) return { ok: false, error: 'room_not_found' };
    const isOwner = row.owner_id === asker.id;
    if (!asker.staff && !(isOwner && asker.club)) return { ok: false, error: 'not_allowed' };
    const limits: FloorPlanLimits = asker.staff ? FLOORPLAN_LIMITS.staff : FLOORPLAN_LIMITS.club;
    const problem = floorPlanProblem(map, door, limits);
    if (problem) return { ok: false, error: problem };
    this.db.prepare('UPDATE rooms SET floor = ? WHERE id = ?').run(JSON.stringify({ map, door }), Number(key));
    return { ok: true, room: this.reload(roomId) };
  }

  create(asker: Asker, rawName: string, rawDescription: string, layoutId: string, now = Date.now()): CreateResult {
    const ownerId = asker.id;
    const name = cleanChat(rawName).slice(0, ROOM_NAME_MAX);
    const description = cleanChat(rawDescription).slice(0, ROOM_DESC_MAX);
    if (name.length < ROOM_NAME_MIN) return { ok: false, error: 'bad_room_name' };
    const layout = this.layout(layoutId);
    const access = layout?.access ?? 'free';
    const allowed = access === 'free' || (access === 'club' && (asker.club || asker.staff)) || (access === 'admin' && asker.staff);
    if (!layout || !allowed) return { ok: false, error: 'layout_not_allowed' };
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
      .prepare(`SELECT ${ROOM_COLUMNS} FROM rooms r JOIN users u ON u.id = r.owner_id ${where}${search} ORDER BY r.id DESC LIMIT 500`)
      .all(...params) as unknown as RoomRow[];
    const infos = rows.map((r) => this.guestInfo(r));
    // Busy rooms first (like Habbo), newest first among equals.
    if (tab === 'all') infos.sort((a, b) => b.users - a.users);
    return infos.slice(0, LIST_LIMIT);
  }

  /** A room's floor plan (public: anyone entering the room sees it). */
  floorPlanOf(id: string): { name: string; map: string[]; door: [number, number] } | null {
    const room = this.active.get(id) ?? this.load(id);
    return room ? { name: room.details.name, map: room.layout.map, door: room.layout.door } : null;
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
        .prepare(`SELECT ${ROOM_COLUMNS} FROM rooms r JOIN users u ON u.id = r.owner_id WHERE r.id = ?`)
        .get(Number(key)) as RoomRow | undefined;
      const layout = row && this.roomLayout(row);
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

  /** Rebuild a loaded room (after its floor changed) and move everyone in it to the new one. */
  private reload(id: string): Room | null {
    const old = this.active.get(id);
    if (!old) return null;
    const visitors = old.visitors();
    old.stop();
    this.active.delete(id);
    this.cancelUnload(id);
    const fresh = this.get(id);
    if (!fresh) return null;
    for (const v of visitors) fresh.enter(v);
    return fresh;
  }

  /** A guest room's floor: its own plan if it has one, else its layout. */
  private roomLayout(row: RoomRow): Layout | null {
    if (row.floor) {
      const f = JSON.parse(row.floor) as { map: string[]; door: [number, number] };
      return { id: `room_${row.id}`, name: row.name, map: f.map, door: f.door, maxUsers: this.layout(row.layout)?.maxUsers ?? DEFAULT_MAX_USERS };
    }
    return this.layout(row.layout);
  }

  private publicInfo(key: string, name: string, description: string, maxUsers: number): RoomInfo {
    const id = `p:${key}`;
    return { id, name, description, owner: null, users: this.active.get(id)?.count ?? 0, maxUsers };
  }

  private guestInfo(r: RoomRow): RoomInfo {
    const id = `r:${r.id}`;
    const layout = this.layout(r.layout);
    return { id, name: r.name, description: r.description, owner: r.owner_name, users: this.active.get(id)?.count ?? 0, maxUsers: layout?.maxUsers ?? DEFAULT_MAX_USERS };
  }
}

function fromLayoutRow(r: LayoutRow): Layout {
  return { id: r.id, name: r.name, map: JSON.parse(r.map) as string[], door: [r.door_x, r.door_y], access: r.access === 'club' ? 'club' : 'free' };
}
