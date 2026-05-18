#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/tls.env}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "[ERROR] Missing env file: $ENV_FILE"
  echo "Copy tls.env.example to tls.env and edit it first."
  exit 1
fi

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] Required command missing: $cmd"
    exit 1
  fi
}

init_dirs() {
  mkdir -p "$TLS_OUTPUT_DIR"/{private,csr,certs,signed,stores,ca,configs,logs}
  chmod 700 "$TLS_OUTPUT_DIR/private"
}

trim() {
  local v="$*"
  v="${v#${v%%[![:space:]]*}}"
  v="${v%${v##*[![:space:]]}}"
  printf '%s' "$v"
}

read_hosts() {
  local file="${TLS_HOSTS_FILE:-$SCRIPT_DIR/hosts.csv}"
  if [[ ! -f "$file" ]]; then
    echo "[ERROR] Missing host inventory: $file"
    echo "Copy hosts.csv.example to hosts.csv and edit it first."
    exit 1
  fi

  while IFS=, read -r host_id cn san_dns san_ip rest; do
    host_id="$(trim "${host_id:-}")"
    cn="$(trim "${cn:-}")"
    san_dns="$(trim "${san_dns:-}")"
    san_ip="$(trim "${san_ip:-}")"

    [[ -z "$host_id" ]] && continue
    [[ "$host_id" =~ ^# ]] && continue

    if [[ -z "$cn" ]]; then
      echo "[ERROR] Missing common_name for host_id=$host_id in $file"
      exit 1
    fi

    printf '%s|%s|%s|%s\n' "$host_id" "$cn" "$san_dns" "$san_ip"
  done < "$file"
}

sanitize_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

openssl_req_config() {
  local host_id="$1" cn="$2" san_dns="$3" san_ip="$4" out="$5"
  local alt_lines=() idx=1 item

  # Always include CN as DNS SAN unless already supplied.
  alt_lines+=("DNS.${idx} = ${cn}")
  idx=$((idx+1))

  IFS=';' read -ra dns_parts <<< "$san_dns"
  for item in "${dns_parts[@]}"; do
    item="$(trim "$item")"
    [[ -z "$item" ]] && continue
    [[ "$item" == "$cn" ]] && continue
    alt_lines+=("DNS.${idx} = ${item}")
    idx=$((idx+1))
  done

  local ipidx=1
  IFS=';' read -ra ip_parts <<< "$san_ip"
  for item in "${ip_parts[@]}"; do
    item="$(trim "$item")"
    [[ -z "$item" ]] && continue
    alt_lines+=("IP.${ipidx} = ${item}")
    ipidx=$((ipidx+1))
  done

  cat > "$out" <<EOFCONF
[ req ]
default_bits       = ${TLS_RSA_BITS:-3072}
default_md         = ${TLS_DIGEST:-sha256}
prompt             = no
distinguished_name = req_distinguished_name
req_extensions     = v3_req
string_mask        = utf8only

[ req_distinguished_name ]
C  = ${TLS_COUNTRY:-US}
ST = ${TLS_STATE:-Demo State}
L  = ${TLS_CITY:-Demo City}
O  = ${TLS_ORG:-Cloudera Demo}
OU = ${TLS_OU:-CFM}
CN = ${cn}

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[ alt_names ]
$(printf '%s\n' "${alt_lines[@]}")
EOFCONF
}

java_keytool() {
  "${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk}/bin/keytool" "$@"
}

keytool_with_fips_args() {
  java_keytool \
    -J--module-path="${TLS_CCJ_JAR}:${TLS_BCTLS_JAR}" \
    -J--add-exports=java.base/sun.security.provider="${TLS_CCJ_MODULE}" \
    -J--add-modules="${TLS_CCJ_MODULE},${TLS_BCTLS_MODULE}" \
    "$@"
}
