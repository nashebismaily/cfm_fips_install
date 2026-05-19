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
: "${AUTO_TLS_HOST_KEY_PASSWORD:?AUTO_TLS_HOST_KEY_PASSWORD is required}"

AUTO_TLS_CA_CN="${AUTO_TLS_CA_CN:-CFM Internal CA}"
AUTO_TLS_CA_DAYS="${AUTO_TLS_CA_DAYS:-3650}"
AUTO_TLS_CA_KEY_PASSWORD="${AUTO_TLS_CA_KEY_PASSWORD:-${AUTO_TLS_HOST_KEY_PASSWORD}}"
AUTO_TLS_KEY_SIZE="${AUTO_TLS_KEY_SIZE:-4096}"
AUTO_TLS_DIGEST="${AUTO_TLS_DIGEST:-sha256}"

CA_DIR="${AUTO_TLS_WORKDIR}/ca"
CA_KEY="${CA_DIR}/demo-ca-key.pem"
CA_CERT="${CA_DIR}/demo-ca-cert.pem"
CA_CHAIN="${CA_DIR}/ca-chain.pem"

mkdir -p "${CA_DIR}" "${AUTO_TLS_WORKDIR}/openssl"
chmod 700 "${CA_DIR}"

cat > "${CA_DIR}/demo-ca-openssl.cnf" <<EOF_CNF
[ req ]
prompt = no
default_md = ${AUTO_TLS_DIGEST}
distinguished_name = dn
x509_extensions = v3_ca

[ dn ]
CN = ${AUTO_TLS_CA_CN}

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, keyCertSign, cRLSign
EOF_CNF

openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:"${AUTO_TLS_KEY_SIZE}" \
  -aes-256-cbc \
  -pass "pass:${AUTO_TLS_CA_KEY_PASSWORD}" \
  -out "${CA_KEY}"
chmod 600 "${CA_KEY}"

openssl req -x509 -new \
  -key "${CA_KEY}" \
  -passin "pass:${AUTO_TLS_CA_KEY_PASSWORD}" \
  -days "${AUTO_TLS_CA_DAYS}" \
  -out "${CA_CERT}" \
  -config "${CA_DIR}/demo-ca-openssl.cnf"

cp -f "${CA_CERT}" "${CA_CHAIN}"
chmod 644 "${CA_CERT}" "${CA_CHAIN}"
echo "[OK] Created CA certificate: ${CA_CERT}"
echo "[OK] Created CA chain: ${CA_CHAIN}"
