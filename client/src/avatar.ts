// Shared avatar rules: which sprite layers a look is made of (the room and the wardrobe both use this).
export type Look = { sex: string; body: number; hair: number; top: number; bottom: number; shoes: number };
export const FW = 64, FH = 80, AX = 32, AY = 75; // frame size; where the feet are
/** facing (0=N .. 7=NW clockwise) -> sheet row (0 down-left, 1 down-right, 2 up-right, 3 up-left) */
export const ROW = [2, 2, 1, 1, 0, 0, 3, 3];
const TUCKED: Record<string, number[]> = { f: [1, 3, 5, 6, 7, 8], m: [] }; // hairstyles that have a "tucked" version for tops 13-15
const two = (n: number) => String(n).padStart(2, '0');
export const SLOTS = [['hair', 10], ['top', 15], ['bottom', 10], ['shoes', 10]] as const;

/** Layer pictures bottom to top. skip = slots to leave out (for piece previews). */
export function layerPaths(l: Look, anim: string, only?: string): string[] {
  const f = (part: string, n: number, suf = '') => `cozy/${l.sex}/${anim}/${part}_${two(n)}${suf}.png`;
  if (only === 'body') return [f('body', l.body)];
  const out = [f('body', l.body)];
  if (l.shoes) out.push(f('shoes', l.shoes));
  if (l.bottom) out.push(f('bottom', l.bottom));
  const high = l.top >= 13, tucked = high && TUCKED[l.sex]?.includes(l.hair);
  const hair = l.hair ? f('hair', l.hair, tucked ? '_tucked' : '') : null;
  if (high && hair) out.push(hair);
  if (l.top) out.push(f('top', l.top));
  if (!high && hair) out.push(hair);
  return out;
}
