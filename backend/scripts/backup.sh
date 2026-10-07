#!/usr/bin/env bash
# A compressed dump of the server's Postgres (the team store and counters), kept 14 days, for a
# daily cron job on the server:
#
#   0 4 * * * /home/ubuntu/PKReference/backend/scripts/backup.sh
#
# The dumps are on the server's own disk: copy them off it too (README, "Running it on a server"),
# so losing the machine doesn't lose them. Kafka's topics can be fetched again from Limitless.
set -euo pipefail
dir="${BACKUP_DIR:-$HOME/pkref-backups}"
mkdir -p "$dir"
file="$dir/pkref-$(date -u +%Y-%m-%dT%H%MZ).sql.gz"
trap 'rm -f "$file.tmp"' EXIT
docker exec "${PG_CONTAINER:-pkref-postgres}" pg_dump -U pkref -d pkref | gzip > "$file.tmp"
mv "$file.tmp" "$file"
find "$dir" -name 'pkref-*.sql.gz' -mtime +14 -delete
echo "$file"
