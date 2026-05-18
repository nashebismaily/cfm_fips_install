#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "06_configure_postgres_networking"
need_root
validate_platform

PG_MAJOR="${PG_MAJOR:-14}"
PGDATA_DIR="${PGDATA_DIR:-/data/postgres${PG_MAJOR}}"
SERVICE="$(pg_service_name)"
ALLOWED_CIDR="${ALLOWED_CIDR:-10.0.0.0/20}"

if [[ ! -d "$PGDATA_DIR" ]]; then
  echo "[ERROR] PGDATA_DIR not found: $PGDATA_DIR"
  exit 1
fi

POSTGRESQL_CONF="$PGDATA_DIR/postgresql.conf"
PG_HBA="$PGDATA_DIR/pg_hba.conf"

cp -a "$POSTGRESQL_CONF" "${POSTGRESQL_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
cp -a "$PG_HBA" "${PG_HBA}.bak.$(date +%Y%m%d_%H%M%S)"

if grep -q "^[#[:space:]]*listen_addresses" "$POSTGRESQL_CONF"; then
  sed -i "s/^[#[:space:]]*listen_addresses.*/listen_addresses = '*'/" "$POSTGRESQL_CONF"
else
  echo "listen_addresses = '*'" >> "$POSTGRESQL_CONF"
fi

# Keep local socket access and allow the VPC/application CIDR using scram-sha-256.
ensure_line "$PG_HBA" "host    all             all             127.0.0.1/32            scram-sha-256"
ensure_line "$PG_HBA" "host    all             all             ::1/128                 scram-sha-256"
ensure_line "$PG_HBA" "host    all             all             ${ALLOWED_CIDR}            scram-sha-256"

systemctl restart "$SERVICE"
sleep 3
ss -plnt | grep 5432 || true
sudo -u postgres psql -c "SHOW listen_addresses;"

echo "[OK] PostgreSQL networking configured for ${ALLOWED_CIDR}"
