// A room on screen: floor and walls, avatars, the hover outline, clicks to walk, dragging to look
// around, zooming (mouse wheel, pinch or the toolbar) and chat bubbles. Works with a mouse and
// with touch: tap to walk, drag to look around, pinch to zoom, hold to see a name.
import { Container, Graphics, type Application, type FederatedPointerEvent } from 'pixi.js';
import { heightAt, isFloor, parseMap, type DataOf, type Grid, type ServerMessage } from '@bobba/shared';
import { AvatarView } from './AvatarView.ts';
import { toolbarHeight } from '../layout.ts';
import { ChatBubbles } from './ChatBubbles.ts';
import { FurniView } from './FurniView.ts';
import { furniDefs } from './furniAssets.ts';
import { depthToZIndex, drawRoom, drawTileOutline, floorDepth } from './drawRoom.ts';
import { pointInTile, tileCenter } from './iso.ts';

const TICK_MS = 500;
const DRAG_THRESHOLD = 5;
/** Zoom levels, like Habbo: half size for big rooms and small screens, double for big screens. */
const ZOOMS = [0.5, 1, 2];
/** Holding a finger still this long on an avatar or furni shows its name (touch has no hover). */
const LONG_PRESS_MS = 450;
/** How long a name shown by holding stays up. */
const NAME_SHOW_MS = 2500;

export class RoomView {
  private readonly app: Application;
  private readonly world = new Container();
  private readonly hover = new Graphics();
  /** Floor, walls, furni and avatars, depth-sorted together. */
  private readonly objects = new Container();
  private readonly bubbles = new ChatBubbles();
  private readonly avatars = new Map<number, AvatarView>();
  private furni: FurniView[] = [];
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
    for (const f of this.furni) f.destroy();
    this.furni = [];
    this.hoveredFurni = null;
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

    for (const piece of drawRoom(this.grid, room.door)) {
      piece.graphics.zIndex = depthToZIndex(piece.depth);
      this.objects.addChild(piece.graphics);
      this.roomPieces.push(piece.graphics);
    }
    this.hover.clear();
    for (const u of room.users) this.addUser(u);
    void furniDefs().then((defs) => {
      if (serial !== this.roomSerial) return;
      for (const f of room.furni) {
        const def = defs.get(f.def);
        if (!def) continue;
        const view = new FurniView(f, def);
        this.furni.push(view);
        this.objects.addChild(view.container);
      }
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
    for (const s of updates) this.avatars.get(s.id)?.moveTo(s.x, s.y, s.z, s.dir, s.moving, TICK_MS, now);
  }

  furniState(uid: number, state: number): void {
    this.furni.find((f) => f.uid === uid)?.setState(state);
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
    for (const a of this.avatars.values()) a.update(now);
    for (const f of this.furni) f.update(now);
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
    for (const f of this.furni) if (f.hits(px, py) && (!best || f.container.zIndex > best.container.zIndex)) best = f;
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
        this.world.position.set(Math.round(this.drag.worldX + dx), Math.round(this.drag.worldY + dy));
        return;
      }
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
    if (wasPinch) return;
    this.drag = null;
    if (!started || started.moved || e.button !== 0) return;
    // Double-click a furni to use it (switch it on/off, open it…).
    const f = this.avatarAt(e.global.x, e.global.y) ? null : this.furniAt(e.global.x, e.global.y);
    const now = performance.now();
    if (f && this.lastClick.uid === f.uid && now - this.lastClick.at < 400) {
      this.lastClick = { uid: -1, at: 0 };
      this.onUseFurni(f.uid);
      return;
    }
    this.lastClick = { uid: f?.uid ?? -1, at: now };
    const t = this.tileAt(e.global.x, e.global.y);
    if (t && isFloor(this.grid, t[0], t[1])) this.onWalk(t[0], t[1]);
  }
}

export { tileCenter };
