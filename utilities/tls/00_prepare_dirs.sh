#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_root
require_cmd openssl
require_cmd python3

password_check AUTO_TLS_KEYSTORE_PASSWORD "$AUTO_TLS_KEYSTORE_PASSWORD"
password_check AUTO_TLS_TRUSTSTORE_PASSWORD "$AUTO_TLS_TRUSTSTORE_PASSWORD"

mkdir -p "$AUTO_TLS_WORKDIR" "$AUTO_TLS_KEYS_DIR" "$AUTO_TLS_CSRS_DIR" "$AUTO_TLS_CERTS_DIR" "$AUTO_TLS_CA_CERTS_DIR" "$AUTO_TLS_PAYLOAD_DIR"
mkdir -p "$AUTO_TLS_LOCATION"

printf '%s\n' "$AUTO_TLS_KEYSTORE_PASSWORD" > "$AUTO_TLS_KEY_PASSWORD_FILE"
printf '%s\n' "$AUTO_TLS_TRUSTSTORE_PASSWORD" > "$AUTO_TLS_TRUSTSTORE_PASSWORD_FILE"
chmod 600 "$AUTO_TLS_KEY_PASSWORD_FILE" "$AUTO_TLS_TRUSTSTORE_PASSWORD_FILE"

chown -R cloudera-scm:cloudera-scm "$AUTO_TLS_WORKDIR" "$AUTO_TLS_LOCATION" 2>/dev/null || true
chmod -R u+rwX,go-rwx "$AUTO_TLS_WORKDIR"

echo "[OK] Prepared Auto-TLS directories: $AUTO_TLS_WORKDIR and $AUTO_TLS_LOCATION"
echo "[OK] Password files created."
