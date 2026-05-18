#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
MANAGER_ARG="${1:-${MANAGER_HOST:-}}"
log_init "10_configure_cm_agent"
need_root
validate_platform
ensure_java_default
validate_java_11
configure_java_fips_safelogic
install_required_agent_python
validate_cm_agent_python_wrapper

if [[ -z "$MANAGER_ARG" ]]; then
  echo "Usage: sudo -E bash 10_configure_cm_agent.sh <manager-fqdn-or-private-dns>"
  echo "Or set MANAGER_HOST in EXPORTS."
  exit 1
fi

CONFIG_FILE="/etc/cloudera-scm-agent/config.ini"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[ERROR] Missing $CONFIG_FILE. Install cloudera-manager-agent first."
  exit 1
fi

cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
sed -i "s/^server_host=.*/server_host=${MANAGER_ARG}/" "$CONFIG_FILE"
if ! grep -q '^server_host=' "$CONFIG_FILE"; then
  echo "server_host=${MANAGER_ARG}" >> "$CONFIG_FILE"
fi

# Avoid old cert/proc state when reusing hosts.
rm -rf /var/lib/cloudera-scm-agent/cm_guid /var/lib/cloudera-scm-agent/uuid || true

systemctl enable cloudera-scm-agent
systemctl restart cloudera-scm-agent
sleep 5
systemctl status cloudera-scm-agent --no-pager || true

echo "[OK] CM agent points to ${MANAGER_ARG}"
