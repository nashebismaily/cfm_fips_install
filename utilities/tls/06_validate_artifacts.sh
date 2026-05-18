#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd openssl
[[ -x "$KEYTOOL" ]] || fail "keytool not found or not executable: $KEYTOOL"

validate_host() {
  local host_id="$1" cn="$2" dns_sans="$3" ip_sans="$4" csr cert fullchain keystore truststore
  csr="$(host_csr "$host_id")"
  cert="$(host_cert "$host_id")"
  fullchain="$(host_fullchain "$host_id")"
  keystore="$(host_keystore "$host_id")"
  truststore="$(host_truststore "$host_id")"

  echo "==== ${host_id} ===="
  [[ -f "$csr" ]] && openssl req -in "$csr" -noout -subject || echo "[WARN] Missing CSR: $csr"
  if [[ -f "$cert" ]]; then
    openssl x509 -in "$cert" -noout -subject -issuer -dates
    openssl x509 -in "$cert" -noout -text | grep -A2 "Subject Alternative Name" || true
  else
    echo "[WARN] Missing cert: $cert"
  fi
  if [[ -f "$keystore" ]]; then
    "$KEYTOOL" -list -keystore "$keystore" -storetype "${TLS_STORE_TYPE}" -storepass "${TLS_KEYSTORE_PASSWORD}" | head -40
  else
    echo "[WARN] Missing keystore: $keystore"
  fi
  if [[ -f "$truststore" ]]; then
    "$KEYTOOL" -list -keystore "$truststore" -storetype "${TLS_STORE_TYPE}" -storepass "${TLS_TRUSTSTORE_PASSWORD}" | head -40
  else
    echo "[WARN] Missing truststore: $truststore"
  fi
  echo
}

read_hosts_loop validate_host
ok "Validation complete"
