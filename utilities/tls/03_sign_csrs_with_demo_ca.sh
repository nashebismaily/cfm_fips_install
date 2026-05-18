#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

need_cmd openssl
init_dirs

CA_KEY="$TLS_OUTPUT_DIR/ca/demo-ca.key"
CA_CERT="$TLS_OUTPUT_DIR/ca/demo-ca.crt"

if [[ ! -f "$CA_KEY" || ! -f "$CA_CERT" ]]; then
  echo "[ERROR] Missing demo CA. Run 02_create_demo_ca.sh first, or use your enterprise CA instead."
  exit 1
fi

read_hosts | while IFS='|' read -r host_id cn san_dns san_ip; do
  safe_id="$(sanitize_name "$host_id")"
  csr_file="$TLS_OUTPUT_DIR/csr/${safe_id}.csr"
  cfg_file="$TLS_OUTPUT_DIR/configs/${safe_id}-openssl.cnf"
  cert_file="$TLS_OUTPUT_DIR/signed/${safe_id}.crt"

  if [[ ! -f "$csr_file" ]]; then
    echo "[ERROR] Missing CSR: $csr_file"
    exit 1
  fi

  openssl x509 -req \
    -in "$csr_file" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$cert_file" \
    -days "${TLS_DEMO_CA_DAYS:-825}" \
    -"${TLS_DIGEST:-sha256}" \
    -extensions v3_req \
    -extfile "$cfg_file"

  chmod 644 "$cert_file"
  echo "[OK] Signed cert: $cert_file"
 done
