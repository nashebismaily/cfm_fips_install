#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "12_start_cm_services"
need_root
validate_platform
ensure_java_default
validate_java_11
configure_java_fips_safelogic
configure_cm_server_fips_opts
install_required_agent_python
validate_cm_agent_python_wrapper

CM_DEFAULTS_FILE="/etc/default/cloudera-scm-server"
touch "$CM_DEFAULTS_FILE"

# Make Java explicit for the CM Server process.
if ! grep -Eq '^[[:space:]]*export[[:space:]]+JAVA_HOME=' "$CM_DEFAULTS_FILE"; then
  echo "export JAVA_HOME='${JAVA_HOME:-$(java_home_target)}'" >> "$CM_DEFAULTS_FILE"
else
  sed -i "s|^[[:space:]]*export[[:space:]]\+JAVA_HOME=.*|export JAVA_HOME='${JAVA_HOME:-$(java_home_target)}'|" "$CM_DEFAULTS_FILE"
fi

# This avoids 403 host-header issues in lab/private-DNS environments. Remove if your security policy disallows it.
if ! grep -Eq '^[[:space:]]*export[[:space:]]+CMF_FF_PREVENT_HOST_HEADER_INJECTION=' "$CM_DEFAULTS_FILE"; then
  echo 'export CMF_FF_PREVENT_HOST_HEADER_INJECTION="false"' >> "$CM_DEFAULTS_FILE"
fi

echo "==== Starting Cloudera Manager Server ===="
systemctl daemon-reload
systemctl enable cloudera-scm-server
systemctl restart cloudera-scm-server

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

echo "==== Starting local Cloudera Manager agent services on CM Server host ===="
# The CM Server host must also be managed by CM, so the local agent and supervisord must run here too.
systemctl enable cloudera-scm-supervisord
systemctl enable cloudera-scm-agent
systemctl reset-failed cloudera-scm-supervisord cloudera-scm-agent || true
systemctl restart cloudera-scm-supervisord
systemctl restart cloudera-scm-agent
sleep 5

systemctl status cloudera-scm-server --no-pager
systemctl status cloudera-scm-supervisord --no-pager
systemctl status cloudera-scm-agent --no-pager

if ! systemctl is-active --quiet cloudera-scm-server; then
  echo "[ERROR] cloudera-scm-server is not active."
  journalctl -u cloudera-scm-server -n 120 --no-pager || true
  exit 1
fi

if ! systemctl is-active --quiet cloudera-scm-supervisord; then
  echo "[ERROR] local cloudera-scm-supervisord is not active on the CM Server host."
  journalctl -u cloudera-scm-supervisord -n 80 --no-pager || true
  exit 1
fi

if ! systemctl is-active --quiet cloudera-scm-agent; then
  echo "[ERROR] local cloudera-scm-agent is not active on the CM Server host."
  journalctl -u cloudera-scm-agent -n 80 --no-pager || true
  exit 1
fi

curl -I http://localhost:7180 || true
PRIVATE_IP="$(hostname -I | awk '{print $1}')"
echo "[OK] CM is up: http://${PRIVATE_IP}:7180"
echo "[OK] Local CM agent and supervisord are running on the CM Server host."
echo "Default login: admin / admin"
