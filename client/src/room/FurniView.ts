// One furni in the room: its picture for its state (mirrored for mirrored directions), animated
// if that state has frames, depth-sorted with avatars and walls. Floor furni stand on their tiles;
// wall furni hang on the wall at the edge of their tile. Also used for the see-through "ghost"
// that follows the mouse while placing or moving a furni.
import { Container, Sprite, Text } from 'pixi.js';
import { furniFootprint, type FurniDef, type FurniDir, type RoomFurni } from '@bobba/shared';
import { corner, depthToZIndex, FLAT_FLOOR_BELOW, tileDepth } from './drawRoom.ts';
import { furniFrames, type FurniFrames, type FurniTexture } from './furniAssets.ts';

export class FurniView {
  readonly uid: number;
  readonly def: FurniDef;
  readonly container = new Container();
  private readonly sprite = new Sprite();
  private readonly label: Text;
  private all: FurniFrames | null = null;
  private states: FurniTexture[][] = [];
  private state: number;
  private dir: FurniDir;
  private flip = false;
  private destroyed = false;
  /** When the current state started (for animations that play once); long ago for the state it was loaded in. */
  private stateStart = -Infinity;
  private frameShown = -1;
  /** Where it is now (kept up to date when moved). */
  data: RoomFurni;

  /** floorZ: the floor height of its tile (wall furni hang relative to it). */
  constructor(furni: RoomFurni, def: FurniDef, floorZ = 0) {
    this.uid = furni.uid;
    this.def = def;
    this.data = furni;
    this.state = furni.state;
    this.dir = furni.dir;

    this.label = new Text({
      text: def.name,
      style: { fontFamily: 'Verdana, sans-serif', fontSize: 11, fontWeight: 'bold', fill: 0xffffff, stroke: { color: 0x000000, width: 3 } },
      resolution: 2,
    });
    this.label.anchor.set(0.5, 1);
    this.label.visible = false;
    this.container.addChild(this.sprite, this.label);
    this.place(furni, floorZ);

    void furniFrames(def.id).then((frames) => {
      if (this.destroyed || !frames) return;
      this.all = frames;
      this.pickDir();
    });
  }

  /** Put it somewhere (and facing some way). */
  place(furni: RoomFurni, floorZ = 0): void {
    this.data = furni;
    const def = this.def;
    // The offset is for its picture: mirrored with it.
    const images = def.dirs[furni.dir];
    const [ox0, oy] = def.offset ?? [0, 0];
    const ox = images && 'mirror' in images ? -ox0 : ox0;
    if (def.kind === 'wall') {
      // On the wall at the tile's x edge (direction 4) or y edge (2), `off` along it.
      const off = furni.off ?? 0.5;
      const [px, py] = furni.dir === 4 ? corner(furni.x, furni.y + off, floorZ + furni.z) : corner(furni.x + off, furni.y, floorZ + furni.z);
      this.container.position.set(px + ox, py + oy);
    } else {
      const [w, l] = furniFootprint(def, furni.dir);
      // Stands with its footprint's front corner on the floor (or hangs above it).
      const [px, py] = corner(furni.x + w, furni.y + l, furni.z + (def.hang ?? 0));
      this.container.position.set(px + ox, py + oy);
    }
    if (furni.dir !== this.dir) {
      this.dir = furni.dir;
      this.pickDir();
    }
    this.sortDepth();
  }

  /**
   * Floor furni sort with their front tile; rugs and mats lie flat on the floor (sorted with the
   * flat floor, just above it), so they never cover the feet of someone standing behind them.
   * Wall furni sort just in front of the wall pieces they cover (a wide picture covers the next
   * tile's piece too), behind anything standing on the floor.
   */
  private sortDepth(): void {
    const furni = this.data;
    const def = this.def;
    if (def.kind === 'wall') {
      const off = furni.off ?? 0.5;
      const f = this.frames[0];
      // Half the picture's width, in tiles along the wall (a tile's edge is 32 px wide on screen).
      const half = f ? (f.texture.width * (def.scale ?? 1)) / 2 / 32 : 0.5;
      const lastTile = Math.max(0, Math.floor(off + half - 0.001));
      this.container.zIndex = depthToZIndex(furni.x + furni.y + lastTile + 0.55);
    } else {
      const [w, l] = furniFootprint(def, furni.dir);
      const front = tileDepth(furni.x + w - 1, furni.y + l - 1);
      this.container.zIndex = depthToZIndex(def.walk ? front + 0.95 - FLAT_FLOOR_BELOW : front + 0.3 + (furni.z + (def.hang ?? 0)) * 0.01);
    }
  }

  /** Ghost look: see-through, red when it can't go there. */
  setGhost(ok: boolean): void {
    this.container.alpha = 0.7;
    this.sprite.tint = ok ? 0xffffff : 0xff6060;
  }

  /** Advance the animation. */
  update(now: number): void {
    const n = this.frames.length;
    if (n <= 1) return;
    const fps = this.def.fps ?? 8;
    if (this.def.once) {
      // Plays once from when the state started, then stays on its last frame.
      if (this.stateStart === -Infinity) return this.show(n - 1);
      if (this.stateStart === 0) this.stateStart = now;
      return this.show(Math.min(n - 1, Math.floor(((now - this.stateStart) / 1000) * fps)));
    }
    this.show(Math.floor((now / 1000) * fps) % n);
  }

  setState(state: number): void {
    this.state = state;
    this.data = { ...this.data, state };
    // The next update starts its animation from the beginning.
    this.stateStart = 0;
    this.show(0);
  }

  showName(show: boolean): void {
    this.label.visible = show;
  }

  /** Rough hit test in room coordinates: inside the picture's box. */
  hits(px: number, py: number): boolean {
    if (this.frames.length === 0 || !this.container.visible) return false;
    const b = this.sprite.getLocalBounds();
    const x = px - this.container.x;
    const y = py - this.container.y;
    const sx = this.sprite.scale.x;
    const left = sx < 0 ? -b.maxX * -sx : b.minX * sx;
    const right = sx < 0 ? -b.minX * -sx : b.maxX * sx;
    return x >= left && x <= right && y >= b.minY * this.sprite.scale.y && y <= b.maxY * this.sprite.scale.y;
  }

  destroy(): void {
    this.destroyed = true;
    this.container.destroy({ children: true });
  }

  private get frames(): FurniTexture[] {
    return this.states[Math.min(this.state, this.states.length - 1)] ?? [];
  }

  private pickDir(): void {
    if (!this.all) return;
    const images = this.def.dirs[this.dir];
    const source: FurniDir | undefined = images ? ('mirror' in images ? images.mirror : this.dir) : undefined;
    this.flip = !!images && 'mirror' in images;
    this.states = (source !== undefined && this.all[source]) || [];
    this.frameShown = -1;
    this.show(this.def.once && this.stateStart === -Infinity ? this.frames.length - 1 : 0);
  }

  private show(i: number): void {
    const f = this.frames[i];
    if (!f) return;
    if (f.texture === this.sprite.texture && i === this.frameShown) return;
    this.frameShown = i;
    const scale = this.def.scale ?? 1;
    this.sprite.texture = f.texture;
    // Floor furni stand on their front corner; wall furni hang by their middle.
    if (this.def.kind === 'wall') this.sprite.anchor.set(0.5, 0.5);
    else this.sprite.anchor.set(f.ax / f.texture.width, f.ay / f.texture.height);
    this.sprite.scale.set(this.flip ? -scale : scale, scale);
    this.label.y = (this.def.kind === 'wall' ? -f.texture.height / 2 : -f.ay) * scale - 4;
    if (this.def.kind === 'wall') this.sortDepth();
  }
}
