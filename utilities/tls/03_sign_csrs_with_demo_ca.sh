#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd openssl
prepare_dirs
[[ -f "$CA_KEY" ]] || fail "Demo CA key not found. Run 02_create_demo_ca.sh first."
[[ -f "$CA_CERT" ]] || fail "Demo CA cert not found. Run 02_create_demo_ca.sh first."

sign_host() {
  local host_id="$1" cn="$2" dns_sans="$3" ip_sans="$4" csr cert ext san_line
  csr="$(host_csr "$host_id")"
  cert="$(host_cert "$host_id")"
  ext="${OPENSSL_DIR}/${host_id}-cert-ext.cnf"
  san_line="$(build_san_line "$dns_sans" "$ip_sans")"
  [[ -f "$csr" ]] || fail "CSR not found for ${host_id}: ${csr}"

  cat > "$ext" <<EOF_EXT
basicConstraints = CA:false
subjectAltName = ${san_line}
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
EOF_EXT

  openssl x509 -req \
    -in "$csr" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -passin pass:"${TLS_DEMO_CA_KEY_PASSWORD}" \
    -CAcreateserial \
    -out "$cert" \
    -days "${TLS_CERT_DAYS}" \
    -"${TLS_DIGEST}" \
    -extfile "$ext"

  cat "$cert" "$CA_CHAIN" > "$(host_fullchain "$host_id")"
  chmod 644 "$cert" "$(host_fullchain "$host_id")"
  ok "Signed cert for ${host_id}: ${cert}"
}

read_hosts_loop sign_host
ok "Signed host CSRs using demo CA"
