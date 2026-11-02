import { describe, expect, it } from 'vitest';
import { findPath, tileKey } from './path.ts';
import { doorFacing, parseMap } from './room.ts';

const flat = parseMap(['00000', '00000', '00000', '00000', '00000']);

describe('findPath', () => {
  it('walks diagonally on open floor', () => {
    expect(findPath(flat, 0, 0, 3, 3)).toEqual([
      [1, 1],
      [2, 2],
      [3, 3],
    ]);
  });

  it('returns an empty path when already there', () => {
    expect(findPath(flat, 2, 2, 2, 2)).toEqual([]);
  });

  it('refuses missing floor and blocked targets', () => {
    const g = parseMap(['00x', '000']);
    expect(findPath(g, 0, 0, 2, 0)).toBeNull();
    expect(findPath(flat, 0, 0, 4, 4, { blocked: new Set([tileKey(4, 4)]) })).toBeNull();
  });

  it('does not cut corners past missing floor', () => {
    const g = parseMap(['0x', '00']);
    // (0,0) -> (1,1) diagonally would cut past the hole at (1,0)
    expect(findPath(g, 0, 0, 1, 1)).toEqual([
      [0, 1],
      [1, 1],
    ]);
  });

  it('goes around avatars', () => {
    const path = findPath(flat, 0, 2, 4, 2, { blocked: new Set([tileKey(2, 2)]) })!;
    expect(path.at(-1)).toEqual([4, 2]);
    expect(path).not.toContainEqual([2, 2]);
  });

  it('climbs one step at a time but not two', () => {
    expect(findPath(parseMap(['012']), 0, 0, 2, 0)).toEqual([
      [1, 0],
      [2, 0],
    ]);
    expect(findPath(parseMap(['02']), 0, 0, 1, 0)).toBeNull();
  });

  it('finds the way across the lobby', () => {
    const lobby = parseMap([
      '11111111xxxxxx',
      '11111111000000',
      '11111111000000',
      '00000000000000',
      '00000000000000',
    ]);
    const path = findPath(lobby, 13, 4, 0, 0)!;
    expect(path.at(-1)).toEqual([0, 0]);
  });
});

describe('doorFacing', () => {
  it('faces into the room', () => {
    expect(doorFacing(parseMap(['000', '000']), [0, 1])).toBe(2);
  });
});
