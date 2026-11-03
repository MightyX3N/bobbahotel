#!/bin/sh
# Builds Bobba Hotel Desktop for Windows: desktop/ zipped into a .love and joined onto Love2D's
# love.exe (a "fused" game), with Love's DLLs next to it.
#   tools/desktop/build.sh <love-11.5-win64.zip> <out folder>
# (love-11.5-win64.zip: https://github.com/love2d/love/releases/tag/11.5)
set -e
LOVEZIP="$1"; OUT="$2"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
( cd "$ROOT/desktop" && zip -9 -qr "$TMP/game.love" . -x "*.DS_Store" )
unzip -q "$LOVEZIP" -d "$TMP/love"
LOVEDIR="$(dirname "$(find "$TMP/love" -name love.exe | head -1)")"
rm -rf "$OUT"; mkdir -p "$OUT"
cp "$LOVEDIR"/*.dll "$OUT/"
cp "$LOVEDIR/license.txt" "$OUT/love-license.txt"
cat "$LOVEDIR/love.exe" "$TMP/game.love" > "$OUT/BobbaHotel.exe"
cp "$ROOT/desktop/README.txt" "$OUT/README.txt"
rm -rf "$TMP"
echo "built $OUT"
