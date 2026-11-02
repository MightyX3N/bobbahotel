// A room on screen: floor and walls, avatars, the hover outline, clicks to walk, dragging to look
// around, zooming (mouse wheel or the toolbar) and chat bubbles.
import { Container, Graphics, type Application, type FederatedPointerEvent } from 'pixi.js';
import { heightAt, isFloor, parseMap, type DataOf, type Grid, type ServerMessage } from '@bobba/shared';
import { AvatarView } from './AvatarView.ts';
import { ChatBubbles } from './ChatBubbles.ts';
import { depthToZIndex, drawRoom, drawTileOutline, tileDepth } from './drawRoom.ts';
import { pointInTile, tileCenter } from './iso.ts';

const TICK_MS = 500;
/** Height of the UI toolbar along the bottom (see the theme). */
const TOOLBAR_HEIGHT = 55;
const DRAG_THRESHOLD = 5;
/** Zoom levels, like Habbo: half size for big rooms and small screens, double for big screens. */
const ZOOMS = [0.5, 1, 2];

export class RoomView {
  private readonly app: Application;
  private readonly world = new Container();
  private readonly hover = new Graphics();
  private readonly objects = new Container();
  private readonly bubbles = new ChatBubbles();
  private readonly avatars = new Map<number, AvatarView>();
  private grid: Grid = [];
  private door: [number, number] = [0, 0];
  /** Floor and wall pieces (depth-sorted together with the avatars). */
  private roomPieces: Graphics[] = [];
  private tilesFrontToBack: [number, number][] = [];
  private hoveredAvatar: AvatarView | null = null;
  private zoom = 1;
  private drag: { startX: number; startY: number; worldX: number; worldY: number; moved: boolean } | null = null;

  /** Called when the player clicks a floor tile. */
  onWalk: (x: number, y: number) => void = () => {};

  constructor(app: Application) {
    this.app = app;
    this.objects.sortableChildren = true;
    this.world.addChild(this.objects);
    this.objects.addChild(this.hover);
    app.stage.addChild(this.world, this.bubbles.container);

    app.stage.eventMode = 'static';
    app.stage.hitArea = app.screen;
    app.stage.on('pointermove', (e) => this.pointerMove(e));
    app.stage.on('pointerdown', (e) => this.pointerDown(e));
    app.stage.on('pointerup', (e) => this.pointerUp(e));
    app.stage.on('pointerupoutside', () => (this.drag = null));
    app.ticker.add(() => this.update());
    app.renderer.on('resize', () => this.center());
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
  setZoom(zoom: number, sx = this.app.screen.width / 2, sy = (this.app.screen.height - TOOLBAR_HEIGHT) / 2): void {
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

    this.bubbles.clear();
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
    // Start at normal size, or half size when the room doesn't fit the screen.
    const b = this.roomBounds();
    const fits = b.width <= this.app.screen.width && b.height <= this.app.screen.height - TOOLBAR_HEIGHT;
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
    const height = this.app.screen.height - TOOLBAR_HEIGHT;
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

  private pointerMove(e: FederatedPointerEvent): void {
    if (this.drag) {
      const dx = e.global.x - this.drag.startX;
      const dy = e.global.y - this.drag.startY;
      if (!this.drag.moved && Math.hypot(dx, dy) > DRAG_THRESHOLD) this.drag.moved = true;
      if (this.drag.moved) {
        this.world.position.set(Math.round(this.drag.worldX + dx), Math.round(this.drag.worldY + dy));
        return;
      }
    }
    const t = this.tileAt(e.global.x, e.global.y);
    if (t) {
      drawTileOutline(this.hover, t[0], t[1], heightAt(this.grid, t[0], t[1]));
      // Just above its tile, so walls and anything in front still cover it.
      this.hover.zIndex = depthToZIndex(tileDepth(t[0], t[1]) - 0.05);
    } else this.hover.clear();


    const a = this.avatarAt(e.global.x, e.global.y);
    if (a !== this.hoveredAvatar) {
      this.hoveredAvatar?.showName(false);
      a?.showName(true);
      this.hoveredAvatar = a;
    }
  }

  private pointerDown(e: FederatedPointerEvent): void {
    if (e.button !== 0) return;
    this.drag = { startX: e.global.x, startY: e.global.y, worldX: this.world.x, worldY: this.world.y, moved: false };
  }

  private pointerUp(e: FederatedPointerEvent): void {
    // Pixi hears pointer-ups anywhere on the page; only a click that also started on the room
    // (not on a window above it) walks.
    const started = this.drag;
    this.drag = null;
    if (!started || started.moved || e.button !== 0) return;
    const t = this.tileAt(e.global.x, e.global.y);
    if (t && isFloor(this.grid, t[0], t[1])) this.onWalk(t[0], t[1]);
  }
}

export { tileCenter };
