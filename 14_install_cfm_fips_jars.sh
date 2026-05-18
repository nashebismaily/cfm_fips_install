#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "14_install_cfm_fips_jars"
need_root
validate_platform

SRC_DIR="${FIPS_JAR_SOURCE_DIR:-}"
DEST_DIR="${CFM_TOOLKIT_LIB_DIR:-}"

if [[ -z "$SRC_DIR" ]]; then
  echo "[ERROR] FIPS_JAR_SOURCE_DIR is not set. Set it in EXPORTS to the uploaded SafeLogic jar directory."
  exit 1
fi
if [[ ! -d "$SRC_DIR" ]]; then
  echo "[ERROR] FIPS_JAR_SOURCE_DIR does not exist: $SRC_DIR"
  echo "Upload/extract the SafeLogic jars there, or update EXPORTS."
  exit 1
fi
if [[ -z "$DEST_DIR" ]]; then
  echo "[ERROR] CFM_TOOLKIT_LIB_DIR is not set."
  exit 1
fi
if [[ ! -d "$DEST_DIR" ]]; then
  echo "[ERROR] CFM toolkit lib directory does not exist: $DEST_DIR"
  echo "Activate the CFM parcel first, or update CFM_PARCEL_DIR_NAME/CFM_TOOLKIT_LIB_DIR in EXPORTS."
  exit 1
fi

JARS=("${FIPS_BCTLS_JAR:-bctls.jar}" "${FIPS_CCJ_JAR:-ccj-3.0.2.1.jar}")
if [[ -n "${FIPS_EXTRA_JARS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA=( ${FIPS_EXTRA_JARS} )
  JARS+=("${EXTRA[@]}")
fi

echo "==== Copying SafeLogic/Bouncy Castle FIPS jars ===="
echo "Source:      $SRC_DIR"
echo "Destination: $DEST_DIR"

for jar in "${JARS[@]}"; do
  if [[ ! -f "$SRC_DIR/$jar" ]]; then
    echo "[ERROR] Missing jar: $SRC_DIR/$jar"
    echo "Current files in source directory:"
    ls -lh "$SRC_DIR" || true
    exit 1
  fi
  cp -af "$SRC_DIR/$jar" "$DEST_DIR/"
  chmod 644 "$DEST_DIR/$jar"
  echo "[OK] Copied $jar"
done

ls -lh "$DEST_DIR" | grep -E "$(printf '%s|' "${JARS[@]}" | sed 's/|$//')" || true

cat <<EOFMSG

[OK] CFM FIPS jars copied.
Later, when configuring real-certificate TLS for NiFi/NiFi Registry, use BCFKS keystores/truststores and add the FIPS bootstrap safety-valve settings from README.md.

EOFMSG
