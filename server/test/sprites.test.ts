// Checks LOOK_PARTS against the real Cozy sprite files. The sprites are licensed and not in git,
// so this only runs where a local sprites/ folder exists (skipped in CI).
import { existsSync, readdirSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { LOOK_PARTS, lookLayers, type Look, type Pose } from '@bobba/shared';

const dir = new URL('../../sprites/', import.meta.url);
const have = existsSync(new URL('cozy/', dir));

describe.skipIf(!have)('Cozy sprite files', () => {
  it('has exactly the parts LOOK_PARTS says', () => {
    for (const sex of ['m', 'f'] as const) {
      for (const pose of ['idle', 'walk', 'sit'] as const) {
        const files = readdirSync(new URL(`cozy/${sex}/${pose}/`, dir));
        for (const [part, count] of Object.entries(LOOK_PARTS[sex])) {
          const n = files.filter((f) => new RegExp(`^${part}_\\d\\d\\.png$`).test(f)).length;
          expect(`${sex}/${pose}/${part}: ${n}`).toBe(`${sex}/${pose}/${part}: ${count}`);
        }
      }
    }
  });

  it('every layer of every look exists', () => {
    for (const sex of ['m', 'f'] as const) {
      const max = LOOK_PARTS[sex];
      for (let hair = 0; hair <= max.hair; hair++) {
        for (let top = 0; top <= max.top; top++) {
          const look: Look = { sex, body: 1, hair, top, bottom: 1, shoes: 1 };
          for (const pose of ['idle', 'walk', 'sit'] as Pose[]) {
            for (const layer of lookLayers(look, pose)) expect(existsSync(new URL(layer, dir)), layer).toBe(true);
          }
        }
      }
    }
  });
});
