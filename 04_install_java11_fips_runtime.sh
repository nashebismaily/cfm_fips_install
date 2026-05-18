#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "04_install_java11_fips_runtime"
need_root
validate_platform

case "${JAVA_INSTALL_MODE:-system}" in
  system)
    echo "==== Installing system OpenJDK ${JAVA_MAJOR:-11} ===="
    dnf install -y "java-${JAVA_MAJOR:-11}-openjdk" "java-${JAVA_MAJOR:-11}-openjdk-devel"
    ;;
  custom)
    echo "==== Using custom Java ===="
    if [[ -z "${CUSTOM_JAVA_HOME:-}" ]]; then
      echo "[ERROR] JAVA_INSTALL_MODE=custom requires CUSTOM_JAVA_HOME"
      exit 1
    fi
    ;;
  skip)
    echo "[INFO] JAVA_INSTALL_MODE=skip; not installing or validating Java"
    exit 0
    ;;
  *)
    echo "[ERROR] Invalid JAVA_INSTALL_MODE=${JAVA_INSTALL_MODE}. Use system, custom, or skip."
    exit 1
    ;;
esac

ensure_java_default
validate_java_11
configure_java_fips_safelogic

echo "[OK] Java runtime ready. JAVA_HOME=${JAVA_HOME:-$(java_home_target)}"
