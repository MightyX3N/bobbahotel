import { describe, expect, it } from 'vitest';
import { deflateRawSync } from 'node:zlib';
import { readZip, safeTarget } from '../src/art.ts';

/** A small zip (deflated entries) for the tests. */
function makeZip(files: Record<string, string>): Buffer {
  const locals: Buffer[] = [];
  const centrals: Buffer[] = [];
  let offset = 0;
  for (const [name, text] of Object.entries(files)) {
    const raw = Buffer.from(text);
    const data = deflateRawSync(raw);
    const n = Buffer.from(name);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(8, 8); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(raw.length, 22); local.writeUInt16LE(n.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(8, 10); central.writeUInt32LE(data.length, 20); central.writeUInt32LE(raw.length, 24); central.writeUInt16LE(n.length, 28); central.writeUInt32LE(offset, 42);
    locals.push(local, n, data);
    centrals.push(central, n);
    offset += 30 + n.length + data.length;
  }
  const cd = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(Object.keys(files).length, 8); end.writeUInt16LE(Object.keys(files).length, 10); end.writeUInt32LE(cd.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, cd, end]);
}

describe('art packs', () => {
  it('takes only pictures inside the pack folders', () => {
    expect(safeTarget('casino/poker_table.png')).toBe('casino/poker_table.png');
    expect(safeTarget('city/6_PHC_Props_Floor_Tiles/Bench.png')).toBe('city/6_PHC_Props_Floor_Tiles/Bench.png');
    expect(safeTarget('../etc/passwd.png')).toBeNull();
    expect(safeTarget('casino/../../x.png')).toBeNull();
    expect(safeTarget('/casino/x.png')).toBeNull();
    expect(safeTarget('web/src/app.png')).toBeNull();
    expect(safeTarget('casino/run.sh')).toBeNull();
    expect(safeTarget('casino/.hidden.png')).toBeNull();
    expect(safeTarget('poker.png')).toBeNull();
  });

  it('reads a zip, skipping one folder around the packs', () => {
    const zip = makeZip({ 'packs/casino/a.png': 'AAA', 'packs/cats/b.png': 'BB', 'packs/notes.doc': 'x', 'packs/__MACOSX/cats/._b.png': 'm' });
    const entries = readZip(zip);
    const taken = entries.filter((e) => e.target);
    expect(taken.map((e) => e.target)).toEqual(['casino/a.png', 'cats/b.png']);
    expect(taken[0]!.read().toString()).toBe('AAA');
  });

  it('refuses what is not a zip', () => {
    expect(() => readZip(Buffer.from('hello, not a zip at all, just some text to be long enough'))).toThrow('not_a_zip');
  });
});
