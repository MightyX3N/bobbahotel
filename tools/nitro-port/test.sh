#!/bin/sh
# Runs Nitro's TypeScript (Node) and the gamemode's port.lua (LuaJIT) on every Habbo room layout and
# compares everything. Also fails when port.lua is out of date with src/.
set -e
cd "$(dirname "$0")"
[ -d node_modules ] || npm ci --silent
cp ../../gamemodes/bobbahotel/gamemode/nitro/port.lua /tmp/bobba_port_committed.lua
cp ../../gamemodes/bobbahotel/gamemode/nitro/avatar.lua /tmp/bobba_avatar_committed.lua
sh build.sh > /dev/null
for f in port avatar; do
	if ! cmp -s /tmp/bobba_${f}_committed.lua ../../gamemodes/bobbahotel/gamemode/nitro/$f.lua; then
		echo "$f.lua is out of date: run tools/nitro-port/build.sh and commit it"; exit 1
	fi
done
npx esbuild src/Port.ts --bundle --platform=node --format=cjs --outfile=out/nitro.js --log-level=warning
node test/run_js.js
python3 test/run_lua.py ../../gamemodes/bobbahotel/gamemode/nitro/port.lua
python3 test/compare.py

# The avatar renderer: Nitro's TypeScript against avatar.lua, on Habbo's own avatar data. Habbo's
# files are never in this repository: HABBO_DATA is a folder made from a game's download (see
# avatar/README.md). Without it this part is skipped.
if [ -n "$HABBO_DATA" ]; then
	(cd avatar && ../node_modules/.bin/esbuild src/Avatar.ts --bundle --platform=node --format=cjs --outfile=out/avatar.js --log-level=warning \
		&& node test/run_js.js "$HABBO_DATA" && python3 test/run_lua.py out/avatar.lua "$HABBO_DATA" && python3 test/compare.py)
else
	echo "avatar renderer: skipped (set HABBO_DATA to check it against Nitro on Habbo's data)"
fi
