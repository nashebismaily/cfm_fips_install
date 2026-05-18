#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

need_cmd openssl
need_cmd sed
init_dirs

if [[ ! -f "$TLS_CA_CHAIN_FILE" ]]; then
  echo "[ERROR] Missing CA chain file: $TLS_CA_CHAIN_FILE"
  echo "Put your issuing/root CA chain there before building stores."
  exit 1
fi

split_ca_chain() {
  local chain_file="$1" out_dir="$2"
  mkdir -p "$out_dir"
  rm -f "$out_dir"/*.pem
  awk -v outdir="$out_dir" '
    /-----BEGIN CERTIFICATE-----/ {i++; file=sprintf("%s/ca-%02d.pem", outdir, i)}
    file {print > file}
    /-----END CERTIFICATE-----/ {file=""}
  ' "$chain_file"
}

build_truststore_pkcs12() {
  local truststore="$1" pass="$2" chain_dir="$3"
  rm -f "$truststore"
  local idx=0 cert
  for cert in "$chain_dir"/*.pem; do
    [[ -f "$cert" ]] || continue
    idx=$((idx+1))
    java_keytool -importcert -noprompt \
      -alias "ca-${idx}" \
      -file "$cert" \
      -keystore "$truststore" \
      -storetype PKCS12 \
      -storepass "$pass"
  done
}

CHAIN_SPLIT_DIR="$TLS_OUTPUT_DIR/ca/split-chain"
split_ca_chain "$TLS_CA_CHAIN_FILE" "$CHAIN_SPLIT_DIR"

read_hosts | while IFS='|' read -r host_id cn san_dns san_ip; do
  safe_id="$(sanitize_name "$host_id")"
  key_file="$TLS_OUTPUT_DIR/private/${safe_id}.key"
  cert_file="$TLS_OUTPUT_DIR/signed/${safe_id}.crt"
  fullchain_file="$TLS_OUTPUT_DIR/certs/${safe_id}-fullchain.pem"
  keystore="$TLS_OUTPUT_DIR/stores/${safe_id}-keystore.p12"
  truststore="$TLS_OUTPUT_DIR/stores/${safe_id}-truststore.p12"
  password_file="$TLS_OUTPUT_DIR/stores/${safe_id}-passwords.txt"

  echo "---- $host_id"
  [[ -f "$key_file" ]] || { echo "[ERROR] Missing private key: $key_file"; exit 1; }
  [[ -f "$cert_file" ]] || { echo "[ERROR] Missing signed cert: $cert_file"; exit 1; }

  cat "$cert_file" "$TLS_CA_CHAIN_FILE" > "$fullchain_file"
  chmod 644 "$fullchain_file"

  rm -f "$keystore" "$truststore"

  openssl pkcs12 -export \
    -name "$safe_id" \
    -inkey "$key_file" \
    -in "$cert_file" \
    -certfile "$TLS_CA_CHAIN_FILE" \
    -out "$keystore" \
    -passout "pass:${TLS_KEYSTORE_PASSWORD}" \
    -macalg sha256

  build_truststore_pkcs12 "$truststore" "$TLS_TRUSTSTORE_PASSWORD" "$CHAIN_SPLIT_DIR"

  chmod 600 "$keystore" "$truststore"

  cat > "$password_file" <<EOFPASS
host_id=${safe_id}
keystore=${keystore}
keystoreType=PKCS12
keystorePasswd=${TLS_KEYSTORE_PASSWORD}
keyPasswd=${TLS_KEYSTORE_PASSWORD}
truststore=${truststore}
truststoreType=PKCS12
truststorePasswd=${TLS_TRUSTSTORE_PASSWORD}
certificate=${cert_file}
private_key=${key_file}
fullchain=${fullchain_file}
ca_chain=${TLS_CA_CHAIN_FILE}
EOFPASS
  chmod 600 "$password_file"

  echo "[OK] Full chain: $fullchain_file"
  echo "[OK] Keystore: $keystore"
  echo "[OK] Truststore: $truststore"
  echo "[OK] Password reference: $password_file"
  echo
 done

echo "[DONE] PKCS12 stores created in $TLS_OUTPUT_DIR/stores"
echo "Use keystoreType=PKCS12 and truststoreType=PKCS12 in CM."
