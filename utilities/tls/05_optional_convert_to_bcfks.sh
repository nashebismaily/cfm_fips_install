#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

init_dirs

if [[ "${TLS_CREATE_BCFKS:-false}" != "true" ]]; then
  echo "[INFO] TLS_CREATE_BCFKS is not true. Skipping BCFKS conversion."
  echo "Set TLS_CREATE_BCFKS=true in tls.env if you want to attempt BCFKS conversion."
  exit 0
fi

if [[ ! -x "${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk}/bin/keytool" ]]; then
  echo "[ERROR] keytool not found under JAVA_HOME=${JAVA_HOME:-unset}"
  exit 1
fi

if [[ ! -f "$TLS_CCJ_JAR" || ! -f "$TLS_BCTLS_JAR" ]]; then
  echo "[ERROR] Missing SafeLogic jars for optional BCFKS conversion:"
  echo "  $TLS_CCJ_JAR"
  echo "  $TLS_BCTLS_JAR"
  exit 1
fi

read_hosts | while IFS='|' read -r host_id cn san_dns san_ip; do
  safe_id="$(sanitize_name "$host_id")"
  p12_keystore="$TLS_OUTPUT_DIR/stores/${safe_id}-keystore.p12"
  p12_truststore="$TLS_OUTPUT_DIR/stores/${safe_id}-truststore.p12"
  bcfks_keystore="$TLS_OUTPUT_DIR/stores/${safe_id}-keystore.bcfks"
  bcfks_truststore="$TLS_OUTPUT_DIR/stores/${safe_id}-truststore.bcfks"

  [[ -f "$p12_keystore" ]] || { echo "[ERROR] Missing $p12_keystore. Run 04_build_pkcs12_stores.sh first."; exit 1; }
  [[ -f "$p12_truststore" ]] || { echo "[ERROR] Missing $p12_truststore. Run 04_build_pkcs12_stores.sh first."; exit 1; }

  echo "---- $host_id"
  rm -f "$bcfks_keystore" "$bcfks_truststore"

  if keytool_with_fips_args -importkeystore \
      -srckeystore "$p12_keystore" \
      -srcstoretype PKCS12 \
      -srcstorepass "$TLS_KEYSTORE_PASSWORD" \
      -destkeystore "$bcfks_keystore" \
      -deststoretype BCFKS \
      -deststorepass "$TLS_KEYSTORE_PASSWORD" \
      -destkeypass "$TLS_KEYSTORE_PASSWORD" \
      -noprompt; then
    chmod 600 "$bcfks_keystore"
    echo "[OK] BCFKS keystore: $bcfks_keystore"
  else
    echo "[WARN] BCFKS keystore conversion failed. Use PKCS12 unless your provider/keytool supports BCFKS conversion."
  fi

  if keytool_with_fips_args -importkeystore \
      -srckeystore "$p12_truststore" \
      -srcstoretype PKCS12 \
      -srcstorepass "$TLS_TRUSTSTORE_PASSWORD" \
      -destkeystore "$bcfks_truststore" \
      -deststoretype BCFKS \
      -deststorepass "$TLS_TRUSTSTORE_PASSWORD" \
      -noprompt; then
    chmod 600 "$bcfks_truststore"
    echo "[OK] BCFKS truststore: $bcfks_truststore"
  else
    echo "[WARN] BCFKS truststore conversion failed. Use PKCS12 unless your provider/keytool supports BCFKS conversion."
  fi
 done
