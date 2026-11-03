#!/usr/bin/env python3
"""Runs Arcturus's pathfinder (Java, PathCheck.java) and the gamemode's hotel/pathfinder.lua on the
same walks in every Habbo layout, with blocked tiles, chairs, beds, players and stacked furni
around, and compares every path.   python3 tools/arcturus-check/check.py   (needs java, lupa)"""
import json, os, random, subprocess, sys
from lupa import luajit21 as lj

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
GM = os.path.join(ROOT, "gamemodes", "bobbahotel", "gamemode")
OUT = os.path.join(ROOT, "out", "java")

def cases():
    models = json.load(open(os.path.join(ROOT, "tools", "nitro-port", "data", "habbo_models.json")))
    extra = [  # small rooms to hit the edges: walls of others, stairs, falls, gaps
        {"name": "corridor", "heightmap": "xxxxxx\rx0000x\rxxxx0x\r00000x\rxxxxxx", "door_x": 0, "door_y": 3, "door_dir": 2},
        {"name": "steps", "heightmap": "xxxxxx\rx4321x\rx4321x\r00000x\rxxxxxx", "door_x": 0, "door_y": 3, "door_dir": 2},
        {"name": "cliff", "heightmap": "xxxxx\rx0x0x\rx2x0x\r00000\rxxxxx", "door_x": 0, "door_y": 3, "door_dir": 2},
        {"name": "empty rows", "heightmap": "xxxx\r\rx00x\r000x\rxxxx\r\r", "door_x": 0, "door_y": 3, "door_dir": 2},
    ]
    rnd = random.Random(1)
    for m in models + extra:
        rows = m["heightmap"].split("\r")
        tiles = [(x, y) for y, r in enumerate(rows) for x, c in enumerate(r) if c.lower() != "x" and len(r) == len(rows[0])]
        if not tiles: continue
        for scene in range(4):
            ops = []
            walk = rnd.random() < 0.3
            ops.append("ROOM %s %d %d %d %d" % (m["heightmap"].replace("\r", "|"), m["door_x"], m["door_y"], m["door_dir"], 1 if walk else 0))
            if scene > 0:
                for (x, y) in rnd.sample(tiles, min(len(tiles), max(1, len(tiles) // 6))):
                    k = rnd.random()
                    if k < 0.35: ops.append("STATE %d %d BLOCKED" % (x, y))
                    elif k < 0.5: ops.append("STATE %d %d SIT" % (x, y))
                    elif k < 0.6: ops.append("STATE %d %d LAY" % (x, y))
                    elif k < 0.8: ops.append("UNIT %d %d" % (x, y))
                    else: ops.append("STACK %d %d %s" % (x, y, rnd.choice(["0.5", "1.0", "1.1", "1.2", "2.5", "-1"])))
            for _ in range(25 if len(tiles) > 4 else 6):
                a = rnd.choice(tiles + [(m["door_x"], m["door_y"])])
                b = rnd.choice(tiles + [(0, 0)])
                ops.append("PATH %d %d %d %d" % (a[0], a[1], b[0], b[1]))
            yield m["name"], ops

def run_java(lines):
    r = subprocess.run(["java", "-cp", OUT, "PathCheck"], input="\n".join(lines) + "\n", capture_output=True, text=True)
    if r.returncode != 0: sys.exit("java failed: " + r.stderr[-2000:])
    return r.stdout.splitlines()

def run_lua(lines):
    L = lj.LuaRuntime(unpack_returned_tuples=True)
    L.execute("BOBBA = {}")
    L.execute(open(os.path.join(GM, "hotel", "util.lua")).read())
    L.execute(open(os.path.join(GM, "hotel", "pathfinder.lua")).read())
    run = L.execute("""
local PF = BOBBA.pathfinder
local g
return function(line)
	local p = {}
	for w in line:gmatch("%S+") do p[#p + 1] = w end
	if p[1] == "ROOM" then
		g = PF.grid(p[2]:gsub("|", "\\r"), tonumber(p[3]), tonumber(p[4]), tonumber(p[5]))
		g.allowWalkthrough = p[6] == "1"
	elseif p[1] == "STATE" then
		PF.tile(g, tonumber(p[2]), tonumber(p[3])).state = p[4]:lower()
	elseif p[1] == "UNIT" then
		PF.addUnit(g, tonumber(p[2]), tonumber(p[3]))
	elseif p[1] == "STACK" then
		-- RoomTile.setStackHeight
		local t = PF.tile(g, tonumber(p[2]), tonumber(p[3]))
		local h = tonumber(p[4])
		if t.state == PF.INVALID then t.stackHeight = 32767 t.allowStack = false
		elseif h >= 0 and h ~= 32767 then t.stackHeight = h t.allowStack = true
		else t.allowStack = false t.stackHeight = t.z end
	elseif p[1] == "PATH" then
		local path = PF.find(g, tonumber(p[2]), tonumber(p[3]), tonumber(p[4]), tonumber(p[5]))
		if path == nil then return "NULL" end
		local out = { "P" }
		for _, t in ipairs(path) do out[#out + 1] = t.x .. "," .. t.y end
		return table.concat(out, " ")
	end
end
""")
    out = []
    for line in lines:
        r = run(line)
        if r is not None: out.append(r)
    return out

def main():
    subprocess.run(["javac", "-d", OUT, os.path.join(HERE, "PathCheck.java")], check=True, stderr=subprocess.DEVNULL)
    allops, names = [], []
    for name, ops in cases():
        allops += ops
        names += [name for o in ops if o.startswith("PATH")]
    pathops = [o for o in allops if o.startswith("PATH")]
    j, l = run_java(allops), run_lua(allops)
    assert len(j) == len(pathops), (len(j), len(pathops))
    bad = [(names[i], pathops[i], j[i], l[i]) for i in range(len(j)) if j[i] != l[i]]
    for b in bad[:10]: print("DIFF", b[0], b[1], "\n  java:", b[2], "\n  lua: ", b[3])
    found = sum(1 for x in j if x.startswith("P ") and len(x) > 2)
    print("%d walks (%d with a path, %d nowhere to go, %d no way), %d differ" % (len(j), found, sum(1 for x in j if x == "P"), j.count("NULL"), len(bad)))
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
