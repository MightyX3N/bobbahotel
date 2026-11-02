// Every message between client and server is defined here, once. Both sides import this file,
// so they can't drift apart. The server checks every incoming message against its schema
// before acting on it.
//
// Wire format: JSON `{ "t": <type>, "d": <data> }`.
import { z } from 'zod';

/** Bump when a change means old clients can't talk to the new server. */
export const PROTOCOL_VERSION = 1;

/** Client -> server */
export const clientMessages = {
  hello: z.object({ protocol: z.number().int() }),
} satisfies Schemas;

/** Server -> client */
export const serverMessages = {
  welcome: z.object({ server: z.string(), protocol: z.number().int() }),
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
