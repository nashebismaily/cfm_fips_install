#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ ! -f ./tls.env ]]; then
  echo "[ERROR] tls.env not found in ${SCRIPT_DIR}"
  exit 1
fi

source ./tls.env

: "${AUTO_TLS_WORKDIR:?AUTO_TLS_WORKDIR is required}"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

prepare_dirs
ok "Prepared TLS artifact directories under ${TLS_WORKDIR}"
find "$TLS_WORKDIR" -maxdepth 2 -type d | sort
