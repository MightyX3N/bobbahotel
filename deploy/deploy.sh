#!/usr/bin/env bash
# Installed to /usr/local/bin/bobbahotel-deploy by deploy/setup.sh.
#
# GitHub Actions runs this on the VPS (as user bobba, through an SSH key that can do nothing else)
# with the command "deploy <commit sha>" and the release tarball on stdin. It unpacks the release,
# points /opt/bobbahotel/current at it, restarts the server and checks that the new version answers.
# If it doesn't, it switches back to the previous release.
set -euo pipefail

APP="${BOBBA_APP:-/opt/bobbahotel}"
ENV_FILE="${BOBBA_ENV_FILE:-/etc/bobbahotel/env}"
RESTART="${BOBBA_RESTART:-sudo -n /usr/bin/systemctl restart bobbahotel}"
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

PREV="$(readlink -f "$APP/current" 2>/dev/null || true)"

switch_to() {
  ln -sfn "$1" "$APP/current.new"
  mv -Tf "$APP/current.new" "$APP/current"
  $RESTART 9>&-  # don't let the restarted server inherit (and hold) the deploy lock
}

healthy() {  # $1 = expected version
  for _ in $(seq 1 20); do
    if curl -fsS "http://127.0.0.1:$PORT/api/health" 2>/dev/null | grep -q "\"version\":\"$1\""; then return 0; fi
    sleep 1
  done
  return 1
}

switch_to "$REL"
if healthy "$SHA"; then
  echo "Live: ${SHA:0:7}"
else
  echo "The new version did not answer its health check." >&2
  if [ -n "$PREV" ] && [ -d "$PREV" ] && [ "$PREV" != "$REL" ]; then
    echo "Rolling back to $(basename "$PREV" | cut -c1-7)" >&2
    switch_to "$PREV"
    healthy "$(basename "$PREV")" && echo "Rolled back." >&2 || echo "The previous version does not answer either!" >&2
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
