#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TLS_ENV_FILE="${TLS_ENV_FILE:-${SCRIPT_DIR}/tls.env}"

if [[ -f "$TLS_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$TLS_ENV_FILE"
else
  echo "[ERROR] Missing tls.env. Copy tls.env.example to tls.env and edit it." >&2
  exit 1
fi

TLS_WORKDIR="${TLS_WORKDIR:-${AUTO_TLS_WORKDIR}}"
TLS_HOSTS_FILE="${TLS_HOSTS_FILE:-./hosts.csv}"
TLS_STORE_TYPE="${TLS_STORE_TYPE:-PKCS12}"
TLS_KEY_ALGORITHM="${TLS_KEY_ALGORITHM:-RSA}"
TLS_KEY_SIZE="${TLS_KEY_SIZE:-3072}"
TLS_DIGEST="${TLS_DIGEST:-sha256}"
TLS_CERT_DAYS="${TLS_CERT_DAYS:-825}"
TLS_KEY_PASSWORD="${TLS_KEY_PASSWORD:-ChangeMeKeyPass2026}"
TLS_KEYSTORE_PASSWORD="${TLS_KEYSTORE_PASSWORD:-ChangeMeKeyStore2026}"
TLS_TRUSTSTORE_PASSWORD="${TLS_TRUSTSTORE_PASSWORD:-ChangeMeTrustStore2026}"
TLS_DEMO_CA_CN="${TLS_DEMO_CA_CN:-CFM Demo Internal CA}"
TLS_DEMO_CA_DAYS="${TLS_DEMO_CA_DAYS:-3650}"
TLS_DEMO_CA_KEY_PASSWORD="${TLS_DEMO_CA_KEY_PASSWORD:-ChangeMeDemoCA2026}"
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk}"
KEYTOOL="${KEYTOOL:-${JAVA_HOME}/bin/keytool}"

KEYS_DIR="${TLS_WORKDIR}/keys"
CSRS_DIR="${TLS_WORKDIR}/csrs"
CERTS_DIR="${TLS_WORKDIR}/certs"
FULLCHAINS_DIR="${TLS_WORKDIR}/fullchains"
STORES_DIR="${TLS_WORKDIR}/stores"
CA_DIR="${TLS_WORKDIR}/ca"
OPENSSL_DIR="${TLS_WORKDIR}/openssl"
PASSWORD_DIR="${TLS_WORKDIR}/passwords"

CA_KEY="${CA_DIR}/demo-ca-key.pem"
CA_CERT="${CA_DIR}/demo-ca-cert.pem"
CA_CHAIN="${CA_DIR}/ca-chain.pem"

fail() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }
ok() { echo "[OK] $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command missing: $1"
}

prepare_dirs() {
  mkdir -p "$KEYS_DIR" "$CSRS_DIR" "$CERTS_DIR" "$FULLCHAINS_DIR" "$STORES_DIR" "$CA_DIR" "$OPENSSL_DIR" "$PASSWORD_DIR"
  chmod 700 "$KEYS_DIR" "$PASSWORD_DIR" "$CA_DIR"
  printf '%s' "$TLS_KEY_PASSWORD" > "${PASSWORD_DIR}/key.pass"
  printf '%s' "$TLS_KEYSTORE_PASSWORD" > "${PASSWORD_DIR}/keystore.pass"
  printf '%s' "$TLS_TRUSTSTORE_PASSWORD" > "${PASSWORD_DIR}/truststore.pass"
  chmod 600 "${PASSWORD_DIR}"/*.pass
}

hosts_file_path() {
  if [[ "$TLS_HOSTS_FILE" = /* ]]; then
    echo "$TLS_HOSTS_FILE"
  else
    echo "${SCRIPT_DIR}/${TLS_HOSTS_FILE}"
  fi
}

normalize_host_file() {
  local hf
  hf="$(hosts_file_path)"
  [[ -f "$hf" ]] || fail "Hosts file not found: $hf"
  echo "$hf"
}

host_key() { echo "${KEYS_DIR}/$1-key.pem"; }
host_csr() { echo "${CSRS_DIR}/$1-csr.pem"; }
host_cert() { echo "${CERTS_DIR}/$1-cert.pem"; }
host_fullchain() { echo "${FULLCHAINS_DIR}/$1-fullchain.pem"; }
host_keystore() { echo "${STORES_DIR}/$1-keystore.p12"; }
host_truststore() { echo "${STORES_DIR}/$1-truststore.p12"; }
host_openssl_cnf() { echo "${OPENSSL_DIR}/$1-openssl.cnf"; }

build_san_line() {
  local dns_sans="$1" ip_sans="$2" entries=() item
  IFS=';' read -ra dns_parts <<< "$dns_sans"
  for item in "${dns_parts[@]}"; do
    [[ -n "$item" ]] && entries+=("DNS:${item}")
  done
  IFS=';' read -ra ip_parts <<< "$ip_sans"
  for item in "${ip_parts[@]}"; do
    [[ -n "$item" ]] && entries+=("IP:${item}")
  done
  local IFS=,
  echo "${entries[*]}"
}

read_hosts_loop() {
  local callback="$1" hf line host_id cn dns_sans ip_sans
  hf="$(normalize_host_file)"
  tail -n +2 "$hf" | while IFS=, read -r host_id cn dns_sans ip_sans; do
    [[ -z "${host_id// }" ]] && continue
    [[ "$host_id" =~ ^# ]] && continue
    [[ -n "${cn:-}" ]] || fail "Missing CN for host_id=$host_id in $hf"
    "$callback" "$host_id" "$cn" "${dns_sans:-}" "${ip_sans:-}"
  done
}
