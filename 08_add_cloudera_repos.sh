#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "08_add_cloudera_repos"
need_root
validate_platform
require_cloudera_credentials

cat >/etc/yum.repos.d/cloudera-manager.repo <<EOFREPO
[cloudera-manager]
name=Cloudera Manager ${CM_VERSION}
baseurl=${CM_REPO_BASE_URL}
username=${CLOUDERA_REPO_USER}
password=${CLOUDERA_REPO_PASS}
enabled=1
gpgcheck=0
EOFREPO

chmod 600 /etc/yum.repos.d/cloudera-manager.repo

dnf clean all || true
dnf makecache --disablerepo='*' --enablerepo='cloudera-manager' || true
dnf repolist cloudera-manager || true

echo "[OK] Cloudera Manager repo configured: ${CM_REPO_BASE_URL}"
