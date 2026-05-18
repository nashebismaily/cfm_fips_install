#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd openssl
prepare_dirs

make_host() {
  local host_id="$1" cn="$2" dns_sans="$3" ip_sans="$4" san_line cnf key csr
  san_line="$(build_san_line "$dns_sans" "$ip_sans")"
  [[ -n "$san_line" ]] || fail "No SAN entries found for host_id=$host_id. Add dns_sans or ip_sans."
  cnf="$(host_openssl_cnf "$host_id")"
  key="$(host_key "$host_id")"
  csr="$(host_csr "$host_id")"

  cat > "$cnf" <<EOF_CNF
[ req ]
default_bits = ${TLS_KEY_SIZE}
prompt = no
default_md = ${TLS_DIGEST}
distinguished_name = dn
req_extensions = req_ext

[ dn ]
CN = ${cn}

[ req_ext ]
subjectAltName = ${san_line}
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
EOF_CNF

  info "Generating encrypted private key for ${host_id}: ${key}"
  openssl genpkey \
    -algorithm "${TLS_KEY_ALGORITHM}" \
    -pkeyopt rsa_keygen_bits:"${TLS_KEY_SIZE}" \
    -aes-256-cbc \
    -pass pass:"${TLS_KEY_PASSWORD}" \
    -out "$key"
  chmod 600 "$key"

  info "Generating CSR for ${host_id}: ${csr}"
  openssl req -new \
    -key "$key" \
    -passin pass:"${TLS_KEY_PASSWORD}" \
    -out "$csr" \
    -config "$cnf"

  ok "Created key and CSR for ${host_id}"
}

read_hosts_loop make_host
ok "Generated host keys and CSRs under ${TLS_WORKDIR}"
