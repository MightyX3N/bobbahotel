#!/bin/sh
# Runs Nitro's TypeScript (Node) and the gamemode's port.lua (LuaJIT) on every Habbo room layout and
# compares everything. Also fails when port.lua is out of date with src/.
set -e
cd "$(dirname "$0")"
[ -d node_modules ] || npm ci --silent
cp ../../gamemodes/bobbahotel/gamemode/nitro/port.lua /tmp/bobba_port_committed.lua
sh build.sh > /dev/null
if ! cmp -s /tmp/bobba_port_committed.lua ../../gamemodes/bobbahotel/gamemode/nitro/port.lua; then
	echo "port.lua is out of date: run tools/nitro-port/build.sh and commit it"; exit 1
fi
npx esbuild src/Port.ts --bundle --platform=node --format=cjs --outfile=out/nitro.js --log-level=warning
node test/run_js.js
python3 test/run_lua.py ../../gamemodes/bobbahotel/gamemode/nitro/port.lua
python3 test/compare.py
