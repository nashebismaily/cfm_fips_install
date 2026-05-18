#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "01_bootstrap_repos"
need_root
validate_platform

if [[ "${ALLOW_EXTERNAL:-true}" != "true" ]]; then
  echo "[INFO] ALLOW_EXTERNAL=false. Current repos only:"
  dnf repolist || true
  exit 0
fi

dnf clean all || true

if [[ "${ENABLE_EPEL:-false}" == "true" ]]; then
  echo "==== Installing EPEL for EL8 ===="
  dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm"
else
  echo "[INFO] EPEL disabled by ENABLE_EPEL=false"
fi

if [[ "${ENABLE_PGDG:-true}" == "true" ]]; then
  echo "==== Installing PGDG repo for EL8 ===="
  dnf install -y "https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
  dnf -qy module disable postgresql || true
else
  echo "[INFO] PGDG disabled by ENABLE_PGDG=false"
fi

dnf makecache || true
dnf repolist || true

echo "[OK] Repo bootstrap complete"
