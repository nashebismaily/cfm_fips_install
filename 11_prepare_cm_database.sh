#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "11_prepare_cm_database"
need_root
validate_platform
validate_java_11

PREP_SCRIPT="/opt/cloudera/cm/schema/scm_prepare_database.sh"
if [[ ! -x "$PREP_SCRIPT" ]]; then
  echo "[ERROR] Missing $PREP_SCRIPT. Install cloudera-manager-server first."
  exit 1
fi

# Ensure PostgreSQL JDBC driver is available where CM expects it.
JDBC_DIR="/usr/share/java"
mkdir -p "$JDBC_DIR"
if ! ls "$JDBC_DIR"/postgresql*.jar >/dev/null 2>&1; then
  echo "==== Installing PostgreSQL JDBC driver package if available ===="
  dnf install -y postgresql-jdbc || true
fi

if ! ls "$JDBC_DIR"/postgresql*.jar >/dev/null 2>&1; then
  echo "[WARN] PostgreSQL JDBC jar not found in /usr/share/java. CM database prep may fail unless the package installed it elsewhere."
fi

echo "==== Running scm_prepare_database.sh ===="
"$PREP_SCRIPT" postgresql "${CM_DB_NAME}" "${CM_DB_USER}" "${CM_DB_PASS}"

echo "[OK] Cloudera Manager database prepared"
