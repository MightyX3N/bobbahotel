// Every message between client and server is defined here, once. Both sides import this file,
// so they can't drift apart. The server checks every incoming message against its schema
// before acting on it.
//
// Wire format: JSON `{ "t": <type>, "d": <data> }`.
import { z } from 'zod';
import { lookSchema } from './look.ts';

/** Bump when a change means old clients can't talk to the new server. */
export const PROTOCOL_VERSION = 2;

export const CHAT_MAX = 100;
export const NAME_MIN = 3;
export const NAME_MAX = 15;
/** Characters allowed in hotel names. */
export const NAME_PATTERN = /^[A-Za-z0-9_\-=?!@:.,]+$/;

const tile = z.number().int().min(0).max(4095);

export const roomUserSchema = z.object({
  id: z.number().int(),
  name: z.string(),
  look: lookSchema,
  x: z.number().int(),
  y: z.number().int(),
  z: z.number(),
  dir: z.number().int().min(0).max(7),
});
export type RoomUser = z.output<typeof roomUserSchema>;

export const ROOM_NAME_MIN = 3;
export const ROOM_NAME_MAX = 30;
export const ROOM_DESC_MAX = 128;

const roomId = z.string().min(1).max(40);

export const roomInfoSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string(),
  /** Owner's name; null for public rooms. */
  owner: z.string().nullable(),
  users: z.number().int(),
  maxUsers: z.number().int(),
});
export type RoomInfo = z.output<typeof roomInfoSchema>;

export const layoutInfoSchema = z.object({
  id: z.string(),
  name: z.string(),
  map: z.array(z.string()),
  door: z.tuple([z.number().int(), z.number().int()]),
  maxUsers: z.number().int(),
  club: z.boolean(),
  /** Made in the editor (staff can change or remove it); false for the built-in layouts. */
  custom: z.boolean(),
});
export type LayoutInfo = z.output<typeof layoutInfoSchema>;

export const meSchema = z.object({
  id: z.number().int(),
  name: z.string(),
  guest: z.boolean(),
  staff: z.boolean(),
  /** Bobba Club runs until this time (ms since 1970); 0 = no Club. */
  clubUntil: z.number(),
});
export type Me = z.output<typeof meSchema>;

const floorPlan = z.object({
  map: z.array(z.string().max(64)).max(64),
  door: z.tuple([z.number().int().min(0).max(63), z.number().int().min(0).max(63)]),
});

export const NAVIGATOR_TABS = ['public', 'all', 'mine'] as const;
export type NavigatorTab = (typeof NAVIGATOR_TABS)[number];

/** Client -> server */
export const clientMessages = {
  /** Room list for a navigator tab, optionally searched by name. */
  navigator: z.object({ tab: z.enum(NAVIGATOR_TABS), query: z.string().max(40).optional() }),
  /** The layouts a new room can be built from. */
  layouts: z.object({}),
  createRoom: z.object({ name: z.string().max(ROOM_NAME_MAX * 2), description: z.string().max(ROOM_DESC_MAX * 2), layout: z.string().max(40) }),
  goToRoom: z.object({ id: roomId }),
  /** Staff: save a layout made in the editor (new, or update a custom one by id). */
  saveLayout: floorPlan.extend({ id: z.string().max(40).optional(), name: z.string().max(60), club: z.boolean() }),
  /** Staff: remove a custom layout. */
  deleteLayout: z.object({ id: z.string().max(40) }),
  /** Owner with Bobba Club (or staff): give a room its own floor plan. */
  saveRoomFloor: floorPlan.extend({ roomId }),
  hello: z.object({ protocol: z.number().int() }),
  /** Walk to a tile. */
  walk: z.object({ x: tile, y: tile }),
  /** Say something in the room. */
  chat: z.object({ text: z.string().max(CHAT_MAX * 2) }),
} satisfies Schemas;

/** Server -> client */
export const serverMessages = {
  welcome: z.object({
    server: z.string(),
    protocol: z.number().int(),
    me: meSchema,
  }),
  navigator: z.object({ tab: z.enum(NAVIGATOR_TABS), query: z.string(), rooms: z.array(roomInfoSchema) }),
  layouts: z.object({ layouts: z.array(layoutInfoSchema) }),
  roomCreated: z.object({ id: z.string() }),
  layoutSaved: z.object({ id: z.string() }),
  /** Your account changed (e.g. Bobba Club was granted). */
  me: meSchema,
  /** Something worked; shown as a short notice (text from the language file). */
  info: z.object({ code: z.string(), vars: z.record(z.string(), z.union([z.string(), z.number()])).optional() }),
  /** You entered a room: everything needed to draw it. */
  room: z.object({
    id: z.string(),
    name: z.string(),
    description: z.string(),
    owner: z.string().nullable(),
    ownerId: z.number().int().nullable(),
    map: z.array(z.string()),
    door: z.tuple([z.number().int(), z.number().int()]),
    users: z.array(roomUserSchema),
  }),
  userJoin: roomUserSchema,
  userLeave: z.object({ id: z.number().int() }),
  /**
   * Sent every room tick (500 ms) for avatars that moved or stopped. `moving` means "now walking
   * to this tile": the client animates from where the avatar is to (x, y, z) over one tick.
   */
  status: z.array(
    z.object({
      id: z.number().int(),
      x: z.number().int(),
      y: z.number().int(),
      z: z.number(),
      dir: z.number().int().min(0).max(7),
      moving: z.boolean(),
    }),
  ),
  chat: z.object({ id: z.number().int(), text: z.string() }),
  error: z.object({ code: z.string(), message: z.string() }),
} satisfies Schemas;

export type Schemas = Record<string, z.ZodType>;

export type MessageOf<S extends Schemas> = {
  [K in keyof S & string]: { t: K; d: z.output<S[K]> };
}[keyof S & string];

export type ClientMessage = MessageOf<typeof clientMessages>;
export type ServerMessage = MessageOf<typeof serverMessages>;

/** Picks out one message's data type, e.g. `DataOf<ServerMessage, 'welcome'>`. */
export type DataOf<M extends { t: string; d: unknown }, T extends M['t']> = Extract<M, { t: T }>['d'];

/** Parses and checks one raw message. Returns null for anything malformed or unknown. */
export function parseMessage<S extends Schemas>(schemas: S, raw: string): MessageOf<S> | null {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof value !== 'object' || value === null) return null;
  const { t, d } = value as { t?: unknown; d?: unknown };
  if (typeof t !== 'string' || !Object.hasOwn(schemas, t)) return null;
  const result = schemas[t]!.safeParse(d);
  if (!result.success) return null;
  return { t, d: result.data } as MessageOf<S>;
}

export function encodeMessage(message: ClientMessage | ServerMessage): string {
  return JSON.stringify(message);
}

/** Checks a hotel name. Returns an error key, or null if the name is fine. */
export function nameProblem(name: string): 'too_short' | 'too_long' | 'bad_characters' | null {
  if (name.length < NAME_MIN) return 'too_short';
  if (name.length > NAME_MAX) return 'too_long';
  if (!NAME_PATTERN.test(name)) return 'bad_characters';
  return null;
}

/** Control characters, zero-width and direction-changing characters. */
const INVISIBLE = new RegExp('[\\u0000-\\u001f\\u007f-\\u009f\\u200b-\\u200f\\u2028-\\u202e\\u2066-\\u2069\\ufeff]', 'g');

/** Cleans chat text: no control characters, collapsed spaces, at most CHAT_MAX characters. */
export function cleanChat(text: string): string {
  return text.replace(INVISIBLE, '').replace(/\s+/g, ' ').trim().slice(0, CHAT_MAX);
}
