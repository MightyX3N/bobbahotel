// One avatar in the room: the Cozy layers, walking smoothly between tiles.
import { Container, Graphics, Sprite, Text } from 'pixi.js';
import { AVATAR_FRAME, lookLayers, SHEET_ROW, type Look, type Pose, type RoomUser } from '@bobba/shared';
import { loadSprite, sheetFrame } from '../sprites.ts';
import { depthToZIndex, tileDepth } from './drawRoom.ts';
import { tileCenter } from './iso.ts';

// The Cozy figure is about 73 px tall at its own size. Measured from Habbo, the avatar is about
// as tall as the door opening (~85-88 px on 64 px tiles), so it is drawn at 1.2x: ~88 px.
const SCALE = 1.2;
const WALK_FPS = 12;
const IDLE_FPS = 4;

export class AvatarView {
  readonly id: number;
  readonly name: string;
  readonly container = new Container();
  private readonly body = new Container();
  private readonly label: Text;
  private look: Look;
  private layers: Sprite[] = [];
  private layerPaths: string[] = [];
  private pose: Pose | null = null;

  // Position in tiles (fractional while walking).
  private from = { x: 0, y: 0, z: 0 };
  private to = { x: 0, y: 0, z: 0 };
  private moveStart = 0;
  private moveMs = 1;
  private dir: number;
  private moving = false;
  private readonly seed: number;

  constructor(user: RoomUser) {
    this.id = user.id;
    this.name = user.name;
    this.look = user.look;
    this.dir = user.dir;
    this.seed = (user.id * 9301) % 1000;
    this.from = this.to = { x: user.x, y: user.y, z: user.z };

    const shadow = new Graphics().ellipse(0, 0, 13, 6).fill({ color: 0x000000, alpha: 0.2 });
    this.label = new Text({
      text: user.name,
      style: { fontFamily: 'Verdana, sans-serif', fontSize: 11, fontWeight: 'bold', fill: 0xffffff, stroke: { color: 0x000000, width: 3 } },
      resolution: 2,
    });
    this.label.anchor.set(0.5, 1);
    this.label.y = -AVATAR_FRAME.footY * SCALE + 2;
    this.label.visible = false;
    this.container.addChild(shadow, this.body, this.label);
    this.setPose('idle');
  }

  /** Start walking to a tile (arrives in `ms`) or stop there. */
  moveTo(x: number, y: number, z: number, dir: number, moving: boolean, ms: number, now: number): void {
    const cur = this.positionAt(now);
    this.from = cur;
    this.to = { x, y, z };
    this.moveStart = now;
    this.moveMs = moving ? ms : 1;
    this.dir = dir;
    this.moving = moving;
  }

  /** Where the avatar is right now, in tiles (fractional while walking). */
  tilePosition(now: number): { x: number; y: number; z: number } {
    return this.positionAt(now);
  }

  showName(show: boolean): void {
    this.label.visible = show;
  }

  /** Screen point just above the head (for chat bubbles). */
  headPoint(): { x: number; y: number } {
    return { x: this.container.x, y: this.container.y - (AVATAR_FRAME.footY - 2) * SCALE };
  }

  /** Rough hit test in room coordinates. */
  hits(px: number, py: number): boolean {
    const dx = px - this.container.x;
    const dy = py - this.container.y;
    return Math.abs(dx) < 15 * SCALE && dy < 2 && dy > -72 * SCALE;
  }

  update(now: number): void {
    const p = this.positionAt(now);
    const s = tileCenter(p.x, p.y, p.z);
    this.container.position.set(Math.round(s.x), Math.round(s.y));
    // Sorted by where the avatar actually is (also mid-step), a little above its own tile, so a
    // wall or raised floor in front hides it at the right moment (e.g. stepping through the door)
    // while flat floor it walks onto never covers its feet.
    this.container.zIndex = depthToZIndex(tileDepth(p.x, p.y) + 0.6);

    const walking = this.moving && now - this.moveStart < this.moveMs + 120;
    this.setPose(walking ? 'walk' : 'idle');
    const fps = walking ? WALK_FPS : IDLE_FPS;
    const frame = Math.floor(((now + this.seed * 37) / 1000) * fps) % AVATAR_FRAME.frames;
    const row = SHEET_ROW[this.dir] ?? 0;
    for (let i = 0; i < this.layers.length; i++) {
      const t = sheetFrame(this.layerPaths[i]!, frame, row, AVATAR_FRAME.w, AVATAR_FRAME.h);
      if (t) this.layers[i]!.texture = t;
      this.layers[i]!.visible = t !== null;
    }
  }

  destroy(): void {
    this.container.destroy({ children: true });
  }

  private positionAt(now: number): { x: number; y: number; z: number } {
    const t = Math.min(1, Math.max(0, (now - this.moveStart) / this.moveMs));
    return {
      x: this.from.x + (this.to.x - this.from.x) * t,
      y: this.from.y + (this.to.y - this.from.y) * t,
      z: this.from.z + (this.to.z - this.from.z) * t,
    };
  }

  private setPose(pose: Pose): void {
    if (pose === this.pose) return;
    this.pose = pose;
    this.layerPaths = lookLayers(this.look, pose);
    this.body.removeChildren().forEach((c) => c.destroy());
    this.layers = this.layerPaths.map((path) => {
      const sprite = new Sprite();
      sprite.scale.set(SCALE);
      sprite.position.set(-AVATAR_FRAME.footX * SCALE, -AVATAR_FRAME.footY * SCALE);
      sprite.visible = false;
      void loadSprite(path);
      this.body.addChild(sprite);
      return sprite;
    });
  }
}
