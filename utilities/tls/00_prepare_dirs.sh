#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ ! -f ./tls.env ]]; then
  echo "[ERROR] tls.env not found in ${SCRIPT_DIR}"
  echo "[ERROR] Copy tls.env.example to tls.env and edit it."
  exit 1
fi

source ./tls.env

: "${AUTO_TLS_LOCATION:?AUTO_TLS_LOCATION is required}"
: "${AUTO_TLS_WORKDIR:?AUTO_TLS_WORKDIR is required}"
: "${AUTO_TLS_KEY_DIR:?AUTO_TLS_KEY_DIR is required}"
: "${AUTO_TLS_CSR_DIR:?AUTO_TLS_CSR_DIR is required}"
: "${AUTO_TLS_CERT_DIR:?AUTO_TLS_CERT_DIR is required}"
: "${AUTO_TLS_STORE_DIR:?AUTO_TLS_STORE_DIR is required}"
: "${AUTO_TLS_PAYLOAD_DIR:?AUTO_TLS_PAYLOAD_DIR is required}"

mkdir -p \
  "${AUTO_TLS_LOCATION}" \
  "${AUTO_TLS_WORKDIR}" \
  "${AUTO_TLS_KEY_DIR}" \
  "${AUTO_TLS_CSR_DIR}" \
  "${AUTO_TLS_CERT_DIR}" \
  "${AUTO_TLS_STORE_DIR}" \
  "${AUTO_TLS_PAYLOAD_DIR}" \
  "${AUTO_TLS_WORKDIR}/ca" \
  "${AUTO_TLS_WORKDIR}/ca-certs" \
  "${AUTO_TLS_WORKDIR}/fullchains" \
  "${AUTO_TLS_WORKDIR}/openssl" \
  "${AUTO_TLS_WORKDIR}/passwords"

chmod 755 "${AUTO_TLS_LOCATION}"
chmod 750 "${AUTO_TLS_WORKDIR}"
chmod 700 "${AUTO_TLS_KEY_DIR}" "${AUTO_TLS_WORKDIR}/ca" "${AUTO_TLS_WORKDIR}/passwords"

if id cloudera-scm >/dev/null 2>&1; then
  chown -R cloudera-scm:cloudera-scm "${AUTO_TLS_LOCATION}"
fi

echo "[OK] Prepared TLS artifact directories under ${AUTO_TLS_WORKDIR}"
find "${AUTO_TLS_WORKDIR}" -maxdepth 2 -type d | sort
