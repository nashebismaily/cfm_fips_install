#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_root
require_cmd openssl
require_cmd python3

if ! is_true "${GENERATE_KEYS_AND_CSRS:-true}"; then
  echo "[SKIP] GENERATE_KEYS_AND_CSRS=false. Customer-provided keys/certs mode."
  echo "Place keys at:  ${AUTO_TLS_KEYS_DIR}/<hostname>${HOST_KEY_SUFFIX}"
  echo "Place certs at: ${AUTO_TLS_CERTS_DIR}/<hostname>${HOST_CERT_SUFFIX}"
  echo "Place CA chain: ${AUTO_TLS_CA_CHAIN_FILE}"
  exit 0
fi

mkdir -p "$AUTO_TLS_KEYS_DIR" "$AUTO_TLS_CSRS_DIR"

while IFS=$'\t' read -r hostname cn san_dns san_ip; do
  [[ -z "$hostname" ]] && continue
  key="$(host_key_file "$hostname")"
  csr="$(host_csr_file "$hostname")"
  cfg="${AUTO_TLS_CSRS_DIR}/${hostname}-openssl.cnf"

  if [[ -e "$key" || -e "$csr" ]] && ! is_true "${OVERWRITE_KEYS_AND_CSRS:-false}"; then
    echo "[SKIP] Existing key/CSR for $hostname. Set OVERWRITE_KEYS_AND_CSRS=true to replace."
    continue
  fi

  make_san_config "$hostname" "$cn" "$san_dns" "$san_ip" "$cfg"
  subj="/CN=${cn}/O=${TLS_SUBJECT_O}/OU=${TLS_SUBJECT_OU}/L=${TLS_SUBJECT_L}/ST=${TLS_SUBJECT_ST}/C=${TLS_SUBJECT_C}"

  echo "[INFO] Generating key and CSR for $hostname"
  openssl req -newkey "${TLS_KEY_ALGORITHM}:${TLS_RSA_BITS}" "-${TLS_SIGNATURE_DIGEST}" \
    -keyout "$key" \
    -out "$csr" \
    -passout "file:${AUTO_TLS_KEY_PASSWORD_FILE}" \
    -subj "$subj" \
    -config "$cfg"

  chmod 600 "$key"
  chmod 644 "$csr" "$cfg"
done < <(read_hosts_python)

chown -R cloudera-scm:cloudera-scm "$AUTO_TLS_WORKDIR" 2>/dev/null || true
echo "[OK] Generated keys and CSRs under $AUTO_TLS_WORKDIR"
