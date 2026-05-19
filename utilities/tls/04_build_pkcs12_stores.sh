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
: "${AUTO_TLS_KEY_DIR:?AUTO_TLS_KEY_DIR is required}"
: "${AUTO_TLS_CERT_DIR:?AUTO_TLS_CERT_DIR is required}"
: "${AUTO_TLS_STORE_DIR:?AUTO_TLS_STORE_DIR is required}"
: "${AUTO_TLS_KEYSTORE_PASSWORD:?AUTO_TLS_KEYSTORE_PASSWORD is required}"
: "${AUTO_TLS_TRUSTSTORE_PASSWORD:?AUTO_TLS_TRUSTSTORE_PASSWORD is required}"

AUTO_TLS_ENCRYPT_HOST_KEYS="${AUTO_TLS_ENCRYPT_HOST_KEYS:-true}"
AUTO_TLS_HOST_KEY_PASSWORD="${AUTO_TLS_HOST_KEY_PASSWORD:-}"
if [[ "${AUTO_TLS_ENCRYPT_HOST_KEYS}" == "true" ]]; then
  : "${AUTO_TLS_HOST_KEY_PASSWORD:?AUTO_TLS_HOST_KEY_PASSWORD is required when AUTO_TLS_ENCRYPT_HOST_KEYS=true}"
fi

JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk}"
KEYTOOL="${KEYTOOL:-${JAVA_HOME}/bin/keytool}"
STORE_TYPE="${AUTO_TLS_STORE_TYPE:-PKCS12}"
CA_CHAIN="${AUTO_TLS_WORKDIR}/ca/ca-chain.pem"
FULLCHAINS_DIR="${AUTO_TLS_WORKDIR}/fullchains"

command -v openssl >/dev/null 2>&1 || { echo "[ERROR] openssl not found"; exit 1; }
[[ -x "${KEYTOOL}" ]] || { echo "[ERROR] keytool not found or not executable: ${KEYTOOL}"; exit 1; }
[[ -f "${CA_CHAIN}" ]] || { echo "[ERROR] CA chain not found: ${CA_CHAIN}"; exit 1; }
mkdir -p "${AUTO_TLS_STORE_DIR}" "${FULLCHAINS_DIR}"

while IFS=, read -r host_id rest; do
  [[ "${host_id}" == "host_id" ]] && continue
  [[ -z "${host_id// }" ]] && continue

  key="${AUTO_TLS_KEY_DIR}/${host_id}-key.pem"
  cert="${AUTO_TLS_CERT_DIR}/${host_id}-cert.pem"
  fullchain="${FULLCHAINS_DIR}/${host_id}-fullchain.pem"
  keystore="${AUTO_TLS_STORE_DIR}/${host_id}-keystore.p12"
  truststore="${AUTO_TLS_STORE_DIR}/${host_id}-truststore.p12"

  [[ -f "${key}" ]] || { echo "[ERROR] Missing key for ${host_id}: ${key}"; exit 1; }
  [[ -f "${cert}" ]] || { echo "[ERROR] Missing cert for ${host_id}: ${cert}"; exit 1; }
  [[ -f "${fullchain}" ]] || cat "${cert}" "${CA_CHAIN}" > "${fullchain}"

  rm -f "${keystore}" "${truststore}"

  PKCS12_CMD=(openssl pkcs12 -export -name "${host_id}" -inkey "${key}" -in "${cert}" -certfile "${CA_CHAIN}" -out "${keystore}" -passout "pass:${AUTO_TLS_KEYSTORE_PASSWORD}")

  if [[ "${AUTO_TLS_ENCRYPT_HOST_KEYS}" == "true" ]]; then
    PKCS12_CMD+=(-passin "pass:${AUTO_TLS_HOST_KEY_PASSWORD}")
  fi

  "${PKCS12_CMD[@]}"
  chmod 600 "${keystore}"

  "${KEYTOOL}" -importcert -noprompt -alias cfm-ca-chain -file "${CA_CHAIN}" -keystore "${truststore}" -storetype "${STORE_TYPE}" -storepass "${AUTO_TLS_TRUSTSTORE_PASSWORD}"
  chmod 600 "${truststore}"

  echo "[OK] Built stores for ${host_id}: ${keystore}, ${truststore}"
done < "${AUTO_TLS_HOSTS_CSV}"

echo "[OK] Built PKCS12 keystores and truststores under ${AUTO_TLS_STORE_DIR}"
