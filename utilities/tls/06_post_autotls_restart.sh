#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_root

echo "[INFO] Restarting Cloudera Manager Server on this host"
systemctl restart cloudera-scm-server
sleep 20
systemctl status cloudera-scm-server -l --no-pager || true

echo "[INFO] Restarting local CM agent and supervisord"
systemctl restart cloudera-scm-supervisord || true
systemctl restart cloudera-scm-agent || true
systemctl status cloudera-scm-agent -l --no-pager || true

echo "[INFO] Restart agents on every other cluster host as well:"
echo "  systemctl restart cloudera-scm-supervisord cloudera-scm-agent"
