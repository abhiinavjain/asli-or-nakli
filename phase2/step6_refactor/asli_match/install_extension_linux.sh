#!/bin/bash
# Asli-or-Nakli: copies the asli_match extension files into PostgreSQL.
# For Linux and WSL (run it INSIDE the Linux / WSL terminal where PostgreSQL runs):
#     sudo bash install_extension_linux.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
EXT=""

# 1. ask the running server its major version (e.g. 16) and use the usual folders
VER=$(sudo -u postgres psql -Atc "SHOW server_version_num" 2>/dev/null | cut -c1-2 || true)
for d in /usr/share/postgresql/$VER/extension /usr/pgsql-$VER/share/extension /usr/share/pgsql/extension; do
  if [ -n "$VER" ] && [ -d "$d" ]; then EXT="$d"; break; fi
done
# 2. otherwise ask pg_config
if [ -z "$EXT" ] && command -v pg_config >/dev/null; then EXT="$(pg_config --sharedir)/extension"; fi

if [ -z "$EXT" ] || [ ! -d "$EXT" ]; then
  echo "Could not find the PostgreSQL extension folder."
  echo "Find it with:  ls -d /usr/share/postgresql/*/extension   and copy the two files there by hand."
  exit 1
fi
cp "$DIR/asli_match.control" "$DIR/asli_match--1.0.sql" "$EXT/"
echo "Installed asli_match into $EXT (PostgreSQL $VER)."
echo "Now run the *_06_candidate_indexes.sql script for this database in DBeaver."
