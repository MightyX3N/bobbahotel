// Content files (room layouts and public rooms), checked when the server starts.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { z } from 'zod';
import type { Layout } from '@bobba/shared';

const layoutSchema = z.object({
  id: z.string(),
  name: z.string(),
  map: z.array(z.string().regex(/^[0-9a-zA-Z]+$/)).min(1),
  door: z.tuple([z.number().int().min(0), z.number().int().min(0)]),
  maxUsers: z.number().int().positive().optional(),
});

const roomsFileSchema = z.object({
  layouts: z.record(z.string(), layoutSchema),
  public: z.array(z.object({ id: z.string(), name: z.string(), description: z.string().optional(), layout: z.string() })),
});

export interface Content {
  layouts: Map<string, Layout>;
  publicRooms: { id: string; name: string; layout: Layout }[];
}

export function loadContent(dir: string): Content {
  const file = roomsFileSchema.parse(JSON.parse(readFileSync(join(dir, 'rooms.json'), 'utf8')));
  const layouts = new Map<string, Layout>();
  for (const [id, raw] of Object.entries(file.layouts)) {
    const { maxUsers, ...rest } = raw;
    const layout: Layout = maxUsers === undefined ? rest : { ...rest, maxUsers };
    const [dx, dy] = layout.door;
    const doorRow = layout.map[dy];
    if (!doorRow || doorRow[dx] === undefined || doorRow[dx] === 'x') throw new Error(`Layout ${id}: the door is not on a floor tile`);
    layouts.set(id, layout);
  }
  const publicRooms = file.public.map((p) => {
    const layout = layouts.get(p.layout);
    if (!layout) throw new Error(`Public room ${p.id}: unknown layout ${p.layout}`);
    return { id: p.id, name: p.name, layout };
  });
  return { layouts, publicRooms };
}
