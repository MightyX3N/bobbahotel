// One avatar in the room: the Cozy layers, walking smoothly between tiles.
import { Container, Graphics, Matrix, Sprite, Text } from 'pixi.js';
import { AVATAR_FRAME, lookLayers, SHEET_ROW, type Look, type Pose, type RoomUser } from '@bobba/shared';
import { loadSprite, sheetFrame } from '../sprites.ts';
import { tileCenter } from './iso.ts';

// The Cozy figure is about 73 px tall at its own size. Measured from Habbo, the avatar is about
// as tall as the door opening (~85-88 px on 64 px tiles), so it is drawn at 1.2x: ~88 px.
const SCALE = 1.2;
const WALK_FPS = 12;
const IDLE_FPS = 4;
/**
 * Lying down: the Cozy kit has no lying pictures, so the standing figure (seen from the front) is
 * laid flat along the bed: its up-down runs along the bed, its left-right across it. Head to feet
 * it is this many tiles long (less on a short bed).
 */
const LAY_LENGTH = 2.1;
/** Where the head is: tiles from the middle of the head tile, towards the headboard. */
const LAY_HEAD = 0.38;

/** The bed someone lies on. */
export interface RestingOn {
  /** How many tiles long. */
  length: number;
}

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
  private sitting = false;
  private lying = false;
  /** Set by the room while lying: the bed it's on. */
  restingOn: RestingOn | null = null;
  private readonly shadow: Graphics;
  private readonly seed: number;

  constructor(user: RoomUser) {
    this.id = user.id;
    this.name = user.name;
    this.look = user.look;
    this.dir = user.dir;
    this.seed = (user.id * 9301) % 1000;
    this.from = this.to = { x: user.x, y: user.y, z: user.z };
    this.sitting = user.sit;
    this.lying = user.lay;

    const shadow = new Graphics().ellipse(0, 0, 13, 6).fill({ color: 0x000000, alpha: 0.2 });
    this.shadow = shadow;
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

  /** Start walking to a tile (arrives in `ms`) or stop there (sitting on a seat, lying on a bed). */
  moveTo(x: number, y: number, z: number, dir: number, moving: boolean, ms: number, now: number, sit = false, lay = false): void {
    this.sitting = sit;
    this.lying = lay;
    const cur = this.positionAt(now);
    this.from = cur;
    this.to = { x, y, z };
    this.moveStart = now;
    this.moveMs = moving ? ms : 1;
    this.dir = dir;
    this.moving = moving;
  }

  /** Which way it faces (0-7). */
  facing(): number {
    return this.dir;
  }

  /** Sitting or lying (not walking), on the tile it's going to. */
  resting(): { x: number; y: number; how: 'sit' | 'lay' } | null {
    if (this.moving || !(this.sitting || this.lying)) return null;
    return { x: this.to.x, y: this.to.y, how: this.lying ? 'lay' : 'sit' };
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
    // (The room works out the drawing order: see depthSort.ts.)

    const walking = this.moving && now - this.moveStart < this.moveMs + 120;
    const lying = this.lying && !walking;
    const resting = (this.sitting || this.lying) && !walking;
    this.setPose(walking ? 'walk' : this.sitting ? 'sit' : 'idle');
    this.layDown(lying, this.restingOn?.length ?? 2);
    // No shadow while sitting or lying: the seat is under you.
    this.shadow.visible = !resting;
    const fps = walking ? WALK_FPS : IDLE_FPS;
    const frame = lying ? 0 : Math.floor(((now + this.seed * 37) / 1000) * fps) % AVATAR_FRAME.frames;
    // Lying, the figure is seen from the front, turned towards the room.
    const row = lying ? (this.dir === 2 || this.dir === 6 ? SHEET_ROW[4] : SHEET_ROW[2]) : (SHEET_ROW[this.dir] ?? 0);
    for (let i = 0; i < this.layers.length; i++) {
      const t = sheetFrame(this.layerPaths[i]!, frame, row, AVATAR_FRAME.w, AVATAR_FRAME.h);
      if (t) this.layers[i]!.texture = t;
      this.layers[i]!.visible = t !== null;
    }
  }

  destroy(): void {
    this.container.destroy({ children: true });
  }

  /**
   * Lays the figure flat along the bed (or stands it up again). The bed's foot faces `dir`: the
   * figure's head goes to the other end, its feet towards the foot.
   */
  private layDown(lying: boolean, bedLength: number): void {
    if (!lying) {
      this.body.setFromMatrix(new Matrix());
      this.body.pivot.set(0, 0);
      this.label.y = -AVATAR_FRAME.footY * SCALE + 2;
      return;
    }
    // Screen direction of one tile towards the foot: dir 4 = +y, 2 = +x, 0 = -y, 6 = -x.
    const along = ({ 4: [-32, 16], 2: [32, 16], 0: [32, -16], 6: [-32, -16] } as Record<number, [number, number]>)[this.dir] ?? [-32, 16];
    // Across the bed (the figure's left-right), the other floor axis, pointing down the screen.
    const across: [number, number] = [along[1] * 2 * (along[0] < 0 ? 1 : -1), Math.abs(along[1])];
    // The figure is AVATAR_FRAME.footY * SCALE units tall (feet to the top of the frame).
    const tiles = Math.min(LAY_LENGTH, bedLength - 0.35);
    const k = tiles / (AVATAR_FRAME.footY * SCALE * 0.95);
    // Figure x (left-right) -> across, figure y (head to feet, downwards) -> along.
    const m = new Matrix(across[0] * k, across[1] * k, along[0] * k, along[1] * k, 0, 0);
    this.body.setFromMatrix(m);
    // Turn around the figure's middle, which lies half its length past its head.
    const centre = tiles / 2 - LAY_HEAD;
    this.body.pivot.set(0, -AVATAR_FRAME.footY * SCALE * 0.5);
    this.body.position.set(along[0] * centre, along[1] * centre);
    this.label.y = -40;
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
