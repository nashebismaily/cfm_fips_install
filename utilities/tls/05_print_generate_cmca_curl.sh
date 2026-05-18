#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
PAYLOAD="${AUTO_TLS_PAYLOAD_DIR}/generateCmca.json"
URL="${CM_API_SCHEME}://${CM_HOST_FQDN}:${CM_API_PORT}/api/${CM_API_VERSION}/cm/commands/generateCmca"
cat <<EOF2
curl -i -v -u '${CM_API_USER}:<CM_API_PASSWORD>' \\
  -X POST \\
  --header 'Content-Type: application/json' \\
  --header 'Accept: application/json' \\
  -d '@${PAYLOAD}' \\
  '${URL}'
EOF2
