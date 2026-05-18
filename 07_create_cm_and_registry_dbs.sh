#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "07_create_cm_and_registry_dbs"
need_root
validate_platform

SERVICE="$(pg_service_name)"
systemctl is-active --quiet "$SERVICE" || systemctl start "$SERVICE"

create_db_user() {
  local db="$1" user="$2" pass="$3"
  echo "---- Ensuring role/database: ${user}/${db}"
  sudo -u postgres psql -v ON_ERROR_STOP=1 <<EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${user}') THEN
    CREATE ROLE ${user} LOGIN PASSWORD '${pass}';
  ELSE
    ALTER ROLE ${user} WITH LOGIN PASSWORD '${pass}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${db} OWNER ${user} ENCODING ''UTF8''' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db}')\gexec
GRANT ALL PRIVILEGES ON DATABASE ${db} TO ${user};
EOSQL
}

create_db_user "${CM_DB_NAME}" "${CM_DB_USER}" "${CM_DB_PASS}"
create_db_user "${RM_DB_NAME}" "${RM_DB_USER}" "${RM_DB_PASS}"
create_db_user "${REG_DB_NAME}" "${REG_DB_USER}" "${REG_DB_PASS}"

if [[ "${CREATE_EXTRA_DBS:-false}" == "true" ]]; then
  create_db_user "${HUE_DB_NAME}" "${HUE_DB_USER}" "${HUE_DB_PASS}"
  create_db_user "${HIVE_DB_NAME}" "${HIVE_DB_USER}" "${HIVE_DB_PASS}"
  create_db_user "${RANGER_DB_NAME}" "${RANGER_DB_USER}" "${RANGER_DB_PASS}"
fi

echo
echo "==== Databases ===="
sudo -u postgres psql -c "\l"

echo "[OK] CM / Reports Manager / NiFi Registry databases ready"
