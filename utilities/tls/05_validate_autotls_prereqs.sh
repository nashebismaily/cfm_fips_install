#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ ! -f ./tls.env ]]; then
  echo "[ERROR] tls.env not found in ${SCRIPT_DIR}"
  exit 1
fi

source ./tls.env

: "${AUTO_TLS_LOCATION:?AUTO_TLS_LOCATION is required}"
: "${AUTO_TLS_WORKDIR:?AUTO_TLS_WORKDIR is required}"
: "${AUTO_TLS_HOSTS_CSV:?AUTO_TLS_HOSTS_CSV is required}"
: "${AUTO_TLS_KEY_DIR:?AUTO_TLS_KEY_DIR is required}"
: "${AUTO_TLS_CERT_DIR:?AUTO_TLS_CERT_DIR is required}"
: "${CM_HOST:?CM_HOST is required}"
: "${CM_PORT:?CM_PORT is required}"
: "${CM_API_VERSION:?CM_API_VERSION is required}"
: "${CM_USER:?CM_USER is required}"
: "${CM_PASSWORD:?CM_PASSWORD is required}"
: "${AUTO_TLS_SSH_USER:?AUTO_TLS_SSH_USER is required}"
: "${AUTO_TLS_SSH_PORT:?AUTO_TLS_SSH_PORT is required}"
: "${AUTO_TLS_KEYSTORE_PASSWORD:?AUTO_TLS_KEYSTORE_PASSWORD is required}"
: "${AUTO_TLS_TRUSTSTORE_PASSWORD:?AUTO_TLS_TRUSTSTORE_PASSWORD is required}"
: "${AUTO_TLS_HOST_KEY_PASSWORD:?AUTO_TLS_HOST_KEY_PASSWORD is required}"

echo "[INFO] Validating Auto-TLS prerequisites"
echo "[INFO] CM_HOST=${CM_HOST}"
echo "[INFO] CM_PORT=${CM_PORT}"
echo "[INFO] CM_API_VERSION=${CM_API_VERSION}"
echo "[INFO] AUTO_TLS_LOCATION=${AUTO_TLS_LOCATION}"
echo "[INFO] AUTO_TLS_WORKDIR=${AUTO_TLS_WORKDIR}"
echo "[INFO] AUTO_TLS_HOSTS_CSV=${AUTO_TLS_HOSTS_CSV}"
echo

for cmd in curl python3 ssh getent openssl; do
  command -v "${cmd}" >/dev/null 2>&1 || { echo "[ERROR] Required command not found: ${cmd}"; exit 1; }
done
echo "[PASS] Required local commands found"

for password_name in AUTO_TLS_KEYSTORE_PASSWORD AUTO_TLS_TRUSTSTORE_PASSWORD AUTO_TLS_HOST_KEY_PASSWORD; do
  password_value="${!password_name}"
  if [[ ${#password_value} -le 12 ]]; then
    echo "[ERROR] ${password_name} must be longer than 12 characters"
    exit 1
  fi
  if [[ "${password_value}" =~ [^a-zA-Z0-9] ]]; then
    echo "[ERROR] ${password_name} must not contain special characters for this Auto-TLS flow"
    exit 1
  fi
done
echo "[PASS] Auto-TLS passwords meet expected requirements"

[[ -f "${AUTO_TLS_HOSTS_CSV}" ]] || { echo "[ERROR] hosts.csv not found: ${AUTO_TLS_HOSTS_CSV}"; exit 1; }

python3 - <<PY > /tmp/autotls_hosts_to_check.txt
import csv
from pathlib import Path
hosts_csv = Path("${AUTO_TLS_HOSTS_CSV}")
count = 0
with hosts_csv.open(newline="") as f:
    reader = csv.DictReader(f)
    if not reader.fieldnames:
        raise SystemExit("[ERROR] hosts.csv has no header row")
    for row in reader:
        host = (row.get("host_id") or row.get("hostname") or row.get("host") or "").strip()
        if host:
            print(host)
            count += 1
if count < 1:
    raise SystemExit("[ERROR] No hosts found in hosts.csv")
PY

HOST_COUNT="$(wc -l < /tmp/autotls_hosts_to_check.txt | tr -d ' ')"
echo "[PASS] hosts.csv found with ${HOST_COUNT} host(s)"

echo
echo "[INFO] Validating DNS/host resolution"
while read -r host; do
  [[ -z "${host}" ]] && continue
  if getent hosts "${host}" >/dev/null 2>&1; then
    echo "[PASS] Host resolves: ${host}"
  else
    echo "[ERROR] Host does not resolve: ${host}"
    exit 1
  fi
done < /tmp/autotls_hosts_to_check.txt

echo
echo "[INFO] Validating Cloudera Manager API access"
CM_VERSION_URL="http://${CM_HOST}:${CM_PORT}/api/${CM_API_VERSION}/cm/version"
CM_AUTOTLS_URL="http://${CM_HOST}:${CM_PORT}/api/${CM_API_VERSION}/cm/commands/generateCmca"
echo "[INFO] Testing CM version endpoint: ${CM_VERSION_URL}"
HTTP_CODE="$(curl -sS -o /tmp/cm_version_response.txt -w "%{http_code}" -u "${CM_USER}:${CM_PASSWORD}" "${CM_VERSION_URL}" || true)"
if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "[ERROR] CM API version check failed. HTTP status: ${HTTP_CODE}"
  cat /tmp/cm_version_response.txt || true
  exit 1
fi
echo "[PASS] CM API credentials worked"
cat /tmp/cm_version_response.txt
echo
echo "[INFO] Auto-TLS endpoint that 07 will call: ${CM_AUTOTLS_URL}"

echo
echo "[INFO] Validating passwordless SSH"
SSH_OPTS=(-p "${AUTO_TLS_SSH_PORT}" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)
if [[ -n "${AUTO_TLS_SSH_KEY_FILE:-}" ]]; then
  [[ -f "${AUTO_TLS_SSH_KEY_FILE}" ]] || { echo "[ERROR] AUTO_TLS_SSH_KEY_FILE does not exist: ${AUTO_TLS_SSH_KEY_FILE}"; exit 1; }
  SSH_OPTS+=(-i "${AUTO_TLS_SSH_KEY_FILE}" -o IdentitiesOnly=yes)
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
    cat /tmp/ssh_test_error.txt || true
    exit 1
  fi
done < /tmp/autotls_hosts_to_check.txt

echo
echo "[INFO] Validating Auto-TLS filesystem paths"
mkdir -p "${AUTO_TLS_LOCATION}" "${AUTO_TLS_WORKDIR}"
if id cloudera-scm >/dev/null 2>&1; then
  chown -R cloudera-scm:cloudera-scm "${AUTO_TLS_LOCATION}"
  if command -v sudo >/dev/null 2>&1; then
    sudo -u cloudera-scm test -r "${AUTO_TLS_LOCATION}" || { echo "[ERROR] cloudera-scm cannot read ${AUTO_TLS_LOCATION}"; exit 1; }
    sudo -u cloudera-scm test -w "${AUTO_TLS_LOCATION}" || { echo "[ERROR] cloudera-scm cannot write ${AUTO_TLS_LOCATION}"; exit 1; }
  else
    runuser -u cloudera-scm -- test -r "${AUTO_TLS_LOCATION}" || { echo "[ERROR] cloudera-scm cannot read ${AUTO_TLS_LOCATION}"; exit 1; }
    runuser -u cloudera-scm -- test -w "${AUTO_TLS_LOCATION}" || { echo "[ERROR] cloudera-scm cannot write ${AUTO_TLS_LOCATION}"; exit 1; }
  fi
  echo "[PASS] cloudera-scm can read/write AUTO_TLS_LOCATION"
else
  echo "[WARN] cloudera-scm user not found. Skipping cloudera-scm filesystem validation."
fi

echo
echo "[INFO] Checking whether generated artifacts already exist"
MISSING=0
CA_CERT="${AUTO_TLS_WORKDIR}/ca/demo-ca-cert.pem"
if [[ -f "${CA_CERT}" ]]; then echo "[PASS] CA certificate found: ${CA_CERT}"; else echo "[WARN] CA certificate not found yet: ${CA_CERT}"; MISSING=1; fi
while read -r host; do
  [[ -z "${host}" ]] && continue
  CERT="${AUTO_TLS_CERT_DIR}/${host}-cert.pem"
  KEY="${AUTO_TLS_KEY_DIR}/${host}-key.pem"
  if [[ -f "${CERT}" ]]; then echo "[PASS] Host cert found: ${CERT}"; else echo "[WARN] Host cert not found yet: ${CERT}"; MISSING=1; fi
  if [[ -f "${KEY}" ]]; then
    echo "[PASS] Host key found: ${KEY}"
    if openssl pkey -in "${KEY}" -passin "pass:${AUTO_TLS_HOST_KEY_PASSWORD}" -check -noout >/tmp/key_check.txt 2>/tmp/key_check_err.txt; then
      echo "[PASS] Host key password works for ${host}"
    else
      echo "[ERROR] Host key password failed for ${host}"
      cat /tmp/key_check_err.txt || true
      exit 1
    fi
  else
    echo "[WARN] Host key not found yet: ${KEY}"
    MISSING=1
  fi
done < /tmp/autotls_hosts_to_check.txt

echo
if [[ "${MISSING}" -eq 1 ]]; then
  echo "[WARN] Some cert artifacts are missing. That is okay before steps 01 through 04."
else
  echo "[PASS] Required cert/key artifacts are present."
fi

echo
echo "[PASS] Auto-TLS prerequisite validation completed"
echo "[INFO] Next recommended steps:"
echo "[INFO] ./06_validate_artifacts.sh"
echo "[INFO] ./07_enable_autotls.sh"
