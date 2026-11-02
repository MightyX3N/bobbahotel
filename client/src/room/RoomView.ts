// A room on screen: floor and walls, avatars, the hover outline, clicks to walk, dragging to look
// around, and chat bubbles.
import { Container, Graphics, type Application, type FederatedPointerEvent } from 'pixi.js';
import { heightAt, isFloor, parseMap, type DataOf, type Grid, type ServerMessage } from '@bobba/shared';
import { AvatarView } from './AvatarView.ts';
import { ChatBubbles } from './ChatBubbles.ts';
import { doorHolePolygon, drawRoom, drawTileOutline } from './drawRoom.ts';
import { pointInTile, tileCenter } from './iso.ts';

const TICK_MS = 500;
const DRAG_THRESHOLD = 5;

export class RoomView {
  private readonly app: Application;
  private readonly world = new Container();
  private readonly floorLayer = new Container();
  private readonly hover = new Graphics();
  private readonly objects = new Container();
  private readonly bubbles = new ChatBubbles();
  private readonly avatars = new Map<number, AvatarView>();
  private grid: Grid = [];
  private door: [number, number] = [0, 0];
  /** Per-avatar clip to the door hole, used while the avatar is still behind the wall. */
  private readonly doorMasks = new Map<number, Graphics>();
  private tilesFrontToBack: [number, number][] = [];
  private hoveredAvatar: AvatarView | null = null;
  private drag: { startX: number; startY: number; worldX: number; worldY: number; moved: boolean } | null = null;

  /** Called when the player clicks a floor tile. */
  onWalk: (x: number, y: number) => void = () => {};

  constructor(app: Application) {
    this.app = app;
    this.objects.sortableChildren = true;
    this.world.addChild(this.floorLayer, this.hover, this.objects);
    app.stage.addChild(this.world, this.bubbles.container);

    app.stage.eventMode = 'static';
    app.stage.hitArea = app.screen;
    app.stage.on('pointermove', (e) => this.pointerMove(e));
    app.stage.on('pointerdown', (e) => this.pointerDown(e));
    app.stage.on('pointerup', (e) => this.pointerUp(e));
    app.stage.on('pointerupoutside', () => (this.drag = null));
    app.ticker.add(() => this.update());
    app.renderer.on('resize', () => this.center());
  }

  enter(room: DataOf<ServerMessage, 'room'>): void {
    for (const a of this.avatars.values()) a.destroy();
    this.avatars.clear();
    for (const m of this.doorMasks.values()) m.destroy();
    this.doorMasks.clear();
    this.bubbles.clear();
    this.grid = parseMap(room.map);
    this.door = room.door;
    this.tilesFrontToBack = [];
    this.grid.forEach((row, y) => row.forEach((h, x) => h >= 0 && this.tilesFrontToBack.push([x, y])));
    this.tilesFrontToBack.sort((a, b) => b[0] + b[1] - (a[0] + a[1]) || heightAt(this.grid, b[0], b[1]) - heightAt(this.grid, a[0], a[1]));

    this.floorLayer.removeChildren().forEach((c) => c.destroy());
    this.floorLayer.addChild(drawRoom(this.grid, room.door));
    this.hover.clear();
    for (const u of room.users) this.addUser(u);
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
    this.doorMasks.get(id)?.destroy();
    this.doorMasks.delete(id);
  }

  status(updates: DataOf<ServerMessage, 'status'>): void {
    const now = performance.now();
    for (const s of updates) this.avatars.get(s.id)?.moveTo(s.x, s.y, s.z, s.dir, s.moving, TICK_MS, now);
  }

  chat(id: number, text: string): void {
    const a = this.avatars.get(id);
    if (!a) return;
    const head = a.headPoint();
    this.bubbles.add(a.name, text, head.x + this.world.x, head.y + this.world.y, this.app.screen.width, performance.now());
  }

  /** Puts the room in the middle of the screen. */
  center(): void {
    const b = this.floorLayer.getLocalBounds();
    if (b.width === 0) return;
    this.world.position.set(Math.round(this.app.screen.width / 2 - (b.x + b.width / 2)), Math.round(this.app.screen.height / 2 - (b.y + b.height / 2)));
  }

  private update(): void {
    const now = performance.now();
    for (const a of this.avatars.values()) {
      a.update(now);
      this.clipAtDoor(a, now);
    }
    this.bubbles.update(now);
  }

  /**
   * The door tile is outside the wall: an avatar standing there (or walking through) is only
   * visible through the door hole, like in Habbo.
   */
  private clipAtDoor(a: AvatarView, now: number): void {
    const p = a.tilePosition(now);
    const [dx, dy] = this.door;
    const behindWall = p.x < dx + 0.98 && Math.abs(p.y - dy) < 0.5;
    if (!behindWall) {
      const old = this.doorMasks.get(a.id);
      if (old) {
        // A released mask would be drawn as a plain shape, so it goes away completely.
        a.container.mask = null;
        old.destroy();
        this.doorMasks.delete(a.id);
      }
      return;
    }
    let mask = this.doorMasks.get(a.id);
    if (!mask) {
      mask = new Graphics().poly(doorHolePolygon(this.grid, this.door)).fill(0xffffff);
      this.world.addChild(mask);
      this.doorMasks.set(a.id, mask);
    }
    if (a.container.mask !== mask) a.container.mask = mask;
  }

  private tileAt(sx: number, sy: number): [number, number] | null {
    const px = sx - this.world.x;
    const py = sy - this.world.y;
    for (const [x, y] of this.tilesFrontToBack) if (pointInTile(px, py, x, y, heightAt(this.grid, x, y))) return [x, y];
    return null;
  }

  private avatarAt(sx: number, sy: number): AvatarView | null {
    const px = sx - this.world.x;
    const py = sy - this.world.y;
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
    if (t) drawTileOutline(this.hover, t[0], t[1], heightAt(this.grid, t[0], t[1]));
    else this.hover.clear();

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
    const wasDrag = this.drag?.moved;
    this.drag = null;
    if (wasDrag || e.button !== 0) return;
    const t = this.tileAt(e.global.x, e.global.y);
    if (t && isFloor(this.grid, t[0], t[1])) this.onWalk(t[0], t[1]);
  }
}

export { tileCenter };
