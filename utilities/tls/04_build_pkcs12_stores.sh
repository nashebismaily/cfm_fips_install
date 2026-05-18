#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd openssl
[[ -x "$KEYTOOL" ]] || fail "keytool not found or not executable: $KEYTOOL"
prepare_dirs
[[ -f "$CA_CHAIN" ]] || fail "CA chain not found at ${CA_CHAIN}. Place your CA chain there or run demo CA scripts."

build_host() {
  local host_id="$1" cn="$2" dns_sans="$3" ip_sans="$4" key cert fullchain keystore truststore
  key="$(host_key "$host_id")"
  cert="$(host_cert "$host_id")"
  fullchain="$(host_fullchain "$host_id")"
  keystore="$(host_keystore "$host_id")"
  truststore="$(host_truststore "$host_id")"

  [[ -f "$key" ]] || fail "Missing key for ${host_id}: ${key}"
  [[ -f "$cert" ]] || fail "Missing signed cert for ${host_id}: ${cert}"
  [[ -f "$fullchain" ]] || cat "$cert" "$CA_CHAIN" > "$fullchain"

  rm -f "$keystore" "$truststore"

  openssl pkcs12 -export \
    -name "$cn" \
    -inkey "$key" \
    -passin pass:"${TLS_KEY_PASSWORD}" \
    -in "$cert" \
    -certfile "$CA_CHAIN" \
    -out "$keystore" \
    -passout pass:"${TLS_KEYSTORE_PASSWORD}"
  chmod 600 "$keystore"

  "$KEYTOOL" -importcert -noprompt \
    -alias cfm-ca-chain \
    -file "$CA_CHAIN" \
    -keystore "$truststore" \
    -storetype "${TLS_STORE_TYPE}" \
    -storepass "${TLS_TRUSTSTORE_PASSWORD}"
  chmod 600 "$truststore"

  ok "Built stores for ${host_id}: ${keystore}, ${truststore}"
}

read_hosts_loop build_host
ok "Built PKCS12 keystores and truststores under ${STORES_DIR}"
