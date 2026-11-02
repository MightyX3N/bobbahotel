// One furni in the room: its picture for its state (mirrored for mirrored directions), animated
// if that state has frames, depth-sorted with avatars and walls. Floor furni stand on their tiles;
// wall furni hang on the wall at the edge of their tile. Also used for the see-through "ghost"
// that follows the mouse while placing or moving a furni.
import { Container, Matrix, Point, Sprite, Text } from 'pixi.js';
import { furniFootprint, type FurniDef, type FurniDir, type RoomFurni } from '@bobba/shared';
import { corner } from './drawRoom.ts';
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
      // Things that stick out of the wall (a wall cabinet) have their back against it: their middle
      // is half their depth out from the wall, into the room.
      const d = (def.depth ?? 0) / 2;
      const [dx, dy] = furni.dir === 4 ? [32 * d, 16 * d] : [-32 * d, 16 * d];
      this.container.position.set(px + ox + dx, py + oy + dy);
    } else {
      const [w, l] = furniFootprint(def, furni.dir);
      // Its picture is pinned by the middle of its footprint (measured from the picture) to the
      // middle of its tiles, at the height it stands.
      const [px, py] = corner(furni.x + w / 2, furni.y + l / 2, furni.z);
      this.container.position.set(px + ox, py + oy);
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

  /** Hit test in room coordinates: on a solid pixel of its picture (like Habbo). */
  hits(px: number, py: number): boolean {
    const f = this.frames[this.frameShown] ?? this.frames[0];
    if (!f || !this.container.visible) return false;
    const local = this.sprite.localTransform.applyInverse(new Point(px - this.container.x, py - this.container.y));
    return f.solid(local.x + f.ax, local.y + f.ay);
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
    this.sprite.anchor.set(f.ax / f.texture.width, f.ay / f.texture.height);
    const images = this.def.dirs[this.dir];
    const source = images && 'mirror' in images ? this.def.dirs[images.mirror] : images;
    const stretch = source && 'states' in source ? source.stretch : undefined;
    if (stretch) {
      // Rugs: stretched along the floor's x and y on their own (tiles are 32 px across and 16
      // down per step along x, -32 and 16 along y), then mirrored like the picture.
      const [sx, sy] = stretch;
      const flip = this.flip ? -1 : 1;
      this.sprite.setFromMatrix(new Matrix(flip * ((sx + sy) / 2) * scale, ((sx - sy) / 4) * scale, flip * (sx - sy) * scale, ((sx + sy) / 2) * scale, 0, 0));
    } else {
      this.sprite.setFromMatrix(new Matrix(this.flip ? -scale : scale, 0, 0, scale, 0, 0));
    }
    this.label.y = (this.def.kind === 'wall' ? -f.texture.height / 2 : -f.ay) * scale - 4;
  }
}
