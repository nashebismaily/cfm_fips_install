#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

prepare_dirs
ok "Prepared TLS artifact directories under ${TLS_WORKDIR}"
find "$TLS_WORKDIR" -maxdepth 2 -type d | sort
