#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "00_check_connectivity"

validate_platform

check_http() {
  local url="$1" name="$2"
  if curl -k -I -L --connect-timeout 8 --max-time 25 "$url" >/dev/null 2>&1; then
    echo "[OK] $name reachable: $url"
  else
    echo "[WARN] $name not reachable: $url"
  fi
}

check_tcp() {
  local host="$1" port="$2" name="$3"
  if command -v nc >/dev/null 2>&1; then
    if nc -zw5 "$host" "$port" >/dev/null 2>&1; then
      echo "[OK] $name reachable at $host:$port"
    else
      echo "[WARN] $name not reachable at $host:$port"
    fi
  else
    echo "[WARN] nc missing; skipping $name TCP check"
  fi
}

echo "==== Basic commands ===="
for c in curl dnf rpm python3 java getenforce timedatectl chronyc host nslookup nc jq; do
  warn_cmd "$c"
done

echo
echo "==== Identity / network ===="
hostname -f || true
hostname -I || true
ip route || true

echo
echo "==== FIPS detail ===="
cat /proc/sys/crypto/fips_enabled || true
fips-mode-setup --check || true

echo
echo "==== SELinux / firewalld / time ===="
getenforce || true
systemctl is-active firewalld 2>/dev/null || true
systemctl is-enabled firewalld 2>/dev/null || true
timedatectl || true
chronyc tracking || true

echo
echo "==== DNF repos ===="
dnf repolist || true

echo
echo "==== Internet/repo reachability ===="
check_http "https://cdn.redhat.com" "Red Hat CDN"
check_http "https://download.postgresql.org/pub/repos/yum/" "PostgreSQL PGDG"
check_http "https://archive.cloudera.com/" "Cloudera archive"
if [[ "${ENABLE_EPEL:-false}" == "true" ]]; then
  check_http "https://dl.fedoraproject.org/pub/epel/" "EPEL"
fi

echo
echo "==== Cloudera protected repo checks ===="
if [[ -n "${CLOUDERA_REPO_USER:-}" && -n "${CLOUDERA_REPO_PASS:-}" ]]; then
  echo "CM repo: ${CM_REPO_BASE_URL}"
  if curl_head_auth "${CM_REPO_BASE_URL}"; then
    echo "[OK] CM repo reachable with supplied credentials"
  else
    echo "[WARN] CM repo not reachable with supplied credentials"
  fi
  echo "CFM parcel repo: ${CFM_PARCEL_REPO_URL}"
  if curl_head_auth "${CFM_PARCEL_REPO_URL}"; then
    echo "[OK] CFM parcel repo reachable with supplied credentials"
  else
    echo "[WARN] CFM parcel repo not reachable with supplied credentials"
  fi
else
  echo "[INFO] CLOUDERA_REPO_USER/PASS not set; skipping protected repo auth checks"
fi

echo
echo "==== East/west checks ===="
if [[ -n "${MANAGER_HOST:-}" ]]; then
  check_tcp "$MANAGER_HOST" 7180 "CM UI"
  check_tcp "$MANAGER_HOST" 7182 "CM agent heartbeat"
  check_tcp "$MANAGER_HOST" 5432 "PostgreSQL"
fi
if [[ -n "${AGENT_HOST:-}" ]]; then
  check_tcp "$AGENT_HOST" 7182 "agent node"
  check_tcp "$AGENT_HOST" 2181 "ZooKeeper client port if assigned there"
fi

echo
echo "[OK] Connectivity check complete"
