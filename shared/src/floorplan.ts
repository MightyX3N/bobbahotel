// Rules for floor plans made in the editor. Both sides use them: the editor to show problems
// while drawing, the server to refuse anything that breaks them.
export interface FloorPlanLimits {
  /** Grid size (columns, rows). */
  maxWidth: number;
  maxHeight: number;
  /** Highest floor step (0-35). */
  maxStep: number;
}

/** Staff can make big layouts; Bobba Club members reshape their own rooms within smaller limits. */
export const FLOORPLAN_LIMITS = {
  staff: { maxWidth: 64, maxHeight: 64, maxStep: 35 },
  club: { maxWidth: 24, maxHeight: 24, maxStep: 9 },
} as const satisfies Record<string, FloorPlanLimits>;

export type FloorPlanProblem =
  | 'plan_empty'
  | 'plan_too_big'
  | 'plan_bad_tiles'
  | 'plan_too_high'
  | 'plan_no_door'
  | 'plan_door_not_out';

/**
 * Checks a floor plan. Returns the first problem, or null if it's fine.
 * - map: rows of "x" (no floor) or 0-9/a-z (floor height), all rows the same length
 * - door: must be a floor tile that sticks out of the left wall (floor only to its right, Habbo-style)
 * Tiles don't have to be reachable from the door: teleporters and wired can take you there later.
 */
export function floorPlanProblem(map: string[], door: [number, number], limits: FloorPlanLimits): FloorPlanProblem | null {
  const h = map.length;
  const w = map[0]?.length ?? 0;
  if (h === 0 || w === 0) return 'plan_empty';
  if (w > limits.maxWidth || h > limits.maxHeight) return 'plan_too_big';
  if (map.some((row) => row.length !== w || !/^[0-9a-zx]+$/.test(row))) return 'plan_bad_tiles';
  const height = (x: number, y: number) => {
    const c = map[y]?.[x];
    return c === undefined || c === 'x' ? -1 : parseInt(c, 36);
  };
  let tiles = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const z = height(x, y);
      if (z < 0) continue;
      tiles++;
      if (z > limits.maxStep) return 'plan_too_high';
    }
  }
  if (tiles < 2) return 'plan_empty';
  const [dx, dy] = door;
  if (height(dx, dy) < 0) return 'plan_no_door';
  if (height(dx - 1, dy) >= 0 || height(dx, dy - 1) >= 0 || height(dx, dy + 1) >= 0 || height(dx + 1, dy) < 0) return 'plan_door_not_out';

  return null;
}

/** Club status: active until this time (ms since 1970), or not. */
export function clubDaysLeft(clubUntil: number, now = Date.now()): number {
  return clubUntil > now ? Math.ceil((clubUntil - now) / 86_400_000) : 0;
}
