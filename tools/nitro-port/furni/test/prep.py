#!/usr/bin/env python3
"""Reads Habbo furni SWFs (the .dat files the game downloads to garrysmod/data/bobbahotel/habbo/raw/furni/)
into out/furni.json: each furni's XML (index, visualization, assets, logic) and its pictures' sizes,
for run_js.js and run_lua.py.     prep.py <folder with the .dat files>"""
import json, os, struct, sys, zlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "..", "addons", "bobba_habbo", "tests"))
from verify_download import read_swf

def binaries(data):
    if data[:3] == b"CWS": data = b"FWS" + data[3:8] + zlib.decompress(data[8:])
    nbits = data[8] >> 3
    pos = 8 + (5 + nbits * 4 + 7) // 8 + 4
    out = {}
    while pos < len(data):
        head = struct.unpack_from("<H", data, pos)[0]; pos += 2
        code, ln = head >> 6, head & 63
        if ln == 63: ln = struct.unpack_from("<I", data, pos)[0]; pos += 4
        body = data[pos:pos + ln]; pos += ln
        if code == 0: break
        if code == 87: out[struct.unpack_from("<H", body, 0)[0]] = body[6:]
    return out

furni = []
folder = sys.argv[1]
for f in sorted(os.listdir(folder)):
    if not f.endswith(".dat"): continue
    name = f[:-4]
    data = open(os.path.join(folder, f), "rb").read()
    try:
        syms, imgs = read_swf(data)
        bins = binaries(data)
    except Exception as e:
        print("skipped %s: %s" % (name, e)); continue
    xml, sizes = {}, {}
    for cid, n in syms:
        if cid in bins:
            for kind in ("index", "visualization", "assets", "logic"):
                if n.endswith("_" + kind): xml[kind] = bins[cid].decode("latin1")
        elif cid in imgs:
            sizes[n] = [imgs[cid][0], imgs[cid][1]]
    if len(xml) < 4:
        print("skipped %s: missing %s" % (name, {"index", "visualization", "assets", "logic"} - set(xml))); continue
    furni.append({"name": name, "xml": xml, "sizes": sizes})
os.makedirs(os.path.join(HERE, "..", "out"), exist_ok=True)
json.dump(furni, open(os.path.join(HERE, "..", "out", "furni.json"), "w"))
print("prep: %d furni" % len(furni))
