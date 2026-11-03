#!/usr/bin/env python3
"""Runs the hotel core's tests on LuaJIT (the Lua GMod uses) with a real SQLite database.

    pip install lupa      then      python3 tests/run.py
"""
import glob, os, sqlite3, sys
from lupa import luajit21 as lj

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GM = os.path.join(ROOT, "gamemodes", "bobbahotel", "gamemode")


def fresh_runtime():
    lua = lj.LuaRuntime(unpack_returned_tuples=True)
    db = sqlite3.connect(":memory:", isolation_level=None)

    def query(s):
        try:
            cur = db.execute(s)
            cols = [d[0] for d in cur.description] if cur.description else []
            rows = [lua.table_from(dict(zip(cols, r))) for r in cur.fetchall()]
            return lua.table_from(rows)
        except sqlite3.Error as e:
            return False, str(e)

    lua.globals().TEST_DB_QUERY = query
    lua.globals().GM_ROOT = GM
    lua.globals().TEST_ROOT = os.path.join(ROOT, "tests")
    lua.execute(open(os.path.join(ROOT, "tests", "boot.lua")).read())
    return lua


def main():
    failed = total = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "tests", "test_*.lua"))):
        src = open(path).read()
        names = sorted(fresh_runtime().execute(src).keys())
        for name in names:
            total += 1
            # every test gets its own fresh hotel and database, so tests can't affect each other
            lua = fresh_runtime()
            fn = lua.execute(src)[name]
            r = lua.globals().pcall(fn)
            ok, err = (r[0], r[1] if len(r) > 1 else None) if isinstance(r, tuple) else (r, None)
            label = os.path.basename(path)[:-4] + " / " + name
            if ok:
                print("  ok    " + label)
            else:
                failed += 1
                print("  FAIL  " + label + "\n        " + str(err))
    print("\n%d tests, %d failed" % (total, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
