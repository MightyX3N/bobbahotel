import { describe, expect, it } from 'vitest';
import { clientMessages, encodeMessage, parseMessage, PROTOCOL_VERSION } from './protocol.ts';

describe('parseMessage', () => {
  it('accepts a valid message', () => {
    const raw = encodeMessage({ t: 'hello', d: { protocol: PROTOCOL_VERSION } });
    expect(parseMessage(clientMessages, raw)).toEqual({ t: 'hello', d: { protocol: PROTOCOL_VERSION } });
  });

  it.each([
    ['not JSON', '{nope'],
    ['not an object', '42'],
    ['null', 'null'],
    ['unknown type', '{"t":"teleport","d":{}}'],
    ['inherited key as type', '{"t":"toString","d":{}}'],
    ['wrong data', '{"t":"hello","d":{"protocol":"1"}}'],
    ['missing data', '{"t":"hello"}'],
  ])('rejects %s', (_name, raw) => {
    expect(parseMessage(clientMessages, raw)).toBeNull();
  });
});
