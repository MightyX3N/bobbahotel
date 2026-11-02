// A room: who is in it, where they are, the 500 ms tick that moves them (like Habbo's room cycle),
// and its furni: placing, moving, stacking, and sitting on seats.
import {
  cleanChat,
  dirTowards,
  doorFacing,
  findPath,
  furniBlocks,
  furniFootprint,
  furniStateCount,
  furniTop,
  LAY_HEIGHT,
  standHeight,
  wallItemZ,
  wallKindAt,
  furniTiles,
  heightAt,
  isFloor,
  SIT_HEIGHT,
  parseMap,
  tileKey,
  type FurniDef,
  type FurniDir,
  type FurniSheet,
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
  sit: boolean;
  lay: boolean;
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

/** Where a room's furni are kept (the database), so they are still there next time. */
export interface FurniStore {
  /** Saves a new furni and returns its id (used as its uid). */
  add(f: Omit<RoomFurni, 'uid'>): number;
  update(f: RoomFurni): void;
  remove(uid: number): void;
}

/** Why a furni can't go somewhere (shown to the player). */
export type FurniProblem = 'furni_not_found' | 'furni_cant_place' | 'furni_not_here';

export interface RoomOptions {
  autoTick?: boolean;
  furni?: RoomFurni[];
  defs?: ReadonlyMap<string, FurniDef>;
  /** Built sprite sheets, for furni heights measured from their pictures. */
  sheets?: ReadonlyMap<string, FurniSheet>;
  store?: FurniStore;
}

export class Room {
  readonly id: string;
  details: RoomDetails;
  readonly layout: Layout;
  readonly grid: Grid;
  private readonly occupants = new Map<number, Occupant>();
  private timer: ReturnType<typeof setInterval> | undefined;
  private readonly autoTick: boolean;
  /** Furni in the room. */
  readonly furni: RoomFurni[];
  /** Tiles furni stand on that you can't walk onto (rugs and seats don't count). */
  private readonly furniBlocked = new Set<number>();
  private readonly defs: ReadonlyMap<string, FurniDef>;
  private readonly sheets: ReadonlyMap<string, FurniSheet>;
  private readonly store: FurniStore | undefined;
  /** Next uid for rooms without a store (the furni test room). */
  private nextUid: number;

  constructor(id: string, details: RoomDetails, layout: Layout, opts: RoomOptions = {}) {
    this.id = id;
    this.details = details;
    this.layout = layout;
    this.grid = parseMap(layout.map);
    this.autoTick = opts.autoTick ?? true;
    this.furni = (opts.furni ?? []).map((f) => ({ ...f }));
    this.defs = opts.defs ?? new Map();
    this.sheets = opts.sheets ?? new Map();
    this.store = opts.store;
    this.nextUid = Math.max(0, ...this.furni.map((f) => f.uid)) + 1;
    this.rebuildBlocked();
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
      sit: false,
      lay: false,
      chatTimes: [],
    };
    this.occupants.set(visitor.id, occupant);
    this.sendSnapshot(visitor.id);
    this.broadcast({ t: 'userJoin', d: toRoomUser(occupant) }, visitor.id);
    this.startTicking();
  }

  /** Everything needed to draw the room, to one visitor (on entering, or after reconnecting). */
  sendSnapshot(id: number): void {
    const o = this.occupants.get(id);
    if (!o) return;
    o.visitor.send({
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
  }

  /** A visitor reconnected: their avatar stays where it is, messages go to the new connection. */
  rebind(visitor: Visitor): boolean {
    const o = this.occupants.get(visitor.id);
    if (!o) return false;
    o.visitor = visitor;
    return true;
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
    this.store?.update(f);
    this.broadcast({ t: 'furniState', d: { uid, state: f.state } });
  }

  // ---- furni ----

  /** Puts a new furni in the room. Returns a problem, or null if it worked. */
  placeFurni(defId: string, x: number, y: number, dir: FurniDir, off?: number, z?: number): FurniProblem | null {
    const def = this.defs.get(defId);
    if (!def) return 'furni_not_found';
    const spot = this.spotFor(def, { x, y, dir, off, z }, null);
    if (!spot) return 'furni_cant_place';
    const f: Omit<RoomFurni, 'uid'> = { def: def.id, ...spot, state: 0 };
    const uid = this.store ? this.store.add(f) : this.nextUid++;
    const placed: RoomFurni = { uid, ...f };
    this.furni.push(placed);
    this.furniChanged();
    this.broadcast({ t: 'furniAdd', d: placed });
    return null;
  }

  /** Moves or turns a furni. Returns a problem, or null if it worked. */
  moveFurni(uid: number, x: number, y: number, dir: FurniDir, off?: number, z?: number): FurniProblem | null {
    const f = this.furni.find((it) => it.uid === uid);
    const def = f && this.defs.get(f.def);
    if (!f || !def) return 'furni_not_here';
    const spot = this.spotFor(def, { x, y, dir, off, z }, f);
    if (!spot) return 'furni_cant_place';
    Object.assign(f, spot);
    if (spot.off === undefined) delete f.off;
    this.store?.update(f);
    this.furniChanged();
    this.broadcast({ t: 'furniMove', d: f });
    return null;
  }

  /** Takes a furni out of the room (anything stacked on it stays where it was). */
  pickUpFurni(uid: number): FurniProblem | null {
    const i = this.furni.findIndex((it) => it.uid === uid);
    if (i < 0) return 'furni_not_here';
    this.furni.splice(i, 1);
    this.store?.remove(uid);
    this.furniChanged();
    this.broadcast({ t: 'furniRemove', d: { uid } });
    return null;
  }

  /**
   * Where a furni would end up: floor furni on free floor tiles (not the door, nobody standing
   * there unless it's a seat or rug), stacked on furni that things can go on, at the highest of
   * them; wall furni on a wall at the edge of a floor tile. null if it can't go there.
   */
  private spotFor(def: FurniDef, want: { x: number; y: number; dir: FurniDir; off?: number | undefined; z?: number | undefined }, moving: RoomFurni | null): Omit<RoomFurni, 'uid' | 'def' | 'state'> | null {
    const { x, y, dir } = want;
    if (!(dir in def.dirs)) return null;
    if (def.kind === 'wall') {
      // Direction 4: on the left wall at the tile's x edge; 2: on the back wall at its y edge.
      if (dir !== 2 && dir !== 4) return null;
      const off = Math.min(1, Math.max(0, want.off ?? 0.5));
      const z = wallItemZ(def, this.sheets.get(def.id), { x, y, dir, off }, want.z ?? 1.5, (tx, ty) => wallKindAt(this.grid, this.layout.door, dir, tx, ty));
      if (z === null) return null;
      return { x, y, z, dir, off };
    }
    const [door] = [this.layout.door];
    let z = 0;
    for (const [tx, ty] of furniTiles(def, { x, y, dir })) {
      if (!isFloor(this.grid, tx, ty) || (tx === door[0] && ty === door[1])) return null;
      const floorZ = heightAt(this.grid, tx, ty);
      const below = this.furniOn(tx, ty)
        .filter((it) => it !== moving)
        .flatMap((it) => {
          const d = this.defs.get(it.def);
          return d ? [{ def: d, top: this.topOf(it) }] : [];
        });
      const top = standHeight(def, floorZ, below);
      if (top === null) return null;
      // Not onto someone (unless it's something you sit, lie or stand on, or it's over their head).
      if (furniBlocks(def, top, floorZ) && [...this.occupants.values()].some((o) => o.x === tx && o.y === ty)) return null;
      z = Math.max(z, top);
    }
    return { x, y, z: Math.round(z * 100) / 100, dir };
  }

  /** Floor furni covering a tile. */
  private furniOn(x: number, y: number): RoomFurni[] {
    return this.furni.filter((f) => {
      const def = this.defs.get(f.def);
      return def?.kind === 'floor' && furniTiles(def, f).some(([tx, ty]) => tx === x && ty === y);
    });
  }

  private topOf(f: RoomFurni): number {
    const def = this.defs.get(f.def);
    return def ? furniTop(def, f, this.sheets.get(def.id)) : f.z;
  }

  /** The seat or bed on a tile, if any (the highest). */
  private seatAt(x: number, y: number): RoomFurni | null {
    return (
      this.furniOn(x, y)
        .filter((f) => {
          const def = this.defs.get(f.def);
          return def?.sit || def?.lay;
        })
        .sort((a, b) => b.z - a.z)[0] ?? null
    );
  }

  /** How high someone stands (or sits, or lies) on a tile. */
  private standZ(x: number, y: number): number {
    const seat = this.seatAt(x, y);
    const def = seat && this.defs.get(seat.def);
    if (seat && def) return seat.z + (def.sitHeight ?? (def.lay ? LAY_HEIGHT : SIT_HEIGHT));
    let z = Math.max(0, heightAt(this.grid, x, y));
    for (const f of this.furniOn(x, y)) if (this.defs.get(f.def)?.walk) z = Math.max(z, this.topOf(f));
    return z;
  }

  private rebuildBlocked(): void {
    this.furniBlocked.clear();
    for (const f of this.furni) {
      const def = this.defs.get(f.def);
      if (!def) continue;
      for (const [x, y] of furniTiles(def, f)) if (furniBlocks(def, f.z, heightAt(this.grid, x, y))) this.furniBlocked.add(tileKey(x, y));
    }
  }

  /** After furni changed: avatars stand (or sit) at the new height, and walk around new furni. */
  private furniChanged(): void {
    this.rebuildBlocked();
    const changes: ServerMessage & { t: 'status' } = { t: 'status', d: [] };
    for (const o of this.occupants.values()) {
      const before = `${o.x}|${o.y}|${o.z}|${o.sit}|${o.lay}|${o.dir}`;
      if (!o.moving) this.settle(o);
      else o.z = this.standZ(o.x, o.y);
      if (`${o.x}|${o.y}|${o.z}|${o.sit}|${o.lay}|${o.dir}` !== before) changes.d.push(statusOf(o));
    }
    if (changes.d.length > 0) this.broadcast(changes);
  }

  /**
   * Someone who stopped: sits down if they're on a seat (facing the way it faces), or lies down if
   * they're on a bed: moved to its head end (like Habbo), lying along it.
   */
  private settle(o: Occupant): void {
    const seat = this.seatAt(o.x, o.y);
    const def = seat && this.defs.get(seat.def);
    o.sit = !!def?.sit;
    o.lay = !!def?.lay;
    if (seat && def) {
      o.dir = seat.dir;
      if (o.lay) {
        const [w, l] = furniFootprint(def, seat.dir);
        // The head end is the end the bed's foot faces away from.
        const head: [number, number] =
          seat.dir === 4 ? [o.x, seat.y] : seat.dir === 2 ? [seat.x, o.y] : seat.dir === 0 ? [o.x, seat.y + l - 1] : [seat.x + w - 1, o.y];
        const taken = [...this.occupants.values()].some((other) => other !== o && other.x === head[0] && other.y === head[1]);
        if (!taken) [o.x, o.y] = head;
      }
    }
    o.z = this.standZ(o.x, o.y);
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
        o.z = this.standZ(o.x, o.y);
        o.moving = true;
        o.sit = false;
        o.lay = false;
        o.nextStepAt = now + TICK_MS;
        if (o.path.length === 0) o.goal = null;
        changes.d.push(statusOf(o));
      } else if (o.moving) {
        o.moving = false;
        this.settle(o);
        changes.d.push(statusOf(o));
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
  return { id: o.visitor.id, name: o.visitor.name, look: o.visitor.look, x: o.x, y: o.y, z: o.z, dir: o.dir, sit: o.sit, lay: o.lay };
}

function statusOf(o: Occupant) {
  return { id: o.visitor.id, x: o.x, y: o.y, z: o.z, dir: o.dir, moving: o.moving, sit: o.sit, lay: o.lay };
}
