#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
ROLE="${1:-}"
log_init "09_install_cm_packages_${ROLE:-unknown}"
need_root
validate_platform
validate_java_11

if [[ "$ROLE" != "manager" && "$ROLE" != "agent" ]]; then
  echo "Usage: sudo -E bash 09_install_cm_packages.sh manager|agent"
  exit 1
fi

if [[ "$ROLE" == "manager" ]]; then
  echo "==== Installing Cloudera Manager server + agent packages ===="
  dnf install -y cloudera-manager-daemons cloudera-manager-agent cloudera-manager-server
else
  echo "==== Installing Cloudera Manager agent packages ===="
  dnf install -y cloudera-manager-daemons cloudera-manager-agent
fi

rpm -qa | grep -E '^cloudera-manager' | sort || true

echo "[OK] CM packages installed for role=${ROLE}"
