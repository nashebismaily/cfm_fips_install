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

echo "==== Starting Cloudera Manager agent services ===="
# The CM Server host must also run the local CM agent and supervisord so it appears as a managed host.
# Remote worker/agent hosts need both services as well. Starting only cloudera-scm-agent is not enough.
systemctl daemon-reload
systemctl enable cloudera-scm-supervisord
systemctl enable cloudera-scm-agent
systemctl reset-failed cloudera-scm-supervisord cloudera-scm-agent || true
systemctl restart cloudera-scm-supervisord
systemctl restart cloudera-scm-agent
sleep 5

systemctl status cloudera-scm-supervisord --no-pager
systemctl status cloudera-scm-agent --no-pager

if ! systemctl is-active --quiet cloudera-scm-supervisord; then
  echo "[ERROR] cloudera-scm-supervisord is not active."
  journalctl -u cloudera-scm-supervisord -n 80 --no-pager || true
  exit 1
fi

if ! systemctl is-active --quiet cloudera-scm-agent; then
  echo "[ERROR] cloudera-scm-agent is not active."
  journalctl -u cloudera-scm-agent -n 80 --no-pager || true
  exit 1
fi

echo "[OK] CM agent services are running and point to ${MANAGER_ARG}"
