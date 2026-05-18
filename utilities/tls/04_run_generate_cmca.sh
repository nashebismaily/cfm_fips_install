#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_root
require_cmd curl

PAYLOAD="${AUTO_TLS_PAYLOAD_DIR}/generateCmca.json"
if [[ ! -f "$PAYLOAD" ]]; then
  "${SCRIPT_DIR}/03_build_generate_cmca_payload.sh"
fi

URL="${CM_API_SCHEME}://${CM_HOST_FQDN}:${CM_API_PORT}/api/${CM_API_VERSION}/cm/commands/generateCmca"
echo "[INFO] Calling: $URL"

curl -i -v -u "${CM_API_USER}:${CM_API_PASS}" \
  -X POST \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  -d "@${PAYLOAD}" \
  "$URL"

echo
echo "[OK] generateCmca API submitted. Watch /var/log/cloudera-scm-server/cloudera-scm-server.log"
echo "[NEXT] After command success: restart cloudera-scm-server, then restart cloudera-scm-agent on all hosts."
