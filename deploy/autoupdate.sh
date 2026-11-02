#!/usr/bin/env bash
# Runs every minute (systemd timer). If GitHub has new commits: pull, build, restart. If the new version doesn't start, go back to the old one.
{
set -uo pipefail
APP=/opt/bobbahotel
cd "$APP" || exit 1
exec 9>/var/lock/bobbahotel-update.lock; flock -n 9 || exit 0

git fetch -q origin main || exit 0
OLD=$(git rev-parse HEAD); NEW=$(git rev-parse origin/main)
[ "$OLD" = "$NEW" ] && exit 0

build() {  # build the client into dist.new, then swap it in; install server packages
  (cd server && npm ci --no-audit --no-fund) || return 1
  (cd client && npm ci --no-audit --no-fund && rm -rf dist.new && npx vite build --outDir dist.new) || return 1
  rm -rf client/dist.old; [ -d client/dist ] && mv client/dist client/dist.old
  mv client/dist.new client/dist
}
healthy() {  # the game server answers within ~15 seconds
  for _ in $(seq 1 15); do curl -fsS -o /dev/null http://127.0.0.1:8080/api/me && return 0; sleep 1; done; return 1
}
apply_config() {  # copy service/Caddy config if it changed
  cmp -s deploy/bobbahotel.service /etc/systemd/system/bobbahotel.service || { cp deploy/bobbahotel.service /etc/systemd/system/; systemctl daemon-reload; }
  cmp -s deploy/Caddyfile /etc/caddy/Caddyfile || { cp deploy/Caddyfile /etc/caddy/Caddyfile; systemctl reload caddy; }
}

echo "updating ${OLD:0:7} -> ${NEW:0:7}"
git reset -q --hard "$NEW"
if build; then
  apply_config; systemctl restart bobbahotel
  if healthy; then echo "updated to ${NEW:0:7}"; exit 0; fi
  echo "new version did not start, rolling back"
else
  echo "build failed, keeping the old version"
fi
git reset -q --hard "$OLD"
build && apply_config; systemctl restart bobbahotel
exit 1
}
