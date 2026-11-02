// A room: who is in it, where they are, and the 500 ms tick that moves them (like Habbo's room cycle).
import {
  cleanChat,
  dirTowards,
  doorFacing,
  findPath,
  furniStateCount,
  furniTiles,
  heightAt,
  parseMap,
  tileKey,
  type FurniDef,
  type Grid,
  type Layout,
  type RoomFurni,
  type Look,
  type RoomUser,
  type ServerMessage,
} from '@bobba/shared';

/** How long one step takes (Habbo's room cycle). */
export const TICK_MS = 500;
/** How often the room checks who is due a step. Each avatar keeps its own step rhythm, so the
 *  first step after a click happens right away instead of waiting for a shared beat. */
const CHECK_MS = 50;

/** Someone who can be in a room. */
export interface Visitor {
  id: number;
  name: string;
  look: Look;
  send(message: ServerMessage): void;
}

interface Occupant {
  visitor: Visitor;
  x: number;
  y: number;
  z: number;
  dir: number;
  path: [number, number][];
  goal: [number, number] | null;
  moving: boolean;
  /** When this avatar may take its next step (or stop). */
  nextStepAt: number;
  chatTimes: number[];
}

/** At most this many chat messages per CHAT_WINDOW_MS. */
const CHAT_BURST = 5;
const CHAT_WINDOW_MS = 4000;

/** What a room is called and who owns it. */
export interface RoomDetails {
  name: string;
  description: string;
  /** Owner's name; null for public rooms. */
  owner: string | null;
  ownerId: number | null;
  maxUsers: number;
  /** Only staff can go in (e.g. the furni test room). */
  staffOnly?: boolean;
}

export class Room {
  readonly id: string;
  details: RoomDetails;
  readonly layout: Layout;
  readonly grid: Grid;
  private readonly occupants = new Map<number, Occupant>();
  private timer: ReturnType<typeof setInterval> | undefined;
  private readonly autoTick: boolean;
  /** Furni standing in the room. */
  readonly furni: RoomFurni[];
  /** Tiles furni stand on that you can't walk onto (rugs and seats don't count). */
  private readonly furniBlocked = new Set<number>();
  private readonly defs: ReadonlyMap<string, FurniDef>;

  constructor(id: string, details: RoomDetails, layout: Layout, opts: { autoTick?: boolean; furni?: RoomFurni[]; defs?: ReadonlyMap<string, FurniDef> } = {}) {
    this.id = id;
    this.details = details;
    this.layout = layout;
    this.grid = parseMap(layout.map);
    this.autoTick = opts.autoTick ?? true;
    this.furni = (opts.furni ?? []).map((f) => ({ ...f }));
    this.defs = opts.defs ?? new Map();
    for (const f of this.furni) {
      const def = opts.defs?.get(f.def);
      if (!def || def.walk || def.sit) continue;
      for (const [x, y] of furniTiles(def, f)) this.furniBlocked.add(tileKey(x, y));
    }
  }

  get count(): number {
    return this.occupants.size;
  }

  get name(): string {
    return this.details.name;
  }

  get isFull(): boolean {
    return this.occupants.size >= this.details.maxUsers;
  }

  has(id: number): boolean {
    return this.occupants.has(id);
  }

  /** Everyone in the room (e.g. to move them into a reloaded room). */
  visitors(): Visitor[] {
    return [...this.occupants.values()].map((o) => o.visitor);
  }

  enter(visitor: Visitor): void {
    this.leave(visitor.id);
    const [x, y] = this.layout.door;
    const occupant: Occupant = {
      visitor,
      x,
      y,
      z: Math.max(0, heightAt(this.grid, x, y)),
      dir: doorFacing(this.grid, this.layout.door),
      path: [],
      goal: null,
      moving: false,
      nextStepAt: 0,
      chatTimes: [],
    };
    this.occupants.set(visitor.id, occupant);
    visitor.send({
      t: 'room',
      d: {
        id: this.id,
        name: this.details.name,
        description: this.details.description,
        owner: this.details.owner,
        ownerId: this.details.ownerId,
        map: this.layout.map,
        door: this.layout.door,
        users: [...this.occupants.values()].map(toRoomUser),
        furni: this.furni,
      },
    });
    this.broadcast({ t: 'userJoin', d: toRoomUser(occupant) }, visitor.id);
    this.startTicking();
  }

  leave(id: number): void {
    if (!this.occupants.delete(id)) return;
    this.broadcast({ t: 'userLeave', d: { id } });
    if (this.occupants.size === 0) this.stopTicking();
  }

  walkTo(id: number, x: number, y: number): void {
    const o = this.occupants.get(id);
    if (!o) return;
    const path = findPath(this.grid, o.x, o.y, x, y, { blocked: this.blockedFor(id) });
    if (!path || path.length === 0) return;
    o.goal = [x, y];
    o.path = path;
  }

  /** Switch a furni to its next state (the caller checks who may). */
  useFurni(uid: number): void {
    const f = this.furni.find((it) => it.uid === uid);
    const def = f && this.defs.get(f.def);
    if (!f || !def) return;
    f.state = (f.state + 1) % furniStateCount(def);
    this.broadcast({ t: 'furniState', d: { uid, state: f.state } });
  }

  say(id: number, raw: string, now = Date.now()): void {
    const o = this.occupants.get(id);
    if (!o) return;
    const text = cleanChat(raw);
    if (!text) return;
    o.chatTimes = o.chatTimes.filter((t) => now - t < CHAT_WINDOW_MS);
    if (o.chatTimes.length >= CHAT_BURST) return;
    o.chatTimes.push(now);
    this.broadcast({ t: 'chat', d: { id, text } });
  }

  /** Everyone whose step is due and who has somewhere to go takes one step. */
  tick(now = Date.now()): void {
    const changes: ServerMessage & { t: 'status' } = { t: 'status', d: [] };
    for (const o of this.occupants.values()) {
      if (now < o.nextStepAt) continue;
      let next = o.path[0];
      if (next && this.blockedFor(o.visitor.id).has(tileKey(next[0], next[1]))) {
        // Someone stepped in the way: find a new way to the same goal, or stop.
        const goal = o.goal;
        o.path = (goal && findPath(this.grid, o.x, o.y, goal[0], goal[1], { blocked: this.blockedFor(o.visitor.id) })) || [];
        next = o.path[0];
      }
      if (next) {
        o.path.shift();
        o.dir = dirTowards(next[0] - o.x, next[1] - o.y);
        [o.x, o.y] = next;
        o.z = heightAt(this.grid, o.x, o.y);
        o.moving = true;
        o.nextStepAt = now + TICK_MS;
        if (o.path.length === 0) o.goal = null;
        changes.d.push({ id: o.visitor.id, x: o.x, y: o.y, z: o.z, dir: o.dir, moving: true });
      } else if (o.moving) {
        o.moving = false;
        changes.d.push({ id: o.visitor.id, x: o.x, y: o.y, z: o.z, dir: o.dir, moving: false });
      }
    }
    if (changes.d.length > 0) this.broadcast(changes);
  }

  stop(): void {
    this.stopTicking();
  }

  /** Tiles taken by furni and other avatars. The door tile never counts, so people can always come in. */
  private blockedFor(id: number): Set<number> {
    const [dx, dy] = this.layout.door;
    const blocked = new Set<number>(this.furniBlocked);
    for (const o of this.occupants.values()) {
      if (o.visitor.id !== id && !(o.x === dx && o.y === dy)) blocked.add(tileKey(o.x, o.y));
    }
    return blocked;
  }

  private broadcast(message: ServerMessage, exceptId?: number): void {
    for (const o of this.occupants.values()) if (o.visitor.id !== exceptId) o.visitor.send(message);
  }

  private startTicking(): void {
    if (this.autoTick && !this.timer) this.timer = setInterval(() => this.tick(), CHECK_MS);
  }

  private stopTicking(): void {
    clearInterval(this.timer);
    this.timer = undefined;
  }
}

function toRoomUser(o: Occupant): RoomUser {
  return { id: o.visitor.id, name: o.visitor.name, look: o.visitor.look, x: o.x, y: o.y, z: o.z, dir: o.dir };
}
