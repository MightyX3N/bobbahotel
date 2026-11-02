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
    const [ox, oy] = def.offset ?? [0, 0];
    if (def.kind === 'wall') {
      // On the wall at the tile's x edge (direction 4) or y edge (2), `off` along it.
      const off = furni.off ?? 0.5;
      const [px, py] = furni.dir === 4 ? corner(furni.x, furni.y + off, floorZ + furni.z) : corner(furni.x + off, furni.y, floorZ + furni.z);
      this.container.position.set(px + ox, py + oy);
      // Just in front of its piece of wall, behind anything standing on the floor.
      this.container.zIndex = depthToZIndex(furni.x + furni.y + off + 0.45);
    } else {
      const [w, l] = furniFootprint(def, furni.dir);
      // Stands with its footprint's front corner on the floor; sorts with its front tile.
      const [px, py] = corner(furni.x + w, furni.y + l, furni.z);
      this.container.position.set(px + ox, py + oy);
      // Rugs and mats lie flat on the floor: sorted with the flat floor (just above it), so they
      // never cover the feet of someone standing behind them.
      const front = tileDepth(furni.x + w - 1, furni.y + l - 1);
      this.container.zIndex = depthToZIndex(def.walk ? front + 0.95 - FLAT_FLOOR_BELOW : front + 0.3 + furni.z * 0.01);
    }
    if (furni.dir !== this.dir) {
      this.dir = furni.dir;
      this.pickDir();
    }
  }

  /** Ghost look: see-through, red when it can't go there. */
  setGhost(ok: boolean): void {
    this.container.alpha = 0.7;
    this.sprite.tint = ok ? 0xffffff : 0xff6060;
  }

  /** Advance the animation. */
  update(now: number): void {
    if (this.frames.length > 1) this.show(Math.floor((now / 1000) * (this.def.fps ?? 8)) % this.frames.length);
  }

  setState(state: number): void {
    this.state = state;
    this.data = { ...this.data, state };
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
    this.show(0);
  }

  private show(i: number): void {
    const f = this.frames[i];
    if (!f) return;
    const scale = this.def.scale ?? 1;
    this.sprite.texture = f.texture;
    // Floor furni stand on their front corner; wall furni hang by their middle.
    if (this.def.kind === 'wall') this.sprite.anchor.set(0.5, 0.5);
    else this.sprite.anchor.set(f.ax / f.texture.width, f.ay / f.texture.height);
    this.sprite.scale.set(this.flip ? -scale : scale, scale);
    this.label.y = (this.def.kind === 'wall' ? -f.texture.height / 2 : -f.ay) * scale - 4;
  }
}
