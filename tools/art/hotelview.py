#!/usr/bin/env python3
"""Draws the hotel view pictures (content/nitro/hotelview.png and hotelview-sky.png).

hotelview.py <lounge.png>: lounge.png is a picture of the Welcome Lounge on a black background
(a screenshot of the room with the interface hidden). The black around it becomes transparent, the
doorway stays dark, and the room is stood on a little grass island; the sky behind it is drawn too.
"""
import collections
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw

out = Path(__file__).resolve().parents[2] / 'content' / 'nitro'
random.seed(7)

# The lounge: black reachable from the edges -> transparent; black left over is the doorway.
lob = Image.open(sys.argv[1]).convert('RGBA')
W, H = lob.size
px = lob.load()
q = collections.deque([(x, y) for x in range(W) for y in (0, H - 1)] + [(x, y) for y in range(H) for x in (0, W - 1)])
seen = set()
while q:
    x, y = q.popleft()
    if (x, y) in seen or not (0 <= x < W and 0 <= y < H):
        continue
    seen.add((x, y))
    if sum(px[x, y][:3]) > 12:
        continue
    px[x, y] = (0, 0, 0, 0)
    q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
for x in range(W):
    for y in range(H):
        if px[x, y] == (0, 0, 0, 255):
            px[x, y] = (28, 22, 18, 255)
lob = lob.crop(lob.getchannel('A').getbbox())

# The island.
img = Image.new('RGBA', (900, 640), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
cx, cy, hw, hh, depth = 470, 370, 420, 210, 70
top = [(cx, cy - hh), (cx + hw, cy), (cx, cy + hh), (cx - hw, cy)]
left = [top[3], top[2], (top[2][0], top[2][1] + depth), (top[3][0], top[3][1] + depth)]
right = [top[2], top[1], (top[1][0], top[1][1] + depth), (top[2][0], top[2][1] + depth)]
d.polygon(left, fill=(134, 92, 58, 255))
d.polygon(right, fill=(108, 72, 44, 255))
for k in range(1, 4):
    yy = depth * k // 4
    d.line([(top[3][0], top[3][1] + yy), (top[2][0], top[2][1] + yy)], fill=(118, 80, 50, 255), width=2)
    d.line([(top[2][0], top[2][1] + yy), (top[1][0], top[1][1] + yy)], fill=(94, 62, 38, 255), width=2)
d.polygon(top, fill=(112, 176, 72, 255))
d.line([top[3], top[0], top[1]], fill=(150, 206, 96, 255), width=3)
d.line([top[3], top[2], top[1]], fill=(78, 136, 48, 255), width=4)


def on_island():
    u, v = random.random(), random.random()
    return top[3][0] + u * hw + v * hw, top[3][1] - u * hh + v * hh


for _ in range(260):
    x, y = on_island()
    d.line([(x, y), (x, y - 3)], fill=random.choice([(98, 160, 62), (132, 192, 84), (90, 150, 56)]) + (255,), width=2)


def bush(x, y, s):
    for dx, dy, r in [(-s, 0, s), (s, 0, s), (0, -s * 0.8, s * 1.1)]:
        d.ellipse([x + dx - r, y + dy - r, x + dx + r, y + dy + r], fill=(64, 128, 48, 255), outline=(40, 90, 30, 255))
    d.ellipse([x - s * 0.4, y - s * 1.4, x + s * 0.3, y - s * 0.9], fill=(110, 176, 80, 255))


for x, y, s in [(140, 370, 14), (170, 392, 10), (230, 420, 8), (780, 380, 15), (812, 358, 10), (470, 560, 13), (505, 575, 9), (640, 500, 8)]:
    bush(x, y, s)
for _ in range(40):
    x, y = on_island()
    if abs(x - cx) < 270 and y < cy + 140:
        continue
    d.rectangle([x, y, x + 2, y + 2], fill=random.choice([(240, 90, 90), (250, 220, 90), (255, 255, 255), (200, 120, 230)]) + (255,))
img.alpha_composite(lob, (cx - lob.width // 2 + 10, cy + hh - lob.height - 34))
img.crop(img.getbbox()).save(out / 'hotelview.png', optimize=True)

# The sky (the client repeats it downwards).
BW, BH = 2560, 1200
sky = Image.new('RGB', (BW, BH))
sd = ImageDraw.Draw(sky)
top_c, bot_c = (92, 164, 214), (186, 226, 244)
for y in range(BH):
    t = y / BH
    sd.line([(0, y), (BW, y)], fill=tuple(int(top_c[i] + (bot_c[i] - top_c[i]) * t) for i in range(3)))


def cloud(x, y, s):
    for dx, dy, r in [(0, 0, 1.0), (1.1, 0.15, 0.8), (-1.0, 0.2, 0.75), (0.5, -0.45, 0.8), (-0.45, -0.35, 0.7)]:
        rr = r * s
        sd.ellipse([x + dx * s - rr, y + dy * s - rr * 0.7, x + dx * s + rr, y + dy * s + rr * 0.7], fill=(255, 255, 255))
    sd.rectangle([x - 1.9 * s, y + 0.25 * s, x + 1.9 * s, y + 0.55 * s], fill=(255, 255, 255))
    sd.rectangle([x - 1.9 * s, y + 0.55 * s, x + 1.9 * s, y + 0.7 * s], fill=(222, 238, 248))


for x, y, s in [(220, 140, 36), (760, 90, 26), (1240, 190, 44), (1720, 110, 30), (2200, 170, 38), (480, 420, 22), (1500, 460, 28), (2380, 520, 20), (980, 640, 18), (140, 760, 24), (1900, 820, 22)]:
    cloud(x, y, s)
sky.save(out / 'hotelview-sky.png', optimize=True)
