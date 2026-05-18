#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "03_configure_os"
need_root
validate_platform

echo "==== SELinux/firewall choices ===="
if [[ "${DISABLE_SELINUX:-false}" == "true" ]]; then
  sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config || true
  setenforce 0 || true
  echo "[INFO] SELinux disabled by request"
else
  echo "[INFO] SELinux left unchanged. Current: $(getenforce 2>/dev/null || echo unknown)"
fi

if [[ "${DISABLE_FIREWALLD:-false}" == "true" ]]; then
  systemctl stop firewalld || true
  systemctl disable firewalld || true
  echo "[INFO] firewalld disabled by request"
else
  echo "[INFO] firewalld left unchanged. Make sure AWS SG/firewalld allow CM and CDP ports."
fi

cat >/etc/systemd/system/disable-thp.service <<'THP'
[Unit]
Description=Disable Transparent Huge Pages
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then echo never > /sys/kernel/mm/transparent_hugepage/enabled; fi; if [ -f /sys/kernel/mm/transparent_hugepage/defrag ]; then echo never > /sys/kernel/mm/transparent_hugepage/defrag; fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
THP

systemctl daemon-reload
systemctl enable disable-thp.service
systemctl restart disable-thp.service || true

cat >/etc/sysctl.d/90-cloudera.conf <<'SYSCTL'
vm.swappiness=1
fs.file-max=1000000
vm.max_map_count=262144
net.core.somaxconn=65535
SYSCTL
sysctl --system || true

mkdir -p /etc/systemd/system.conf.d
cat >/etc/systemd/system.conf.d/99-cloudera-limits.conf <<'LIMITS_SYSTEMD'
[Manager]
DefaultLimitNOFILE=65536
DefaultLimitNPROC=65536
LIMITS_SYSTEMD

cat >/etc/security/limits.d/99-cloudera.conf <<'LIMITS'
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
cloudera-scm soft nofile 65536
cloudera-scm hard nofile 65536
cloudera-scm soft nproc 65536
cloudera-scm hard nproc 65536
LIMITS

systemctl daemon-reexec || true

echo "THP: $(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo unknown)"
sysctl vm.swappiness || true
ulimit -n || true

echo "[OK] OS configuration complete"
