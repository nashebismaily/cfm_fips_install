#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd openssl
prepare_dirs

cat > "${CA_DIR}/demo-ca-openssl.cnf" <<EOF_CNF
[ req ]
prompt = no
default_md = ${TLS_DIGEST}
distinguished_name = dn
x509_extensions = v3_ca

[ dn ]
CN = ${TLS_DEMO_CA_CN}

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, keyCertSign, cRLSign
EOF_CNF

openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:"${TLS_KEY_SIZE}" \
  -aes-256-cbc \
  -pass pass:"${TLS_DEMO_CA_KEY_PASSWORD}" \
  -out "$CA_KEY"
chmod 600 "$CA_KEY"

openssl req -x509 -new \
  -key "$CA_KEY" \
  -passin pass:"${TLS_DEMO_CA_KEY_PASSWORD}" \
  -days "${TLS_DEMO_CA_DAYS}" \
  -out "$CA_CERT" \
  -config "${CA_DIR}/demo-ca-openssl.cnf"

cp -f "$CA_CERT" "$CA_CHAIN"
chmod 644 "$CA_CERT" "$CA_CHAIN"
ok "Created demo CA: ${CA_CERT}"
