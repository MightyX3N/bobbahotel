#!/bin/sh
# Runs Nitro's TypeScript (Node) and the gamemode's port.lua (LuaJIT) on every Habbo room layout and
# compares everything. Also fails when port.lua is out of date with src/.
set -e
cd "$(dirname "$0")"
[ -d node_modules ] || npm ci --silent
cp ../../gamemodes/bobbahotel/gamemode/nitro/port.lua /tmp/bobba_port_committed.lua
cp ../../gamemodes/bobbahotel/gamemode/nitro/avatar.lua /tmp/bobba_avatar_committed.lua
cp ../../gamemodes/bobbahotel/gamemode/nitro/furni.lua /tmp/bobba_furni_committed.lua 2>/dev/null || true
sh build.sh > /dev/null
for f in port avatar furni; do
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

# The avatar editor's logic: nitro-react's TypeScript (src/api/avatar) against hotel/figureeditor.lua,
# on Habbo's figuredata (HABBO_DATA/data/figuredata.xml): the same random clicks through every category.
if [ -n "$HABBO_DATA" ]; then
	(cd editor && ../node_modules/.bin/esbuild src/Editor.ts --bundle --platform=node --format=cjs --outfile=out/editor.js --log-level=warning --alias:@nitrots/nitro-renderer=./src/renderer-stub.ts \
		&& python3 test/make_script.py out/script.json 60 && node test/run_js.js "$HABBO_DATA/data/figuredata.xml" out/script.json out/js.json \
		&& python3 test/run_lua.py "$HABBO_DATA/data/figuredata.xml" out/script.json out/lua.json && python3 test/compare.py out/js.json out/lua.json)
else
	echo "avatar editor: skipped (set HABBO_DATA to check it against nitro-react on Habbo's figuredata)"
fi

# The furniture: Nitro's TypeScript against furni.lua, on Habbo furni. HABBO_FURNI is a folder of furni
# files as a game downloads them (garrysmod/data/bobbahotel/habbo/raw/furni/, e.g. after
# bobba_habbo_furni_sample). Without it this part is skipped.
if [ -n "$HABBO_FURNI" ]; then
	(cd furni && python3 test/prep.py "$HABBO_FURNI" && ../node_modules/.bin/esbuild src/Furni.ts --bundle --platform=node --format=cjs --outfile=out/furni.js --log-level=warning \
		&& node test/run_js.js && python3 test/run_lua.py out/furni.lua && python3 test/compare.py)
else
	echo "furniture: skipped (set HABBO_FURNI to check it against Nitro on Habbo's furni)"
fi
