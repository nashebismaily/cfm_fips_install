#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

need_cmd openssl
init_dirs

echo "==== Generating private keys and CSRs ===="
echo "Output: $TLS_OUTPUT_DIR"
echo

read_hosts | while IFS='|' read -r host_id cn san_dns san_ip; do
  safe_id="$(sanitize_name "$host_id")"
  key_file="$TLS_OUTPUT_DIR/private/${safe_id}.key"
  csr_file="$TLS_OUTPUT_DIR/csr/${safe_id}.csr"
  cfg_file="$TLS_OUTPUT_DIR/configs/${safe_id}-openssl.cnf"

  echo "---- $host_id"
  echo "CN: $cn"
  echo "DNS SANs: ${san_dns:-$cn}"
  echo "IP SANs: ${san_ip:-none}"

  openssl_req_config "$host_id" "$cn" "$san_dns" "$san_ip" "$cfg_file"

  if [[ ! -f "$key_file" ]]; then
    openssl genpkey \
      -algorithm "${TLS_KEY_ALGORITHM:-RSA}" \
      -pkeyopt rsa_keygen_bits:"${TLS_RSA_BITS:-3072}" \
      -out "$key_file"
    chmod 600 "$key_file"
  else
    echo "[INFO] Existing key kept: $key_file"
  fi

  openssl req -new \
    -key "$key_file" \
    -out "$csr_file" \
    -config "$cfg_file" \
    -"${TLS_DIGEST:-sha256}"

  echo "[OK] Key: $key_file"
  echo "[OK] CSR: $csr_file"
  echo "[OK] OpenSSL config: $cfg_file"
  echo
 done

echo "[DONE] Send the CSR files in $TLS_OUTPUT_DIR/csr to your certificate authority."
echo "After receiving certificates, save each host cert as: $TLS_OUTPUT_DIR/signed/<host_id>.crt"
echo "Save the issuing CA chain as: $TLS_CA_CHAIN_FILE"
