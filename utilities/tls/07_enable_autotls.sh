#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ ! -f ./tls.env ]]; then
  echo "[ERROR] tls.env not found in ${SCRIPT_DIR}"
  exit 1
fi

source ./tls.env

: "${AUTO_TLS_WORKDIR:?AUTO_TLS_WORKDIR is required}"
: "${AUTO_TLS_HOSTS_CSV:?AUTO_TLS_HOSTS_CSV is required}"
: "${AUTO_TLS_KEYSTORE_PASSWORD:?AUTO_TLS_KEYSTORE_PASSWORD is required}"
: "${AUTO_TLS_TRUSTSTORE_PASSWORD:?AUTO_TLS_TRUSTSTORE_PASSWORD is required}"
: "${AUTO_TLS_KEY_DIR:?AUTO_TLS_KEY_DIR is required}"
: "${AUTO_TLS_CERT_DIR:?AUTO_TLS_CERT_DIR is required}"
: "${AUTO_TLS_PAYLOAD_DIR:?AUTO_TLS_PAYLOAD_DIR is required}"
: "${CM_HOST:?CM_HOST is required}"
: "${CM_PORT:?CM_PORT is required}"
: "${CM_API_VERSION:?CM_API_VERSION is required}"
: "${CM_USER:?CM_USER is required}"
: "${CM_PASSWORD:?CM_PASSWORD is required}"
: "${AUTO_TLS_LOCATION:?AUTO_TLS_LOCATION is required}"
: "${AUTO_TLS_PAYLOAD_FILE:?AUTO_TLS_PAYLOAD_FILE is required}"
: "${AUTO_TLS_SSH_USER:?AUTO_TLS_SSH_USER is required}"
: "${AUTO_TLS_SSH_PORT:?AUTO_TLS_SSH_PORT is required}"
: "${AUTO_TLS_CONFIGURE_ALL_SERVICES:?AUTO_TLS_CONFIGURE_ALL_SERVICES is required}"

AUTO_TLS_ENCRYPT_HOST_KEYS="${AUTO_TLS_ENCRYPT_HOST_KEYS:-true}"
AUTO_TLS_HOST_KEY_PASSWORD="${AUTO_TLS_HOST_KEY_PASSWORD:-}"
AUTO_TLS_SSH_KEY_FILE="${AUTO_TLS_SSH_KEY_FILE:-}"

if [[ "${AUTO_TLS_ENCRYPT_HOST_KEYS}" != "true" && "${AUTO_TLS_ENCRYPT_HOST_KEYS}" != "false" ]]; then
  echo "[ERROR] AUTO_TLS_ENCRYPT_HOST_KEYS must be true or false. Current value: ${AUTO_TLS_ENCRYPT_HOST_KEYS}"
  exit 1
fi

for password_name in AUTO_TLS_KEYSTORE_PASSWORD AUTO_TLS_TRUSTSTORE_PASSWORD; do
  password_value="${!password_name}"
  if [[ ${#password_value} -le 12 ]]; then
    echo "[ERROR] ${password_name} must be longer than 12 characters."
    exit 1
  fi
  if [[ "${password_value}" =~ [^a-zA-Z0-9] ]]; then
    echo "[ERROR] ${password_name} must not contain special characters for this Auto-TLS flow."
    exit 1
  fi
done

if [[ "${AUTO_TLS_ENCRYPT_HOST_KEYS}" == "true" ]]; then
  : "${AUTO_TLS_HOST_KEY_PASSWORD:?AUTO_TLS_HOST_KEY_PASSWORD is required when AUTO_TLS_ENCRYPT_HOST_KEYS=true}"
  if [[ ${#AUTO_TLS_HOST_KEY_PASSWORD} -le 12 ]]; then
    echo "[ERROR] AUTO_TLS_HOST_KEY_PASSWORD must be longer than 12 characters."
    exit 1
  fi
  if [[ "${AUTO_TLS_HOST_KEY_PASSWORD}" =~ [^a-zA-Z0-9] ]]; then
    echo "[ERROR] AUTO_TLS_HOST_KEY_PASSWORD must not contain special characters for this Auto-TLS flow."
    exit 1
  fi
fi

[[ -f "${AUTO_TLS_HOSTS_CSV}" ]] || { echo "[ERROR] Hosts CSV not found: ${AUTO_TLS_HOSTS_CSV}"; exit 1; }
[[ -z "${AUTO_TLS_SSH_KEY_FILE}" || -f "${AUTO_TLS_SSH_KEY_FILE}" ]] || { echo "[ERROR] AUTO_TLS_SSH_KEY_FILE does not exist: ${AUTO_TLS_SSH_KEY_FILE}"; exit 1; }

CA_CERT="${AUTO_TLS_WORKDIR}/ca/demo-ca-cert.pem"
CM_CERT="${AUTO_TLS_CERT_DIR}/${CM_HOST}-cert.pem"
CM_KEY="${AUTO_TLS_KEY_DIR}/${CM_HOST}-key.pem"
[[ -f "${CA_CERT}" ]] || { echo "[ERROR] CA certificate not found: ${CA_CERT}"; exit 1; }
[[ -f "${CM_CERT}" ]] || { echo "[ERROR] CM certificate not found: ${CM_CERT}"; exit 1; }
[[ -f "${CM_KEY}" ]] || { echo "[ERROR] CM key not found: ${CM_KEY}"; exit 1; }

mkdir -p "${AUTO_TLS_PAYLOAD_DIR}" "${AUTO_TLS_LOCATION}"
KEYSTORE_PASSWORD_FILE="${AUTO_TLS_WORKDIR}/keys/key.pwd"
TRUSTSTORE_PASSWORD_FILE="${AUTO_TLS_WORKDIR}/ca/truststore.pwd"
printf '%s\n' "${AUTO_TLS_KEYSTORE_PASSWORD}" > "${KEYSTORE_PASSWORD_FILE}"
printf '%s\n' "${AUTO_TLS_TRUSTSTORE_PASSWORD}" > "${TRUSTSTORE_PASSWORD_FILE}"
chmod 600 "${KEYSTORE_PASSWORD_FILE}" "${TRUSTSTORE_PASSWORD_FILE}"

echo "[INFO] Validating host private keys"
echo "[INFO] AUTO_TLS_ENCRYPT_HOST_KEYS=${AUTO_TLS_ENCRYPT_HOST_KEYS}"
python3 - <<PY
import csv
import subprocess
from pathlib import Path
hosts_csv = Path("${AUTO_TLS_HOSTS_CSV}")
key_dir = Path("${AUTO_TLS_KEY_DIR}")
encrypt_keys = "${AUTO_TLS_ENCRYPT_HOST_KEYS}" == "true"
host_key_password = "${AUTO_TLS_HOST_KEY_PASSWORD}"
with hosts_csv.open(newline="") as f:
    reader = csv.DictReader(f)
    for row in reader:
        host = (row.get("host_id") or row.get("hostname") or row.get("host") or "").strip()
        if not host:
            continue
        key_path = key_dir / (host + "-key.pem")
        if not key_path.exists():
            raise SystemExit("[ERROR] Missing key for %s: %s" % (host, key_path))
        cmd = ["openssl", "pkey", "-in", str(key_path), "-check", "-noout"]
        if encrypt_keys:
            cmd[3:3] = ["-passin", "pass:%s" % host_key_password]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        if result.returncode != 0:
            print(result.stdout)
            print(result.stderr)
            if encrypt_keys:
                raise SystemExit("[ERROR] Could not read encrypted private key for %s. AUTO_TLS_HOST_KEY_PASSWORD does not match." % host)
            raise SystemExit("[ERROR] Could not read unencrypted private key for %s." % host)
        print("[PASS] Private key is readable for %s" % host)
PY

if [[ "${AUTO_TLS_ENCRYPT_HOST_KEYS}" == "true" ]]; then
  echo "[INFO] Creating per-host private key password files for Cert Manager"
  python3 - <<PY
import csv
from pathlib import Path
hosts_csv = Path("${AUTO_TLS_HOSTS_CSV}")
auto_tls_location = Path("${AUTO_TLS_LOCATION}")
host_key_password = "${AUTO_TLS_HOST_KEY_PASSWORD}"
with hosts_csv.open(newline="") as f:
    reader = csv.DictReader(f)
    if not reader.fieldnames:
        raise SystemExit("[ERROR] hosts.csv has no header row")
    for row in reader:
        host = (row.get("host_id") or row.get("hostname") or row.get("host") or "").strip()
        if not host:
            continue
        host_dir = auto_tls_location / "hosts-key-store" / host
        host_dir.mkdir(parents=True, exist_ok=True)
        pw_file = host_dir / "cm-auto-host_key.pw"
        pw_file.write_text(host_key_password + "\n")
        print("[INFO] Wrote host key password file: %s" % pw_file)
PY
else
  echo "[INFO] Host keys are unencrypted. Removing stale per-host key password files if present."
  python3 - <<PY
import csv
from pathlib import Path
hosts_csv = Path("${AUTO_TLS_HOSTS_CSV}")
auto_tls_location = Path("${AUTO_TLS_LOCATION}")
with hosts_csv.open(newline="") as f:
    reader = csv.DictReader(f)
    for row in reader:
        host = (row.get("host_id") or row.get("hostname") or row.get("host") or "").strip()
        if not host:
            continue
        pw_file = auto_tls_location / "hosts-key-store" / host / "cm-auto-host_key.pw"
        if pw_file.exists():
            pw_file.unlink()
            print("[INFO] Removed stale host key password file: %s" % pw_file)
PY
fi

echo "[INFO] Building Auto-TLS payload: ${AUTO_TLS_PAYLOAD_FILE}"
python3 - <<PY
import csv
import json
from pathlib import Path
hosts_csv = Path("${AUTO_TLS_HOSTS_CSV}")
workdir = Path("${AUTO_TLS_WORKDIR}")
key_dir = Path("${AUTO_TLS_KEY_DIR}")
cert_dir = Path("${AUTO_TLS_CERT_DIR}")
payload_file = Path("${AUTO_TLS_PAYLOAD_FILE}")
cm_host = "${CM_HOST}"
ssh_private_key_file = "${AUTO_TLS_SSH_KEY_FILE:-}"
host_certs = []
with hosts_csv.open(newline="") as f:
    reader = csv.DictReader(f)
    if not reader.fieldnames:
        raise SystemExit("[ERROR] hosts.csv has no header row")
    for row in reader:
        host = (row.get("host_id") or row.get("hostname") or row.get("host") or "").strip()
        if not host:
            continue
        cert_path = cert_dir / (host + "-cert.pem")
        key_path = key_dir / (host + "-key.pem")
        if not cert_path.exists():
            raise SystemExit("[ERROR] Missing certificate for %s: %s" % (host, cert_path))
        if not key_path.exists():
            raise SystemExit("[ERROR] Missing key for %s: %s" % (host, key_path))
        host_certs.append({"hostname": host, "certificate": str(cert_path), "key": str(key_path)})
if not host_certs:
    raise SystemExit("[ERROR] No hosts found in hosts.csv")
payload = {
    "location": "${AUTO_TLS_LOCATION}",
    "customCA": True,
    "interpretAsFilenames": True,
    "cmHostCert": str(cert_dir / (cm_host + "-cert.pem")),
    "cmHostKey": str(key_dir / (cm_host + "-key.pem")),
    "caCert": str(workdir / "ca" / "demo-ca-cert.pem"),
    "keystorePasswd": str(workdir / "keys" / "key.pwd"),
    "truststorePasswd": str(workdir / "ca" / "truststore.pwd"),
    "hostCerts": host_certs,
    "configureAllServices": "${AUTO_TLS_CONFIGURE_ALL_SERVICES}",
    "sshPort": int("${AUTO_TLS_SSH_PORT}"),
    "userName": "${AUTO_TLS_SSH_USER}"
}
if ssh_private_key_file:
    key_path = Path(ssh_private_key_file)
    if not key_path.exists():
        raise SystemExit("[ERROR] SSH private key does not exist: %s" % key_path)
    payload["privateKey"] = key_path.read_text()
else:
    payload["password"] = ""
payload_file.write_text(json.dumps(payload, indent=2) + "\n")
print("[INFO] Payload written: %s" % payload_file)
print("[INFO] Hosts included: %d" % len(host_certs))
for host in host_certs:
    print("[INFO]   - %s" % host["hostname"])
PY

echo "[INFO] Setting ownership and permissions for Cloudera Manager"
if id cloudera-scm >/dev/null 2>&1; then
  chown -R cloudera-scm:cloudera-scm "${AUTO_TLS_LOCATION}"
else
  echo "[WARN] cloudera-scm user not found. Skipping chown."
fi
find "${AUTO_TLS_LOCATION}" -type d -exec chmod 750 {} \;
find "${AUTO_TLS_LOCATION}" -type f -exec chmod 640 {} \;
chmod 600 "${KEYSTORE_PASSWORD_FILE}" "${TRUSTSTORE_PASSWORD_FILE}"
if [[ "${AUTO_TLS_ENCRYPT_HOST_KEYS}" == "true" ]]; then
  chmod 600 "${AUTO_TLS_LOCATION}/hosts-key-store"/*/cm-auto-host_key.pw 2>/dev/null || true
fi
chmod 600 "${AUTO_TLS_KEY_DIR}"/*-key.pem

echo "[INFO] Payload summary:"
python3 - <<PY
import json
from pathlib import Path
payload_file = Path("${AUTO_TLS_PAYLOAD_FILE}")
payload = json.loads(payload_file.read_text())
safe_payload = dict(payload)
if "privateKey" in safe_payload:
    safe_payload["privateKey"] = "[REDACTED]"
if "password" in safe_payload and safe_payload["password"]:
    safe_payload["password"] = "[REDACTED]"
print(json.dumps(safe_payload, indent=2))
PY

CM_AUTOTLS_ENDPOINT="http://${CM_HOST}:${CM_PORT}/api/${CM_API_VERSION}/cm/commands/generateCmca"
echo "[INFO] Auto-TLS endpoint: ${CM_AUTOTLS_ENDPOINT}"
echo "[INFO] Payload file: ${AUTO_TLS_PAYLOAD_FILE}"
echo "[INFO] Submitting Auto-TLS command to Cloudera Manager"
HTTP_RESPONSE_FILE="/tmp/autotls_generate_cmca_response.json"
HTTP_CODE="$(curl -sS -o "${HTTP_RESPONSE_FILE}" -w "%{http_code}" -u "${CM_USER}:${CM_PASSWORD}" -X POST --header "Content-Type: application/json" --header "Accept: application/json" -d @"${AUTO_TLS_PAYLOAD_FILE}" "${CM_AUTOTLS_ENDPOINT}" || true)"
echo "[INFO] HTTP status: ${HTTP_CODE}"
echo "[INFO] Response body:"
cat "${HTTP_RESPONSE_FILE}" || true
echo
if [[ "${HTTP_CODE}" != "200" && "${HTTP_CODE}" != "201" && "${HTTP_CODE}" != "202" ]]; then
  echo "[ERROR] Auto-TLS API call failed."
  echo "[ERROR] Check logs:"
  echo "[ERROR] tail -f /var/log/cloudera-scm-server/cloudera-scm-server.log"
  echo "[ERROR] tail -f /var/log/cloudera-scm-agent/certmanager.log"
  exit 1
fi

echo "[OK] Auto-TLS command submitted successfully."
echo "[INFO] Next, watch the Cloudera Manager server log:"
echo "[INFO] tail -f /var/log/cloudera-scm-server/cloudera-scm-server.log"
echo "[INFO] Also watch Cert Manager log:"
echo "[INFO] tail -f /var/log/cloudera-scm-agent/certmanager.log"
echo "[INFO] After the command succeeds, restart Cloudera Manager:"
echo "[INFO] systemctl restart cloudera-scm-server"
echo "[INFO] Then restart agents on all hosts:"
echo "[INFO] systemctl restart cloudera-scm-agent"
echo "[INFO] After restart, access Cloudera Manager at:"
echo "[INFO] https://${CM_HOST}:7183"
