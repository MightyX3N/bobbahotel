# The action script both sides run: random steps over every category, with a fixed seed
import json, random, sys
rnd = random.Random(7)
models = {"generic": ["hd"], "head": ["hr", "ha", "he", "ea", "fa"], "torso": ["ch", "cp", "cc", "ca"], "legs": ["lg", "sh", "wa"]}
figures = [("hr-100.hd-180-7.ch-215-66.lg-270-79.sh-305-62.ha-1002-70.wa-2007", "M"), ("hr-515-33.hd-600-1.ch-635-70.lg-716-66-62.sh-735-68", "F"),
           ("hd-180-1", "M"), ("hd-180-1.ch-210-66.lg-270-82.sh-290-80.hr-100-61", "M"), ("", "F"), ("xx-1.hd-600-1.ch-9999999.lg-270", "F")]
runs = []
for i in range(int(sys.argv[2]) if len(sys.argv) > 2 else 12):
    fig, g = figures[i % len(figures)]
    steps = [{"op": "load", "figure": fig, "gender": g}]
    for _ in range(40):
        k = rnd.random()
        if k < 0.45:
            m = rnd.choice(list(models)); steps.append({"op": "part", "model": m, "cat": rnd.choice(models[m]), "index": rnd.randrange(400)})
        elif k < 0.85:
            m = rnd.choice(list(models)); steps.append({"op": "color", "model": m, "cat": rnd.choice(models[m]), "index": rnd.randrange(200), "palette": rnd.randrange(2)})
        elif k < 0.9: steps.append({"op": "gender", "gender": rnd.choice("MF")})
        elif k < 0.93: steps.append({"op": "clear"})
        elif k < 0.96: steps.append({"op": "reset"})
        else: steps.append({"op": "random"})
    runs.append({"club": [0, 0, 1, 2][i % 4], "steps": steps})
json.dump({"random": [rnd.random() for _ in range(5000)], "runs": runs}, open(sys.argv[1], "w"))
