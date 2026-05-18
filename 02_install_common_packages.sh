#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "02_install_common_packages"
need_root
validate_platform

COMMON_PACKAGES=(
  wget curl vim tar unzip bind-utils net-tools lsof which rsync jq
  chrony rng-tools nmap-ncat tcpdump telnet perl iproute rpcbind
  python3 python3-pip python3-devel gcc gcc-c++ make openssl-devel libffi-devel
  redhat-lsb-core policycoreutils-python-utils
)

FAILED=()
for pkg in "${COMMON_PACKAGES[@]}"; do
  echo "---- Installing $pkg"
  if ! dnf install -y "$pkg"; then
    echo "[WARN] Failed to install $pkg"
    FAILED+=("$pkg")
  fi
done

systemctl enable chronyd || true
systemctl restart chronyd || true
systemctl enable rngd || true
systemctl restart rngd || true

echo
echo "Python: $(python3 --version 2>/dev/null || echo missing)"
which nc || true
which jq || true

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "[WARN] Failed packages: ${FAILED[*]}"
else
  echo "[OK] Common packages installed"
fi
