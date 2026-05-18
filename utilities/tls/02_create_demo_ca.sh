#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

need_cmd openssl
init_dirs

CA_KEY="$TLS_OUTPUT_DIR/ca/demo-ca.key"
CA_CERT="$TLS_OUTPUT_DIR/ca/demo-ca.crt"
CA_CHAIN="$TLS_OUTPUT_DIR/ca/ca-chain.pem"

if [[ -f "$CA_KEY" || -f "$CA_CERT" ]]; then
  echo "[ERROR] Demo CA already exists under $TLS_OUTPUT_DIR/ca. Remove it manually if you really want to regenerate."
  exit 1
fi

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:"${TLS_RSA_BITS:-3072}" -out "$CA_KEY"
chmod 600 "$CA_KEY"

openssl req -x509 -new -nodes \
  -key "$CA_KEY" \
  -"${TLS_DIGEST:-sha256}" \
  -days "${TLS_DEMO_CA_DAYS:-825}" \
  -out "$CA_CERT" \
  -subj "/C=${TLS_COUNTRY:-US}/ST=${TLS_STATE:-Demo State}/L=${TLS_CITY:-Demo City}/O=${TLS_ORG:-Cloudera Demo}/OU=${TLS_OU:-CFM}/CN=${TLS_DEMO_CA_CN:-CFM Demo Root CA}" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

cp -f "$CA_CERT" "$CA_CHAIN"
chmod 644 "$CA_CERT" "$CA_CHAIN"

echo "[OK] Demo CA key: $CA_KEY"
echo "[OK] Demo CA cert: $CA_CERT"
echo "[OK] CA chain: $CA_CHAIN"
echo "[WARN] Demo CA is for lab testing only. Use your enterprise CA for real deployments."
