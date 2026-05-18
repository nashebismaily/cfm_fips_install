#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "11_prepare_cm_database"
need_root
validate_platform
ensure_java_default
validate_java_11

PREP_SCRIPT="/opt/cloudera/cm/schema/scm_prepare_database.sh"
if [[ ! -x "$PREP_SCRIPT" ]]; then
  echo "[ERROR] Missing $PREP_SCRIPT. Install cloudera-manager-server first."
  exit 1
fi

SERVICE="$(pg_service_name)"
if ! systemctl is-active --quiet "$SERVICE"; then
  echo "[ERROR] ${SERVICE} is not running. Start PostgreSQL before preparing the CM database."
  exit 1
fi

if command -v nc >/dev/null 2>&1; then
  nc -zv localhost "${POSTGRES_PORT:-5432}"
fi

# Ensure PostgreSQL JDBC driver is available where CM expects it.
JDBC_DIR="/usr/share/java"
mkdir -p "$JDBC_DIR"
if ! ls "$JDBC_DIR"/postgresql*.jar >/dev/null 2>&1; then
  echo "==== Installing PostgreSQL JDBC driver package if available ===="
  dnf install -y postgresql-jdbc
  # postgresql-jdbc may pull Java 8 on RHEL 8. Force Java 11 back as the default.
  ensure_java_default
  validate_java_11
fi

if ! ls "$JDBC_DIR"/postgresql*.jar >/dev/null 2>&1; then
  echo "[ERROR] PostgreSQL JDBC jar not found in /usr/share/java. Install postgresql-jdbc or place the driver jar there."
  exit 1
fi

# One more Java check immediately before scm_prepare_database.sh.
ensure_java_default
validate_java_11

echo "==== Running scm_prepare_database.sh ===="
"$PREP_SCRIPT" postgresql "${CM_DB_NAME}" "${CM_DB_USER}" "${CM_DB_PASS}"

echo "[OK] Cloudera Manager database prepared"
