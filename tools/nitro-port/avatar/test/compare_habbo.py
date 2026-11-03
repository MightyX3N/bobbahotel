#!/usr/bin/env python3
"""Compares the port's avatars (out/imaging.json) with Habbo's own pictures (habbo-imaging, saved by
bobba_habbo_imaging). Habbo crops its canvas, so the best overlap is searched.
compare_habbo.py <data folder> <imaging folder> [sheet.png]"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render import paint
from PIL import Image, ImageChops

d, imgdir = sys.argv[1], sys.argv[2]
assets = json.load(open(os.path.join(d, "assets.json")))
ours = json.load(open(os.path.join(os.path.dirname(__file__), "..", "out", "imaging.json")))
rows, total_bad = [], 0
for name in sorted(ours):
    mine = paint(d, assets, ours[name])
    theirs = Image.open(os.path.join(imgdir, name + ".png")).convert("RGBA")
    best = None
    for dy in range(-30, 31):
        for dx in range(-40, 41):
            crop = Image.new("RGBA", theirs.size, (0, 0, 0, 0))
            crop.paste(mine, (-dx, -dy))
            a, b = list(crop.getdata()), list(theirs.getdata())
            bad = sum(1 for p, q in zip(a, b) if (p if p[3] else (0,0,0,0)) != (q if q[3] else (0,0,0,0)))
            if best is None or bad < best[0]: best = (bad, dx, dy, crop)
            if bad == 0: break
        if best[0] == 0: break
    total_bad += best[0]
    print("%-8s %5d pixels differ (at %d,%d)" % (name, best[0], best[1], best[2]))
    rows.append((theirs, best[3]))
print("total differing pixels:", total_bad)
if len(sys.argv) > 3:
    W, H = rows[0][0].size
    sheet = Image.new("RGBA", (W * 2 * 8, H * (len(rows) // 8)), (150, 150, 150, 255))
    for i, (t, m) in enumerate(rows):
        x, y = (i % 8) * W * 2, (i // 8) * H
        sheet.alpha_composite(t, (x, y)); sheet.alpha_composite(m, (x + W, y))
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(sys.argv[3])
