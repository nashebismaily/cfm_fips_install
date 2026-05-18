#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TLS_ENV_FILE="${TLS_ENV_FILE:-${SCRIPT_DIR}/tls.env}"
if [[ -f "$TLS_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$TLS_ENV_FILE"
else
  echo "[ERROR] Missing tls.env. Copy tls.env.example to tls.env and edit it."
  exit 1
fi

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] Required command missing: $cmd"
    exit 1
  fi
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Run as root or with sudo -E."
    exit 1
  fi
}

is_true() {
  [[ "${1:-}" == "true" || "${1:-}" == "TRUE" || "${1:-}" == "1" || "${1:-}" == "yes" ]]
}

password_check() {
  local name="$1" value="$2"
  if (( ${#value} <= 12 )); then
    echo "[ERROR] $name must be more than 12 characters."
    exit 1
  fi
  if [[ "$value" =~ [^A-Za-z0-9] ]]; then
    echo "[ERROR] $name must not include special characters for this Cloudera Auto-TLS flow."
    exit 1
  fi
}

host_key_file() { echo "${AUTO_TLS_KEYS_DIR}/$1${HOST_KEY_SUFFIX:--key.pem}"; }
host_cert_file() { echo "${AUTO_TLS_CERTS_DIR}/$1${HOST_CERT_SUFFIX:-.pem}"; }
host_csr_file() { echo "${AUTO_TLS_CSRS_DIR}/$1${HOST_CSR_SUFFIX:-.csr}"; }

read_hosts_python() {
python3 - "$HOSTS_CSV" <<'PY'
import csv, sys
path=sys.argv[1]
with open(path, newline='') as f:
    for row in csv.reader(line for line in f if line.strip() and not line.lstrip().startswith('#')):
        if len(row) < 2:
            continue
        hostname=row[0].strip(); cn=row[1].strip() or hostname
        san_dns=row[2].strip() if len(row)>2 else ''
        san_ip=row[3].strip() if len(row)>3 else ''
        print('\t'.join([hostname, cn, san_dns, san_ip]))
PY
}

make_san_config() {
  local hostname="$1" cn="$2" san_dns="$3" san_ip="$4" out="$5"
  python3 - "$hostname" "$cn" "$san_dns" "$san_ip" "$out" <<'PY'
import sys
hostname, cn, san_dns, san_ip, out = sys.argv[1:]
dns=[]
for v in [hostname, cn] + [x.strip() for x in san_dns.split('|') if x.strip()]:
    if v and v not in dns:
        dns.append(v)
ips=[]
for v in [x.strip() for x in san_ip.split('|') if x.strip()]:
    if v and v not in ips:
        ips.append(v)
lines=[]
lines.append('[req]')
lines.append('distinguished_name = req_distinguished_name')
lines.append('req_extensions = v3_req')
lines.append('prompt = no')
lines.append('[req_distinguished_name]')
lines.append(f'CN = {cn}')
lines.append('[v3_req]')
lines.append('keyUsage = critical, digitalSignature, keyEncipherment')
lines.append('extendedKeyUsage = serverAuth, clientAuth')
san=[]
for i,v in enumerate(dns,1): san.append(f'DNS.{i} = {v}')
for i,v in enumerate(ips,1): san.append(f'IP.{i} = {v}')
if san:
    lines.append('subjectAltName = @alt_names')
    lines.append('[alt_names]')
    lines.extend(san)
with open(out,'w') as f:
    f.write('\n'.join(lines)+'\n')
PY
}

json_escape_private_key() {
  local key_file="$1"
  awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' "$key_file"
}
