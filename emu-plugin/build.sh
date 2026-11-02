#!/bin/bash
# Builds the game server plugin (emu-plugin/) into a jar: build.sh <arcturus.jar> <out.jar>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
javac -nowarn --release 8 -cp "$1" -d "$tmp" $(find "$here/src" -name '*.java')
cp "$here/plugin.json" "$tmp/"
# A fixed date: the same source gives the same jar (the deploy restarts the game server only when it changes).
jar --create --date=2026-01-01T00:00:00Z --file "$2" -C "$tmp" .
rm -rf "$tmp"
