#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_root
require_cmd openssl
require_cmd python3

[[ -f "$AUTO_TLS_CA_CHAIN_FILE" ]] || { echo "[ERROR] Missing CA chain: $AUTO_TLS_CA_CHAIN_FILE"; exit 1; }

while IFS=$'\t' read -r hostname cn san_dns san_ip; do
  [[ -z "$hostname" ]] && continue
  key="$(host_key_file "$hostname")"
  cert="$(host_cert_file "$hostname")"
  [[ -f "$key" ]] || { echo "[ERROR] Missing key for $hostname: $key"; exit 1; }
  [[ -f "$cert" ]] || { echo "[ERROR] Missing cert for $hostname: $cert"; exit 1; }

  echo "==== Validating $hostname ===="
  openssl x509 -in "$cert" -noout -subject -issuer -dates

  text="$(openssl x509 -in "$cert" -noout -text)"
  echo "$text" | grep -q "DNS:${hostname}" || echo "[WARN] SAN does not appear to include DNS:${hostname}"
  echo "$text" | grep -q "TLS Web Server Authentication" || { echo "[ERROR] Missing EKU: TLS Web Server Authentication"; exit 1; }
  echo "$text" | grep -q "TLS Web Client Authentication" || { echo "[ERROR] Missing EKU: TLS Web Client Authentication"; exit 1; }

  cert_mod="$(openssl x509 -in "$cert" -noout -modulus | openssl md5)"
  key_mod="$(openssl rsa -in "$key" -passin "file:${AUTO_TLS_KEY_PASSWORD_FILE}" -noout -modulus 2>/dev/null | openssl md5)"
  if [[ "$cert_mod" != "$key_mod" ]]; then
    echo "[ERROR] Key and certificate do not match for $hostname"
    exit 1
  fi
  echo "[OK] $hostname cert/key validation passed"
done < <(read_hosts_python)

chown -R cloudera-scm:cloudera-scm "$AUTO_TLS_WORKDIR" "$AUTO_TLS_LOCATION" 2>/dev/null || true
echo "[OK] All host certs validated"
