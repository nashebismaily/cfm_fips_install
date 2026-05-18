#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "12_start_cm_services"
need_root
validate_platform
validate_java_11

CM_DEFAULTS_FILE="/etc/default/cloudera-scm-server"
touch "$CM_DEFAULTS_FILE"

# This avoids 403 host-header issues in lab/private-DNS environments. Remove if your security policy disallows it.
if ! grep -Eq '^[[:space:]]*export[[:space:]]+CMF_FF_PREVENT_HOST_HEADER_INJECTION=' "$CM_DEFAULTS_FILE"; then
  echo 'export CMF_FF_PREVENT_HOST_HEADER_INJECTION="false"' >> "$CM_DEFAULTS_FILE"
fi

systemctl daemon-reload
systemctl enable cloudera-scm-server
systemctl enable cloudera-scm-agent
systemctl restart cloudera-scm-server
systemctl restart cloudera-scm-agent

echo "==== Waiting for CM on 7180 ===="
READY=false
for i in {1..90}; do
  if ss -plnt | grep -q ':7180'; then
    READY=true
    break
  fi
  echo "Waiting for CM startup ${i}/90"
  sleep 5
done

if [[ "$READY" != "true" ]]; then
  echo "[ERROR] CM did not listen on 7180. Check /var/log/cloudera-scm-server/cloudera-scm-server.log"
  exit 1
fi

systemctl status cloudera-scm-server --no-pager || true
systemctl status cloudera-scm-agent --no-pager || true
curl -I http://localhost:7180 || true
PRIVATE_IP="$(hostname -I | awk '{print $1}')"
echo "[OK] CM is up: http://${PRIVATE_IP}:7180"
echo "Default login: admin / admin"
