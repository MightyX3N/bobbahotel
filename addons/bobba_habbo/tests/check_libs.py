#!/usr/bin/env python3
"""Checks the Habbo addon's plain-Lua libraries on LuaJIT: SWF reading, PNG writing, XML reading,
zlib (LibDeflate). Builds SWF files with known contents (every picture format Habbo uses) and
checks the pixels survive SWF -> Lua -> PNG -> Pillow exactly.    python3 check_libs.py"""
import io, os, random, struct, sys, zlib
from lupa import luajit21 as lj
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(HERE, "..", "lua", "bobbahotel", "addons", "bobba_habbo", "lib")
failed = 0

def check(cond, what):
    global failed
    if cond: print("  ok    " + what)
    else: failed += 1; print("  FAIL  " + what)

L = lj.LuaRuntime(unpack_returned_tuples=True, encoding=None)
def call(fn, *a):
    r = fn(*a)
    return r if isinstance(r, tuple) else (r, None)

def load(name):
    return L.execute(open(os.path.join(LIB, name), "rb").read())
deflate = load("libdeflate.lua")
swf, png, xml = load("swf.lua"), load("png.lua"), load("xml.lua")
L.globals().LD = deflate
inflate = L.eval(b"function(s) return (LD:DecompressZlib(s)) end")
compress = L.eval(b"function(s) return (LD:CompressZlib(s, { level = 6 })) end")

# --- SWF building ------------------------------------------------------------------------------
def tag(code, data):
    if len(data) < 63: return struct.pack("<H", (code << 6) | len(data)) + data
    return struct.pack("<HI", (code << 6) | 63, len(data)) + data

def swf_file(tags, compressed=True):
    rect = bytes([0x00])  # the stage size: 5 bits "0 bits each", four empty values
    body = rect + struct.pack("<HH", 0x1800, 1) + b"".join(tags) + tag(0, b"")
    head = struct.pack("<I", 8 + len(body))
    if compressed: return b"CWS\x09" + head + zlib.compress(body)
    return b"FWS\x09" + head + body

def premul(c, a): return (c * a + 127) // 255

def lossless2_argb(cid, w, h, px, alpha=True):  # px: list of (r,g,b,a)
    raw = b"".join(bytes([a if alpha else 255, premul(r, a) if alpha else r, premul(g, a) if alpha else g, premul(b, a) if alpha else b]) for (r, g, b, a) in px)
    return tag(36 if alpha else 20, struct.pack("<HBHH", cid, 5, w, h) + zlib.compress(raw))

def lossless2_mapped(cid, w, h, palette, idx):  # palette: (r,g,b,a); idx: list of ints
    table = b"".join(bytes([premul(r, a), premul(g, a), premul(b, a), a]) for (r, g, b, a) in palette)
    row = w + (4 - w % 4) % 4
    data = b"".join(bytes(idx[y * w:(y + 1) * w]) + b"\0" * (row - w) for y in range(h))
    return tag(36, struct.pack("<HBHHB", cid, 3, w, h, len(palette) - 1) + zlib.compress(table + data))

def symbols(pairs):
    return tag(76, struct.pack("<H", len(pairs)) + b"".join(struct.pack("<H", i) + n.encode() + b"\0" for i, n in pairs))

def binary(cid, data):
    return tag(87, struct.pack("<HI", cid, 0) + data)

def unpremul_expected(r, g, b, a):
    # what a premultiplied colour comes back as (the same rounding as swf.lua)
    def u(c):
        if a == 0: return 0
        if a == 255: return c
        return min(255, int(premul(c, a) * 255 / a + 0.5))
    return (u(r), u(g), u(b), a) if a > 0 else (0, 0, 0, 0)

rnd = random.Random(5)
W1, H1 = 37, 23   # odd sizes: row padding
img1 = [(rnd.randrange(256), rnd.randrange(256), rnd.randrange(256), rnd.choice([0, 255, 255, 128, 1, 254])) for _ in range(W1 * H1)]
W2, H2 = 13, 9
pal = [(0, 0, 0, 0), (255, 0, 0, 255), (10, 200, 30, 255), (40, 50, 255, 100)]
idx2 = [rnd.randrange(len(pal)) for _ in range(W2 * H2)]
W3, H3 = 5, 4
img3 = [(rnd.randrange(256), rnd.randrange(256), rnd.randrange(256), 255) for _ in range(W3 * H3)]
visual = '<?xml version="1.0" encoding="UTF-8"?>\n<visualizationData type="throne"><graphics><visualization size="64" layerCount="2" angle="45"><layers><layer id="0" z="1" alpha="128"/></layers><directions><direction id="2"/><direction id="4"/></directions></visualization></graphics></visualizationData>'.encode()
tags = [lossless2_argb(1, W1, H1, img1), lossless2_mapped(2, W2, H2, pal, idx2), lossless2_argb(3, W3, H3, img3, alpha=False),
        binary(4, b"\xef\xbb\xbf" + visual), symbols([(1, "throne_throne_64_a_2_0"), (2, "throne_throne_64_b_2_0"), (3, "throne_icon_a"), (4, "throne_throne_visualization")])]

for compressed in (True, False):
    data = swf_file(tags, compressed)
    out, err = call(swf.read, data, inflate)
    label = "CWS" if compressed else "FWS"
    check(out is not None, label + ": read (%s)" % err)
    by = out[b"byName"]
    check(set(k.decode() for k in by.keys()) == {"throne_throne_64_a_2_0", "throne_throne_64_b_2_0", "throne_icon_a", "throne_throne_visualization"}, label + ": every name found")
    check(len(out[b"problems"]) == 0, label + ": no problems")
    for name, w, h, expect in [("throne_throne_64_a_2_0", W1, H1, [unpremul_expected(*p) for p in img1]),
                               ("throne_throne_64_b_2_0", W2, H2, [unpremul_expected(*pal[i]) for i in idx2]),
                               ("throne_icon_a", W3, H3, [p for p in img3])]:
        im = by[name.encode()][b"image"]
        check(im[b"width"] == w and im[b"height"] == h, "%s: %s is %dx%d" % (label, name, w, h))
        p = im[b"pixels"]
        got = [tuple(p[i * 4 + k + 1] for k in range(4)) for i in range(w * h)]
        bad = [i for i in range(w * h) if (got[i] if got[i][3] > 0 else (0, 0, 0, 0)) != expect[i]]
        check(not bad, "%s: %s pixels exact (premultiplied colours undone)%s" % (label, name, "" if not bad else " first bad %d: %s vs %s" % (bad[0], got[bad[0]], expect[bad[0]])))
        # through PNG and back with Pillow
        pngbytes = png.encode(w, h, p, compress)
        back = list(Image.open(io.BytesIO(pngbytes)).convert("RGBA").get_flattened_data())
        check(back == got, "%s: %s survives PNG (Pillow reads the same pixels)" % (label, name))
    vis = by[b"throne_throne_visualization"][b"binary"]
    root = xml.parse(vis)
    v = xml.find(root, b"visualization")
    check(v is not None and v[b"attrs"][b"size"] == b"64" and v[b"attrs"][b"layerCount"] == b"2", label + ": XML inside the SWF read (and its byte order mark skipped)")
    check(len(xml.all(root, b"direction")) == 2, label + ": all directions found")

# --- XML odds and ends -------------------------------------------------------------------------
root = xml.parse(b'<a x="1" y=\'two &amp; &lt;3&gt;\'><!-- c --><b/><b z="&#65;"></b><c><![CDATA[<raw>]]></c>text</a>')
a = xml.find(root, b"a")
check(a[b"attrs"][b"y"] == b"two & <3>", "XML: entities in attributes")
check(len(xml.children(a, b"b")) == 2 and xml.children(a, b"b")[2][b"attrs"][b"z"] == b"A", "XML: self-closing and numeric entities")
check(xml.find(a, b"c")[b"text"] == b"<raw>", "XML: CDATA")
check(a[b"text"] == b"text", "XML: text")

# --- zlib both ways, against Python's zlib --------------------------------------------------------
blob = bytes(rnd.randrange(256) for _ in range(50000)) + b"habbo" * 3000
check(zlib.decompress(compress(blob)) == blob, "zlib: LibDeflate output unpacks with real zlib")
check(inflate(zlib.compress(blob, 9)) == blob, "zlib: LibDeflate unpacks real zlib")
crc = png.crc32(b"123456789")
check(crc == 0xCBF43926, "PNG: CRC-32 check value")

# --- bad input doesn't crash -------------------------------------------------------------------
o, e = call(swf.read, b"not a swf at all", inflate)
check(o is None and e is not None, "a file that isn't a SWF gives a reason, not a crash")
o, e = call(swf.read, b"CWS\x09\x00\x00\x00\x00garbage", inflate)
check(o is None, "a broken SWF gives a reason, not a crash")


# --- ZIP reading (Habbo's desktop client comes as a ZIP) ------------------------------------------
import zipfile
zipmod = load("zip.lua")
inflate_raw = L.eval(b"function(s) return (LD:DecompressDeflate(s)) end")
big = bytes(rnd.randrange(256) for _ in range(20000)) + b"HabboAir" * 5000
zb = io.BytesIO()
with zipfile.ZipFile(zb, "w") as z:
    z.writestr(zipfile.ZipInfo("stored.txt"), b"plain bytes", compress_type=zipfile.ZIP_STORED)
    z.writestr("dir/packed.bin", big, compress_type=zipfile.ZIP_DEFLATED)
    z.comment = b"a comment at the end"
zo, ze = call(zipmod.open, zb.getvalue())
check(zo is not None and sorted(x.decode() for x in zo[b"names"].values()) == ["dir/packed.bin", "stored.txt"], "ZIP: every file listed (%s)" % ze)
check(call(zo[b"read"], b"stored.txt", inflate_raw)[0] == b"plain bytes", "ZIP: a stored file")
check(call(zo[b"read"], b"dir/packed.bin", inflate_raw)[0] == big, "ZIP: a packed file comes out exact")
r, e = call(zo[b"read"], b"nope", inflate_raw)
check(r is None and e, "ZIP: a missing file gives a reason")
check(call(zipmod.open, b"not a zip, just text that is long enough")[0] is None, "ZIP: not a ZIP gives a reason")

# --- SWF without pictures (for big files) --------------------------------------------------------
o2, _ = call(swf.read, swf_file(tags), inflate, L.table_from({b"images": False}))
by2 = o2[b"byName"]
check(by2[b"throne_icon_a"][b"image"] is None and by2[b"throne_throne_visualization"][b"binary"] is not None, "SWF: pictures can be skipped, the XML still read")

# --- downloading, the cache and unpacking (library.lua) with a stand-in platform ------------------
L2 = lj.LuaRuntime(unpack_returned_tuples=True, encoding=None)
served = {"https://example/throne.swf": swf_file(tags), "https://example/settings": b"x=1\nflash.client.url=https://images/gordon/\nflash.dynamic.download.url=//images/dcr/hof_furni/\n"}
requests, files = [], {}
def http(url, ok, fail):
    u = url.decode() if isinstance(url, bytes) else url
    requests.append(u)
    if u in served: ok(served[u])
    else: fail(b"HTTP 404")
L2.globals().PY_HTTP = http
L2.globals().PY_FILES = L2.table()
L2.execute(b"""
BOBBA = { platform = {
	httpGet = function(url, ok, fail) PY_HTTP(url, ok, fail) end,
	writeData = function(path, bytes) PY_FILES[path] = bytes end,
	readData = function(path) return PY_FILES[path] end,
	dataExists = function(path) return PY_FILES[path] ~= nil end,
	runAddonFile = function(folder, name) return dofile(LIB_DIR .. "/" .. name:gsub("^lib/", "")) end,
} }
""")
L2.globals().LIB_DIR = LIB.encode()
L2.execute(open(os.path.join(LIB, "..", "shared.lua"), "rb").read())
H = L2.eval(b"BOBBA.habbo")
H.SETTINGS_URL = b"https://example/settings"
res = {}
H.config(lambda cfg, err=None: res.update(cfg=cfg, err=err))
check(res["cfg"] is not None and res["cfg"][b"furniUrl"] == b"https://images/dcr/hof_furni/", "settings: Habbo's file addresses read (and // made https://)")
got = {}
H.library(b"furni/throne", b"https://example/throne.swf", lambda lib, err=None: got.update(lib=lib, err=err))
lib = got["lib"]
check(lib is not None, "library: downloaded and unpacked")
names = sorted(k.decode() for k in lib[b"images"].keys())
check(names == ["throne_icon_a", "throne_throne_64_a_2_0", "throne_throne_64_b_2_0"], "library: every picture")
pngs = [k for k in L2.globals().PY_FILES.keys() if k.endswith(b".png")]
check(len(pngs) == 3, "library: a PNG file for each picture")
img = Image.open(io.BytesIO(L2.globals().PY_FILES[lib[b"images"][b"throne_throne_64_a_2_0"][b"path"]]))
check(img.size == (W1, H1), "library: the PNG on disk is a real picture of the right size")
check(b"throne_throne_visualization" in list(lib[b"xml"].keys()), "library: the XML")
n = len(requests)
L2.execute(b"package = nil")  # a new run of the game: nothing in memory, only the cache on disk
L2.execute(open(os.path.join(LIB, "library.lua"), "rb").read())
got2 = {}
L2.eval(b"BOBBA.habbo").library(b"furni/throne", b"https://example/throne.swf", lambda lib, err=None: got2.update(lib=lib))
check(got2["lib"] is not None and len(requests) == n, "library: the second time it comes from the cache, no download")
bad = {}
L2.eval(b"BOBBA.habbo").library(b"furni/nothing", b"https://example/nothing.swf", lambda lib, err=None: bad.update(lib=lib, err=err))
check(bad["lib"] is None and b"404" in bad["err"], "library: a missing file gives a reason")
served["https://example/broken.swf"] = b"CWS\x09\x00\x00\x00\x00broken"
L2.eval(b"BOBBA.habbo").library(b"furni/broken", b"https://example/broken.swf", lambda lib, err=None: bad.update(lib=lib, err=err))
check(bad["lib"] is None and bad["err"], "library: a broken file gives a reason")


# --- avatar data: Habbo's client ZIP -> HabboAir.swf -> the avatar XML (avatardata.lua) ---------------
names_in_air = ["HabboAvatarGeometry_xml$abc1", "HabboAvatarPartSets_xml$abc2", "HabboAvatarAnimation_xml$abc3",
                "HabboAvatarFigure_xml$abc4", "action_offset_lay_xml$abc5", "action_offset_swim_xml$abc6", "some_window_xml$zz"]
air_tags = [binary(10 + i, ("<data n='%s'/>" % n).encode() * 50) for i, n in enumerate(names_in_air)]
air_tags.append(lossless2_argb(40, W3, H3, img3, alpha=False))
air_tags.append(symbols([(10 + i, n) for i, n in enumerate(names_in_air)] + [(40, "a_png$1")]))
zb = io.BytesIO()
with zipfile.ZipFile(zb, "w") as z:
    z.writestr("HabboAir.swf", swf_file(air_tags), compress_type=zipfile.ZIP_DEFLATED)
    z.writestr("META-INF/AIR/application.xml", b"<x/>")
served["https://www.habbo.com/gamedata/clienturls"] = b'{"flash-windows-version":"35","flash-windows":"https:\\/\\/clients\\/HabboWin.zip","unity-windows":"x"}'
served["https://clients/HabboWin.zip"] = zb.getvalue()
served["https://example/settings"] = (b"x=1\nflash.client.url=https://images/gordon/PRODUCTION-1/\nflash.dynamic.download.url=//images/dcr/hof_furni/\n"
    b"external.figurepartlist.txt=http://www.habbo.com/gamedata/figuredata\nexternal.figurepartlist.txt=http://www.habbo.com/gamedata/figuredata/f00d\n")
for f in ("HabboAvatarActions.xml", "figuremap.xml", "effectmap.xml"):
    served["https://images/gordon/PRODUCTION-1/" + f] = ("<" + f + "/>").encode()
served["https://www.habbo.com/gamedata/figuredata/f00d"] = b"<figuredata/>"
L3 = lj.LuaRuntime(unpack_returned_tuples=True, encoding=None)
L3.globals().PY_HTTP = http
L3.globals().PY_FILES = L3.table()
L3.globals().LIB_DIR = LIB.encode()
L3.execute(b"""
BOBBA = { platform = {
	httpGet = function(url, ok, fail) PY_HTTP(url, ok, fail) end,
	writeData = function(path, bytes) PY_FILES[path] = bytes end,
	readData = function(path) return PY_FILES[path] end,
	dataExists = function(path) return PY_FILES[path] ~= nil end,
	runAddonFile = function(folder, name) return dofile(LIB_DIR .. "/" .. name:gsub("^lib/", "")) end,
} }
""")
L3.execute(open(os.path.join(LIB, "..", "shared.lua"), "rb").read())
H3 = L3.eval(b"BOBBA.habbo")
H3.SETTINGS_URL = b"https://example/settings"
ad = {}
requests.clear()
H3.avatarData(lambda d, err=None: ad.update(d=d, err=err))
d = ad["d"]
check(d is not None, "avatar data: everything found (%s)" % ad.get("err"))
if d is not None:
    check(d[b"geometry"] == b"<data n='HabboAvatarGeometry_xml$abc1'/>" * 50, "avatar data: the geometry XML out of HabboAir.swf inside the ZIP, exact")
    check(d[b"offsets"][b"lay"].startswith(b"<data n='action_offset_lay"), "avatar data: the lay offsets")
    check(d[b"figuredata"] == b"<figuredata/>" and "https://www.habbo.com/gamedata/figuredata/f00d" in requests, "avatar data: figuredata from the revision Habbo's settings name (the last one, made https)")
    check(d[b"figuremap"] == b"<figuremap.xml/>" and d[b"actions"] == b"<HabboAvatarActions.xml/>", "avatar data: figuremap and actions from the client folder")
txt = [k.decode() for k in L3.globals().PY_FILES.keys() if b"client_35" in k]
check(len(txt) == 6, "avatar data: the 6 client XML kept (per client version), not the ZIP")
L4 = lj.LuaRuntime(unpack_returned_tuples=True, encoding=None)
L4.globals().PY_HTTP = http
L4.globals().PY_FILES = L4.table_from({k: v for k, v in L3.globals().PY_FILES.items()})  # what's on disk, a new run of the game
L4.globals().LIB_DIR = LIB.encode()
L4.execute(b"""
BOBBA = { platform = {
	httpGet = function(url, ok, fail) PY_HTTP(url, ok, fail) end,
	writeData = function(path, bytes) PY_FILES[path] = bytes end,
	readData = function(path) return PY_FILES[path] end,
	dataExists = function(path) return PY_FILES[path] ~= nil end,
	runAddonFile = function(folder, name) return dofile(LIB_DIR .. "/" .. name:gsub("^lib/", "")) end,
} }
""")
L4.execute(open(os.path.join(LIB, "..", "shared.lua"), "rb").read())
L4.eval(b"BOBBA.habbo").SETTINGS_URL = b"https://example/settings"
requests.clear()
ad2 = {}
L4.eval(b"BOBBA.habbo").avatarData(lambda d, err=None: ad2.update(d=d, err=err))
check(ad2["d"] is not None and "https://clients/HabboWin.zip" not in requests and len(requests) == 2, "avatar data: next game start only asks Habbo for its settings and client version (%s)" % requests)

print("\n%d failed" % failed)
sys.exit(1 if failed else 0)
