// A room on screen: floor and walls, avatars, furni, the hover outline, clicks to walk, dragging
// to look around, zooming (mouse wheel, pinch or the toolbar) and chat bubbles. Works with a mouse
// and with touch: tap to walk, drag to look around, pinch to zoom, hold to see a name.
// Furni: click to select, double-click to use; with rights, drag to move (mouse) and place new
// ones with a see-through "ghost" that follows the pointer (R turns it, Esc stops).
import { Container, Graphics, type Application, type FederatedPointerEvent } from 'pixi.js';
import {
  furniDirs,
  furniFootprint,
  furniTiles,
  furniTop,
  standHeight,
  wallItemFits,
  heightAt,
  isFloor,
  parseMap,
  WALL_ITEM_MAX_Z,
  WALL_ITEM_MIN_Z,
  type DataOf,
  type FurniBelow,
  type FurniDef,
  type FurniDir,
  type FurniSheet,
  type Grid,
  type RoomFurni,
  type ServerMessage,
} from '@bobba/shared';
import { AvatarView, type RestingOn } from './AvatarView.ts';
import { toolbarHeight } from '../layout.ts';
import { ChatBubbles } from './ChatBubbles.ts';
import { FurniView } from './FurniView.ts';
import { furniDefs, furniSheets } from './furniAssets.ts';
import { corner, depthToZIndex, drawRoom, drawTileOutline, floorDepth, type WallFace } from './drawRoom.ts';
import { pointInTile, tileCenter } from './iso.ts';

const TICK_MS = 500;
const DRAG_THRESHOLD = 5;
/** Zoom levels, like Habbo: half size for big rooms and small screens, double for big screens. */
const ZOOMS = [0.5, 1, 2];
/** Holding a finger still this long on an avatar or furni shows its name (touch has no hover). */
const LONG_PRESS_MS = 450;
/** How long a name shown by holding stays up. */
const NAME_SHOW_MS = 2500;

/** Where a furni goes: a floor tile and direction, or (wall furni) also where on the wall. */
export interface FurniSpot {
  x: number;
  y: number;
  dir: FurniDir;
  off?: number;
  z?: number;
}

export class RoomView {
  private readonly app: Application;
  private readonly world = new Container();
  private readonly hover = new Graphics();
  /** Floor, walls, furni and avatars, depth-sorted together. */
  private readonly objects = new Container();
  private readonly bubbles = new ChatBubbles();
  private readonly avatars = new Map<number, AvatarView>();
  private readonly furni = new Map<number, FurniView>();
  private walls: WallFace[] = [];
  private defs = new Map<string, FurniDef>();
  private sheets = new Map<string, FurniSheet>();
  /** What you may do with furni here (set by the UI from who you are and whose room it is). */
  private rights = { edit: false, place: false };
  private selected: number | null = null;
  /** Placing a new furni (uid null) or moving one: the ghost following the pointer. */
  private placing: { def: FurniDef; uid: number | null; ghost: FurniView; dir: FurniDir; spot: RoomFurni | null; drag: boolean } | null = null;
  /** A press on a furni you may move: dragging it moves it (mouse). */
  private pressedFurni: number | null = null;
  private roomId: string | null = null;
  /** Bumped on every room change, so furni loading for an old room is dropped. */
  private roomSerial = 0;
  private hoveredFurni: FurniView | null = null;
  private grid: Grid = [];
  private door: [number, number] = [0, 0];
  /** Floor and wall pieces (depth-sorted together with the avatars). */
  private roomPieces: Graphics[] = [];
  private tilesFrontToBack: [number, number][] = [];
  private hoveredAvatar: AvatarView | null = null;
  private zoom = 1;
  private drag: { startX: number; startY: number; worldX: number; worldY: number; moved: boolean } | null = null;
  /** Fingers (and the mouse) currently down, by pointer id. */
  private readonly pointers = new Map<number, { x: number; y: number }>();
  private pinch: { dist: number; zoom: number } | null = null;
  private longPress: ReturnType<typeof setTimeout> | undefined;
  private shownName: { hide: () => void; timer: ReturnType<typeof setTimeout> } | null = null;

  /** Called when the player clicks a floor tile. */
  onWalk: (x: number, y: number) => void = () => {};
  /** Called when the player double-clicks a furni. */
  onUseFurni: (uid: number) => void = () => {};
  /** A furni was selected (clicked) or nothing is selected any more. */
  onSelectFurni: (furni: { uid: number; def: FurniDef; state: number } | null) => void = () => {};
  /** Placing or moving started (with the furni) or ended (null). */
  onPlacing: (def: FurniDef | null) => void = () => {};
  onPlaceFurni: (def: string, f: FurniSpot) => void = () => {};
  onMoveFurni: (uid: number, f: FurniSpot) => void = () => {};
  private lastClick = { uid: -1, at: 0 };

  constructor(app: Application) {
    this.app = app;
    this.objects.sortableChildren = true;
    this.world.addChild(this.objects);
    // The tile under the mouse: on the floor, under furni and avatars.
    this.objects.addChild(this.hover);
    app.stage.addChild(this.world, this.bubbles.container);

    app.stage.eventMode = 'static';
    app.stage.hitArea = app.screen;
    app.stage.on('pointermove', (e) => this.pointerMove(e));
    app.stage.on('pointerdown', (e) => this.pointerDown(e));
    app.stage.on('pointerup', (e) => this.pointerUp(e));
    app.stage.on('pointerupoutside', (e) => this.pointerGone(e));
    app.stage.on('pointercancel', (e) => this.pointerGone(e));
    app.ticker.add(() => this.update());
    // When the screen changes size (window resized, phone turned, keyboard opened) the room keeps
    // its middle in the middle, instead of jumping back to the start.
    let size = { w: app.screen.width, h: app.screen.height };
    app.renderer.on('resize', () => {
      const w = app.screen.width;
      const h = app.screen.height;
      this.world.position.set(Math.round(this.world.x + (w - size.w) / 2), Math.round(this.world.y + (h - size.h) / 2));
      size = { w, h };
    });
    app.canvas.addEventListener(
      'wheel',
      (e) => {
        e.preventDefault();
        const i = ZOOMS.indexOf(this.zoom) + (e.deltaY < 0 ? 1 : -1);
        if (i >= 0 && i < ZOOMS.length) this.setZoom(ZOOMS[i]!, e.offsetX, e.offsetY);
      },
      { passive: false },
    );
    // R turns what you're placing, Esc stops (not while typing).
    window.addEventListener('keydown', (e) => {
      const el = document.activeElement;
      if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) return;
      if (!this.placing) return;
      if (e.key === 'r' || e.key === 'R') this.rotatePlacing();
      if (e.key === 'Escape') this.cancelPlacing();
    });
    void furniDefs().then((d) => (this.defs = d));
    void furniSheets().then((s) => (this.sheets = s));
  }

  setRights(rights: { edit: boolean; place: boolean }): void {
    this.rights = rights;
    if (!rights.edit && !rights.place) this.cancelPlacing();
  }

  /** Zoom to a level, keeping the point under (sx, sy) (default: the middle of the screen) in place. */
  setZoom(zoom: number, sx = this.app.screen.width / 2, sy = (this.app.screen.height - toolbarHeight()) / 2): void {
    const wx = (sx - this.world.x) / this.zoom;
    const wy = (sy - this.world.y) / this.zoom;
    this.zoom = zoom;
    this.world.scale.set(zoom);
    this.world.position.set(Math.round(sx - wx * zoom), Math.round(sy - wy * zoom));
    this.hover.clear();
  }

  /** The toolbar's zoom button: between normal size and half size. */
  toggleZoom(): void {
    this.setZoom(this.zoom === 1 ? 0.5 : 1);
  }

  enter(room: DataOf<ServerMessage, 'room'>): void {
    for (const a of this.avatars.values()) a.destroy();
    this.avatars.clear();
    for (const g of this.roomPieces) g.destroy();
    this.roomPieces = [];
    this.cancelPlacing();
    for (const f of this.furni.values()) f.destroy();
    this.furni.clear();
    this.hoveredFurni = null;
    this.select(null);
    const serial = ++this.roomSerial;

    this.bubbles.clear();
    // The same room again (after reconnecting): keep the view as it was.
    const sameRoom = room.id === this.roomId;
    this.roomId = room.id;
    this.grid = parseMap(room.map);
    this.door = room.door;
    this.tilesFrontToBack = [];
    this.grid.forEach((row, y) => row.forEach((h, x) => h >= 0 && this.tilesFrontToBack.push([x, y])));
    this.tilesFrontToBack.sort((a, b) => b[0] + b[1] - (a[0] + a[1]) || heightAt(this.grid, b[0], b[1]) - heightAt(this.grid, a[0], a[1]));

    const drawn = drawRoom(this.grid, room.door);
    this.walls = drawn.walls;
    for (const piece of drawn.pieces) {
      piece.graphics.zIndex = depthToZIndex(piece.depth);
      this.objects.addChild(piece.graphics);
      this.roomPieces.push(piece.graphics);
    }
    this.hover.clear();
    for (const u of room.users) this.addUser(u);
    void furniDefs().then(() => {
      if (serial !== this.roomSerial) return;
      for (const f of room.furni) this.addFurni(f);
    });
    if (sameRoom) return;
    // Start at normal size, or half size when the room doesn't fit the screen.
    const b = this.roomBounds();
    const fits = b.width <= this.app.screen.width && b.height <= this.app.screen.height - toolbarHeight();
    this.zoom = fits ? 1 : 0.5;
    this.world.scale.set(this.zoom);
    this.center();
  }

  addUser(user: DataOf<ServerMessage, 'userJoin'>): void {
    this.avatars.get(user.id)?.destroy();
    const view = new AvatarView(user);
    this.avatars.set(user.id, view);
    this.objects.addChild(view.container);
    view.update(performance.now());
  }

  removeUser(id: number): void {
    this.avatars.get(id)?.destroy();
    this.avatars.delete(id);
  }

  status(updates: DataOf<ServerMessage, 'status'>): void {
    const now = performance.now();
    for (const s of updates) this.avatars.get(s.id)?.moveTo(s.x, s.y, s.z, s.dir, s.moving, TICK_MS, now, s.sit, s.lay);
  }

  furniState(uid: number, state: number): void {
    this.furni.get(uid)?.setState(state);
    if (this.selected === uid) this.select(uid);
  }

  addFurni(f: RoomFurni): void {
    const def = this.defs.get(f.def);
    if (!def) return;
    this.furni.get(f.uid)?.destroy();
    const view = new FurniView(f, def, heightAt(this.grid, f.x, f.y));
    this.furni.set(f.uid, view);
    this.objects.addChild(view.container);
  }

  moveFurni(f: RoomFurni): void {
    const view = this.furni.get(f.uid);
    if (!view) return this.addFurni(f);
    view.place(f, heightAt(this.grid, f.x, f.y));
    view.container.visible = this.placing?.uid !== f.uid;
  }

  removeFurni(uid: number): void {
    if (this.placing?.uid === uid) this.cancelPlacing();
    this.furni.get(uid)?.destroy();
    this.furni.delete(uid);
    if (this.selected === uid) this.select(null);
    if (this.hoveredFurni?.uid === uid) this.hoveredFurni = null;
  }

  /** Start placing a new furni: a ghost follows the pointer until you click (or tap) somewhere. */
  startPlacing(defId: string): void {
    const def = this.defs.get(defId);
    if (!def || !this.rights.place) return;
    this.beginPlacing(def, null, furniDirs(def)[0] ?? 4);
  }

  /** Start moving a furni in the room (like placing, from where it is). */
  startMoving(uid: number): void {
    const view = this.furni.get(uid);
    if (!view || !this.rights.edit) return;
    this.beginPlacing(view.def, uid, view.data.dir);
    view.container.visible = false;
  }

  /** Turn the furni you're placing, or the selected one (to its next direction). */
  rotatePlacing(): void {
    const p = this.placing;
    if (p) {
      if (p.def.kind === 'wall') return;
      const dirs = furniDirs(p.def);
      p.dir = dirs[(dirs.indexOf(p.dir) + 1) % dirs.length] ?? p.dir;
      if (p.spot) this.showGhost({ ...p.spot, dir: p.dir });
      return;
    }
    const view = this.selected !== null ? this.furni.get(this.selected) : undefined;
    if (!view || !this.rights.edit || view.def.kind === 'wall') return;
    const dirs = furniDirs(view.def);
    const dir = dirs[(dirs.indexOf(view.data.dir) + 1) % dirs.length] ?? view.data.dir;
    this.onMoveFurni(view.uid, { x: view.data.x, y: view.data.y, dir });
  }

  cancelPlacing(): void {
    const p = this.placing;
    if (!p) return;
    p.ghost.destroy();
    if (p.uid !== null) {
      const view = this.furni.get(p.uid);
      if (view) view.container.visible = true;
    }
    this.placing = null;
    this.onPlacing(null);
  }

  /** The furni selected in the room, if any. */
  selectedFurni(): number | null {
    return this.selected;
  }

  private beginPlacing(def: FurniDef, uid: number | null, dir: FurniDir): void {
    this.cancelPlacing();
    const ghost = new FurniView({ uid: -1, def: def.id, x: 0, y: 0, z: 0, dir, state: 0 }, def);
    ghost.container.visible = false;
    ghost.setGhost(true);
    this.objects.addChild(ghost.container);
    this.placing = { def, uid, ghost, dir, spot: null, drag: false };
    this.onPlacing(def);
  }

  private select(uid: number | null): void {
    this.selected = uid;
    const view = uid !== null ? this.furni.get(uid) : undefined;
    this.onSelectFurni(view ? { uid: view.uid, def: view.def, state: view.data.state } : null);
  }

  /** Follow the pointer with the ghost: on a floor tile, or on a wall for wall furni. */
  private moveGhost(sx: number, sy: number): void {
    const p = this.placing;
    if (!p) return;
    let spot: RoomFurni | null = null;
    if (p.def.kind === 'wall') {
      const hit = this.wallAt(sx, sy);
      if (hit) spot = { uid: -1, def: p.def.id, x: hit.face.x, y: hit.face.y, z: hit.z, dir: hit.face.dir, state: 0, off: hit.off };
    } else {
      const t = this.tileAt(sx, sy);
      if (t) spot = { uid: -1, def: p.def.id, x: t[0], y: t[1], z: 0, dir: p.dir, state: 0 };
    }
    p.spot = spot;
    if (spot) this.showGhost(spot);
    else p.ghost.container.visible = false;
  }

  private showGhost(spot: RoomFurni): void {
    const p = this.placing!;
    const z = p.def.kind === 'wall' ? (this.wallFits(p.def, spot) ? spot.z : null) : this.stackZ(p.def, spot, p.uid);
    const shown = { ...spot, z: z ?? (p.def.kind === 'wall' ? spot.z : heightAt(this.grid, spot.x, spot.y)), dir: p.def.kind === 'wall' ? spot.dir : p.dir };
    p.spot = { ...shown };
    p.ghost.place(shown, heightAt(this.grid, spot.x, spot.y));
    p.ghost.setGhost(z !== null);
    p.ghost.container.visible = true;
  }

  /**
   * Where a floor furni would stand (the same rules as the server): on floor, not the door,
   * stacked on furni things can go on. null if it can't go there.
   */
  private stackZ(def: FurniDef, spot: Pick<RoomFurni, 'x' | 'y' | 'dir'>, except: number | null): number | null {
    let z = 0;
    for (const [tx, ty] of furniTiles(def, spot)) {
      if (!isFloor(this.grid, tx, ty) || (tx === this.door[0] && ty === this.door[1])) return null;
      const below: FurniBelow[] = [];
      for (const f of this.furni.values()) {
        if (f.uid === except || f.def.kind !== 'floor') continue;
        if (!furniTiles(f.def, f.data).some(([x, y]) => x === tx && y === ty)) continue;
        below.push({ def: f.def, top: furniTop(f.def, f.data, this.sheets.get(f.def.id)) });
      }
      const top = standHeight(def, heightAt(this.grid, tx, ty), below);
      if (top === null) return null;
      z = Math.max(z, top);
    }
    return Math.round(z * 100) / 100;
  }

  /** Does a wall furni fit there: wall all along its picture (the same rule as the server)? */
  private wallFits(def: FurniDef, spot: RoomFurni): boolean {
    const [dx, dy] = this.door;
    const dir = spot.dir;
    const wallAt = (tx: number, ty: number) =>
      isFloor(this.grid, tx, ty) && !(tx === dx && ty === dy) && !(dir === 4 ? isFloor(this.grid, tx - 1, ty) : isFloor(this.grid, tx, ty - 1));
    return wallAt(spot.x, spot.y) && wallItemFits(def, this.sheets.get(def.id), { x: spot.x, y: spot.y, dir, off: spot.off ?? 0.5 }, wallAt);
  }

  /** The seat (or bed) on a tile, the highest. */
  private seatAt(x: number, y: number, how: 'sit' | 'lay'): RestingOn | null {
    let best: FurniView | null = null;
    for (const f of this.furni.values()) {
      if (!(how === 'lay' ? f.def.lay : f.def.sit) || f.def.kind !== 'floor') continue;
      if (!furniTiles(f.def, f.data).some(([tx, ty]) => tx === x && ty === y)) continue;
      if (!best || f.data.z > best.data.z) best = f;
    }
    if (!best) return null;
    const [w, l] = furniFootprint(best.def, best.data.dir);
    return { zIndex: best.container.zIndex, length: best.data.dir === 2 || best.data.dir === 6 ? w : l };
  }

  /** The wall under a screen point, where on it, and how high. */
  private wallAt(sx: number, sy: number): { face: WallFace; off: number; z: number } | null {
    const px = (sx - this.world.x) / this.zoom;
    const py = (sy - this.world.y) / this.zoom;
    let best: { face: WallFace; off: number; z: number; depth: number } | null = null;
    for (const face of this.walls) {
      // Screen x = (gx - gy) * 32 and y = (gx + gy) * 16 - z * 32: solve for the point on this wall.
      const along = face.dir === 4 ? face.x - px / 32 : px / 32 + face.y;
      const off = along - (face.dir === 4 ? face.y : face.x);
      if (off < 0 || off > 1) continue;
      const [gx, gy] = face.dir === 4 ? [face.x, along] : [along, face.y];
      const z = ((gx + gy) * 16 - py) / 32;
      if (z < face.base || z > face.top) continue;
      const depth = gx + gy;
      if (!best || depth > best.depth) {
        const h = Math.min(WALL_ITEM_MAX_Z, Math.max(WALL_ITEM_MIN_Z, z - face.base));
        best = { face, off: Math.min(0.9, Math.max(0.1, off)), z: Math.round(h * 100) / 100, depth };
      }
    }
    return best && { face: best.face, off: best.off, z: best.z };
  }

  /** Place (or move) the ghost where it is now. */
  private confirmPlacing(): void {
    const p = this.placing;
    if (!p?.spot || !p.ghost.container.visible) return;
    const { x, y, dir, off, z } = p.spot;
    if (p.def.kind === 'floor' && this.stackZ(p.def, p.spot, p.uid) === null) return;
    if (p.def.kind === 'wall' && !this.wallFits(p.def, p.spot)) return;
    const where = p.def.kind === 'wall' ? { x, y, dir, off: off ?? 0.5, z } : { x, y, dir };
    if (p.uid === null) this.onPlaceFurni(p.def.id, where);
    else this.onMoveFurni(p.uid, where);
    this.cancelPlacing();
  }

  chat(id: number, text: string): void {
    const a = this.avatars.get(id);
    if (!a) return;
    const head = a.headPoint();
    this.bubbles.add(a.name, text, head.x * this.zoom + this.world.x, head.y * this.zoom + this.world.y, this.app.screen.width, performance.now());
  }

  /** Puts the room in the middle of the screen (or the door, for rooms bigger than the screen). */
  center(): void {
    const b = this.roomBounds();
    if (b.width === 0) return;
    // Centred in the space above the toolbar.
    const width = this.app.screen.width;
    const height = this.app.screen.height - toolbarHeight();
    // A room bigger than the screen is centred on the door instead, so you see yourself come in
    // (drag to look around).
    const [dx, dy] = this.door;
    const door = tileCenter(dx, dy, heightAt(this.grid, dx, dy));
    const z = this.zoom;
    const x = b.width * z > width ? door.x : b.x + b.width / 2;
    const y = b.height * z > height ? door.y - 40 : b.y + b.height / 2;
    this.world.position.set(Math.round(width / 2 - x * z), Math.round(height / 2 - y * z));
  }

  /** Bounds of the room's floor and walls (avatars left out, so the room doesn't shift as they move). */
  private roomBounds(): { x: number; y: number; width: number; height: number } {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const g of this.roomPieces) {
      const b = g.getLocalBounds();
      if (b.width === 0) continue;
      minX = Math.min(minX, b.x); minY = Math.min(minY, b.y);
      maxX = Math.max(maxX, b.x + b.width); maxY = Math.max(maxY, b.y + b.height);
    }
    return minX === Infinity ? { x: 0, y: 0, width: 0, height: 0 } : { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
  }

  private update(): void {
    const now = performance.now();
    for (const a of this.avatars.values()) {
      const r = a.resting();
      a.restingOn = r ? this.seatAt(r.x, r.y, r.how) : null;
      a.update(now);
    }
    for (const f of this.furni.values()) f.update(now);
    this.placing?.ghost.update(now);
    this.bubbles.update(now);
  }


  private tileAt(sx: number, sy: number): [number, number] | null {
    const px = (sx - this.world.x) / this.zoom;
    const py = (sy - this.world.y) / this.zoom;
    for (const [x, y] of this.tilesFrontToBack) if (pointInTile(px, py, x, y, heightAt(this.grid, x, y))) return [x, y];
    return null;
  }

  private avatarAt(sx: number, sy: number): AvatarView | null {
    const px = (sx - this.world.x) / this.zoom;
    const py = (sy - this.world.y) / this.zoom;
    let best: AvatarView | null = null;
    for (const a of this.avatars.values()) if (a.hits(px, py) && (!best || a.container.zIndex > best.container.zIndex)) best = a;
    return best;
  }

  private furniAt(sx: number, sy: number): FurniView | null {
    const px = (sx - this.world.x) / this.zoom;
    const py = (sy - this.world.y) / this.zoom;
    let best: FurniView | null = null;
    for (const f of this.furni.values()) if (f.hits(px, py) && (!best || f.container.zIndex > best.container.zIndex)) best = f;
    return best;
  }

  private pointerMove(e: FederatedPointerEvent): void {
    if (this.pointers.has(e.pointerId)) this.pointers.set(e.pointerId, { x: e.global.x, y: e.global.y });
    if (this.pinch) return this.pinchMove();
    if (this.drag) {
      const dx = e.global.x - this.drag.startX;
      const dy = e.global.y - this.drag.startY;
      if (!this.drag.moved && Math.hypot(dx, dy) > (e.pointerType === 'touch' ? DRAG_THRESHOLD * 2 : DRAG_THRESHOLD)) {
        this.drag.moved = true;
        clearTimeout(this.longPress);
      }
      if (this.drag.moved) {
        // Dragging a furni you may move picks it up and moves it (mouse, like Habbo).
        if (this.pressedFurni !== null && !this.placing) {
          this.startMoving(this.pressedFurni);
          this.pressedFurni = null;
          if (this.placing) (this.placing as { drag: boolean }).drag = true;
        }
        if (this.placing?.drag) {
          this.moveGhost(e.global.x, e.global.y);
          return;
        }
        this.world.position.set(Math.round(this.drag.worldX + dx), Math.round(this.drag.worldY + dy));
        return;
      }
    }
    if (this.placing) {
      this.hover.clear();
      if (e.pointerType !== 'touch') this.moveGhost(e.global.x, e.global.y);
      return;
    }
    // Hover (tile outline, names) is for the mouse; touch has no hover.
    if (e.pointerType === 'touch') return;
    const t = this.tileAt(e.global.x, e.global.y);
    if (t) {
      drawTileOutline(this.hover, t[0], t[1], heightAt(this.grid, t[0], t[1]));
      // Just above its tile's floor, under walls, furni and avatars.
      this.hover.zIndex = depthToZIndex(floorDepth(this.grid, t[0], t[1]) + 0.05);
    } else this.hover.clear();


    const a = this.avatarAt(e.global.x, e.global.y);
    if (a !== this.hoveredAvatar) {
      this.hoveredAvatar?.showName(false);
      a?.showName(true);
      this.hoveredAvatar = a;
    }
    // Furni names on hover (avatars come first).
    const f = a ? null : this.furniAt(e.global.x, e.global.y);
    if (f !== this.hoveredFurni) {
      this.hoveredFurni?.showName(false);
      f?.showName(true);
      this.hoveredFurni = f;
    }
  }

  private pointerDown(e: FederatedPointerEvent): void {
    if (e.button !== 0) return;
    this.pointers.set(e.pointerId, { x: e.global.x, y: e.global.y });
    if (this.pointers.size === 2) {
      // Second finger: pinch to zoom (no walking or dragging until both are lifted).
      const [a, b] = [...this.pointers.values()] as [{ x: number; y: number }, { x: number; y: number }];
      this.pinch = { dist: Math.max(1, Math.hypot(a.x - b.x, a.y - b.y)), zoom: this.zoom };
      this.drag = null;
      clearTimeout(this.longPress);
      return;
    }
    if (this.pointers.size > 2 || this.pinch) return;
    this.drag = { startX: e.global.x, startY: e.global.y, worldX: this.world.x, worldY: this.world.y, moved: false };
    // With a mouse, pressing a furni you may move can start dragging it.
    const pressed = !this.placing && this.rights.edit && e.pointerType !== 'touch' ? this.furniAt(e.global.x, e.global.y) : null;
    this.pressedFurni = pressed ? pressed.uid : null;
    if (e.pointerType === 'touch') {
      const { x, y } = e.global;
      clearTimeout(this.longPress);
      this.longPress = setTimeout(() => {
        if (!this.drag || this.drag.moved) return;
        if (this.showNameAt(x, y)) this.drag = null; // a hold is not a tap: don't walk
      }, LONG_PRESS_MS);
    }
  }

  private pinchMove(): void {
    if (!this.pinch || this.pointers.size < 2) return;
    const [a, b] = [...this.pointers.values()] as [{ x: number; y: number }, { x: number; y: number }];
    const dist = Math.max(1, Math.hypot(a.x - b.x, a.y - b.y));
    const zoom = Math.min(ZOOMS[ZOOMS.length - 1]!, Math.max(ZOOMS[0]!, (this.pinch.zoom * dist) / this.pinch.dist));
    this.setZoom(zoom, (a.x + b.x) / 2, (a.y + b.y) / 2);
  }

  /** A finger lifted or lost: ends a pinch (snapping to the nearest zoom level). */
  private pointerGone(e: FederatedPointerEvent): void {
    if (this.pointers.size <= 1) this.pressedFurni = null;
    const last = this.pointers.get(e.pointerId);
    this.pointers.delete(e.pointerId);
    clearTimeout(this.longPress);
    if (this.pinch && this.pointers.size < 2) {
      this.pinch = null;
      const nearest = ZOOMS.reduce((best, z) => (Math.abs(Math.log(z / this.zoom)) < Math.abs(Math.log(best / this.zoom)) ? z : best), 1);
      const other = [...this.pointers.values()][0] ?? last;
      this.setZoom(nearest, other?.x, other?.y);
      this.drag = null;
    }
    if (this.pointers.size === 0) this.drag = null;
  }

  /** Touch: show the name of the avatar or furni at a screen point for a moment. */
  private showNameAt(sx: number, sy: number): boolean {
    const target = this.avatarAt(sx, sy) ?? this.furniAt(sx, sy);
    if (!target) return false;
    if (this.shownName) {
      clearTimeout(this.shownName.timer);
      this.shownName.hide();
    }
    target.showName(true);
    const hide = () => target.showName(false);
    this.shownName = { hide, timer: setTimeout(() => (hide(), (this.shownName = null)), NAME_SHOW_MS) };
    return true;
  }

  private pointerUp(e: FederatedPointerEvent): void {
    // Pixi hears pointer-ups anywhere on the page; only a click that also started on the room
    // (not on a window above it) walks.
    const started = this.drag;
    const wasPinch = !!this.pinch;
    this.pointerGone(e);
    this.pressedFurni = null;
    if (wasPinch) return;
    this.drag = null;
    // Letting go of a dragged furni puts it there.
    if (this.placing?.drag) {
      this.moveGhost(e.global.x, e.global.y);
      this.confirmPlacing();
      return;
    }
    if (!started || started.moved || e.button !== 0) return;
    // Placing: a click (or tap) puts it there.
    if (this.placing) {
      this.moveGhost(e.global.x, e.global.y);
      this.confirmPlacing();
      return;
    }
    // Double-click a furni to use it (switch it on/off, open it…).
    const f = this.avatarAt(e.global.x, e.global.y) ? null : this.furniAt(e.global.x, e.global.y);
    const now = performance.now();
    if (f && this.lastClick.uid === f.uid && now - this.lastClick.at < 400) {
      this.lastClick = { uid: -1, at: 0 };
      this.onUseFurni(f.uid);
      return;
    }
    this.lastClick = { uid: f?.uid ?? -1, at: now };
    // Clicking a furni selects it (its name and buttons show); clicking the floor stops that.
    this.select(f ? f.uid : null);
    const t = this.tileAt(e.global.x, e.global.y);
    if (t && isFloor(this.grid, t[0], t[1])) this.onWalk(t[0], t[1]);
  }
}

export { tileCenter };
