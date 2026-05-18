# CFM FIPS Install Kit

This repository prepares a small Cloudera Manager + CFM environment on RHEL 8.10 with FIPS enabled.

The current tested profile is:

- RHEL 8.10
- OS FIPS enabled before Cloudera installation
- Cloudera Manager 7.13.1.0
- CDP Runtime 7.3.1
- CFM 2.1.7.3000
- PostgreSQL 14
- Java 11
- SafeLogic / Bouncy Castle FIPS modules from the CDP 7.1.9 SafeLogic bundle

Note: for this environment, CDP 7.3.1 uses the same SafeLogic/FIPS jars as CDP 7.1.9. The jar path remains configurable in `EXPORTS`.

---

## 1. Host layout

This kit assumes two hosts:

| Role | Description |
|---|---|
| Manager | Runs Cloudera Manager Server, local PostgreSQL, and the local Cloudera Manager Agent |
| Agent | Runs Cloudera Manager Agent and is managed by the Manager |

Example values:

```bash
export MANAGER_HOST='ip-10-0-3-31.us-east-2.compute.internal'
export AGENT_HOST='ip-10-0-11-156.us-east-2.compute.internal'
export ALLOWED_CIDR='10.0.0.0/20'
```

Use private DNS names or private IPs that are reachable inside the VPC.

---

## 2. Enable FIPS before running any Cloudera scripts

Run this on every host before installing Cloudera software.

```bash
sudo -i

dnf install -y crypto-policies-scripts dracut-fips
fips-mode-setup --enable
reboot
```

After reboot, verify:

```bash
sudo -i

cat /etc/redhat-release
cat /proc/sys/crypto/fips_enabled
fips-mode-setup --check
update-crypto-policies --show
```

Expected:

```text
Red Hat Enterprise Linux release 8.10
1
FIPS mode is enabled.
FIPS
```

Do not install Cloudera Manager, CDP Runtime, or CFM before FIPS is enabled.

---

## 3. Stage the install kit

Copy the install kit to the manager and unzip it.

```bash
sudo -i
cd /root

unzip cfm_fips_install.zip
cd cfm_fips_install

chmod +x *.sh RUN_MANAGER RUN_AGENT
```

Copy the same folder to each agent host later before running `RUN_AGENT`.

---

## 4. Stage the SafeLogic/FIPS jars on the manager

The SafeLogic tarball should be placed in `/tmp`.

Example file:

```text
/tmp/Cloudera-CDP-PVC-Base-7.1.9-Safelogic-FIPS-Modules-20230815.tar.gz
```

Create the working directory and final jar directory:

```bash
sudo -i

mkdir -p /root/safelogic
mkdir -p /opt/cloudera/fips-jars/cdp-7.1.9
```

Untar the SafeLogic bundle:

```bash
tar -xzvf /tmp/Cloudera-CDP-PVC-Base-7.1.9-Safelogic-FIPS-Modules-20230815.tar.gz -C /root/safelogic
```

Find the jars:

```bash
find /root/safelogic -maxdepth 5 -type f -name "*.jar" -print
```

You should see these two jars:

```text
bctls.jar
ccj-3.0.2.1.jar
```

Copy the jars into the configured jar directory:

```bash
cp -av "/root/safelogic/CCJ 3.0.2.1/ccj-3.0.2.1.jar" /opt/cloudera/fips-jars/cdp-7.1.9/
cp -av "/root/safelogic/BCTLS-CCJ 3.0.2.1/bctls.jar" /opt/cloudera/fips-jars/cdp-7.1.9/
```

Normalize ownership and permissions:

```bash
chown root:root /opt/cloudera/fips-jars/cdp-7.1.9/*.jar
chmod 644 /opt/cloudera/fips-jars/cdp-7.1.9/*.jar
```

Validate:

```bash
ls -lh /opt/cloudera/fips-jars/cdp-7.1.9
sha256sum /opt/cloudera/fips-jars/cdp-7.1.9/*.jar
```

Expected ownership should look like:

```text
-rw-r--r--. 1 root root ... bctls.jar
-rw-r--r--. 1 root root ... ccj-3.0.2.1.jar
```

The SHA values from one validated run were:

```text
5a73ed8d9029bdb5edfea0c90ef47fad09aaeed5baba3186fa9e87de518d44c8  /opt/cloudera/fips-jars/cdp-7.1.9/bctls.jar
920358d92e36884908a23aa211cbdb7d877ed2703683e39470cd721a1033cf25  /opt/cloudera/fips-jars/cdp-7.1.9/ccj-3.0.2.1.jar
```

Those checksums are useful for comparison, but use the checksums provided by your approved SafeLogic package as the authority if they differ.

---

## 5. Configure `EXPORTS`

Edit the file:

```bash
cd /root/cfm_fips_install
vi EXPORTS
```

Set the environment-specific values:

```bash
export CLOUDERA_REPO_USER='your_cloudera_archive_username'
export CLOUDERA_REPO_PASS='your_cloudera_archive_password'

export MANAGER_HOST='ip-10-0-3-31.us-east-2.compute.internal'
export AGENT_HOST='ip-10-0-11-156.us-east-2.compute.internal'
export ALLOWED_CIDR='10.0.0.0/20'
```

For the CDP 7.3.1 profile, keep:

```bash
export EXPECTED_RHEL_MAJOR='8'
export EXPECTED_RHEL_MINOR='10'
export REQUIRE_FIPS='true'

export CM_VERSION='7.13.1.0'
export CDP_RUNTIME_VERSION='7.3.1'

export JAVA_MAJOR='11'
export JAVA_INSTALL_MODE='system'
export CUSTOM_JAVA_HOME=''
export JAVA_HOME_TARGET='/usr/lib/jvm/java-11-openjdk'

export PG_MAJOR='14'
export PGDATA_DIR='/data/postgres14'

export CFM_STREAM='cfm2'
export CFM_VERSION='2.1.7.3000'
export CFM_OS_REPO='redhat8'
export CFM_NIFI_CSD_JAR='NIFI-1.28.1.2.1.7.3000-45.jar'
export CFM_NIFIREGISTRY_CSD_JAR='NIFIREGISTRY-1.28.1.2.1.7.3000-45.jar'
export CFM_PARCEL_DIR_NAME='CFM-2.1.7.3000-45'

Important: The CFM CSD jars and the CFM parcel repository must come from the same CFM build. For this profile, the CSD jars are `NIFI-1.28.1.2.1.7.3000-45.jar` and `NIFIREGISTRY-1.28.1.2.1.7.3000-45.jar`, and the parcel repository is `https://archive.cloudera.com/p/cfm2/2.1.7.3000/redhat8/yum/tars/parcel/`. Do not mix these with 2.1.7.1001 artifacts.

export FIPS_JAR_SOURCE_DIR='/opt/cloudera/fips-jars/cdp-7.1.9'
export FIPS_BCTLS_JAR='bctls.jar'
export FIPS_CCJ_JAR='ccj-3.0.2.1.jar'
export FIPS_EXTRA_JARS=''
```

Although `CDP_RUNTIME_VERSION` is `7.3.1`, the FIPS jar directory is intentionally still:

```bash
/opt/cloudera/fips-jars/cdp-7.1.9
```

That is because CDP 7.3.1 is using the same SafeLogic/FIPS jar bundle as CDP 7.1.9 in this environment.

---

## 6. Validate the manager before installing

On the manager:

```bash
cd /root/cfm_fips_install
source ./EXPORTS

sudo -E bash 00_check_connectivity.sh
```

Warnings for missing packages are normal before the install:

```text
[WARN] command missing: python3
[WARN] command missing: java
[WARN] command missing: host
[WARN] command missing: nslookup
[WARN] command missing: nc
[WARN] command missing: jq
```

Those are installed by later scripts.

Hard blockers include:

- wrong RHEL version
- FIPS not enabled
- invalid Cloudera archive credentials
- inaccessible Cloudera repos
- bad manager/agent host values

---

## 7. Run the manager install

On the manager:

```bash
cd /root/cfm_fips_install
source ./EXPORTS

sudo -E ./RUN_MANAGER
```

`RUN_MANAGER` runs the manager-side scripts in order and stops if a script fails.

It installs/configures:

- common OS packages
- Java 11
- PostgreSQL 14
- Cloudera Manager repo
- Cloudera Manager Server
- local Cloudera Manager Agent
- CM database preparation
- CFM CSDs
- readiness validation

After it completes, check:

```bash
systemctl status cloudera-scm-server
systemctl status cloudera-scm-agent
tail -n 80 /var/log/cloudera-scm-server/cloudera-scm-server.log
```

Then open Cloudera Manager:

```text
http://<manager-host>:7180
```

Default login is usually:

```text
admin / admin
```

---

## 8. Run the agent install

Copy the same folder to the agent.

From the manager:

```bash
scp -r /root/cfm_fips_install ec2-user@<agent-host>:/tmp/
```

On the agent:

```bash
sudo -i

mv /tmp/cfm_fips_install /root/
cd /root/cfm_fips_install

chmod +x *.sh RUN_AGENT
source ./EXPORTS
```

Make sure the agent's `EXPORTS` has:

```bash
export MANAGER_HOST='<manager-private-dns-or-ip>'
export AGENT_HOST='<this-agent-private-dns-or-ip>'
export ALLOWED_CIDR='10.0.0.0/20'
```

Run the precheck:

```bash
sudo -E bash 00_check_connectivity.sh
```

Then run the agent installer:

```bash
sudo -E ./RUN_AGENT
```

Check the agent:

```bash
systemctl status cloudera-scm-agent
tail -n 80 /var/log/cloudera-scm-agent/cloudera-scm-agent.log
```

The agent should connect back to the manager host.

For additional agents, leave the shared values the same and change only:

```bash
export AGENT_HOST='<this-agent-private-dns-or-ip>'
```

The most important value for every agent is:

```bash
export MANAGER_HOST='<manager-private-dns-or-ip>'
```

---

## 9. What the wrappers do

`RUN_MANAGER` is a wrapper that runs the manager-side scripts in order.

`RUN_AGENT` is a wrapper that runs the agent-side scripts in order.

Both wrappers are designed to fail fast. If one script exits with a non-zero status, the wrapper should stop and should not continue blindly.

You can confirm this with:

```bash
head -40 RUN_MANAGER
head -40 RUN_AGENT
```

Look for:

```bash
set -e
```

or:

```bash
set -euo pipefail
```

---

## 10. PostgreSQL model

The current kit assumes local PostgreSQL on the manager.

Default:

```bash
export PG_MAJOR='14'
export PGDATA_DIR='/data/postgres14'
```

Before running `RUN_MANAGER`, make sure `/data` exists and has enough space:

```bash
df -h
lsblk -f
```

The FIPS requirements for CDP 7.1.9 supported PostgreSQL up to 14, so PostgreSQL 14 is the conservative default. It also remains fine for this CDP 7.3.1 profile.

If a future customer uses external PostgreSQL, the scripts should be adjusted to skip local PostgreSQL installation and use external DB connection settings. That is not the current default.

---

## 11. Cloudera Manager deployment sequence

After manager and agent are installed:

1. Log into Cloudera Manager.
2. Confirm both hosts appear.
3. Deploy the CDP Runtime cluster.
4. ZooKeeper comes from CDP Base/Runtime. Do not manually install ZooKeeper outside CM.
5. Add/use the CFM 2.1.7.3000 parcel repo.
6. Download, distribute, and activate the CFM parcel.
7. Deploy NiFi and NiFi Registry from Cloudera Manager.

---

## 12. Do not run the SafeLogic parcel-copy script too early

Do not run this immediately after `RUN_MANAGER`:

```bash
sudo -E bash 14_install_cfm_fips_jars.sh
```

That script copies the staged SafeLogic jars into the activated CFM parcel directory:

```bash
/opt/cloudera/parcels/CFM-2.1.7.3000-45/TOOLKIT/lib
```

That directory does not exist until the CFM parcel has been downloaded, distributed, and activated in Cloudera Manager.

The correct order is:

```text
Run RUN_MANAGER
Run RUN_AGENT
Log into Cloudera Manager
Deploy CDP Runtime / Base services
Activate CFM parcel
Then run 14_install_cfm_fips_jars.sh
Then run 15_validate_ready_state.sh
```

After CFM parcel activation, run on each host where the CFM parcel is present:

```bash
cd /root/cfm_fips_install
source ./EXPORTS

sudo -E bash 14_install_cfm_fips_jars.sh
sudo -E bash 15_validate_ready_state.sh
```

---

## 13. TLS approach

This kit does not enable Auto-TLS.

The target deployment uses real enterprise certificates, so TLS for NiFi and NiFi Registry is configured later through Cloudera Manager.

That means the install flow does not require:

- Auto-TLS
- CM-generated Auto-TLS truststore
- Auto-TLS truststore password lookup
- `/var/lib/cloudera-scm-agent/agent-cert/cm-auto-global_truststore.jks`

For the later manual TLS phase, use FIPS-compatible keystore/truststore settings and BCFKS where required by the CFM FIPS guidance.

---

## 14. Version changes later

The install kit is designed to be version-configurable through `EXPORTS`.

For example, if CM stays the same and CDP Runtime changes, update:

```bash
export CDP_RUNTIME_VERSION='7.3.1'
```

and any associated CDP parcel/repo URL variable used by the scripts.

If SafeLogic jars change in a future version, update:

```bash
export FIPS_JAR_SOURCE_DIR='/opt/cloudera/fips-jars/<new-folder>'
export FIPS_BCTLS_JAR='<new-bctls-jar-name>'
export FIPS_CCJ_JAR='<new-ccj-jar-name>'
export FIPS_EXTRA_JARS=''
```

For the current CDP 7.3.1 profile, no SafeLogic jar change is required because the same CDP 7.1.9 SafeLogic/FIPS jars are being used.

---

## 15. Quick command summary

Manager:

```bash
sudo -i
cd /root/cfm_fips_install

source ./EXPORTS
sudo -E bash 00_check_connectivity.sh
sudo -E ./RUN_MANAGER
```

Agent:

```bash
sudo -i
cd /root/cfm_fips_install

source ./EXPORTS
sudo -E bash 00_check_connectivity.sh
sudo -E ./RUN_AGENT
```

After CFM parcel activation:

```bash
sudo -i
cd /root/cfm_fips_install

source ./EXPORTS
sudo -E bash 14_install_cfm_fips_jars.sh
sudo -E bash 15_validate_ready_state.sh
```


## Update: CM Agent Python 3.8 is required on RHEL 8

During testing, the CM agent failed on the agent host with:

```text
ExecStart=/opt/cloudera/cm-agent/bin/cm agent (code=exited, status=126)
```

The root cause was the CM agent Python launcher:

```bash
/opt/cloudera/cm-agent/bin/python -> python3.8
```

When only the generic RHEL 8 `python3` was installed, the host had Python 3.6.8 but not Python 3.8. The CM agent wrapper selected an invalid path and failed with:

```text
/usr/local/bin/: Is a directory
exec: /usr/local/bin/: cannot execute: Is a directory
```

The scripts now install and validate Python 3.8 on both the manager and agent hosts. The relevant configurable values are in `EXPORTS`:

```bash
export CM_AGENT_PYTHON_BIN='/usr/bin/python3.8'
export CM_AGENT_PYTHON_PACKAGES='python38 python38-devel python38-pip'
export CM_AGENT_PYTHON_STRICT_VERSION='true'
```

The updated scripts validate this after the CM agent package is installed:

```bash
/opt/cloudera/cm-agent/bin/python --version
```

Expected output:

```text
Python 3.8.x
```

If the agent exits with status `126`, check these first:

```bash
ls -l /opt/cloudera/cm-agent/bin/python
/opt/cloudera/cm-agent/bin/python --version
ls -l /usr/bin/python3.8
systemctl status cloudera-scm-agent -l --no-pager
```

## Update: Java SafeLogic FIPS setup required before CM startup

During testing on RHEL 8.10 FIPS with CM 7.13.1 and CDP Runtime 7.3.1, CM Server failed with:

```text
java.security.KeyManagementException: FIPS mode: only SunJSSE TrustManagers may be used
```

The fix is not to disable FIPS. The SafeLogic jars must be configured for the Java runtime before CM Server starts.

The scripts now do this automatically in `04_install_java11_fips_runtime.sh`, `10_configure_cm_agent.sh`, and `12_start_cm_services.sh`:

1. Copy the staged SafeLogic jars from the configurable versioned source directory:

```bash
/opt/cloudera/fips-jars/cdp-7.1.9
```

into the active Java FIPS directory:

```bash
/opt/cloudera/fips
```

The active directory should contain:

```bash
/opt/cloudera/fips/ccj-3.0.2.1.jar
/opt/cloudera/fips/bctls-safelogic.jar
```

2. Set ownership and permissions:

```bash
chown root:root /opt/cloudera/fips/*.jar
chmod 0644 /opt/cloudera/fips/*.jar
```

3. Write `/etc/profile.d/ccj.sh` with the required `JDK_JAVA_OPTIONS` module path.

4. Patch the active Java 11 security files:

```bash
$JAVA_HOME/conf/security/java.policy
$JAVA_HOME/conf/security/java.security
```

The script backs up both files before patching them.

5. Validate that Java loads these providers:

```text
Provider: CCJ
Provider: BCJSSE
```

6. For CM Server, write active FIPS options into:

```bash
/etc/default/cloudera-scm-server
```

including:

```bash
-Dcom.cloudera.cmf.fipsMode=true
-Dcom.safelogic.cryptocomply.fips.approved_only=true
-Dcom.cloudera.cloudera.cmf.fipsMode.jdk11plus.ccj.jar.path=/opt/cloudera/fips/ccj-3.0.2.1.jar
-Dcom.cloudera.cloudera.cmf.fipsMode.jdk11plus.ccj.moduleName=com.safelogic.cryptocomply.fips.core
-Dcom.cloudera.cloudera.cmf.fipsMode.jdk11plus.bctls.jar.path=/opt/cloudera/fips/bctls-safelogic.jar
-Dcom.cloudera.cloudera.cmf.fipsMode.jdk11plus.bctls.moduleName=bctls.safelogic
```

The double `cloudera.cloudera` in the JDK 11+ property names is intentional because that is how the CM defaults template shows the FIPS properties.

### Important distinction

There are now three SafeLogic locations to understand:

```text
/opt/cloudera/fips-jars/cdp-7.1.9
```

Versioned staging location. This is where the SafeLogic tarball is extracted/copied first. CDP 7.3.1 currently uses the same jars as CDP 7.1.9.

```text
/opt/cloudera/fips
```

Active Java FIPS provider location. Java and CM use this before CM Server starts.

```text
/opt/cloudera/parcels/CFM-*/TOOLKIT/lib
```

CFM/NiFi FIPS location. This does not exist until the CFM parcel is activated. Run `14_install_cfm_fips_jars.sh` only after the CFM parcel is downloaded, distributed, and activated in Cloudera Manager.

### Manual validation commands

Use these if you need to confirm Java FIPS setup manually:

```bash
source /etc/profile.d/ccj.sh
java -version
java -p /opt/cloudera/fips/ --list-modules | grep -E 'cryptocomply|bctls' || true
```

Provider validation:

```bash
cat > /root/ListSecurityProviders.java <<'JAVACODE'
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
JAVACODE

source /etc/profile.d/ccj.sh
java /root/ListSecurityProviders.java | egrep 'Provider:|CCJ|BCJSSE|Bouncy|CryptoComply'
```

Expected output includes:

```text
Provider: CCJ
Provider: BCJSSE
```
