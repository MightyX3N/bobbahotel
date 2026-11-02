#!/usr/bin/env bash
# Run once as root on a fresh Ubuntu 24.04 VPS:  bash setup.sh
set -euo pipefail
apt-get update && apt-get install -y curl git ufw debian-keyring debian-archive-keyring apt-transport-https gpg
# Node 22
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt-get install -y nodejs
# Caddy
rm -f /etc/apt/sources.list.d/caddy.list
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
apt-get update && apt-get install -y caddy
# app
id bobba >/dev/null 2>&1 || useradd -r -m -s /usr/sbin/nologin bobba
mkdir -p /var/lib/bobbahotel /opt/bobbahotel/sprites && chown bobba /var/lib/bobbahotel
[ -d /opt/bobbahotel/.git ] || git clone https://github.com/MightyX3N/bobbahotel /opt/bobbahotel.tmp && { [ -d /opt/bobbahotel/.git ] || { cp -a /opt/bobbahotel.tmp/. /opt/bobbahotel/ && rm -rf /opt/bobbahotel.tmp; }; }
cd /opt/bobbahotel && git pull
(cd server && npm ci)
(cd client && npm ci && npm run build)
chown -R bobba /opt/bobbahotel/server
cp deploy/bobbahotel.service /etc/systemd/system/ && cp deploy/Caddyfile /etc/caddy/Caddyfile
systemctl daemon-reload && systemctl enable --now bobbahotel && systemctl restart caddy
# firewall: SSH + web only
ufw allow 22 && ufw allow 80 && ufw allow 443 && ufw --force enable
bash /opt/bobbahotel/deploy/install-autoupdate.sh
echo "Done. Now upload the sprites to /opt/bobbahotel/sprites (tiles/ and cozy/)."
