#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ ! -f ./tls.env ]]; then
  echo "[ERROR] tls.env not found in ${SCRIPT_DIR}"
  exit 1
fi

source ./tls.env

# -------------------------------------------------------------------
# Required config
# -------------------------------------------------------------------
: "${AUTO_TLS_LOCATION:?AUTO_TLS_LOCATION is required}"
: "${AUTO_TLS_WORKDIR:?AUTO_TLS_WORKDIR is required}"
: "${AUTO_TLS_HOSTS_CSV:?AUTO_TLS_HOSTS_CSV is required}"

: "${CM_HOST:?CM_HOST is required}"
: "${CM_PORT:?CM_PORT is required}"
: "${CM_API_VERSION:?CM_API_VERSION is required}"
: "${CM_USER:?CM_USER is required}"
: "${CM_PASSWORD:?CM_PASSWORD is required}"

: "${AUTO_TLS_SSH_USER:?AUTO_TLS_SSH_USER is required}"
: "${AUTO_TLS_SSH_PORT:?AUTO_TLS_SSH_PORT is required}"

: "${AUTO_TLS_KEYSTORE_PASSWORD:?AUTO_TLS_KEYSTORE_PASSWORD is required}"
: "${AUTO_TLS_TRUSTSTORE_PASSWORD:?AUTO_TLS_TRUSTSTORE_PASSWORD is required}"

echo "[INFO] Validating Auto-TLS prerequisites"
echo "[INFO] CM_HOST=${CM_HOST}"
echo "[INFO] CM_PORT=${CM_PORT}"
echo "[INFO] CM_API_VERSION=${CM_API_VERSION}"
echo "[INFO] AUTO_TLS_LOCATION=${AUTO_TLS_LOCATION}"
echo "[INFO] AUTO_TLS_WORKDIR=${AUTO_TLS_WORKDIR}"
echo "[INFO] AUTO_TLS_HOSTS_CSV=${AUTO_TLS_HOSTS_CSV}"
echo

# -------------------------------------------------------------------
# Validate local commands
# -------------------------------------------------------------------
for cmd in curl python3 ssh getent; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[ERROR] Required command not found: ${cmd}"
    exit 1
  fi
done

echo "[PASS] Required local commands found"

# -------------------------------------------------------------------
# Validate passwords
# -------------------------------------------------------------------
if [[ ${#AUTO_TLS_KEYSTORE_PASSWORD} -le 12 ]]; then
  echo "[ERROR] AUTO_TLS_KEYSTORE_PASSWORD must be longer than 12 characters"
  exit 1
fi

if [[ ${#AUTO_TLS_TRUSTSTORE_PASSWORD} -le 12 ]]; then
  echo "[ERROR] AUTO_TLS_TRUSTSTORE_PASSWORD must be longer than 12 characters"
  exit 1
fi

if [[ "${AUTO_TLS_KEYSTORE_PASSWORD}" =~ [^a-zA-Z0-9] ]]; then
  echo "[ERROR] AUTO_TLS_KEYSTORE_PASSWORD must not contain special characters"
  exit 1
fi

if [[ "${AUTO_TLS_TRUSTSTORE_PASSWORD}" =~ [^a-zA-Z0-9] ]]; then
  echo "[ERROR] AUTO_TLS_TRUSTSTORE_PASSWORD must not contain special characters"
  exit 1
fi

echo "[PASS] Auto-TLS passwords meet expected requirements"

# -------------------------------------------------------------------
# Validate hosts.csv
# -------------------------------------------------------------------
if [[ ! -f "${AUTO_TLS_HOSTS_CSV}" ]]; then
  echo "[ERROR] hosts.csv not found: ${AUTO_TLS_HOSTS_CSV}"
  exit 1
fi

HOST_COUNT="$(python3 - <<PY
import csv
from pathlib import Path

hosts_csv = Path("${AUTO_TLS_HOSTS_CSV}")

with hosts_csv.open(newline="") as f:
    reader = csv.DictReader(f)
    count = 0
    for row in reader:
        host = (row.get("host_id") or row.get("hostname") or row.get("host") or "").strip()
        if host:
            count += 1
    print(count)
PY
)"

if [[ "${HOST_COUNT}" -lt 1 ]]; then
  echo "[ERROR] No hosts found in ${AUTO_TLS_HOSTS_CSV}"
  exit 1
fi

echo "[PASS] hosts.csv found with ${HOST_COUNT} host(s)"

# -------------------------------------------------------------------
# Validate hostname resolution
# -------------------------------------------------------------------
echo
echo "[INFO] Validating DNS/host resolution"

python3 - <<PY > /tmp/autotls_hosts_to_check.txt
import csv
from pathlib import Path

hosts_csv = Path("${AUTO_TLS_HOSTS_CSV}")

with hosts_csv.open(newline="") as f:
    reader = csv.DictReader(f)
    for row in reader:
        host = (row.get("host_id") or row.get("hostname") or row.get("host") or "").strip()
        if host:
            print(host)
PY

while read -r host; do
  [[ -z "${host}" ]] && continue

  if getent hosts "${host}" >/dev/null 2>&1; then
    echo "[PASS] Host resolves: ${host}"
  else
    echo "[ERROR] Host does not resolve: ${host}"
    exit 1
  fi
done < /tmp/autotls_hosts_to_check.txt

# -------------------------------------------------------------------
# Validate Cloudera Manager API
# -------------------------------------------------------------------
echo
echo "[INFO] Validating Cloudera Manager API access"

CM_VERSION_URL="http://${CM_HOST}:${CM_PORT}/api/${CM_API_VERSION}/cm/version"
CM_AUTOTLS_URL="http://${CM_HOST}:${CM_PORT}/api/${CM_API_VERSION}/cm/commands/generateCmca"

echo "[INFO] Testing CM version endpoint:"
echo "[INFO] ${CM_VERSION_URL}"

HTTP_CODE="$(curl -sS -o /tmp/cm_version_response.txt -w "%{http_code}" \
  -u "${CM_USER}:${CM_PASSWORD}" \
  "${CM_VERSION_URL}" || true)"

if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "[ERROR] CM API version check failed"
  echo "[ERROR] HTTP status: ${HTTP_CODE}"
  echo "[ERROR] Response:"
  cat /tmp/cm_version_response.txt || true
  echo
  echo "[ERROR] Check CM_HOST, CM_PORT, CM_API_VERSION, CM_USER, and CM_PASSWORD in tls.env"
  exit 1
fi

echo "[PASS] CM API credentials worked"
echo "[INFO] CM version response:"
cat /tmp/cm_version_response.txt
echo

echo "[INFO] Auto-TLS endpoint that 07 will call:"
echo "[INFO] ${CM_AUTOTLS_URL}"

# -------------------------------------------------------------------
# Validate SSH to all hosts
# -------------------------------------------------------------------
echo
echo "[INFO] Validating passwordless SSH"

SSH_OPTS=(
  -p "${AUTO_TLS_SSH_PORT}"
  -o BatchMode=yes
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
)

if [[ -n "${AUTO_TLS_SSH_KEY_FILE:-}" ]]; then
  if [[ ! -f "${AUTO_TLS_SSH_KEY_FILE}" ]]; then
    echo "[ERROR] AUTO_TLS_SSH_KEY_FILE does not exist: ${AUTO_TLS_SSH_KEY_FILE}"
    exit 1
  fi

  SSH_OPTS+=(
    -i "${AUTO_TLS_SSH_KEY_FILE}"
    -o IdentitiesOnly=yes
  )

  echo "[INFO] Using SSH key: ${AUTO_TLS_SSH_KEY_FILE}"
fi

while read -r host; do
  [[ -z "${host}" ]] && continue

  echo "[INFO] Testing SSH to ${AUTO_TLS_SSH_USER}@${host}:${AUTO_TLS_SSH_PORT}"

  if ssh -n "${SSH_OPTS[@]}" "${AUTO_TLS_SSH_USER}@${host}" "hostname -f" >/tmp/ssh_test_output.txt 2>/tmp/ssh_test_error.txt; then
    echo "[PASS] SSH works: ${AUTO_TLS_SSH_USER}@${host}"
    echo "[INFO] Remote hostname: $(cat /tmp/ssh_test_output.txt)"
  else
    echo "[ERROR] Passwordless SSH failed for ${AUTO_TLS_SSH_USER}@${host}"
    echo "[ERROR] SSH error:"
    cat /tmp/ssh_test_error.txt || true
    echo
    echo "[ERROR] Fix passwordless SSH or update AUTO_TLS_SSH_USER/AUTO_TLS_SSH_PORT in tls.env"
    exit 1
  fi
done < /tmp/autotls_hosts_to_check.txt

# -------------------------------------------------------------------
# Validate Cloudera Manager can read Auto-TLS path
# -------------------------------------------------------------------
echo
echo "[INFO] Validating Auto-TLS filesystem paths"

mkdir -p "${AUTO_TLS_LOCATION}"
mkdir -p "${AUTO_TLS_WORKDIR}"

if id cloudera-scm >/dev/null 2>&1; then
  chown -R cloudera-scm:cloudera-scm "${AUTO_TLS_LOCATION}"

  if sudo -u cloudera-scm test -r "${AUTO_TLS_LOCATION}" 2>/dev/null; then
    echo "[PASS] cloudera-scm can read AUTO_TLS_LOCATION"
  else
    echo "[ERROR] cloudera-scm cannot read AUTO_TLS_LOCATION: ${AUTO_TLS_LOCATION}"
    exit 1
  fi

  if sudo -u cloudera-scm test -w "${AUTO_TLS_LOCATION}" 2>/dev/null; then
    echo "[PASS] cloudera-scm can write AUTO_TLS_LOCATION"
  else
    echo "[ERROR] cloudera-scm cannot write AUTO_TLS_LOCATION: ${AUTO_TLS_LOCATION}"
    exit 1
  fi
else
  echo "[WARN] cloudera-scm user not found. Skipping cloudera-scm filesystem validation."
fi

# -------------------------------------------------------------------
# Validate cert/key artifacts exist if prior steps already ran
# -------------------------------------------------------------------
echo
echo "[INFO] Checking whether generated artifacts already exist"

MISSING_ARTIFACTS=0

CA_CERT="${AUTO_TLS_WORKDIR}/ca/demo-ca-cert.pem"
if [[ -f "${CA_CERT}" ]]; then
  echo "[PASS] CA certificate found: ${CA_CERT}"
else
  echo "[WARN] CA certificate not found yet: ${CA_CERT}"
  MISSING_ARTIFACTS=1
fi

while read -r host; do
  [[ -z "${host}" ]] && continue

  CERT="${AUTO_TLS_WORKDIR}/certs/${host}-cert.pem"
  KEY="${AUTO_TLS_WORKDIR}/keys/${host}-key.pem"

  if [[ -f "${CERT}" ]]; then
    echo "[PASS] Host cert found: ${CERT}"
  else
    echo "[WARN] Host cert not found yet: ${CERT}"
    MISSING_ARTIFACTS=1
  fi

  if [[ -f "${KEY}" ]]; then
    echo "[PASS] Host key found: ${KEY}"
  else
    echo "[WARN] Host key not found yet: ${KEY}"
    MISSING_ARTIFACTS=1
  fi
done < /tmp/autotls_hosts_to_check.txt

echo
if [[ "${MISSING_ARTIFACTS}" -eq 1 ]]; then
  echo "[WARN] Some cert artifacts are missing."
  echo "[WARN] That is okay if you are running this before steps 01 through 04."
  echo "[WARN] Before running 07, make sure steps 01 through 04 and 06 pass."
else
  echo "[PASS] Required cert/key artifacts are present."
fi

echo
echo "[PASS] Auto-TLS prerequisite validation completed"
echo
echo "[INFO] Next recommended steps:"
echo "[INFO] ./06_validate_artifacts.sh"
echo "[INFO] ./07_enable_autotls.sh"
