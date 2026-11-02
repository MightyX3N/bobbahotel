// How an avatar looks: the Cozy Assets parts. Both sides use these rules: the server to check a
// look, the client to know which sprite layers to draw.
import { z } from 'zod';

/** How many of each part exist, per body type. 0 for hair/top/bottom/shoes = none. */
export const LOOK_PARTS = {
  m: { body: 4, hair: 10, top: 15, bottom: 10, shoes: 10 },
  f: { body: 4, hair: 16, top: 15, bottom: 10, shoes: 10 },
} as const;

/** Tops from this number up are high-necked: hair is drawn under them (tucked version if there is one). */
const HIGH_TOP = 13;
/** Hairstyles that have a "_tucked" version for high tops. */
const TUCKED: Record<Sex, readonly number[]> = { m: [], f: [1, 3, 5, 6, 7, 8] };

export type Sex = keyof typeof LOOK_PARTS;

export const lookSchema = z
  .object({
    sex: z.enum(['m', 'f']),
    body: z.number().int(),
    hair: z.number().int(),
    top: z.number().int(),
    bottom: z.number().int(),
    shoes: z.number().int(),
  })
  .refine((l) => {
    const max = LOOK_PARTS[l.sex];
    return (
      l.body >= 1 && l.body <= max.body &&
      [l.hair, l.top, l.bottom, l.shoes].every((n) => n >= 0) &&
      l.hair <= max.hair && l.top <= max.top && l.bottom <= max.bottom && l.shoes <= max.shoes
    );
  }, 'part out of range');

export type Look = z.output<typeof lookSchema>;

export type Pose = 'idle' | 'walk' | 'sit';

/** Sprite sheet layout: 8 frames across, 4 directions down, each frame 64x80, feet at (32, 75). */
export const AVATAR_FRAME = { w: 64, h: 80, footX: 32, footY: 75, frames: 8 } as const;

/** Facing 0-7 (see DIRS) -> sheet row (0 down-left, 1 down-right, 2 up-right, 3 up-left). */
export const SHEET_ROW = [2, 2, 1, 1, 0, 0, 3, 3] as const;

/** The sprite files for a look and pose, bottom layer first, relative to /sprites/. */
export function lookLayers(look: Look, pose: Pose): string[] {
  const file = (part: string, n: number, suffix = '') =>
    `cozy/${look.sex}/${pose}/${part}_${String(n).padStart(2, '0')}${suffix}.png`;
  const layers = [file('body', look.body)];
  if (look.shoes) layers.push(file('shoes', look.shoes));
  if (look.bottom) layers.push(file('bottom', look.bottom));
  const high = look.top >= HIGH_TOP;
  const hair = look.hair ? file('hair', look.hair, high && TUCKED[look.sex].includes(look.hair) ? '_tucked' : '') : null;
  if (high && hair) layers.push(hair);
  if (look.top) layers.push(file('top', look.top));
  if (!high && hair) layers.push(hair);
  return layers;
}

/** A random everyday look for a new account. */
export function randomLook(random: () => number = Math.random): Look {
  const sex: Sex = random() < 0.5 ? 'm' : 'f';
  const pick = (n: number) => 1 + Math.floor(random() * n);
  const max = LOOK_PARTS[sex];
  return { sex, body: pick(max.body), hair: pick(max.hair), top: pick(HIGH_TOP - 1), bottom: pick(max.bottom), shoes: pick(max.shoes) };
}
