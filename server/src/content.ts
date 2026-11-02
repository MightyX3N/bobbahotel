// Content files (room layouts, public rooms and furni definitions), checked when the server starts.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { z } from 'zod';
import { furniDirs, furniFootprint, type FurniDef, type FurniSheet, type Layout, type RoomFurni } from '@bobba/shared';
import { loadFurniDefs } from './furni.ts';

const layoutSchema = z.object({
  id: z.string(),
  name: z.string(),
  map: z.array(z.string().regex(/^[0-9a-zA-Z]+$/)).min(1),
  door: z.tuple([z.number().int().min(0), z.number().int().min(0)]),
  maxUsers: z.number().int().positive().optional(),
  access: z.enum(['free', 'club', 'admin']).default('free'),
});

const roomsFileSchema = z.object({
  layouts: z.record(z.string(), layoutSchema),
  public: z.array(z.object({ id: z.string(), name: z.string(), description: z.string().optional(), layout: z.string() })),
});

export interface PublicRoom {
  id: string;
  name: string;
  description?: string;
  layout: Layout;
  /** Only staff can go in and see it in the navigator. */
  staffOnly?: boolean;
  furni?: RoomFurni[];
}

export interface Content {
  layouts: Map<string, Layout>;
  publicRooms: PublicRoom[];
  furni: Map<string, FurniDef>;
  /** Frame lists of the built furni sprite sheets (filled in once they are built). */
  furniSheets: Map<string, FurniSheet>;
  /** How building the sheets went (shown by /api/furni). */
  furniStatus: string;
}

export function loadContent(dir: string): Content {
  const file = roomsFileSchema.parse(JSON.parse(readFileSync(join(dir, 'rooms.json'), 'utf8')));
  const layouts = new Map<string, Layout>();
  for (const [id, raw] of Object.entries(file.layouts)) {
    const { maxUsers, ...rest } = raw;
    const layout: Layout = maxUsers === undefined ? rest : { ...rest, maxUsers };
    // Like Habbo, the door tile sticks out of the left wall: floor only to its right.
    const [dx, dy] = layout.door;
    const at = (x: number, y: number) => layout.map[y]?.[x] ?? 'x';
    if (at(dx, dy) === 'x') throw new Error(`Layout ${id}: the door is not on a floor tile`);
    if (at(dx - 1, dy) !== 'x' || at(dx, dy - 1) !== 'x' || at(dx, dy + 1) !== 'x' || at(dx + 1, dy) === 'x') {
      throw new Error(`Layout ${id}: the door tile must stick out of the left wall (floor only to its right)`);
    }
    layouts.set(id, layout);
  }
  const publicRooms: PublicRoom[] = file.public.map((p) => {
    const layout = layouts.get(p.layout);
    if (!layout) throw new Error(`Public room ${p.id}: unknown layout ${p.layout}`);
    return { id: p.id, name: p.name, ...(p.description ? { description: p.description } : {}), layout };
  });
  const furni = loadFurniDefs(dir);
  const test = furniTestRoom(furni);
  if (test) publicRooms.push(test);
  return { layouts, publicRooms, furni, furniSheets: new Map(), furniStatus: 'not built' };
}

/**
 * The furni test room (staff only): every floor furni once, in its default direction, in rows
 * with a free tile around each, so sizes and looks can be checked side by side.
 */
export function furniTestRoom(defs: Map<string, FurniDef>): PublicRoom | null {
  const floor = [...defs.values()].filter((d) => d.kind === 'floor');
  if (floor.length === 0) return null;
  const ROW_WIDTH = 40;
  const placed: RoomFurni[] = [];
  let x = 2;
  let y = 2;
  let rowDepth = 0;
  for (const def of floor) {
    const dir = furniDirs(def)[0] ?? 4;
    const [w, l] = furniFootprint(def, dir);
    if (x > 2 && x + w > ROW_WIDTH) {
      x = 2;
      y += rowDepth + 1;
      rowDepth = 0;
    }
    // Shown in its liveliest state (an animation rather than switched off); double-click to change.
    const images = def.dirs[dir];
    const states = images && 'states' in images ? images.states : [];
    const state = states.reduce((best, frames, i) => (frames.length > (states[best]?.length ?? 0) ? i : best), 0);
    placed.push({ uid: placed.length + 1, def: def.id, x, y, z: 0, dir, state });
    x += w + 1;
    rowDepth = Math.max(rowDepth, l);
  }
  const cols = ROW_WIDTH + 2;
  const rows = y + rowDepth + 2;
  const map = Array.from({ length: rows }, (_, r) => (r === 1 ? '0' : 'x') + '0'.repeat(cols - 1));
  map[0] = 'x'.repeat(cols);
  map[rows - 1] = 'x'.repeat(cols);
  const layout: Layout = { id: 'pub_furni_test', name: 'Furni test', map, door: [0, 1], access: 'admin', maxUsers: 25 };
  return { id: 'furni_test', name: 'Furni test', description: 'Every furni, to check how they look', layout, staffOnly: true, furni: placed };
}
