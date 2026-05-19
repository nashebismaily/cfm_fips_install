#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ ! -f ./tls.env ]]; then
  echo "[ERROR] tls.env not found in ${SCRIPT_DIR}"
  exit 1
fi

source ./tls.env

: "${AUTO_TLS_WORKDIR:?AUTO_TLS_WORKDIR is required}"
: "${AUTO_TLS_HOSTS_CSV:?AUTO_TLS_HOSTS_CSV is required}"
: "${AUTO_TLS_CSR_DIR:?AUTO_TLS_CSR_DIR is required}"
: "${AUTO_TLS_CERT_DIR:?AUTO_TLS_CERT_DIR is required}"
: "${AUTO_TLS_HOST_KEY_PASSWORD:?AUTO_TLS_HOST_KEY_PASSWORD is required}"

AUTO_TLS_CA_KEY_PASSWORD="${AUTO_TLS_CA_KEY_PASSWORD:-${AUTO_TLS_HOST_KEY_PASSWORD}}"
AUTO_TLS_CERT_DAYS="${AUTO_TLS_CERT_DAYS:-${AUTO_TLS_VALIDITY_DAYS:-825}}"
AUTO_TLS_DIGEST="${AUTO_TLS_DIGEST:-sha256}"

CA_DIR="${AUTO_TLS_WORKDIR}/ca"
CA_KEY="${CA_DIR}/demo-ca-key.pem"
CA_CERT="${CA_DIR}/demo-ca-cert.pem"
CA_CHAIN="${CA_DIR}/ca-chain.pem"
FULLCHAINS_DIR="${AUTO_TLS_WORKDIR}/fullchains"
OPENSSL_DIR="${AUTO_TLS_WORKDIR}/openssl"

[[ -f "${CA_KEY}" ]] || { echo "[ERROR] CA key not found: ${CA_KEY}"; exit 1; }
[[ -f "${CA_CERT}" ]] || { echo "[ERROR] CA cert not found: ${CA_CERT}"; exit 1; }
[[ -f "${AUTO_TLS_HOSTS_CSV}" ]] || { echo "[ERROR] Hosts CSV not found: ${AUTO_TLS_HOSTS_CSV}"; exit 1; }
mkdir -p "${AUTO_TLS_CERT_DIR}" "${FULLCHAINS_DIR}" "${OPENSSL_DIR}"

python3 - <<PY
import csv
from pathlib import Path

hosts_csv = Path("${AUTO_TLS_HOSTS_CSV}")
openssl_dir = Path("${OPENSSL_DIR}")

def split_list(value):
    if value is None:
        return []
    return [item.strip() for item in value.replace(";", ",").split(",") if item.strip()]

with hosts_csv.open(newline="") as f:
    reader = csv.DictReader(f)
    for row in reader:
        host = (row.get("host_id") or row.get("hostname") or row.get("host") or "").strip()
        if not host:
            continue
        dns_sans = split_list(row.get("dns_sans"))
        ip_sans = split_list(row.get("ip_sans"))
        if host and not any(host == x for x in dns_sans) and not host.replace('.', '').isdigit():
            dns_sans.append(host)
        entries = []
        entries.extend(["DNS:%s" % x for x in dns_sans])
        entries.extend(["IP:%s" % x for x in ip_sans])
        if not entries:
            raise SystemExit("[ERROR] No SANs for host %s" % host)
        ext = "basicConstraints = CA:false\nsubjectAltName = %s\nkeyUsage = critical, digitalSignature, keyEncipherment\nextendedKeyUsage = serverAuth, clientAuth\n" % ",".join(entries)
        (openssl_dir / (host + "-cert-ext.cnf")).write_text(ext)
PY

while IFS=, read -r host_id rest; do
  [[ "${host_id}" == "host_id" ]] && continue
  [[ -z "${host_id// }" ]] && continue
  csr="${AUTO_TLS_CSR_DIR}/${host_id}-csr.pem"
  cert="${AUTO_TLS_CERT_DIR}/${host_id}-cert.pem"
  fullchain="${FULLCHAINS_DIR}/${host_id}-fullchain.pem"
  ext="${OPENSSL_DIR}/${host_id}-cert-ext.cnf"

  [[ -f "${csr}" ]] || { echo "[ERROR] Missing CSR: ${csr}"; exit 1; }
  [[ -f "${ext}" ]] || { echo "[ERROR] Missing ext file: ${ext}"; exit 1; }

  openssl x509 -req \
    -in "${csr}" \
    -CA "${CA_CERT}" \
    -CAkey "${CA_KEY}" \
    -passin "pass:${AUTO_TLS_CA_KEY_PASSWORD}" \
    -CAcreateserial \
    -out "${cert}" \
    -days "${AUTO_TLS_CERT_DAYS}" \
    -"${AUTO_TLS_DIGEST}" \
    -extfile "${ext}"

  cat "${cert}" "${CA_CHAIN}" > "${fullchain}"
  chmod 644 "${cert}" "${fullchain}"
  echo "[OK] Signed cert for ${host_id}: ${cert}"
done < "${AUTO_TLS_HOSTS_CSV}"

echo "[OK] Signed host CSRs using CA"
