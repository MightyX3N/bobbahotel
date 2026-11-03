#!/usr/bin/env python3
"""Checks what the game downloaded and unpacked: reads each raw Habbo SWF in
garrysmod/data/bobbahotel/habbo/raw with its own (Python) SWF reader and compares every picture
with the PNG the game wrote.     python3 verify_download.py <garrysmod/data/bobbahotel/habbo>"""
import io, os, struct, sys, zlib
from PIL import Image

def read_swf(data):
    if data[:3] == b"CWS": data = b"FWS" + data[3:8] + zlib.decompress(data[8:])
    nbits = data[8] >> 3
    pos = 8 + (5 + nbits * 4 + 7) // 8 + 4
    syms, imgs = {}, {}
    while pos < len(data):
        head = struct.unpack_from("<H", data, pos)[0]; pos += 2
        code, ln = head >> 6, head & 63
        if ln == 63: ln = struct.unpack_from("<I", data, pos)[0]; pos += 4
        body = data[pos:pos + ln]; pos += ln
        if code == 0: break
        if code == 76:
            n = struct.unpack_from("<H", body, 0)[0]; p = 2
            for _ in range(n):
                cid = struct.unpack_from("<H", body, p)[0]; p += 2
                e = body.index(b"\0", p); syms[cid] = body[p:e].decode("latin1"); p = e + 1
        elif code in (20, 36):
            cid, fmt, w, h = struct.unpack_from("<HBHH", body, 0)
            alpha = code == 36
            if fmt == 5:
                raw = zlib.decompress(body[7:])
                px = []
                for i in range(w * h):
                    a, r, g, b = raw[i * 4:i * 4 + 4]
                    if not alpha: a = 255
                    un = lambda c: 0 if a == 0 else (c if a == 255 else min(255, int(c * 255 / a + 0.5)))
                    px.append((un(r), un(g), un(b), a))
                imgs[cid] = (w, h, px)
            elif fmt == 3:
                size = body[7] + 1
                raw = zlib.decompress(body[8:])
                ent = 4 if alpha else 3
                pal = []
                for i in range(size):
                    c = raw[i * ent:i * ent + ent]
                    a = c[3] if alpha else 255
                    un = lambda v: 0 if a == 0 else (v if a == 255 else min(255, int(v * 255 / a + 0.5)))
                    pal.append((un(c[0]), un(c[1]), un(c[2]), a))
                row = w + (4 - w % 4) % 4
                base = size * ent
                imgs[cid] = (w, h, [pal[raw[base + y * row + x]] if raw[base + y * row + x] < size else (0, 0, 0, 0) for y in range(h) for x in range(w)])
            else:
                imgs[cid] = (w, h, None)
    return syms, imgs

def main(root):
    raw_dir = os.path.join(root, "raw")
    checked = bad = 0
    for dirpath, _, files in os.walk(raw_dir):
        for f in files:
            if not f.endswith(".dat"): continue
            key = os.path.relpath(os.path.join(dirpath, f), raw_dir)[:-4].replace(os.sep, "/")
            syms, imgs = read_swf(open(os.path.join(dirpath, f), "rb").read())
            n = 0
            for cid, name in syms.items():
                if cid not in imgs: continue
                w, h, px = imgs[cid]
                p = os.path.join(root, "png", key, name + ".png")
                if not os.path.exists(p): print("  MISSING", key, name); bad += 1; continue
                got = list(Image.open(p).convert("RGBA").getdata())
                norm = lambda c: c if c[3] > 0 else (0, 0, 0, 0)
                if px is None: print("  (unsupported format, skipped)", name); continue
                if [norm(c) for c in got] != [norm(c) for c in px] or Image.open(p).size != (w, h):
                    print("  DIFFERENT", key, name); bad += 1
                n += 1; checked += 1
            print("%s: %d pictures checked" % (key, n))
    print("%d pictures, %d wrong" % (checked, bad))
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
