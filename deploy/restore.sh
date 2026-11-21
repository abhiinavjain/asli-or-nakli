#!/bin/bash
# Loads the 4 dumps in deploy/dumps/ into the containers and re-points the
# mediator's foreign servers. Run once on the server:  bash restore.sh
set -euo pipefail
cd "$(dirname "$0")"
# read single values (not `source`: the password hash contains $ signs)
val() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*//'; }
PG_PASSWORD="$(val PG_PASSWORD)"
DOMAIN="$(val DOMAIN)"

# compose service -> database name inside that container
# (the manufacturer DB is called manuf_db; the others are <service>_db)
dbname() { case "$1" in manufacturer) echo manuf_db ;; *) echo "${1}_db" ;; esac; }

SERVICES="manufacturer distributor vendor mediator"   # sources first, mediator last

for svc in $SERVICES; do
  [ -f "dumps/$(dbname "$svc").dump" ] || { echo "missing dumps/$(dbname "$svc").dump"; exit 1; }
done

docker compose up -d --build $SERVICES
docker compose up -d --wait $SERVICES

# "already exists" messages about the public schema are harmless;
# pg_restore prints a count of ignored errors at the end.
for svc in $SERVICES; do
  db="$(dbname "$svc")"
  echo "== restoring ${db} into ${svc}"
  docker compose exec -T "$svc" pg_restore -U postgres -d "$db" --no-owner "/dumps/${db}.dump" || true
done

echo "== re-pointing the mediator's foreign servers"
docker compose exec -T mediator psql -U postgres -d mediator_db -v ON_ERROR_STOP=1 \
  -v pw="$PG_PASSWORD" -f /repoint.sql

docker compose up -d --build app caddy
echo "Done. Open https://$DOMAIN"
