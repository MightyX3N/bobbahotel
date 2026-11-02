#!/usr/bin/env bash
# Installed to /usr/local/bin/bobbahotel-deploy by deploy/setup.sh.
#
# GitHub Actions runs this on the VPS (as user bobba, through an SSH key that can do nothing else)
# with the command "deploy <commit sha>" and the release tarball on stdin. It:
#   1. unpacks the release,
#   2. builds the client's assets from the licensed pictures (tools/nitro),
#   3. brings the database up to date (sql/migrations once each, the furni list every time),
#   4. writes the client's configs for this domain,
#   5. switches to the new release and restarts what changed,
#   6. checks the website and the game server answer, and switches back if not.
set -euo pipefail

APP="${BOBBA_APP:-/opt/bobbahotel}"
ENV_FILE="${BOBBA_ENV_FILE:-/etc/bobbahotel/env}"
STATE="${BOBBA_STATE:-/var/lib/bobbahotel/deploy-state}"
RESTART_WEB="${BOBBA_RESTART_WEB:-sudo -n /usr/bin/systemctl restart bobbahotel-web}"
RESTART_EMU="${BOBBA_RESTART_EMU:-sudo -n /usr/bin/systemctl restart bobbahotel-emu}"
KEEP=5

CMD="${SSH_ORIGINAL_COMMAND:-$*}"
SHA="${CMD#deploy }"
if [[ ! "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "usage: deploy <40-character commit sha>  (release tarball on stdin)" >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
PORT="${PORT:-8080}"
NITRO_DIR="${NITRO_DIR:-/var/lib/bobbahotel/nitro}"
SPRITES_DIR="${SPRITES_DIR:-$APP/sprites}"
sql() { MYSQL_PWD="$DB_PASSWORD" mariadb -h "${DB_HOST:-127.0.0.1}" -u "$DB_USER" "$DB_NAME" "$@"; }

exec 9>"$APP/.deploy.lock"
flock -n 9 || { echo "Another deploy is running" >&2; exit 1; }

REL="$APP/releases/$SHA"
echo "Unpacking ${SHA:0:7}"
rm -rf "$REL.tmp"
mkdir -p "$REL.tmp"
tar -xzf - -C "$REL.tmp"
if [ "$(cat "$REL.tmp/VERSION" 2>/dev/null)" != "$SHA" ]; then
  echo "Release VERSION does not match ${SHA:0:7}" >&2
  rm -rf "$REL.tmp"
  exit 1
fi
rm -rf "$REL"
mv "$REL.tmp" "$REL"

echo "Building the client's assets"
[ -d "$SPRITES_DIR/furni" ] || { echo "No pictures in $SPRITES_DIR (furni, cozy, tiles)" >&2; exit 1; }
rm -rf "$NITRO_DIR.new"
node "$REL/tools/nitro/build-all.mjs" "$NITRO_DIR.new" "$SPRITES_DIR" | sed 's/^/  /'

echo "Updating the database"
sql -e "CREATE TABLE IF NOT EXISTS bobba_migrations (name VARCHAR(100) NOT NULL PRIMARY KEY, applied INT NOT NULL)"
MIGRATED=0
for f in "$REL"/sql/migrations/*.sql; do
  name="$(basename "$f")"
  if [ -z "$(sql -N -e "SELECT 1 FROM bobba_migrations WHERE name='$name'")" ]; then
    echo "  $name"
    sql < "$f"
    sql -e "INSERT INTO bobba_migrations VALUES ('$name', UNIX_TIMESTAMP())"
    MIGRATED=1
  fi
done
sql < "$NITRO_DIR.new/sql/furni.sql"

node "$REL/deploy/nitro-config.mjs" "$REL/client" "$PUBLIC_URL" | sed 's/^/  /'

# The game server only restarts when something it reads changed (it kicks everyone out).
mkdir -p "$STATE"
EMU_HASH="$( (cat "$REL/emu/arcturus.jar" "$REL"/emu/plugins/*.jar "$NITRO_DIR.new/sql/furni.sql"; echo "$MIGRATED") | sha256sum | cut -d' ' -f1)"
EMU_RESTART=1
[ -f "$STATE/emu" ] && [ "$(cat "$STATE/emu")" = "$EMU_HASH" ] && EMU_RESTART=0

PREV="$(readlink -f "$APP/current" 2>/dev/null || true)"

switch_to() {
  ln -sfn "$1" "$APP/current.new"
  mv -Tf "$APP/current.new" "$APP/current"
  $RESTART_WEB 9>&-
  if [ "$EMU_RESTART" = 1 ]; then $RESTART_EMU 9>&-; fi
}

web_ok() {  # $1 = expected version
  for _ in $(seq 1 20); do
    curl -fsS "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q "\"version\":\"$1\"" && return 0
    sleep 1
  done
  return 1
}

game_ok() {  # the websocket plugin listens once Arcturus has loaded
  for _ in $(seq 1 90); do
    ss -ltn 2>/dev/null | grep -q ':2096 ' && return 0
    sleep 1
  done
  return 1
}

# The new assets go live together with the new release.
rm -rf "$NITRO_DIR.old"
[ -d "$NITRO_DIR" ] && mv "$NITRO_DIR" "$NITRO_DIR.old"
mv "$NITRO_DIR.new" "$NITRO_DIR"

switch_to "$REL"
if web_ok "$SHA" && game_ok; then
  echo "$EMU_HASH" > "$STATE/emu"
  echo "Live: ${SHA:0:7}$([ "$EMU_RESTART" = 1 ] && echo ' (game server restarted)')"
  rm -rf "$NITRO_DIR.old"
else
  echo "The new version did not start properly." >&2
  if [ -n "$PREV" ] && [ -d "$PREV" ] && [ "$PREV" != "$REL" ] && [ -f "$PREV/emu/arcturus.jar" ]; then
    echo "Switching back to $(basename "$PREV" | cut -c1-7)" >&2
    if [ -d "$NITRO_DIR.old" ]; then rm -rf "$NITRO_DIR"; mv "$NITRO_DIR.old" "$NITRO_DIR"; fi
    EMU_RESTART=1
    switch_to "$PREV"
    rm -rf "$REL"
  fi
  exit 1
fi

# Keep the newest few releases (and never the one that is live).
CURRENT="$(readlink -f "$APP/current")"
ls -1dt "$APP"/releases/*/ 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r dir; do
  dir="${dir%/}"
  [ "$(readlink -f "$dir")" = "$CURRENT" ] || rm -rf "$dir"
done
