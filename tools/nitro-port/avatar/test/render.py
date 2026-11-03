#!/usr/bin/env python3
"""Paints the draw lists (out/js.json or out/lua.json) as pictures, the way the game will: each
asset multiplied by its colour, mirrored when flipH.   render.py <data folder> <json> <case> <frame> <out.png>"""
import json, os, sys
from PIL import Image, ImageChops

def paint(dirpath, assets, f):
    canvas = Image.new("RGBA", (max(1, int(f["width"])), max(1, int(f["height"]))), (0, 0, 0, 0))
    for s in f["sprites"]:
        a = assets[s["name"]]
        im = Image.open(os.path.join(dirpath, a["lib"], "png", a["file"] + ".png")).convert("RGBA")
        c = s["color"]
        if c != 0xFFFFFF:
            r, g, b, al = im.split()
            r = r.point(lambda v: (v * ((c >> 16) & 255) + 127) // 255)
            g = g.point(lambda v: (v * ((c >> 8) & 255) + 127) // 255)
            b = b.point(lambda v: (v * (c & 255) + 127) // 255)
            im = Image.merge("RGBA", (r, g, b, al))
        if s["flipH"]: im = im.transpose(Image.FLIP_LEFT_RIGHT)
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        layer.paste(im, (int(round(s["x"])), int(round(s["y"]))))
        canvas = Image.alpha_composite(canvas, layer)
    return canvas

if __name__ == "__main__":
    d = sys.argv[1]
    assets = json.load(open(os.path.join(d, "assets.json")))
    data = json.load(open(sys.argv[2]))
    paint(d, assets, data[int(sys.argv[3])][int(sys.argv[4])]).save(sys.argv[5])
