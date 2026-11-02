#!/bin/sh
# Installed to /etc/cron.daily/bobbahotel-backup by deploy/setup.sh.
# Makes a safe copy of the database every night and keeps two weeks of copies.
set -eu
DB=/var/lib/bobbahotel/hotel.db
OUT=/var/backups/bobbahotel
[ -f "$DB" ] || exit 0
mkdir -p "$OUT"
sqlite3 "$DB" ".backup '$OUT/hotel-$(date +%F).db'"
find "$OUT" -name 'hotel-*.db' -mtime +14 -delete
