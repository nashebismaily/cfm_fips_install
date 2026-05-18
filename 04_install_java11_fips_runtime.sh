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

if [[ -n "${CUSTOM_JAVA_HOME:-}" ]]; then
  export JAVA_HOME="$CUSTOM_JAVA_HOME"
elif [[ -d "${JAVA_HOME_TARGET:-/usr/lib/jvm/java-11-openjdk}" ]]; then
  export JAVA_HOME="${JAVA_HOME_TARGET:-/usr/lib/jvm/java-11-openjdk}"
else
  JAVA_HOME_CANDIDATE="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
  export JAVA_HOME="$JAVA_HOME_CANDIDATE"
fi

cat >/etc/profile.d/cloudera-java.sh <<EOFJAVA
export JAVA_HOME='${JAVA_HOME}'
export PATH=\$JAVA_HOME/bin:\$PATH
EOFJAVA

# Cloudera packages read Java through environment/service defaults on many installs.
cat >/etc/default/cloudera-java <<EOFJAVADEFAULT
export JAVA_HOME='${JAVA_HOME}'
EOFJAVADEFAULT

validate_java_11

echo "[OK] Java runtime ready. JAVA_HOME=${JAVA_HOME}"
