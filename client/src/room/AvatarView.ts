// One avatar in the room: the Cozy layers, drawn 2x, walking smoothly between tiles.
import { Container, Graphics, Sprite, Text } from 'pixi.js';
import { AVATAR_FRAME, lookLayers, SHEET_ROW, type Look, type Pose, type RoomUser } from '@bobba/shared';
import { loadSprite, sheetFrame } from '../sprites.ts';
import { depthOf, tileCenter } from './iso.ts';

const SCALE = 2;
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

    const shadow = new Graphics().ellipse(0, 0, 18, 8).fill({ color: 0x000000, alpha: 0.2 });
    this.label = new Text({
      text: user.name,
      style: { fontFamily: 'Verdana, sans-serif', fontSize: 11, fontWeight: 'bold', fill: 0xffffff, stroke: { color: 0x000000, width: 3 } },
      resolution: 2,
    });
    this.label.anchor.set(0.5, 1);
    this.label.y = -AVATAR_FRAME.footY * SCALE + 8;
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

  showName(show: boolean): void {
    this.label.visible = show;
  }

  /** Screen point just above the head (for chat bubbles). */
  headPoint(): { x: number; y: number } {
    return { x: this.container.x, y: this.container.y - (AVATAR_FRAME.footY - 10) * SCALE };
  }

  /** Rough hit test in room coordinates. */
  hits(px: number, py: number): boolean {
    const dx = px - this.container.x;
    const dy = py - this.container.y;
    return Math.abs(dx) < 16 * SCALE && dy < 0 && dy > -62 * SCALE;
  }

  update(now: number): void {
    const p = this.positionAt(now);
    const s = tileCenter(p.x, p.y, p.z);
    this.container.position.set(Math.round(s.x), Math.round(s.y));
    // Sort by the tile being walked onto so the avatar isn't hidden behind the floor in front of it.
    const sortTile = this.moving ? this.to : p;
    this.container.zIndex = depthOf(Math.max(p.x, sortTile.x), Math.max(p.y, sortTile.y), 0) + 50;

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
