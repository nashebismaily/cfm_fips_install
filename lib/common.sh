#!/usr/bin/env bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORTS_FILE="${EXPORTS_FILE:-${SCRIPT_DIR}/EXPORTS}"

if [[ -f "$EXPORTS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$EXPORTS_FILE"
fi

log_init() {
  local name="$1"
  LOG_DIR="${LOG_DIR:-/var/log/cloudera-bootstrap}"
  mkdir -p "$LOG_DIR"
  LOG_FILE="$LOG_DIR/${name}_$(date +%Y%m%d_%H%M%S).log"
  exec > >(tee -a "$LOG_FILE") 2>&1
  echo "==== ${name} ===="
  echo "Timestamp: $(date -Is)"
  echo "Host: $(hostname -f 2>/dev/null || hostname)"
  echo "OS: $(cat /etc/redhat-release 2>/dev/null || echo unknown)"
  echo "Log: $LOG_FILE"
  echo
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Run as root or with sudo -E."
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] Required command missing: $cmd"
    exit 1
  fi
}

warn_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "[OK] command present: $cmd"
  else
    echo "[WARN] command missing: $cmd"
  fi
}

rhel_major() { rpm -E '%{rhel}' 2>/dev/null || echo unknown; }

rhel_minor() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "${VERSION_ID#*.}"
  else
    echo unknown
  fi
}

validate_platform() {
  local arch expected_major expected_minor fips require_fips
  arch="$(uname -m 2>/dev/null || echo unknown)"
  expected_major="${EXPECTED_RHEL_MAJOR:-8}"
  expected_minor="${EXPECTED_RHEL_MINOR:-10}"
  require_fips="${REQUIRE_FIPS:-true}"

  echo "==== Platform validation ===="
  echo "Architecture: $arch"
  echo "RHEL major: $(rhel_major)"
  echo "RHEL minor: $(rhel_minor)"

  if [[ "${REQUIRE_X86_64:-true}" == "true" && "$arch" != "x86_64" ]]; then
    echo "[ERROR] Expected x86_64 but detected $arch"
    exit 1
  fi

  if [[ "$(rhel_major)" != "$expected_major" ]]; then
    echo "[ERROR] Expected RHEL major $expected_major but detected $(rhel_major)"
    exit 1
  fi

  if [[ "$expected_minor" != "" && "$(rhel_minor)" != "$expected_minor" ]]; then
    echo "[ERROR] Expected RHEL ${expected_major}.${expected_minor} but detected $(rhel_major).$(rhel_minor)"
    exit 1
  fi

  fips="$(cat /proc/sys/crypto/fips_enabled 2>/dev/null || echo 0)"
  echo "FIPS kernel flag: $fips"
  if [[ "$require_fips" == "true" && "$fips" != "1" ]]; then
    echo "[ERROR] FIPS is not enabled. Use a FIPS-enabled RHEL 8.10 image or enable FIPS before installing Cloudera software."
    exit 1
  fi

  if command -v fips-mode-setup >/dev/null 2>&1; then
    fips-mode-setup --check || true
  fi
  echo "[OK] Platform validation passed"
  echo
}

require_cloudera_credentials() {
  if [[ -z "${CLOUDERA_REPO_USER:-}" || -z "${CLOUDERA_REPO_PASS:-}" ]]; then
    echo "[ERROR] CLOUDERA_REPO_USER and CLOUDERA_REPO_PASS must be set in EXPORTS or exported in the shell."
    exit 1
  fi
}

curl_head_auth() {
  local url="$1"
  curl -k -I -L --connect-timeout 10 --max-time 30 -u "${CLOUDERA_REPO_USER}:${CLOUDERA_REPO_PASS}" "$url" >/dev/null 2>&1
}

curl_download_auth() {
  local url="$1"
  local out="$2"
  curl -f -L --connect-timeout 20 --max-time 600 -u "${CLOUDERA_REPO_USER}:${CLOUDERA_REPO_PASS}" -o "$out" "$url"
}

pg_service_name() { echo "postgresql-${PG_MAJOR:-14}"; }
pg_bin_dir() { echo "/usr/pgsql-${PG_MAJOR:-14}/bin"; }
pg_default_data_dir() { echo "/var/lib/pgsql/${PG_MAJOR:-14}/data"; }

validate_java_11() {
  local java_bin version_line detected
  if [[ -n "${CUSTOM_JAVA_HOME:-}" ]]; then
    java_bin="${CUSTOM_JAVA_HOME}/bin/java"
  elif [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    java_bin="${JAVA_HOME}/bin/java"
  else
    java_bin="$(command -v java || true)"
  fi

  if [[ -z "$java_bin" || ! -x "$java_bin" ]]; then
    echo "[ERROR] Java executable not found. Install Java 11 or set CUSTOM_JAVA_HOME."
    exit 1
  fi

  version_line="$($java_bin -version 2>&1 | head -1)"
  echo "Java executable: $java_bin"
  echo "Java version: $version_line"
  if [[ "$version_line" =~ version\ \"([0-9]+)\. ]] || [[ "$version_line" =~ openjdk\ ([0-9]+)\. ]]; then
    detected="${BASH_REMATCH[1]}"
  else
    detected="unknown"
  fi

  if [[ "$detected" != "${JAVA_MAJOR:-11}" ]]; then
    echo "[ERROR] Java ${JAVA_MAJOR:-11} required, detected: $detected"
    exit 1
  fi

  echo "[OK] Java ${JAVA_MAJOR:-11} validation passed"
}

ensure_line() {
  local file="$1"
  local line="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}
