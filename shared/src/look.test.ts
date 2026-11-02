import { describe, expect, it } from 'vitest';
import { lookLayers, lookSchema, randomLook } from './look.ts';
import { cleanChat, nameProblem } from './protocol.ts';

describe('looks', () => {
  it('random looks are always valid', () => {
    for (let i = 0; i < 200; i++) expect(lookSchema.safeParse(randomLook()).success).toBe(true);
  });

  it('rejects parts that do not exist', () => {
    expect(lookSchema.safeParse({ sex: 'm', body: 1, hair: 11, top: 1, bottom: 1, shoes: 1 }).success).toBe(false);
    expect(lookSchema.safeParse({ sex: 'f', body: 1, hair: 16, top: 1, bottom: 1, shoes: 1 }).success).toBe(true);
  });

  it('puts hair under high tops, tucked when available', () => {
    expect(lookLayers({ sex: 'f', body: 1, hair: 3, top: 14, bottom: 2, shoes: 0 }, 'walk')).toEqual([
      'cozy/f/walk/body_01.png',
      'cozy/f/walk/bottom_02.png',
      'cozy/f/walk/hair_03_tucked.png',
      'cozy/f/walk/top_14.png',
    ]);
    expect(lookLayers({ sex: 'm', body: 2, hair: 1, top: 1, bottom: 1, shoes: 1 }, 'idle').at(-1)).toBe('cozy/m/idle/hair_01.png');
  });
});

describe('text rules', () => {
  it('checks names', () => {
    expect(nameProblem('Bo')).toBe('too_short');
    expect(nameProblem('Bobba-Fan:1')).toBeNull();
    expect(nameProblem('no spaces')).toBe('bad_characters');
  });

  it('cleans chat', () => {
    expect(cleanChat('  hi\u0000   there\n ')).toBe('hi there');
    expect(cleanChat('x'.repeat(300))).toHaveLength(100);
  });
});
