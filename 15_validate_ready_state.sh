#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "15_validate_ready_state"

validate_platform

echo "==== Python ===="
echo "System Python: $(python3 --version 2>/dev/null || echo missing)"
echo "Required CM Agent Python: $(required_agent_python_bin)"
if [[ -x "$(required_agent_python_bin)" ]]; then
  "$(required_agent_python_bin)" --version || true
else
  echo "[WARN] Required CM Agent Python missing: $(required_agent_python_bin)"
fi
validate_cm_agent_python_wrapper || true

echo
echo "==== Java ===="
validate_java_11 || true
if [[ "${CONFIGURE_JAVA_FIPS:-true}" == "true" ]]; then
  validate_java_fips_providers || true
fi

echo
echo "==== PostgreSQL ===="
SERVICE="$(pg_service_name)"
systemctl status "$SERVICE" --no-pager 2>/dev/null || true
if command -v psql >/dev/null 2>&1; then
  sudo -u postgres psql -c "SELECT version();" 2>/dev/null || true
fi
ss -plnt | grep 5432 || true

echo
echo "==== Cloudera Manager ===="
systemctl status cloudera-scm-server --no-pager 2>/dev/null || true
systemctl status cloudera-scm-supervisord --no-pager 2>/dev/null || true
systemctl status cloudera-scm-agent --no-pager 2>/dev/null || true
ss -plnt | egrep ':7180|:7182' || true

echo
echo "==== CSDs ===="
ls -lh /opt/cloudera/csd 2>/dev/null | grep -E 'NIFI|NIFIREGISTRY' || true

echo
echo "==== CFM parcel / FIPS jars ===="
echo "Expected CFM parcel root: ${CFM_PARCEL_ROOT}"
if [[ -d "${CFM_TOOLKIT_LIB_DIR:-/missing}" ]]; then
  echo "[OK] Toolkit lib dir exists: ${CFM_TOOLKIT_LIB_DIR}"
  for jar in "${FIPS_BCTLS_JAR:-bctls.jar}" "${FIPS_CCJ_JAR:-ccj-3.0.2.1.jar}"; do
    if [[ -f "${CFM_TOOLKIT_LIB_DIR}/$jar" ]]; then
      echo "[OK] Found ${CFM_TOOLKIT_LIB_DIR}/$jar"
    else
      echo "[WARN] Missing ${CFM_TOOLKIT_LIB_DIR}/$jar"
    fi
  done
else
  echo "[WARN] CFM toolkit lib dir not found yet. Activate CFM parcel first."
fi

echo
echo "==== Manual CM UI reminders ===="
cat <<EOFMSG
1. Deploy CDP Base/Runtime ${CDP_RUNTIME_VERSION} services first. ZooKeeper comes from Base.
2. Add CFM parcel repo: ${CFM_PARCEL_REPO_URL}
3. Download, distribute, and activate the CFM parcel.
4. Run 14_install_cfm_fips_jars.sh after the parcel is active.
5. TLS is intentionally not configured by these scripts. Configure real enterprise certs later.
6. For FIPS TLS, use BCFKS keystore/truststore and the bootstrap safety-valve settings in README.md.
7. Set NiFi sensitive props algorithm to ${NIFI_SENSITIVE_PROPS_ALGORITHM} and use a key at least 12 chars.
EOFMSG

echo "[OK] Validation complete"
