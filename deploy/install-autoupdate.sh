#!/usr/bin/env bash
# One-time: turn on automatic updates (checks GitHub every minute).  bash /opt/bobbahotel/deploy/install-autoupdate.sh
set -euo pipefail
chmod +x /opt/bobbahotel/deploy/*.sh
cat > /etc/systemd/system/bobbahotel-update.service <<'UNIT'
[Unit]
Description=Update Bobba Hotel from GitHub
[Service]
Type=oneshot
ExecStart=/opt/bobbahotel/deploy/autoupdate.sh
UNIT
cat > /etc/systemd/system/bobbahotel-update.timer <<'UNIT'
[Unit]
Description=Check GitHub for Bobba Hotel updates every minute
[Timer]
OnBootSec=60
OnUnitActiveSec=60
AccuracySec=5
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload && systemctl enable --now bobbahotel-update.timer
echo "Auto-update is on. Watch it with:  journalctl -u bobbahotel-update -f"
