#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
log_init "13_install_cfm_csds"
need_root
validate_platform
require_cloudera_credentials

CSD_DIR="/opt/cloudera/csd"
TMP_DIR="/tmp/cfm-csds-${CFM_VERSION}"
mkdir -p "$CSD_DIR" "$TMP_DIR"

NIFI_URL="${CFM_PARCEL_REPO_URL%/}/${CFM_NIFI_CSD_JAR}"
REG_URL="${CFM_PARCEL_REPO_URL%/}/${CFM_NIFIREGISTRY_CSD_JAR}"

echo "==== CFM CSD configuration ===="
echo "CFM_VERSION=${CFM_VERSION}"
echo "CFM parcel repo=${CFM_PARCEL_REPO_URL}"
echo "NiFi CSD=${NIFI_URL}"
echo "NiFi Registry CSD=${REG_URL}"

cd "$TMP_DIR"
rm -f ./*.jar
curl_download_auth "$NIFI_URL" "$CFM_NIFI_CSD_JAR"
curl_download_auth "$REG_URL" "$CFM_NIFIREGISTRY_CSD_JAR"

for f in "$CFM_NIFI_CSD_JAR" "$CFM_NIFIREGISTRY_CSD_JAR"; do
  size="$(stat -c%s "$f")"
  if [[ "$size" -lt 50000 ]]; then
    echo "[ERROR] Downloaded file is too small: $f ($size bytes)"
    head -20 "$f" || true
    exit 1
  fi
  echo "[OK] $f ($size bytes)"
done

# Remove older NiFi/Registry CSDs only, not every CSD on the system.
rm -f "$CSD_DIR"/NIFI-*.jar "$CSD_DIR"/NIFIREGISTRY-*.jar
cp -f "$TMP_DIR"/*.jar "$CSD_DIR"/
chown cloudera-scm:cloudera-scm "$CSD_DIR"/*.jar
chmod 644 "$CSD_DIR"/*.jar
ls -lh "$CSD_DIR" | grep -E 'NIFI|NIFIREGISTRY' || true

if systemctl is-active --quiet cloudera-scm-server; then
  echo "==== Restarting Cloudera Manager Server to load CSDs ===="
  systemctl restart cloudera-scm-server
  echo "Waiting for CM to return on 7180"
  for i in {1..90}; do
    if ss -plnt | grep -q ':7180'; then
      echo "[OK] CM listening on 7180"
      break
    fi
    sleep 5
  done
else
  echo "[INFO] CM server is not running; CSDs will load when CM starts."
fi

cat <<EOFMSG

[OK] CFM CSDs installed.
Next in Cloudera Manager UI:
  1. Add this CFM parcel repository URL:
     ${CFM_PARCEL_REPO_URL}
  2. Download, distribute, and activate the CFM parcel.
  3. Deploy CDP Base services first, including ZooKeeper from CDP Runtime ${CDP_RUNTIME_VERSION}.
  4. Deploy NiFi and NiFi Registry after the CFM parcel is active.

EOFMSG
