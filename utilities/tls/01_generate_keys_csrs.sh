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
: "${AUTO_TLS_COUNTRY:?AUTO_TLS_COUNTRY is required}"
: "${AUTO_TLS_STATE:?AUTO_TLS_STATE is required}"
: "${AUTO_TLS_LOCALITY:?AUTO_TLS_LOCALITY is required}"
: "${AUTO_TLS_ORG:?AUTO_TLS_ORG is required}"
: "${AUTO_TLS_ORG_UNIT:?AUTO_TLS_ORG_UNIT is required}"

AUTO_TLS_ENCRYPT_HOST_KEYS="${AUTO_TLS_ENCRYPT_HOST_KEYS:-true}"
AUTO_TLS_HOST_KEY_PASSWORD="${AUTO_TLS_HOST_KEY_PASSWORD:-}"

if [[ ! -f "${AUTO_TLS_HOSTS_CSV}" ]]; then
  echo "[ERROR] Hosts CSV not found: ${AUTO_TLS_HOSTS_CSV}"
  exit 1
fi

if [[ "${AUTO_TLS_ENCRYPT_HOST_KEYS}" != "true" && "${AUTO_TLS_ENCRYPT_HOST_KEYS}" != "false" ]]; then
  echo "[ERROR] AUTO_TLS_ENCRYPT_HOST_KEYS must be true or false. Current value: ${AUTO_TLS_ENCRYPT_HOST_KEYS}"
  exit 1
fi

if [[ "${AUTO_TLS_ENCRYPT_HOST_KEYS}" == "true" ]]; then
  : "${AUTO_TLS_HOST_KEY_PASSWORD:?AUTO_TLS_HOST_KEY_PASSWORD is required when AUTO_TLS_ENCRYPT_HOST_KEYS=true}"
  if [[ ${#AUTO_TLS_HOST_KEY_PASSWORD} -le 12 ]]; then
    echo "[ERROR] AUTO_TLS_HOST_KEY_PASSWORD must be longer than 12 characters."
    exit 1
  fi
  if [[ "${AUTO_TLS_HOST_KEY_PASSWORD}" =~ [^a-zA-Z0-9] ]]; then
    echo "[ERROR] AUTO_TLS_HOST_KEY_PASSWORD must not contain special characters for this Auto-TLS flow."
    exit 1
  fi
fi

mkdir -p "${AUTO_TLS_KEY_DIR}" "${AUTO_TLS_CSR_DIR}" "${AUTO_TLS_WORKDIR}/openssl"

echo "[INFO] Generating private keys and CSRs"
echo "[INFO] AUTO_TLS_WORKDIR=${AUTO_TLS_WORKDIR}"
echo "[INFO] AUTO_TLS_HOSTS_CSV=${AUTO_TLS_HOSTS_CSV}"
echo "[INFO] AUTO_TLS_ENCRYPT_HOST_KEYS=${AUTO_TLS_ENCRYPT_HOST_KEYS}"

python3 - <<PY
import csv
import ipaddress
import subprocess
from pathlib import Path

hosts_csv = Path("${AUTO_TLS_HOSTS_CSV}")
key_dir = Path("${AUTO_TLS_KEY_DIR}")
csr_dir = Path("${AUTO_TLS_CSR_DIR}")
openssl_dir = Path("${AUTO_TLS_WORKDIR}") / "openssl"

encrypt_keys = "${AUTO_TLS_ENCRYPT_HOST_KEYS}" == "true"
host_key_password = "${AUTO_TLS_HOST_KEY_PASSWORD}"

country = "${AUTO_TLS_COUNTRY}"
state = "${AUTO_TLS_STATE}"
locality = "${AUTO_TLS_LOCALITY}"
org = "${AUTO_TLS_ORG}"
org_unit = "${AUTO_TLS_ORG_UNIT}"
key_size = "${AUTO_TLS_KEY_SIZE:-4096}"


def run(cmd):
    printable = []
    hide_next = False
    for item in cmd:
        if hide_next:
            printable.append("[REDACTED]")
            hide_next = False
            continue
        printable.append(str(item))
        if item in ("-pass", "-passin", "-passout"):
            hide_next = True
    print("[DEBUG] " + " ".join(printable))
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr)
    if result.returncode != 0:
        raise SystemExit("[ERROR] Command failed with return code %s" % result.returncode)


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
        host_id = (row.get("host_id") or row.get("hostname") or row.get("host") or "").strip()
        if not host_id:
            continue

        dns_sans = split_list(row.get("dns_sans"))
        ip_sans = split_list(row.get("ip_sans"))

        hostname = (row.get("hostname") or row.get("cn") or "").strip()
        ip_address = (row.get("ip_address") or "").strip()

        if hostname and not is_ip(hostname) and hostname not in dns_sans:
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
            raise SystemExit("[ERROR] No SAN entries found for host_id=%s. Add dns_sans or ip_sans." % host_id)

        for ip in ip_sans:
            if not is_ip(ip):
                raise SystemExit("[ERROR] Invalid IP SAN for host_id=%s: %s" % (host_id, ip))

        key_file = key_dir / (host_id + "-key.pem")
        csr_file = csr_dir / (host_id + "-csr.pem")
        conf_file = openssl_dir / (host_id + "-openssl.cnf")
        tmp_key_file = key_file.with_suffix(".pem.tmp")
        tmp_csr_file = csr_file.with_suffix(".pem.tmp")

        for stale in [key_file, csr_file, tmp_key_file, tmp_csr_file]:
            if stale.exists():
                stale.unlink()

        alt_lines = []
        for i, dns in enumerate(dns_sans, 1):
            alt_lines.append("DNS.%d = %s" % (i, dns))
        for i, ip in enumerate(ip_sans, 1):
            alt_lines.append("IP.%d = %s" % (i, ip))

        conf = """[ req ]
default_bits = {key_size}
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
{alt_names}
""".format(
            key_size=key_size,
            country=country,
            state=state,
            locality=locality,
            org=org,
            org_unit=org_unit,
            host_id=host_id,
            alt_names="\n".join(alt_lines),
        )
        conf_file.write_text(conf)

        if encrypt_keys:
            print("[INFO] Generating encrypted private key for %s: %s" % (host_id, key_file))
            run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:%s" % key_size, "-aes-256-cbc", "-pass", "pass:%s" % host_key_password, "-out", str(tmp_key_file)])
            validate_cmd = ["openssl", "pkey", "-in", str(tmp_key_file), "-passin", "pass:%s" % host_key_password, "-check", "-noout"]
            csr_cmd = ["openssl", "req", "-new", "-key", str(tmp_key_file), "-passin", "pass:%s" % host_key_password, "-out", str(tmp_csr_file), "-config", str(conf_file)]
        else:
            print("[INFO] Generating unencrypted private key for %s: %s" % (host_id, key_file))
            run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:%s" % key_size, "-out", str(tmp_key_file)])
            validate_cmd = ["openssl", "pkey", "-in", str(tmp_key_file), "-check", "-noout"]
            csr_cmd = ["openssl", "req", "-new", "-key", str(tmp_key_file), "-out", str(tmp_csr_file), "-config", str(conf_file)]

        if not tmp_key_file.exists() or tmp_key_file.stat().st_size == 0:
            raise SystemExit("[ERROR] Generated key is missing or empty: %s" % tmp_key_file)

        print("[INFO] Validating key for %s" % host_id)
        run(validate_cmd)

        print("[INFO] Generating CSR for %s: %s" % (host_id, csr_file))
        run(csr_cmd)

        if not tmp_csr_file.exists() or tmp_csr_file.stat().st_size == 0:
            raise SystemExit("[ERROR] Generated CSR is missing or empty: %s" % tmp_csr_file)

        tmp_key_file.replace(key_file)
        tmp_csr_file.replace(csr_file)
        key_file.chmod(0o600)
        csr_file.chmod(0o644)
        conf_file.chmod(0o640)

        mode = "encrypted" if encrypt_keys else "unencrypted"
        print("[OK] Created %s key and CSR for %s" % (mode, host_id))

print("[OK] Generated host keys and CSRs under %s" % key_dir.parent)
PY
