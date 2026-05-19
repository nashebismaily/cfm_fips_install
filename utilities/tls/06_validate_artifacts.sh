#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ ! -f ./tls.env ]]; then
  echo "[ERROR] tls.env not found in ${SCRIPT_DIR}"
  exit 1
fi

source ./tls.env

: "${AUTO_TLS_HOSTS_CSV:?AUTO_TLS_HOSTS_CSV is required}"
: "${AUTO_TLS_KEY_DIR:?AUTO_TLS_KEY_DIR is required}"
: "${AUTO_TLS_CSR_DIR:?AUTO_TLS_CSR_DIR is required}"
: "${AUTO_TLS_CERT_DIR:?AUTO_TLS_CERT_DIR is required}"
: "${AUTO_TLS_STORE_DIR:?AUTO_TLS_STORE_DIR is required}"
: "${AUTO_TLS_WORKDIR:?AUTO_TLS_WORKDIR is required}"
: "${AUTO_TLS_KEYSTORE_PASSWORD:?AUTO_TLS_KEYSTORE_PASSWORD is required}"
: "${AUTO_TLS_TRUSTSTORE_PASSWORD:?AUTO_TLS_TRUSTSTORE_PASSWORD is required}"

AUTO_TLS_ENCRYPT_HOST_KEYS="${AUTO_TLS_ENCRYPT_HOST_KEYS:-true}"
AUTO_TLS_HOST_KEY_PASSWORD="${AUTO_TLS_HOST_KEY_PASSWORD:-}"
if [[ "${AUTO_TLS_ENCRYPT_HOST_KEYS}" == "true" ]]; then
  : "${AUTO_TLS_HOST_KEY_PASSWORD:?AUTO_TLS_HOST_KEY_PASSWORD is required when AUTO_TLS_ENCRYPT_HOST_KEYS=true}"
fi

JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk}"
KEYTOOL="${KEYTOOL:-${JAVA_HOME}/bin/keytool}"
CA_CHAIN="${AUTO_TLS_WORKDIR}/ca/ca-chain.pem"
FULLCHAINS_DIR="${AUTO_TLS_WORKDIR}/fullchains"

[[ -x "${KEYTOOL}" ]] || { echo "[ERROR] keytool not found or not executable: ${KEYTOOL}"; exit 1; }
[[ -f "${CA_CHAIN}" ]] || { echo "[ERROR] CA chain not found: ${CA_CHAIN}"; exit 1; }

while IFS=, read -r host_id rest; do
  [[ "${host_id}" == "host_id" ]] && continue
  [[ -z "${host_id// }" ]] && continue

  key="${AUTO_TLS_KEY_DIR}/${host_id}-key.pem"
  csr="${AUTO_TLS_CSR_DIR}/${host_id}-csr.pem"
  cert="${AUTO_TLS_CERT_DIR}/${host_id}-cert.pem"
  fullchain="${FULLCHAINS_DIR}/${host_id}-fullchain.pem"
  keystore="${AUTO_TLS_STORE_DIR}/${host_id}-keystore.p12"
  truststore="${AUTO_TLS_STORE_DIR}/${host_id}-truststore.p12"

  echo "==== ${host_id} ===="
  [[ -f "${key}" ]] || { echo "[ERROR] Missing key: ${key}"; exit 1; }
  [[ -f "${csr}" ]] || { echo "[ERROR] Missing CSR: ${csr}"; exit 1; }
  [[ -f "${cert}" ]] || { echo "[ERROR] Missing cert: ${cert}"; exit 1; }
  [[ -f "${fullchain}" ]] || { echo "[ERROR] Missing fullchain: ${fullchain}"; exit 1; }
  [[ -f "${keystore}" ]] || { echo "[ERROR] Missing keystore: ${keystore}"; exit 1; }
  [[ -f "${truststore}" ]] || { echo "[ERROR] Missing truststore: ${truststore}"; exit 1; }

  if [[ "${AUTO_TLS_ENCRYPT_HOST_KEYS}" == "true" ]]; then
    openssl pkey -in "${key}" -passin "pass:${AUTO_TLS_HOST_KEY_PASSWORD}" -check -noout
  else
    openssl pkey -in "${key}" -check -noout
  fi
  openssl req -in "${csr}" -noout -subject
  openssl x509 -in "${cert}" -noout -subject -issuer -dates
  openssl x509 -in "${cert}" -noout -text | grep -A 3 "Subject Alternative Name" || true

  "${KEYTOOL}" -list -storetype PKCS12 -keystore "${keystore}" -storepass "${AUTO_TLS_KEYSTORE_PASSWORD}"
  "${KEYTOOL}" -list -storetype PKCS12 -keystore "${truststore}" -storepass "${AUTO_TLS_TRUSTSTORE_PASSWORD}"
  echo
done < "${AUTO_TLS_HOSTS_CSV}"

echo "[OK] Validation complete"
