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
: "${AUTO_TLS_KEY_DIR:?AUTO_TLS_KEY_DIR is required}"
: "${AUTO_TLS_CSR_DIR:?AUTO_TLS_CSR_DIR is required}"
: "${AUTO_TLS_HOST_KEY_PASSWORD:?AUTO_TLS_HOST_KEY_PASSWORD is required}"
: "${AUTO_TLS_COUNTRY:?AUTO_TLS_COUNTRY is required}"
: "${AUTO_TLS_STATE:?AUTO_TLS_STATE is required}"
: "${AUTO_TLS_LOCALITY:?AUTO_TLS_LOCALITY is required}"
: "${AUTO_TLS_ORG:?AUTO_TLS_ORG is required}"
: "${AUTO_TLS_ORG_UNIT:?AUTO_TLS_ORG_UNIT is required}"

if [[ ! -f "${AUTO_TLS_HOSTS_CSV}" ]]; then
  echo "[ERROR] Hosts CSV not found: ${AUTO_TLS_HOSTS_CSV}"
  exit 1
fi

if [[ ${#AUTO_TLS_HOST_KEY_PASSWORD} -le 12 ]]; then
  echo "[ERROR] AUTO_TLS_HOST_KEY_PASSWORD must be longer than 12 characters."
  exit 1
fi

if [[ "${AUTO_TLS_HOST_KEY_PASSWORD}" =~ [^a-zA-Z0-9] ]]; then
  echo "[ERROR] AUTO_TLS_HOST_KEY_PASSWORD must not contain special characters."
  exit 1
fi

mkdir -p "${AUTO_TLS_KEY_DIR}" "${AUTO_TLS_CSR_DIR}" "${AUTO_TLS_WORKDIR}/openssl"

echo "[INFO] Generating encrypted private keys and CSRs"
echo "[INFO] AUTO_TLS_WORKDIR=${AUTO_TLS_WORKDIR}"
echo "[INFO] AUTO_TLS_HOSTS_CSV=${AUTO_TLS_HOSTS_CSV}"

python3 - <<PY
import csv
import ipaddress
import os
import subprocess
from pathlib import Path

hosts_csv = Path("${AUTO_TLS_HOSTS_CSV}")
key_dir = Path("${AUTO_TLS_KEY_DIR}")
csr_dir = Path("${AUTO_TLS_CSR_DIR}")
openssl_dir = Path("${AUTO_TLS_WORKDIR}") / "openssl"

host_key_password = "${AUTO_TLS_HOST_KEY_PASSWORD}"

country = "${AUTO_TLS_COUNTRY}"
state = "${AUTO_TLS_STATE}"
locality = "${AUTO_TLS_LOCALITY}"
org = "${AUTO_TLS_ORG}"
org_unit = "${AUTO_TLS_ORG_UNIT}"

def run(cmd):
    print("[DEBUG] " + " ".join(str(x) for x in cmd if "pass:" not in str(x)))
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr)
    if result.returncode != 0:
        raise SystemExit(f"[ERROR] Command failed with return code {result.returncode}")

def split_list(value):
    if value is None:
        return []
    return [item.strip() for item in value.replace(";", ",").split(",") if item.strip()]

def is_ip(value):
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return False

with hosts_csv.open(newline="") as f:
    reader = csv.DictReader(f)

    if not reader.fieldnames:
        raise SystemExit("[ERROR] hosts.csv has no header row")

    for row in reader:
        host_id = (
            row.get("host_id")
            or row.get("hostname")
            or row.get("host")
            or ""
        ).strip()

        if not host_id:
            continue

        dns_sans = split_list(row.get("dns_sans"))
        ip_sans = split_list(row.get("ip_sans"))

        hostname = (row.get("hostname") or "").strip()
        ip_address = (row.get("ip_address") or "").strip()

        if hostname and hostname not in dns_sans:
            dns_sans.append(hostname)

        if ip_address and ip_address not in ip_sans:
            ip_sans.append(ip_address)

        if is_ip(host_id):
            if host_id not in ip_sans:
                ip_sans.append(host_id)
        else:
            if host_id not in dns_sans:
                dns_sans.append(host_id)

        if not dns_sans and not ip_sans:
            raise SystemExit(f"[ERROR] No SAN entries found for host_id={host_id}. Add dns_sans or ip_sans.")

        for ip in ip_sans:
            if not is_ip(ip):
                raise SystemExit(f"[ERROR] Invalid IP SAN for host_id={host_id}: {ip}")

        key_file = key_dir / f"{host_id}-key.pem"
        csr_file = csr_dir / f"{host_id}-csr.pem"
        conf_file = openssl_dir / f"{host_id}-openssl.cnf"

        tmp_key_file = key_file.with_suffix(".pem.tmp")
        tmp_csr_file = csr_file.with_suffix(".pem.tmp")

        for stale in [key_file, csr_file, tmp_key_file, tmp_csr_file]:
            if stale.exists():
                stale.unlink()

        alt_lines = []
        dns_index = 1
        ip_index = 1

        for dns in dns_sans:
            alt_lines.append(f"DNS.{dns_index} = {dns}")
            dns_index += 1

        for ip in ip_sans:
            alt_lines.append(f"IP.{ip_index} = {ip}")
            ip_index += 1

        conf = f"""[ req ]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[ dn ]
C = {country}
ST = {state}
L = {locality}
O = {org}
OU = {org_unit}
CN = {host_id}

[ req_ext ]
subjectAltName = @alt_names
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth

[ alt_names ]
{chr(10).join(alt_lines)}
"""

        conf_file.write_text(conf)

        print(f"[INFO] Generating encrypted private key for {host_id}: {key_file}")

        # Use genpkey because it is stricter and works cleanly with passout.
        run([
            "openssl", "genpkey",
            "-algorithm", "RSA",
            "-pkeyopt", "rsa_keygen_bits:4096",
            "-aes-256-cbc",
            "-pass", f"pass:{host_key_password}",
            "-out", str(tmp_key_file),
        ])

        if not tmp_key_file.exists() or tmp_key_file.stat().st_size == 0:
            raise SystemExit(f"[ERROR] Generated key is missing or empty: {tmp_key_file}")

        print(f"[INFO] Validating encrypted key password for {host_id}")

        run([
            "openssl", "pkey",
            "-in", str(tmp_key_file),
            "-passin", f"pass:{host_key_password}",
            "-check",
            "-noout",
        ])

        print(f"[INFO] Generating CSR for {host_id}: {csr_file}")

        run([
            "openssl", "req",
            "-new",
            "-key", str(tmp_key_file),
            "-passin", f"pass:{host_key_password}",
            "-out", str(tmp_csr_file),
            "-config", str(conf_file),
        ])

        if not tmp_csr_file.exists() or tmp_csr_file.stat().st_size == 0:
            raise SystemExit(f"[ERROR] Generated CSR is missing or empty: {tmp_csr_file}")

        tmp_key_file.replace(key_file)
        tmp_csr_file.replace(csr_file)

        key_file.chmod(0o600)
        csr_file.chmod(0o644)
        conf_file.chmod(0o640)

        print(f"[OK] Created encrypted key and CSR for {host_id}")

print(f"[OK] Generated host keys and CSRs under {key_dir.parent}")
PY
