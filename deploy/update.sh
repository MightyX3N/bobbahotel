#!/usr/bin/env bash
# Pull the latest code and restart: bash /opt/bobbahotel/deploy/update.sh
set -euo pipefail
cd /opt/bobbahotel && git pull
(cd server && npm ci) && (cd client && npm ci && npm run build)
systemctl restart bobbahotel
