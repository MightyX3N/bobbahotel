#!/usr/bin/env bash
# Sets up the VPS for Bobba Hotel (Nitro client, Arcturus game server, website). Safe to run
# again. Run as root on the VPS:
#
#   curl -fsSL https://raw.githubusercontent.com/MightyX3N/bobbahotel/main/deploy/setup.sh | bash
#
# It installs MariaDB, Java, Node 24 and Caddy, makes swap (the VPS has 2 GB of memory), creates
# the database from Arcturus' base data, the services, the web server config, the deploy command
# and the firewall. The licensed pictures stay in /opt/bobbahotel/sprites (never in git).
set -euo pipefail

RAW="${BOBBA_RAW:-https://raw.githubusercontent.com/MightyX3N/bobbahotel/main/deploy}"
DOMAIN="${BOBBA_DOMAIN:-hotel.playbobba.com}"
APP=/opt/bobbahotel
DATA=/var/lib/bobbahotel
ETC=/etc/bobbahotel
KEY="$ETC/deploy_key"
DB_NAME=bobbahotel
DB_USER=bobba
# Arcturus' base database and its updates, at fixed versions.
BASE_SQL="https://raw.githubusercontent.com/Gurkengewuerz/nitro-docker/aa5826938aa1f9f1660d75f0163e8af1f2fe5dcb/arcturus/arcturus_3.0.0-stable_base_database--compact.sql"
ARCTURUS_RAW="https://raw.githubusercontent.com/UnfamiliarLegacy/Arcturus/eb2ecd71324134bfcc7fcb3c6eb432535fba2a21/sqlupdates"
UPDATES=("3_0_0 to 3_5_0.sql" "Update 3_5_0 to 3_5_2.sql" "Update 3_5_2 to 3_5_3.sql")

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
[ "$(id -u)" = 0 ] || { echo "Run this as root." >&2; exit 1; }

say "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -yq curl ca-certificates gnupg ufw mariadb-server mariadb-client openjdk-17-jre-headless \
  debian-keyring debian-archive-keyring apt-transport-https
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
echo "node $(node --version), java $(java -version 2>&1 | head -1), $(mariadb --version | cut -d, -f1)"

say "Memory: swap and a small database"
if ! swapon --show | grep -q .; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "2 GB swap made."
fi
cat > /etc/mysql/mariadb.conf.d/60-bobbahotel.cnf <<'EOF'
# Bobba Hotel: a small database for a 2 GB VPS.
[mysqld]
bind-address = 127.0.0.1
innodb_buffer_pool_size = 128M
innodb_log_buffer_size = 8M
key_buffer_size = 8M
max_connections = 40
performance_schema = OFF
EOF
systemctl enable mariadb >/dev/null 2>&1
systemctl restart mariadb

say "Retiring the old version"
if systemctl list-unit-files bobbahotel.service >/dev/null 2>&1 && [ -f /etc/systemd/system/bobbahotel.service ]; then
  systemctl disable --now bobbahotel 2>/dev/null || true
  rm -f /etc/systemd/system/bobbahotel.service
  echo "Old game server stopped (its database is kept in $DATA)."
fi
rm -f /etc/cron.daily/bobbahotel-backup

say "User, folders, settings"
id bobba >/dev/null 2>&1 || useradd --system --user-group --home-dir /home/bobba --shell /bin/bash bobba
mkdir -p /home/bobba/.ssh
install -d -o bobba -g bobba "$APP" "$APP/releases" "$APP/sprites" "$DATA" "$DATA/emu" "$DATA/nitro"
install -d -m 750 -o root -g bobba "$ETC"
touch "$ETC/env"
setting() {  # adds KEY=value to the settings file unless it's there already
  grep -q "^$1=" "$ETC/env" || echo "$1=$2" >> "$ETC/env"
}
setting PORT 8080
setting HOST 127.0.0.1
setting PUBLIC_URL "https://$DOMAIN"
setting DOMAIN "$DOMAIN"
setting STAFF_STEAMIDS 76561198346473450
setting SPRITES_DIR "$APP/sprites"
setting NITRO_DIR "$DATA/nitro"
setting DB_HOST 127.0.0.1
setting DB_NAME "$DB_NAME"
setting DB_USER "$DB_USER"
grep -q '^DB_PASSWORD=' "$ETC/env" || echo "DB_PASSWORD=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 28)" >> "$ETC/env"
chown root:bobba "$ETC/env"
chmod 640 "$ETC/env"
DB_PASSWORD="$(grep '^DB_PASSWORD=' "$ETC/env" | cut -d= -f2-)"

say "Database"
mariadb -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
  CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
  ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
  GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
  CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
  ALTER USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
  GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1'; FLUSH PRIVILEGES;"
if [ "$(mariadb -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME' AND table_name='users'")" = 0 ]; then
  TMP=$(mktemp -d)
  curl -fsSL "$BASE_SQL" -o "$TMP/base.sql"
  mariadb "$DB_NAME" < "$TMP/base.sql"
  for u in "${UPDATES[@]}"; do
    curl -fsSL "$ARCTURUS_RAW/${u// /%20}" -o "$TMP/update.sql"
    mariadb "$DB_NAME" < "$TMP/update.sql"
  done
  rm -rf "$TMP"
  echo "Database created from Arcturus' base data; the first deploy adds the hotel's own."
else
  echo "Database already there."
fi

say "Game server folder"
curl -fsSL "$RAW/emu-config.ini" | sed -e "s/@DB_NAME@/$DB_NAME/" -e "s/@DB_USER@/$DB_USER/" -e "s/@DB_PASSWORD@/$DB_PASSWORD/" > "$DATA/emu/config.ini"
ln -sfn "$APP/current/emu/plugins" "$DATA/emu/plugins"
chown -R bobba:bobba "$DATA/emu"
chmod 600 "$DATA/emu/config.ini"

say "Services, web server, deploy command"
curl -fsSL "$RAW/bobbahotel-web.service" -o /etc/systemd/system/bobbahotel-web.service
curl -fsSL "$RAW/bobbahotel-emu.service" -o /etc/systemd/system/bobbahotel-emu.service
curl -fsSL "$RAW/deploy.sh" -o /usr/local/bin/bobbahotel-deploy
chmod 755 /usr/local/bin/bobbahotel-deploy
curl -fsSL "$RAW/Caddyfile" | sed "s/hotel\.playbobba\.com/$DOMAIN/" > /etc/caddy/Caddyfile.new
caddy validate --config /etc/caddy/Caddyfile.new --adapter caddyfile >/dev/null
mv /etc/caddy/Caddyfile.new /etc/caddy/Caddyfile
systemctl enable caddy >/dev/null 2>&1
systemctl reload caddy 2>/dev/null || systemctl restart caddy

# The deploy may restart the two hotel services and nothing else.
cat > /etc/sudoers.d/bobbahotel.new <<'EOF'
bobba ALL=(root) NOPASSWD: /usr/bin/systemctl restart bobbahotel-web, /usr/bin/systemctl restart bobbahotel-emu
EOF
chmod 440 /etc/sudoers.d/bobbahotel.new
visudo -cf /etc/sudoers.d/bobbahotel.new >/dev/null
mv /etc/sudoers.d/bobbahotel.new /etc/sudoers.d/bobbahotel

systemctl daemon-reload
systemctl enable bobbahotel-web bobbahotel-emu >/dev/null 2>&1

say "Deploy key for GitHub Actions"
NEW_KEY=0
[ -f "$KEY" ] || { ssh-keygen -q -t ed25519 -N '' -C "github-actions-deploy" -f "$KEY"; NEW_KEY=1; }
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

if [ -f "$APP/current/emu/arcturus.jar" ]; then
  systemctl restart bobbahotel-emu bobbahotel-web
  echo "Hotel restarted on the current release."
else
  echo "No new-style release yet: the next push to main deploys one."
fi
if [ ! -f "$APP/sprites/hotelview.png" ]; then
  echo "Tip: put the hotel view picture at $APP/sprites/hotelview.png (it is built from the licensed art)."
fi

if [ "$NEW_KEY" = 1 ]; then
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
EOF
else
  say "Done. The GitHub deploy key is unchanged."
fi
