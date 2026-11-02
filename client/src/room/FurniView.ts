// One furni in the room: its picture for its state (mirrored for mirrored directions), animated
// if that state has frames, standing on its tiles and depth-sorted with avatars and walls.
import { Container, Sprite, Text } from 'pixi.js';
import { furniFootprint, type FurniDef, type FurniDir, type RoomFurni } from '@bobba/shared';
import { corner, depthToZIndex, tileDepth } from './drawRoom.ts';
import { furniFrames, type FurniTexture } from './furniAssets.ts';

export class FurniView {
  readonly uid: number;
  readonly def: FurniDef;
  readonly container = new Container();
  private readonly sprite = new Sprite();
  private readonly label: Text;
  private states: FurniTexture[][] = [];
  private state: number;
  private flip = false;
  private destroyed = false;

  constructor(furni: RoomFurni, def: FurniDef) {
    this.uid = furni.uid;
    this.def = def;
    this.state = furni.state;
    const dir = furni.dir;
    const [w, l] = furniFootprint(def, dir);
    // Stands with its footprint's front corner on the floor; sorts with its front tile.
    const [px, py] = corner(furni.x + w, furni.y + l, furni.z);
    const [ox, oy] = def.offset ?? [0, 0];
    this.container.position.set(px + ox, py + oy);
    this.container.zIndex = depthToZIndex(tileDepth(furni.x + w - 1, furni.y + l - 1) + 0.3);

    this.label = new Text({
      text: def.name,
      style: { fontFamily: 'Verdana, sans-serif', fontSize: 11, fontWeight: 'bold', fill: 0xffffff, stroke: { color: 0x000000, width: 3 } },
      resolution: 2,
    });
    this.label.anchor.set(0.5, 1);
    this.label.visible = false;
    this.container.addChild(this.sprite, this.label);

    const images = def.dirs[dir];
    const source: FurniDir | undefined = images ? ('mirror' in images ? images.mirror : dir) : undefined;
    this.flip = !!images && 'mirror' in images;
    if (source === undefined) return;
    void furniFrames(def.id).then((frames) => {
      if (this.destroyed || !frames) return;
      this.states = frames[source] ?? [];
      this.show(0);
    });
  }

  /** Advance the animation. */
  update(now: number): void {
    if (this.frames.length > 1) this.show(Math.floor((now / 1000) * (this.def.fps ?? 8)) % this.frames.length);
  }

  setState(state: number): void {
    this.state = state;
    this.show(0);
  }

  private get frames(): FurniTexture[] {
    return this.states[Math.min(this.state, this.states.length - 1)] ?? [];
  }

  showName(show: boolean): void {
    this.label.visible = show;
  }

  /** Rough hit test in room coordinates: inside the picture's box. */
  hits(px: number, py: number): boolean {
    if (this.frames.length === 0) return false;
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

  private show(i: number): void {
    const f = this.frames[i];
    if (!f) return;
    const scale = this.def.scale ?? 1;
    this.sprite.texture = f.texture;
    this.sprite.anchor.set(f.ax / f.texture.width, f.ay / f.texture.height);
    this.sprite.scale.set(this.flip ? -scale : scale, scale);
    this.label.y = -f.ay * scale - 4;
  }
}
