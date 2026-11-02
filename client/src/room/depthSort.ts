// Drawing order of everything in a room, like Habbo (Nitro's RoomSpriteCanvas):
//
//   1. The doorway: the darkness behind the door, the door tile's floor and whoever stands in the
//      door are drawn behind the walls, and seen through the hole in the wall (Habbo moves
//      objects on the door tile 2000 tiles back for this).
//   2. The room: floor and walls, always behind every furni and avatar.
//   3. Wall furni (on the wall, so in front of it and behind everything standing in the room),
//      and furni lying flat on the floor (rugs).
//   4. Furni and avatars, back to front.
//
// In step 4 Habbo sorts by the tile something stands on (a furni: its back tile) plus a little
// for its height, and its furni come with hand-made depth values per picture layer that make
// furni covering several tiles overlap right. Our furni are one picture each without those, so
// the same result comes from comparing footprints: something standing entirely behind another
// thing's tiles (smaller x or smaller y) is drawn first; on the same tiles, lower first.

/** Bands of zIndex, one per step above; inside a band, the order within it. */
export const BAND = { door: -4e9, room: -3e9, onWall: -2e9, objects: 0 } as const;

/** Something standing in the room, for sorting: the tiles it covers and its height. */
export interface Sortable {
  /** Tiles covered: x0..x1, y0..y1 (whole tiles, inclusive). */
  x0: number;
  x1: number;
  y0: number;
  y1: number;
  /** Bottom and top, in height steps. */
  z0: number;
  z1: number;
  /**
   * Avatars sitting or lying on a furni: drawn in front of it on its own tiles (or behind it,
   * when sitting facing away, so its back covers their legs).
   */
  on?: { target: unknown; behind: boolean };
  /** Its own identity (what `on.target` points at). */
  self: unknown;
  /** A little extra in Habbo's tile order (avatars: in front of a furni they share a tile with). */
  bias?: number;
  /** Set by sortObjects: its place in the drawing order (0 = first). */
  order?: number;
}

/** Fallback order, Habbo's: the tile sum, then height. */
const key = (s: Sortable) => s.x0 + s.y0 + (s.x1 - s.x0 + s.y1 - s.y0) / 2 + s.z0 * 0.01 + (s.bias ?? 0);

/** -1: a is drawn before b; 1: after; 0: they can't overlap, either way. */
function compare(a: Sortable, b: Sortable): number {
  if (a.on && a.on.target === b.self) return a.on.behind ? -1 : 1;
  if (b.on && b.on.target === a.self) return b.on.behind ? 1 : -1;
  const aBehind = a.x1 < b.x0 || a.y1 < b.y0;
  const bBehind = b.x1 < a.x0 || b.y1 < a.y0;
  if (aBehind !== bBehind) return aBehind ? -1 : 1;
  if (aBehind && bBehind) return 0;
  // On the same tiles: lower things first (a lamp on a table).
  if (a.z1 <= b.z0 + 1e-6) return -1;
  if (b.z1 <= a.z0 + 1e-6) return 1;
  return Math.sign(key(a) - key(b));
}

/**
 * Puts things in drawing order (back to front) and sets each one's `order`. Everything that
 * must be behind something else is drawn first; the rest goes by Habbo's tile order.
 */
export function sortObjects(items: Sortable[]): void {
  const n = items.length;
  const before: number[][] = items.map(() => []);
  const waiting = new Array<number>(n).fill(0);
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      const c = compare(items[i]!, items[j]!);
      if (c < 0) {
        before[i]!.push(j);
        waiting[j]!++;
      } else if (c > 0) {
        before[j]!.push(i);
        waiting[i]!++;
      }
    }
  }
  const keys = items.map(key);
  const done = new Array<boolean>(n).fill(false);
  for (let order = 0; order < n; order++) {
    // The free item furthest back; if everything left waits on something (a loop, which only odd
    // shapes make), the one furthest back anyway.
    let pick = -1;
    for (let i = 0; i < n; i++) {
      if (done[i] || waiting[i]! > 0) continue;
      if (pick < 0 || keys[i]! < keys[pick]!) pick = i;
    }
    if (pick < 0) for (let i = 0; i < n; i++) if (!done[i] && (pick < 0 || keys[i]! < keys[pick]!)) pick = i;
    done[pick] = true;
    items[pick]!.order = order;
    for (const j of before[pick]!) waiting[j]!--;
  }
}
