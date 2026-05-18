#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "05_install_postgres"
need_root
validate_platform

PG_MAJOR="${PG_MAJOR:-14}"
PGDATA_DIR="${PGDATA_DIR:-/data/postgres${PG_MAJOR}}"
SERVICE="$(pg_service_name)"
PG_BIN_DIR="$(pg_bin_dir)"

if [[ "$PG_MAJOR" != "14" ]]; then
  echo "[WARN] Default validated target for CDP 7.1.9/7.3.1 FIPS install kit is PG 14. Current PG_MAJOR=$PG_MAJOR. Confirm support matrix before proceeding."
fi

echo "==== Installing PostgreSQL ${PG_MAJOR} ===="
dnf install -y "postgresql${PG_MAJOR}" "postgresql${PG_MAJOR}-server" "postgresql${PG_MAJOR}-contrib" "postgresql${PG_MAJOR}-devel"

if ! id postgres >/dev/null 2>&1; then
  echo "[ERROR] postgres OS user was not created by the PostgreSQL packages."
  exit 1
fi

mkdir -p "$PGDATA_DIR"
chown -R postgres:postgres "$PGDATA_DIR"
chmod 700 "$PGDATA_DIR"

# The PGDG systemd unit defaults to /var/lib/pgsql/<major>/data. The install kit
# uses PGDATA_DIR from EXPORTS, so create a systemd drop-in instead of hardcoding.
OVERRIDE_DIR="/etc/systemd/system/${SERVICE}.service.d"
mkdir -p "$OVERRIDE_DIR"
cat >"${OVERRIDE_DIR}/override.conf" <<EOFPGDATA
[Service]
Environment=PGDATA=${PGDATA_DIR}
EOFPGDATA

# Keep the legacy sysconfig file in sync as well. Some PGDG/RHEL packaging paths
# still read it or make troubleshooting easier.
SYSCONFIG="/etc/sysconfig/pgsql/postgresql-${PG_MAJOR}"
mkdir -p /etc/sysconfig/pgsql
cat >"$SYSCONFIG" <<EOFPG
PGDATA=${PGDATA_DIR}
EOFPG

# Label custom PGDATA for SELinux when available. If semanage is not present yet,
# the script continues, but policycoreutils-python-utils should normally install it.
if command -v semanage >/dev/null 2>&1; then
  semanage fcontext -a -t postgresql_db_t "${PGDATA_DIR}(/.*)?" 2>/dev/null || \
    semanage fcontext -m -t postgresql_db_t "${PGDATA_DIR}(/.*)?" || true
  restorecon -Rv "$PGDATA_DIR" || true
else
  echo "[WARN] semanage not found; skipping SELinux fcontext for ${PGDATA_DIR}"
fi

if [[ ! -f "$PGDATA_DIR/PG_VERSION" ]]; then
  echo "==== Initializing database at ${PGDATA_DIR} ===="
  sudo -u postgres "$PG_BIN_DIR/initdb" -D "$PGDATA_DIR"
else
  echo "[INFO] Existing PostgreSQL data directory detected at ${PGDATA_DIR}"
fi

chown -R postgres:postgres "$PGDATA_DIR"
chmod 700 "$PGDATA_DIR"

systemctl daemon-reload
systemctl enable "$SERVICE"
systemctl reset-failed "$SERVICE" || true
systemctl restart "$SERVICE"

sleep 3
systemctl status "$SERVICE" --no-pager
sudo -u postgres "$PG_BIN_DIR/psql" -c "SELECT version();"

echo "[OK] PostgreSQL ${PG_MAJOR} installed and running with PGDATA=${PGDATA_DIR}"
