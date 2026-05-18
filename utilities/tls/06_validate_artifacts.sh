#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

need_cmd openssl
init_dirs

read_hosts | while IFS='|' read -r host_id cn san_dns san_ip; do
  safe_id="$(sanitize_name "$host_id")"
  key_file="$TLS_OUTPUT_DIR/private/${safe_id}.key"
  csr_file="$TLS_OUTPUT_DIR/csr/${safe_id}.csr"
  cert_file="$TLS_OUTPUT_DIR/signed/${safe_id}.crt"
  keystore="$TLS_OUTPUT_DIR/stores/${safe_id}-keystore.p12"
  truststore="$TLS_OUTPUT_DIR/stores/${safe_id}-truststore.p12"

  echo "==== $host_id ===="

  if [[ -f "$key_file" ]]; then
    echo "[OK] key exists: $key_file"
    openssl pkey -in "$key_file" -noout >/dev/null
  else
    echo "[WARN] missing key: $key_file"
  fi

  if [[ -f "$csr_file" ]]; then
    echo "[OK] csr exists: $csr_file"
    openssl req -in "$csr_file" -noout -subject
    openssl req -in "$csr_file" -noout -text | grep -A2 "Subject Alternative Name" || true
  else
    echo "[WARN] missing csr: $csr_file"
  fi

  if [[ -f "$cert_file" ]]; then
    echo "[OK] cert exists: $cert_file"
    openssl x509 -in "$cert_file" -noout -subject -issuer -dates
    openssl x509 -in "$cert_file" -noout -text | grep -A2 "Subject Alternative Name" || true
  else
    echo "[WARN] missing signed cert: $cert_file"
  fi

  if [[ -f "$keystore" ]]; then
    echo "[OK] keystore exists: $keystore"
    java_keytool -list -keystore "$keystore" -storetype PKCS12 -storepass "$TLS_KEYSTORE_PASSWORD" | head -20
  else
    echo "[WARN] missing keystore: $keystore"
  fi

  if [[ -f "$truststore" ]]; then
    echo "[OK] truststore exists: $truststore"
    java_keytool -list -keystore "$truststore" -storetype PKCS12 -storepass "$TLS_TRUSTSTORE_PASSWORD" | head -30
  else
    echo "[WARN] missing truststore: $truststore"
  fi
  echo
 done
