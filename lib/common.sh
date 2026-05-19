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

java_home_target() {
  if [[ -n "${CUSTOM_JAVA_HOME:-}" ]]; then
    echo "$CUSTOM_JAVA_HOME"
  else
    echo "${JAVA_HOME_TARGET:-/usr/lib/jvm/java-11-openjdk}"
  fi
}

ensure_java_default() {
  local desired_major java_bin java_home javac_bin
  desired_major="${JAVA_MAJOR:-11}"

  if [[ "${JAVA_INSTALL_MODE:-system}" == "custom" ]]; then
    java_home="$(java_home_target)"
    java_bin="${java_home}/bin/java"

    if [[ ! -x "$java_bin" ]]; then
      echo "[ERROR] JAVA_INSTALL_MODE=custom but Java binary is missing or not executable: $java_bin"
      exit 1
    fi

    export JAVA_HOME="$java_home"
    export PATH="$JAVA_HOME/bin:$PATH"
  else
    java_bin=""

    # First preference: use the Java path that is actually registered with alternatives.
    # Do not use /usr/lib/jvm/java-11-openjdk/bin/java unless it is registered,
    # because alternatives --set rejects unregistered symlinks on RHEL.
    if command -v alternatives >/dev/null 2>&1; then
      java_bin="$(
        alternatives --display java 2>/dev/null \
          | awk -v major="$desired_major" '
              $1 ~ "^/usr/lib/jvm/java-" major "-openjdk" && $1 ~ "/bin/java$" { print $1; exit }
            '
      )"
    fi

    # Fallback: find a versioned OpenJDK Java binary.
    # Example:
    # /usr/lib/jvm/java-11-openjdk-11.0.25.0.9-2.el8.x86_64/bin/java
    if [[ -z "${java_bin:-}" || ! -x "$java_bin" ]]; then
      java_bin="$(
        find /usr/lib/jvm -path '*/bin/java' \( -type f -o -type l \) -print 2>/dev/null \
          | grep -E "/java-${desired_major}-openjdk[^/]*/bin/java$" \
          | grep -v "/jre/bin/java$" \
          | sort \
          | head -n 1
      )"
    fi

    # Final fallback: JRE-style path, only if no JDK-style path exists.
    if [[ -z "${java_bin:-}" || ! -x "$java_bin" ]]; then
      java_bin="$(
        find /usr/lib/jvm -path '*/bin/java' \( -type f -o -type l \) -print 2>/dev/null \
          | grep -E "/(java|jre)-${desired_major}-openjdk[^/]*/(jre/)?bin/java$" \
          | sort \
          | head -n 1
      )"
    fi

    if [[ -z "${java_bin:-}" || ! -x "$java_bin" ]]; then
      echo "[ERROR] Could not find Java ${desired_major} under /usr/lib/jvm."
      echo "[INFO] Available Java binaries:"
      find /usr/lib/jvm -path '*/bin/java' \( -type f -o -type l \) -print 2>/dev/null || true
      echo "[INFO] alternatives --display java:"
      alternatives --display java 2>/dev/null || true
      exit 1
    fi

    java_home="$(dirname "$(dirname "$java_bin")")"

    export JAVA_HOME="$java_home"
    export PATH="$JAVA_HOME/bin:$PATH"

    if command -v alternatives >/dev/null 2>&1; then
      echo "[INFO] Setting java alternative to: $java_bin"

      # Try normal --set first. If the path was found on disk but is not registered,
      # install it into alternatives and then set it. This avoids hardcoding the
      # versioned Java path and handles RHEL images where the stable symlink is not registered.
      if ! alternatives --set java "$java_bin"; then
        echo "[WARN] Java path was not registered with alternatives. Registering it now."
        alternatives --install /usr/bin/java java "$java_bin" 200000
        alternatives --set java "$java_bin"
      fi

      javac_bin="${JAVA_HOME}/bin/javac"
      if [[ -x "$javac_bin" ]]; then
        if ! alternatives --set javac "$javac_bin" >/dev/null 2>&1; then
          alternatives --install /usr/bin/javac javac "$javac_bin" 200000 >/dev/null 2>&1 || true
          alternatives --set javac "$javac_bin" >/dev/null 2>&1 || true
        fi
      fi
    fi
  fi

  cat >/etc/profile.d/cloudera-java.sh <<EOFJAVA
export JAVA_HOME='${JAVA_HOME}'
export PATH=\$JAVA_HOME/bin:\$PATH
EOFJAVA

  cat >/etc/default/cloudera-java <<EOFJAVADEFAULT
export JAVA_HOME='${JAVA_HOME}'
EOFJAVADEFAULT

  echo "[OK] JAVA_HOME=${JAVA_HOME}"
  echo "[OK] Active java=$(readlink -f "$(command -v java)")"
}


validate_java_11() {
  local java_bin version_output version_line detected desired_major
  desired_major="${JAVA_MAJOR:-11}"

  if [[ -n "${CUSTOM_JAVA_HOME:-}" ]]; then
    java_bin="${CUSTOM_JAVA_HOME}/bin/java"
  elif [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    java_bin="${JAVA_HOME}/bin/java"
  else
    java_bin="$(command -v java || true)"
  fi

  if [[ -z "$java_bin" || ! -x "$java_bin" ]]; then
    echo "[ERROR] Java executable not found. Install Java ${desired_major} or set CUSTOM_JAVA_HOME."
    exit 1
  fi

  # java -version can print a JDK_JAVA_OPTIONS line before the real version.
  # Parse the real version line instead of blindly taking the first line.
  version_output="$($java_bin -version 2>&1 || true)"
  version_line="$(printf '%s\n' "$version_output" | grep -E '^(openjdk|java) version ' | head -1)"

  echo "Java executable: $java_bin"
  echo "Java version: ${version_line:-unknown}"

  if [[ -z "$version_line" ]]; then
    echo "$version_output"
    echo "[ERROR] Java ${desired_major} required, detected: unknown"
    exit 1
  fi

  # Java 8 reports as version "1.8.0_xxx". Java 11+ reports as "11.0.x".
  if [[ "$version_line" =~ version\ \"1\.([0-9]+)\. ]]; then
    detected="${BASH_REMATCH[1]}"
  elif [[ "$version_line" =~ version\ \"([0-9]+)\. ]]; then
    detected="${BASH_REMATCH[1]}"
  elif [[ "$version_line" =~ openjdk\ ([0-9]+)\. ]]; then
    detected="${BASH_REMATCH[1]}"
  else
    detected="unknown"
  fi

  if [[ "$detected" != "$desired_major" ]]; then
    echo "$version_output"
    echo "[ERROR] Java ${desired_major} required, detected Java major version: $detected"
    echo "[INFO] Active java path: $(readlink -f "$java_bin" 2>/dev/null || echo "$java_bin")"
    echo "[INFO] alternatives --display java:"
    alternatives --display java 2>/dev/null || true
    exit 1
  fi

  echo "[OK] Java ${desired_major} validation passed"
}

# CM 7.13.x agent on RHEL 8 x86_64 needs a supported Python 3 runtime.
# Generic /usr/bin/python3 on RHEL 8 is usually Python 3.6 and is not enough.
# The CM agent launcher selects the highest supported python3.x and failed in testing
# when only Python 3.6 existed, resolving to /usr/local/bin/ and exiting 126.
required_agent_python_bin() {
  echo "${CM_AGENT_PYTHON_BIN:-/usr/bin/python3.8}"
}

install_required_agent_python() {
  local pybin
  pybin="$(required_agent_python_bin)"

  if [[ -x "$pybin" ]]; then
    echo "[OK] Required CM agent Python present: $pybin ($($pybin --version 2>&1))"
    return 0
  fi

  echo "==== Installing required CM agent Python runtime ===="
  echo "Required Python binary: $pybin"

  if [[ "${CM_AGENT_PYTHON_PACKAGES:-python38 python38-devel python38-pip}" == "" ]]; then
    echo "[ERROR] CM_AGENT_PYTHON_PACKAGES is empty and $pybin is missing."
    exit 1
  fi

  # RHEL 8 provides python38 as AppStream packages on the RHUI images used in testing.
  # If the module exists but packages are not visible, enabling the module is harmless.
  dnf module enable -y python38 >/dev/null 2>&1 || true
  dnf install -y ${CM_AGENT_PYTHON_PACKAGES:-python38 python38-devel python38-pip}

  if [[ ! -x "$pybin" ]]; then
    echo "[ERROR] Required CM agent Python binary still missing after install: $pybin"
    echo "Available Python binaries:"
    ls -l /usr/bin/python* /usr/local/bin/python* 2>/dev/null || true
    exit 1
  fi

  echo "[OK] Required CM agent Python installed: $pybin ($($pybin --version 2>&1))"
}

validate_cm_agent_python_wrapper() {
  local wrapper pybin version rc
  wrapper="/opt/cloudera/cm-agent/bin/python"
  pybin="$(required_agent_python_bin)"

  if [[ ! -e "$wrapper" ]]; then
    echo "[INFO] CM agent Python wrapper not present yet: $wrapper"
    return 0
  fi

  if [[ ! -x "$pybin" ]]; then
    echo "[ERROR] Required CM agent Python is missing: $pybin"
    exit 1
  fi

  set +e
  version="$($wrapper --version 2>&1)"
  rc=$?
  set -e
  echo "CM agent Python wrapper: $wrapper"
  echo "CM agent Python wrapper version output: $version"

  if [[ $rc -ne 0 ]]; then
    echo "[ERROR] CM agent Python wrapper failed with exit code $rc."
    echo "This usually means the selected Python executable is wrong or missing."
    echo "Check /opt/cloudera/cm-agent/bin/python3.8 and install python38."
    exit 1
  fi

  if [[ "$version" != *"Python 3.8"* && "${CM_AGENT_PYTHON_STRICT_VERSION:-true}" == "true" ]]; then
    echo "[ERROR] Expected CM agent wrapper to use Python 3.8, got: $version"
    exit 1
  fi

  echo "[OK] CM agent Python wrapper is usable."
}

install_hue_fips_psycopg2() {
  if [[ "${INSTALL_HUE_FIPS_PSYCOPG2:-true}" != "true" ]]; then
    echo "[INFO] INSTALL_HUE_FIPS_PSYCOPG2=false; skipping psycopg2 source install."
    return 0
  fi

  local pybin pg_config version pg_devel_pkg import_out wrapper_out
  pybin="${HUE_PSYCOPG2_PYTHON_BIN:-$(required_agent_python_bin)}"
  version="${HUE_PSYCOPG2_VERSION:-2.9.9}"
  pg_config="$(pg_bin_dir)/pg_config"
  pg_devel_pkg="postgresql${PG_MAJOR:-14}-devel"

  echo "==== Installing FIPS-safe psycopg2 for Hue/PostgreSQL readiness ===="
  echo "Python: ${pybin}"
  echo "psycopg2 target version: ${version}"
  echo "pg_config: ${pg_config}"

  if [[ ! -x "$pybin" ]]; then
    echo "[ERROR] Python binary for psycopg2 is missing: $pybin"
    exit 1
  fi

  # pg_config is provided by the PGDG postgresqlXX-devel package.
  # perl-IPC-Run is in CodeReady Builder on RHEL 8 RHUI and is a dependency of PGDG devel packages.
  dnf install -y perl-IPC-Run gcc python38-devel "${pg_devel_pkg}" openssl-devel libffi-devel

  if [[ ! -x "$pg_config" ]]; then
    echo "[ERROR] pg_config not found or not executable: $pg_config"
    echo "Available pg_config files:"
    find /usr -name pg_config 2>/dev/null || true
    exit 1
  fi

  export PATH="$(pg_bin_dir):$PATH"
  export PG_CONFIG="$pg_config"

  "$pybin" -m pip uninstall -y psycopg2 psycopg2-binary || true

  # Keep pip below 25 to avoid future Python 3.8 compatibility surprises.
  "$pybin" -m pip install --upgrade 'pip<25' setuptools wheel
  "$pybin" -m pip install --no-binary=:all: "psycopg2==${version}"

  import_out="$($pybin - <<'PY'
import psycopg2
print(psycopg2.__version__)
PY
)"
  echo "psycopg2 via ${pybin}: ${import_out}"

  if [[ "$import_out" != ${version}* ]]; then
    echo "[ERROR] Expected psycopg2 ${version}, got: ${import_out}"
    exit 1
  fi

  if [[ -x /opt/cloudera/cm-agent/bin/python ]]; then
    wrapper_out="$(/opt/cloudera/cm-agent/bin/python - <<'PY'
import psycopg2
print(psycopg2.__version__)
PY
)"
    echo "psycopg2 via CM agent Python wrapper: ${wrapper_out}"
    if [[ "$wrapper_out" != ${version}* ]]; then
      echo "[ERROR] CM agent Python wrapper cannot see expected psycopg2 ${version}."
      exit 1
    fi
  else
    echo "[INFO] CM agent Python wrapper not installed yet; skipping wrapper psycopg2 validation."
  fi

  echo "[OK] FIPS-safe psycopg2 ${version} installed from source."
}

validate_hue_fips_psycopg2() {
  if [[ "${INSTALL_HUE_FIPS_PSYCOPG2:-true}" != "true" ]]; then
    echo "[INFO] INSTALL_HUE_FIPS_PSYCOPG2=false; skipping psycopg2 validation."
    return 0
  fi

  local pybin version rc out wrapper_rc wrapper_out
  pybin="${HUE_PSYCOPG2_PYTHON_BIN:-$(required_agent_python_bin)}"
  version="${HUE_PSYCOPG2_VERSION:-2.9.9}"

  if [[ ! -x "$pybin" ]]; then
    echo "[WARN] psycopg2 validation skipped; Python missing: $pybin"
    return 0
  fi

  set +e
  out="$($pybin - <<'PY'
try:
    import psycopg2
    print(psycopg2.__version__)
except Exception as e:
    print("ERROR:", repr(e))
    raise
PY
 2>&1)"
  rc=$?
  set -e
  echo "psycopg2 via ${pybin}: ${out}"
  if [[ $rc -ne 0 || "$out" != ${version}* ]]; then
    echo "[WARN] Expected source-built psycopg2 ${version} via ${pybin}."
  fi

  if [[ -x /opt/cloudera/cm-agent/bin/python ]]; then
    set +e
    wrapper_out="$(/opt/cloudera/cm-agent/bin/python - <<'PY'
try:
    import psycopg2
    print(psycopg2.__version__)
except Exception as e:
    print("ERROR:", repr(e))
    raise
PY
 2>&1)"
    wrapper_rc=$?
    set -e
    echo "psycopg2 via CM agent Python wrapper: ${wrapper_out}"
    if [[ $wrapper_rc -ne 0 || "$wrapper_out" != ${version}* ]]; then
      echo "[WARN] CM agent Python wrapper does not see expected psycopg2 ${version}. Host Inspector may flag Hue/PostgreSQL readiness."
    fi
  fi
}

ensure_line() {
  local file="$1"
  local line="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

timestamped_backup() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "[ERROR] Cannot back up missing file: $file"
    exit 1
  fi
  local backup="${file}.bak.$(date +%Y%m%d_%H%M%S)"
  cp -a "$file" "$backup"
  echo "[OK] Backed up $file to $backup"
}

java_fips_dir() { echo "${JAVA_FIPS_DIR:-/opt/cloudera/fips}"; }
java_fips_ccj_jar() { echo "${JAVA_FIPS_CCJ_JAR:-${FIPS_CCJ_JAR:-ccj-3.0.2.1.jar}}"; }
java_fips_bctls_jar() { echo "${JAVA_FIPS_BCTLS_JAR:-bctls-safelogic.jar}"; }
java_fips_ccj_module() { echo "${JAVA_FIPS_CCJ_MODULE:-com.safelogic.cryptocomply.fips.core}"; }
java_fips_bctls_module() { echo "${JAVA_FIPS_BCTLS_MODULE:-bctls.safelogic}"; }

stage_java_fips_jars() {
  local src_dir active_dir ccj_src bctls_src ccj_dest bctls_dest
  src_dir="${FIPS_JAR_SOURCE_DIR:-}"
  active_dir="$(java_fips_dir)"
  ccj_src="${src_dir}/$(java_fips_ccj_jar)"
  bctls_src="${src_dir}/${FIPS_BCTLS_JAR:-bctls.jar}"
  ccj_dest="${active_dir}/$(java_fips_ccj_jar)"
  bctls_dest="${active_dir}/$(java_fips_bctls_jar)"

  if [[ -z "$src_dir" ]]; then
    echo "[ERROR] FIPS_JAR_SOURCE_DIR is not set. Stage the SafeLogic jars and update EXPORTS."
    exit 1
  fi
  if [[ ! -f "$ccj_src" ]]; then
    echo "[ERROR] Missing SafeLogic CCJ jar: $ccj_src"
    exit 1
  fi
  if [[ ! -f "$bctls_src" ]]; then
    echo "[ERROR] Missing SafeLogic BCTLS jar: $bctls_src"
    exit 1
  fi

  mkdir -p "$active_dir"
  cp -af "$ccj_src" "$ccj_dest"
  cp -af "$bctls_src" "$bctls_dest"
  chown root:root "$ccj_dest" "$bctls_dest"
  chmod 0644 "$ccj_dest" "$bctls_dest"

  echo "[OK] Active Java FIPS jars staged:"
  ls -lh "$active_dir"
}

write_jdk_java_options_profile() {
  local active_dir ccj_jar bctls_jar ccj_mod bctls_mod opts
  active_dir="$(java_fips_dir)"
  ccj_jar="${active_dir}/$(java_fips_ccj_jar)"
  bctls_jar="${active_dir}/$(java_fips_bctls_jar)"
  ccj_mod="$(java_fips_ccj_module)"
  bctls_mod="$(java_fips_bctls_module)"
  opts="--module-path=${ccj_jar}:${bctls_jar} --add-exports java.base/sun.security.provider=${ccj_mod} --add-modules ${ccj_mod},${bctls_mod}"

  cat >/etc/profile.d/ccj.sh <<EOFCCJ
export JDK_JAVA_OPTIONS='${opts}'
EOFCCJ
  chmod 0755 /etc/profile.d/ccj.sh
  export JDK_JAVA_OPTIONS="$opts"
  echo "[OK] Wrote /etc/profile.d/ccj.sh"
}

patch_java_policy_for_fips() {
  local java_home policy_file active_dir ccj_jar bctls_jar tmp
  java_home="${JAVA_HOME:-$(java_home_target)}"
  policy_file="${java_home}/conf/security/java.policy"
  active_dir="$(java_fips_dir)"
  ccj_jar="${active_dir}/$(java_fips_ccj_jar)"
  bctls_jar="${active_dir}/$(java_fips_bctls_jar)"

  if [[ ! -f "$policy_file" ]]; then
    echo "[ERROR] Missing Java policy file: $policy_file"
    exit 1
  fi

  timestamped_backup "$policy_file"
  tmp="$(mktemp)"
  awk '
    /BEGIN MANAGED BY cfm_fips_install - SafeLogic permissions/ {skip=1; next}
    /END MANAGED BY cfm_fips_install - SafeLogic permissions/ {skip=0; next}
    skip != 1 {print}
  ' "$policy_file" > "$tmp"

  cat >> "$tmp" <<EOFPOLICY

// BEGIN MANAGED BY cfm_fips_install - SafeLogic permissions
grant codeBase "file:${ccj_jar}" {
    permission java.security.AllPermission;
};

grant codeBase "file:${bctls_jar}" {
    permission java.security.AllPermission;
};
// END MANAGED BY cfm_fips_install - SafeLogic permissions
EOFPOLICY

  cat "$tmp" > "$policy_file"
  rm -f "$tmp"
  echo "[OK] Patched ${policy_file}"
}

patch_java_security_for_fips() {
  local java_home security_file
  java_home="${JAVA_HOME:-$(java_home_target)}"
  security_file="${java_home}/conf/security/java.security"

  if [[ ! -f "$security_file" ]]; then
    echo "[ERROR] Missing Java security file: $security_file"
    exit 1
  fi

  timestamped_backup "$security_file"

  JAVA_SECURITY_FILE="$security_file" python3 - <<'PY'
from pathlib import Path
import os

p = Path(os.environ["JAVA_SECURITY_FILE"])
text = p.read_text()
lines = text.splitlines()

begin = "# BEGIN MANAGED BY cfm_fips_install - SafeLogic providers"
end = "# END MANAGED BY cfm_fips_install - SafeLogic providers"

# Remove previous managed block, if present.
filtered = []
skip = False
for line in lines:
    if line.strip() == begin:
        skip = True
        continue
    if line.strip() == end:
        skip = False
        continue
    if not skip:
        filtered.append(line)

new_lines = []
for line in filtered:
    stripped = line.strip()
    if stripped.startswith("security.useSystemPropertiesFile="):
        if not line.lstrip().startswith("#"):
            new_lines.append("# " + line)
        else:
            new_lines.append(line)
        continue
    if stripped.startswith("security.provider."):
        if not line.lstrip().startswith("#"):
            new_lines.append("# " + line)
        else:
            new_lines.append(line)
        continue
    if stripped.startswith("fips.provider."):
        if not line.lstrip().startswith("#"):
            new_lines.append("# " + line)
        else:
            new_lines.append(line)
        continue
    if stripped.startswith("ssl.KeyManagerFactory.algorithm="):
        if not line.lstrip().startswith("#"):
            new_lines.append("# " + line)
        else:
            new_lines.append(line)
        continue
    if stripped.startswith("ssl.TrustManagerFactory.algorithm="):
        if not line.lstrip().startswith("#"):
            new_lines.append("# " + line)
        else:
            new_lines.append(line)
        continue
    new_lines.append(line)

block = f"""

{begin}
security.useSystemPropertiesFile=false

security.provider.1=com.safelogic.cryptocomply.jcajce.provider.CryptoComplyFipsProvider
security.provider.2=org.bouncycastle.jsse.provider.BouncyCastleJsseProvider fips:CCJ
security.provider.3=SUN
security.provider.4=SunRsaSign
security.provider.5=SunEC
security.provider.6=SunJSSE
security.provider.7=SunJCE
security.provider.8=SunJGSS
security.provider.9=SunSASL
security.provider.10=XMLDSig
security.provider.11=SunPCSC
security.provider.12=JdkLDAP
security.provider.13=JdkSASL

fips.provider.1=com.safelogic.cryptocomply.jcajce.provider.CryptoComplyFipsProvider
fips.provider.2=org.bouncycastle.jsse.provider.BouncyCastleJsseProvider fips:CCJ
fips.provider.3=SUN
fips.provider.4=SunRsaSign
fips.provider.5=SunEC
fips.provider.6=SunJSSE
fips.provider.7=SunJCE
fips.provider.8=SunJGSS
fips.provider.9=SunSASL
fips.provider.10=XMLDSig
fips.provider.11=SunPCSC
fips.provider.12=JdkLDAP
fips.provider.13=JdkSASL

ssl.KeyManagerFactory.algorithm=X.509
ssl.TrustManagerFactory.algorithm=PKIX
{end}
"""

p.write_text("\n".join(new_lines).rstrip() + block + "\n")
PY

  echo "[OK] Patched ${security_file}"
}

validate_java_fips_providers() {
  local tmpdir out
  ensure_java_default
  validate_java_11
  if [[ -f /etc/profile.d/ccj.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/ccj.sh
  fi

  tmpdir="$(mktemp -d)"
  cat >"$tmpdir/ListSecurityProviders.java" <<'EOFJAVA'
import java.security.Provider;
import java.security.Security;
public class ListSecurityProviders {
  public static void main(String[] args) {
    for (Provider provider : Security.getProviders()) {
      System.out.println("Provider: " + provider.getName());
      System.out.println("Info: " + provider.getInfo());
    }
  }
}
EOFJAVA
  out="$(java "$tmpdir/ListSecurityProviders.java" 2>&1 || true)"
  rm -rf "$tmpdir"
  echo "$out" | egrep 'Provider:|CCJ|BCJSSE|Bouncy|CryptoComply' || true

  if ! echo "$out" | grep -q 'Provider: CCJ'; then
    echo "[ERROR] Java FIPS provider validation failed: Provider CCJ not loaded."
    exit 1
  fi
  if ! echo "$out" | grep -q 'Provider: BCJSSE'; then
    echo "[ERROR] Java FIPS provider validation failed: Provider BCJSSE not loaded."
    exit 1
  fi
  echo "[OK] Java FIPS providers loaded: CCJ and BCJSSE"
}

configure_java_fips_safelogic() {
  if [[ "${CONFIGURE_JAVA_FIPS:-true}" != "true" ]]; then
    echo "[INFO] CONFIGURE_JAVA_FIPS=false; skipping Java SafeLogic FIPS configuration."
    return 0
  fi

  echo "==== Configuring Java SafeLogic FIPS providers ===="
  ensure_java_default
  validate_java_11
  stage_java_fips_jars
  write_jdk_java_options_profile
  patch_java_policy_for_fips
  patch_java_security_for_fips
  validate_java_fips_providers
}

configure_cm_server_fips_opts() {
  if [[ "${CONFIGURE_JAVA_FIPS:-true}" != "true" ]]; then
    echo "[INFO] CONFIGURE_JAVA_FIPS=false; skipping CM Server FIPS options."
    return 0
  fi

  local defaults active_dir ccj_jar bctls_jar ccj_mod bctls_mod tmp
  defaults="/etc/default/cloudera-scm-server"
  active_dir="$(java_fips_dir)"
  ccj_jar="${active_dir}/$(java_fips_ccj_jar)"
  bctls_jar="${active_dir}/$(java_fips_bctls_jar)"
  ccj_mod="$(java_fips_ccj_module)"
  bctls_mod="$(java_fips_bctls_module)"

  touch "$defaults"
  timestamped_backup "$defaults"

  tmp="$(mktemp)"
  awk '
    /BEGIN MANAGED BY cfm_fips_install - CM Server FIPS options/ {skip=1; next}
    /END MANAGED BY cfm_fips_install - CM Server FIPS options/ {skip=0; next}
    skip != 1 {print}
  ' "$defaults" > "$tmp"

  cat >> "$tmp" <<EOFCMF

# BEGIN MANAGED BY cfm_fips_install - CM Server FIPS options
export JDK_JAVA_OPTIONS="\${JDK_JAVA_OPTIONS:-} --module-path=${ccj_jar}:${bctls_jar} --add-exports java.base/sun.security.provider=${ccj_mod} --add-modules ${ccj_mod},${bctls_mod}"
export CMF_JAVA_OPTS="\${CMF_JAVA_OPTS} -Dcom.cloudera.cmf.fipsMode=true -Dcom.safelogic.cryptocomply.fips.approved_only=true"
export CMF_JAVA_OPTS="\${CMF_JAVA_OPTS} -Dcom.cloudera.cloudera.cmf.fipsMode.jdk11plus.ccj.jar.path=${ccj_jar} -Dcom.cloudera.cloudera.cmf.fipsMode.jdk11plus.ccj.moduleName=${ccj_mod}"
export CMF_JAVA_OPTS="\${CMF_JAVA_OPTS} -Dcom.cloudera.cloudera.cmf.fipsMode.jdk11plus.bctls.jar.path=${bctls_jar} -Dcom.cloudera.cloudera.cmf.fipsMode.jdk11plus.bctls.moduleName=${bctls_mod}"
# END MANAGED BY cfm_fips_install - CM Server FIPS options
EOFCMF

  cat "$tmp" > "$defaults"
  rm -f "$tmp"
  echo "[OK] Wrote CM Server FIPS options to ${defaults}"
}