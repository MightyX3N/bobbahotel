import { describe, expect, it } from 'vitest';
import { clubDaysLeft, FLOORPLAN_LIMITS, floorPlanProblem } from './floorplan.ts';

const club = FLOORPLAN_LIMITS.club;

describe('floorPlanProblem', () => {
  it('accepts a room with a door sticking out of the left wall', () => {
    expect(floorPlanProblem(['x000', '0000', 'x000'], [0, 1], club)).toBeNull();
  });
  it('wants the door to stick out', () => {
    expect(floorPlanProblem(['0000', '0000'], [0, 0], club)).toBe('plan_door_not_out');
    expect(floorPlanProblem(['x000', 'x000'], [0, 0], club)).toBe('plan_no_door');
  });
  it('allows tiles you cannot walk to', () => {
    // Tiles you can't walk to are allowed (teleporters and wired can take you there).
    expect(floorPlanProblem(['x00x0', '000x0', 'x00x0'], [0, 1], club)).toBe(null);
    expect(floorPlanProblem(['x002', '0000'], [0, 1], club)).toBe(null); // a 2-step jump
  });
  it('keeps to the limits', () => {
    expect(floorPlanProblem(['x' + '0'.repeat(30), '0'.repeat(31)], [0, 1], club)).toBe('plan_too_big');
    expect(floorPlanProblem(['x' + '0'.repeat(30), '0'.repeat(31)], [0, 1], FLOORPLAN_LIMITS.staff)).toBeNull();
    expect(floorPlanProblem(['x0a', '000'], [0, 1], club)).toBe('plan_too_high');
    expect(floorPlanProblem(['x0Q', '000'], [0, 1], club)).toBe('plan_bad_tiles');
  });
});

describe('clubDaysLeft', () => {
  it('counts whole days, rounding up', () => {
    expect(clubDaysLeft(0, 1000)).toBe(0);
    expect(clubDaysLeft(1000 + 86_400_000 * 1.5, 1000)).toBe(2);
  });
});
