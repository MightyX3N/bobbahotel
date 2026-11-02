#!/usr/bin/env bash
# Sets up the VPS for Bobba Hotel. Safe to run again (for example after the service or
# Caddy config in deploy/ changes). Run as root on the VPS:
#
#   curl -fsSL https://raw.githubusercontent.com/MightyX3N/bobbahotel/main/deploy/setup.sh | bash
#
# It installs Node 24, Caddy and sqlite3, retires the old auto-update setup, creates the folders,
# the service and the web server config, a deploy key for GitHub Actions, the firewall rules and
# a nightly database backup. At the end it prints the two secrets to add on GitHub.
set -euo pipefail

RAW="${BOBBA_RAW:-https://raw.githubusercontent.com/MightyX3N/bobbahotel/main/deploy}"
DOMAIN="${BOBBA_DOMAIN:-hotel.playbobba.com}"
APP=/opt/bobbahotel
DATA=/var/lib/bobbahotel
ETC=/etc/bobbahotel
KEY="$ETC/deploy_key"

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
[ "$(id -u)" = 0 ] || { echo "Run this as root." >&2; exit 1; }

say "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -yq curl ca-certificates gnupg sqlite3 ufw debian-keyring debian-archive-keyring apt-transport-https
if ! node --version 2>/dev/null | grep -q '^v24\.'; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -yq nodejs
fi
if ! command -v caddy >/dev/null; then
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -q
  apt-get install -yq caddy
fi
echo "node $(node --version), $(caddy version | cut -d' ' -f1) caddy"

say "Retiring the old version"
if systemctl list-unit-files bobbahotel-update.timer >/dev/null 2>&1; then
  systemctl disable --now bobbahotel-update.timer 2>/dev/null || true
fi
rm -f /etc/systemd/system/bobbahotel-update.timer /etc/systemd/system/bobbahotel-update.service
if [ -d "$APP/.git" ]; then
  systemctl stop bobbahotel 2>/dev/null || true
  OLD="/opt/bobbahotel-old-$(date +%Y%m%d-%H%M)"
  mv "$APP" "$OLD"
  mkdir -p "$APP"
  [ -d "$OLD/sprites" ] && mv "$OLD/sprites" "$APP/sprites"
  echo "Old code moved to $OLD (sprites kept). Delete it when you no longer need it."
fi
if [ -f "$DATA/hotel.db" ] && [ ! -f "$DATA/.v2" ]; then
  for f in hotel.db hotel.db-wal hotel.db-shm; do [ -f "$DATA/$f" ] && mv "$DATA/$f" "$DATA/old-$f"; done
  echo "Old database kept as $DATA/old-hotel.db"
fi

say "User and folders"
id bobba >/dev/null 2>&1 || useradd --system --user-group --home-dir /home/bobba --shell /bin/bash bobba
mkdir -p /home/bobba/.ssh
usermod --home /home/bobba --shell /bin/bash bobba
install -d -o bobba -g bobba "$APP" "$APP/releases" "$APP/sprites" "$DATA"
touch "$DATA/.v2" && chown bobba:bobba "$DATA/.v2"
install -d -m 750 -o root -g bobba "$ETC"
install -d -m 750 /var/backups/bobbahotel

if [ ! -f "$ETC/env" ]; then
  cat > "$ETC/env" <<EOF
PORT=8080
HOST=127.0.0.1
PUBLIC_URL=https://$DOMAIN
ALLOW_ORIGIN=https://$DOMAIN
STAFF_STEAMIDS=76561198346473450
DB_FILE=$DATA/hotel.db
SPRITES_DIR=$APP/sprites
EOF
  echo "Wrote $ETC/env (edit it to change server settings)"
fi
chown root:bobba "$ETC/env"
chmod 640 "$ETC/env"

say "Service, web server, deploy command, backups"
curl -fsSL "$RAW/bobbahotel.service" -o /etc/systemd/system/bobbahotel.service
curl -fsSL "$RAW/deploy.sh" -o /usr/local/bin/bobbahotel-deploy
chmod 755 /usr/local/bin/bobbahotel-deploy
curl -fsSL "$RAW/backup.sh" -o /etc/cron.daily/bobbahotel-backup
chmod 755 /etc/cron.daily/bobbahotel-backup
curl -fsSL "$RAW/Caddyfile" | sed "s/hotel\.playbobba\.com/$DOMAIN/" > /etc/caddy/Caddyfile.new
caddy validate --config /etc/caddy/Caddyfile.new --adapter caddyfile >/dev/null
mv /etc/caddy/Caddyfile.new /etc/caddy/Caddyfile
systemctl enable caddy >/dev/null 2>&1
systemctl reload caddy 2>/dev/null || systemctl restart caddy

# The deploy may restart the game server and nothing else.
echo 'bobba ALL=(root) NOPASSWD: /usr/bin/systemctl restart bobbahotel' > /etc/sudoers.d/bobbahotel.new
chmod 440 /etc/sudoers.d/bobbahotel.new
visudo -cf /etc/sudoers.d/bobbahotel.new >/dev/null
mv /etc/sudoers.d/bobbahotel.new /etc/sudoers.d/bobbahotel

systemctl daemon-reload
systemctl enable bobbahotel >/dev/null 2>&1

say "Deploy key for GitHub Actions"
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N '' -C "github-actions-deploy" -f "$KEY"
chmod 600 "$KEY"
AUTH=/home/bobba/.ssh/authorized_keys
touch "$AUTH"
if ! grep -qF "$(cut -d' ' -f2 "$KEY.pub")" "$AUTH"; then
  echo "command=\"/usr/local/bin/bobbahotel-deploy\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty $(cat "$KEY.pub")" >> "$AUTH"
fi
chown -R bobba:bobba /home/bobba/.ssh
chmod 700 /home/bobba/.ssh
chmod 600 "$AUTH"

say "Firewall"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
ufw status | head -n 8

if [ -e "$APP/current" ]; then
  systemctl restart bobbahotel
  echo "Game server restarted on the current release."
else
  echo "No release yet: the first push to main will deploy one."
fi

say "Add these two secrets on GitHub"
cat <<EOF
Go to github.com/MightyX3N/bobbahotel -> Settings -> Secrets and variables -> Actions
-> New repository secret, and add:

1) Name: DEPLOY_SSH_KEY
   Value (everything between the lines, including the BEGIN/END lines):
-----------------------------------------------------------------------
$(cat "$KEY")
-----------------------------------------------------------------------

2) Name: DEPLOY_KNOWN_HOSTS
   Value:
$DOMAIN $(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)

This key can only deploy Bobba Hotel; it cannot log in to a shell.
EOF
