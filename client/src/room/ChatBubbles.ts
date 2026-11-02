// Chat bubbles, the Habbo way: a new bubble appears above the speaker's head and pushes the older
// ones up; every few seconds they all drift up a line until they leave the screen.
import { Container, Graphics, Text } from 'pixi.js';

const LINE = 26;
const DRIFT_MS = 4000;
const PAD_X = 8;
const MAX_TEXT_W = 320;

interface Bubble {
  container: Container;
  targetY: number;
}

export class ChatBubbles {
  readonly container = new Container();
  private bubbles: Bubble[] = [];
  private lastDrift = 0;

  /** x, y: screen point above the speaker's head. */
  add(name: string, text: string, x: number, y: number, screenWidth: number, now: number): void {
    const bubble = new Container();
    const nameText = new Text({ text: `${name}: `, style: { fontFamily: 'Verdana, sans-serif', fontSize: 11, fontWeight: 'bold', fill: 0x000000 }, resolution: 2 });
    const body = new Text({
      text,
      style: { fontFamily: 'Verdana, sans-serif', fontSize: 11, fill: 0x000000, wordWrap: false },
      resolution: 2,
    });
    if (nameText.width + body.width > MAX_TEXT_W) body.text = fit(body, text, MAX_TEXT_W - nameText.width);
    nameText.position.set(PAD_X, 5);
    body.position.set(PAD_X + nameText.width, 5);
    const w = Math.ceil(PAD_X * 2 + nameText.width + body.width);
    const h = 22;
    const bg = new Graphics()
      .roundRect(0, 0, w, h, 6)
      .fill(0xffffff)
      .stroke({ color: 0x000000, width: 1, alignment: 1 })
      .poly([w / 2 - 5, h, w / 2 + 5, h, w / 2, h + 5])
      .fill(0xffffff);
    bubble.addChild(bg, nameText, body);
    bubble.x = Math.round(Math.min(Math.max(4, x - w / 2), screenWidth - w - 4));

    // Push everything up so the new bubble has its own line.
    const spawnY = Math.round(y - h - 8);
    for (const b of this.bubbles) b.targetY = Math.min(b.targetY, spawnY) - LINE;
    bubble.y = spawnY;
    this.bubbles.push({ container: bubble, targetY: spawnY });
    this.container.addChild(bubble);
    this.lastDrift = now;
  }

  update(now: number): void {
    if (this.bubbles.length && now - this.lastDrift > DRIFT_MS) {
      this.lastDrift = now;
      for (const b of this.bubbles) b.targetY -= LINE;
    }
    for (const b of this.bubbles) {
      const c = b.container;
      c.y += (b.targetY - c.y) * 0.25;
      if (Math.abs(c.y - b.targetY) < 0.5) c.y = b.targetY;
    }
    const gone = this.bubbles.filter((b) => b.container.y < -40);
    for (const b of gone) b.container.destroy({ children: true });
    this.bubbles = this.bubbles.filter((b) => b.container.y >= -40);
  }

  clear(): void {
    for (const b of this.bubbles) b.container.destroy({ children: true });
    this.bubbles = [];
  }
}

function fit(t: Text, text: string, maxW: number): string {
  let s = text;
  while (s.length > 1) {
    s = s.slice(0, -1);
    t.text = `${s}…`;
    if (t.width <= maxW) return t.text;
  }
  return t.text;
}
