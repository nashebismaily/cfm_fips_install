#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "05_install_postgres"
need_root
validate_platform

PG_MAJOR="${PG_MAJOR:-14}"
PGDATA_DIR="${PGDATA_DIR:-/data/postgres${PG_MAJOR}}"
SERVICE="$(pg_service_name)"

if [[ "$PG_MAJOR" != "14" ]]; then
  echo "[WARN] Default validated target for CDP 7.1.9 FIPS is PG 14. Current PG_MAJOR=$PG_MAJOR. Confirm support matrix before proceeding."
fi

echo "==== Installing PostgreSQL ${PG_MAJOR} ===="
dnf install -y "postgresql${PG_MAJOR}" "postgresql${PG_MAJOR}-server" "postgresql${PG_MAJOR}-contrib" "postgresql${PG_MAJOR}-devel"

mkdir -p "$PGDATA_DIR"
chown -R postgres:postgres "$(dirname "$PGDATA_DIR")" "$PGDATA_DIR"
chmod 700 "$PGDATA_DIR"

# The PGDG unit uses PGDATA from /etc/sysconfig/pgsql/postgresql-XX.
SYSCONFIG="/etc/sysconfig/pgsql/postgresql-${PG_MAJOR}"
mkdir -p /etc/sysconfig/pgsql
cat >"$SYSCONFIG" <<EOFPG
PGDATA=${PGDATA_DIR}
EOFPG

if [[ ! -f "$PGDATA_DIR/PG_VERSION" ]]; then
  echo "==== Initializing database at ${PGDATA_DIR} ===="
  sudo -u postgres "$(pg_bin_dir)/initdb" -D "$PGDATA_DIR"
else
  echo "[INFO] Existing PostgreSQL data directory detected at ${PGDATA_DIR}"
fi

systemctl enable "$SERVICE"
systemctl restart "$SERVICE"

sleep 3
systemctl status "$SERVICE" --no-pager || true
sudo -u postgres psql -c "SELECT version();"

echo "[OK] PostgreSQL ${PG_MAJOR} installed and running"
