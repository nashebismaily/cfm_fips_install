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
```

Important: The CFM CSD jars and the CFM parcel repository must come from the same CFM build. For this profile, the CSD jars are `NIFI-1.28.1.2.1.7.3000-45.jar` and `NIFIREGISTRY-1.28.1.2.1.7.3000-45.jar`, and the parcel repository is `https://archive.cloudera.com/p/cfm2/2.1.7.3000/redhat8/yum/tars/parcel/`. Do not mix these with 2.1.7.1001 artifacts.

Keep the SafeLogic jar values as:

```bash
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
- Python 3.8 for the CM agent wrapper
- Java 11
- SafeLogic Java FIPS provider configuration
- PostgreSQL 14
- Cloudera Manager repo
- Cloudera Manager Server
- the local Cloudera Manager Agent on the manager/server host
- the local `cloudera-scm-supervisord` service on the manager/server host
- CM database preparation
- CFM CSDs
- readiness validation

Important: the Cloudera Manager server host must also run the CM agent and supervisord. Otherwise it may not appear as a managed host in CM. The updated scripts start and validate both local services:

```bash
systemctl status cloudera-scm-supervisord
systemctl status cloudera-scm-agent
```

After `RUN_MANAGER` completes, check:

```bash
systemctl status cloudera-scm-server
systemctl status cloudera-scm-supervisord
systemctl status cloudera-scm-agent
tail -n 80 /var/log/cloudera-scm-server/cloudera-scm-server.log
tail -n 80 /var/log/cloudera-scm-agent/cloudera-scm-agent.log
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

Check the agent services:

```bash
systemctl status cloudera-scm-supervisord
systemctl status cloudera-scm-agent
tail -n 80 /var/log/cloudera-scm-agent/cloudera-scm-agent.log
```

Both `cloudera-scm-supervisord` and `cloudera-scm-agent` should be active. The agent should connect back to the manager host.

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

### Default database names, users, and passwords

The scripts create these PostgreSQL databases by default on the manager host. These are the values you should use in the Cloudera Manager UI unless you changed `EXPORTS`.

| Purpose | Database | Username | Password | Notes |
|---|---|---|---|---|
| Cloudera Manager Server | `scm` | `scm` | `ClouderaCM_2026` | Used by `scm_prepare_database.sh`; not usually entered in the CM UI after install |
| Reports Manager | `rman` | `rman` | `Rman_DB_2026` | Enter this in the CM Management Service Reports Manager database screen |
| NiFi Registry | `nifireg` | `nifireg` | `Registry_DB_2026` | Enter this in the NiFi Registry database configuration |
| Hue, optional | `hue` | `hue` | `Hue_DB_2026` | Created only if `CREATE_EXTRA_DBS=true` |
| Hive Metastore, optional | `metastore` | `hive` | `Hive_DB_2026` | Created only if `CREATE_EXTRA_DBS=true` |
| Ranger, optional | `ranger` | `rangeradmin` | `Ranger_DB_2026` | Created only if `CREATE_EXTRA_DBS=true` |

The database host for UI configuration is normally the manager private DNS name:

```text
ip-10-0-3-31.us-east-2.compute.internal
```

The PostgreSQL port is:

```text
5432
```

If your manager host is different, use the value of `MANAGER_HOST` from `EXPORTS`.

---

## 11. Cloudera Manager deployment sequence

After manager and agent are installed:

1. Log into Cloudera Manager.
2. Confirm the manager/server host appears as a managed host.
3. Confirm each remote agent host appears as a managed host.
4. Deploy the CDP Runtime cluster.
5. ZooKeeper comes from CDP Base/Runtime. Do not manually install ZooKeeper outside CM.
6. Add the CFM parcel repository from `EXPORTS`:

```bash
echo "$CFM_PARCEL_REPO_URL"
```

For the default CFM 2.1.7.3000 profile, this is:

```text
https://archive.cloudera.com/p/cfm2/2.1.7.3000/redhat8/yum/tars/parcel/
```

7. In CM, go to `Hosts -> Parcels -> Configuration` and add that repository URL.
8. Go back to `Hosts -> Parcels`, click `Check for New Parcels`, and look for:

```text
CFM-2.1.7.3000-45
```

9. Download, distribute, and activate the CFM parcel.
10. Deploy NiFi and NiFi Registry from Cloudera Manager.

Important: the CFM CSD jars and the CFM parcel repository must come from the same CFM build. For the default profile, the CSDs are:

```text
NIFI-1.28.1.2.1.7.3000-45.jar
NIFIREGISTRY-1.28.1.2.1.7.3000-45.jar
```

and the parcel repo is:

```text
https://archive.cloudera.com/p/cfm2/2.1.7.3000/redhat8/yum/tars/parcel/
```

Do not mix 2.1.7.3000 CSDs with older 2.1.7.1001 parcel artifacts, or the reverse.

### NiFi Registry PostgreSQL configuration

When adding **NiFi Registry** in Cloudera Manager, replace the default embedded H2 values with PostgreSQL. Use these values unless you changed the database variables in `EXPORTS`:

| CM field | Value |
|---|---|
| NiFi Registry JDBC Url | `jdbc:postgresql://ip-10-0-3-31.us-east-2.compute.internal:5432/nifireg` |
| NiFi Registry JDBC Driver | `org.postgresql.Driver` |
| NiFi Registry Database Driver Directory | `/usr/share/java` |
| NiFi Registry Database Username | `nifireg` |
| NiFi Registry Database Password | `Registry_DB_2026` |
| Maximum connection in db pool | `5` |
| Enable database sql debugging | `false` |

If your manager host is different, replace `ip-10-0-3-31.us-east-2.compute.internal` with `$MANAGER_HOST`.

Install the PostgreSQL JDBC driver on the host where NiFi Registry will run:

```bash
sudo -i
dnf install -y postgresql-jdbc
ls -lh /usr/share/java | grep -i postgres
find /usr/share/java -iname '*postgres*.jar' -print
```

If installing `postgresql-jdbc` changes the active Java alternative, set Java back to 11:

```bash
alternatives --config java
java -version
```

Before saving the NiFi Registry config in CM, you can test the database connection from the NiFi Registry host:

```bash
PGPASSWORD='Registry_DB_2026' /usr/pgsql-14/bin/psql \
  -h ip-10-0-3-31.us-east-2.compute.internal \
  -p 5432 \
  -U nifireg \
  -d nifireg \
  -c "select current_database(), current_user;"
```

Expected result:

```text
 current_database | current_user
------------------+--------------
 nifireg          | nifireg
```


### NiFi post-install FIPS configuration

When adding **NiFi** in Cloudera Manager, some FIPS-related properties may not appear in the initial Add Service wizard. That is expected. Add the NiFi service first, then configure these values after the service exists and before considering the service complete.

Before starting NiFi, make sure `14_install_cfm_fips_jars.sh` has already been run on the host where the NiFi role will run. For example, on the NiFi host:

```bash
cd /root/cfm_fips_install
source ./EXPORTS
sudo -E bash 14_install_cfm_fips_jars.sh

ls -lh /opt/cloudera/parcels/CFM-2.1.7.3000-45/TOOLKIT/lib | egrep 'bctls|ccj'
```

Expected files and permissions:

```text
-rw-r--r--. 1 root root ... bctls.jar
-rw-r--r--. 1 root root ... ccj-3.0.2.1.jar
```

If NiFi and NiFi Registry run only on the agent host, run script 14 only on that agent. You do not need to run script 14 on the CM Server host unless you place NiFi or NiFi Registry roles there.

After the NiFi service is created, go to:

```text
NiFi -> Configuration
```

Search for:

```text
sensitive
```

Set these values:

```properties
nifi.sensitive.props.algorithm=NIFI_PBKDF2_AES_GCM_256
nifi.sensitive.props.key=<real key, at least 12 characters>
```

Use a real environment-specific key. Do not leave the placeholder value from `EXPORTS` in a shared or customer environment.

Next, add the SafeLogic/BCTLS Java module arguments to the NiFi bootstrap configuration. In CM, search for:

```text
bootstrap
```

Use this field:

```text
NiFi Node Advanced Configuration Snippet (Safety Valve) for staging/bootstrap.conf.xml
```

Add the following XML snippet:

```xml
<property>
  <name>java.arg.200</name>
  <value>--module-path=/opt/cloudera/parcels/CFM-2.1.7.3000-45/TOOLKIT/lib/ccj-3.0.2.1.jar:/opt/cloudera/parcels/CFM-2.1.7.3000-45/TOOLKIT/lib/bctls.jar</value>
</property>
<property>
  <name>java.arg.201</name>
  <value>--add-exports=java.base/sun.security.provider=com.safelogic.cryptocomply.fips.core</value>
</property>
<property>
  <name>java.arg.202</name>
  <value>--add-modules=com.safelogic.cryptocomply.fips.core,bctls</value>
</property>
<property>
  <name>java.arg.203</name>
  <value>-Dcom.safelogic.cryptocomply.fips.approved_only=true</value>
</property>
<property>
  <name>java.arg.204</name>
  <value>-Djdk.tls.trustNameService=true</value>
</property>
<property>
  <name>java.arg.205</name>
  <value>-Djdk.tls.ephemeralDHKeySize=2048</value>
</property>
<property>
  <name>java.arg.206</name>
  <value>-Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true</value>
</property>
```

For the CFM 2.1.7.3000 parcel used in this kit, the module names validate as:

```text
ccj-3.0.2.1.jar -> com.safelogic.cryptocomply.fips.core
bctls.jar       -> bctls
```

You can confirm on the NiFi host with:

```bash
/usr/lib/jvm/java-11-openjdk/bin/jar \
  --file=/opt/cloudera/parcels/CFM-2.1.7.3000-45/TOOLKIT/lib/ccj-3.0.2.1.jar \
  --describe-module | head -5

/usr/lib/jvm/java-11-openjdk/bin/jar \
  --file=/opt/cloudera/parcels/CFM-2.1.7.3000-45/TOOLKIT/lib/bctls.jar \
  --describe-module | head -5
```

After saving the NiFi configuration, start or restart NiFi. Then validate that CM generated the bootstrap arguments correctly:

```bash
sudo -i

NIFI_PROC_DIR=$(ls -td /var/run/cloudera-scm-agent/process/*NIFI* /var/run/cloudera-scm-agent/process/*nifi* 2>/dev/null | head -1)
echo "$NIFI_PROC_DIR"

grep -n "java.arg.20\|module-path\|add-modules\|safelogic\|bctls" "$NIFI_PROC_DIR/bootstrap.conf"
```

Expected output includes:

```text
java.arg.200=--module-path=/opt/cloudera/parcels/CFM-2.1.7.3000-45/TOOLKIT/lib/ccj-3.0.2.1.jar:/opt/cloudera/parcels/CFM-2.1.7.3000-45/TOOLKIT/lib/bctls.jar
java.arg.201=--add-exports=java.base/sun.security.provider=com.safelogic.cryptocomply.fips.core
java.arg.202=--add-modules=com.safelogic.cryptocomply.fips.core,bctls
java.arg.203=-Dcom.safelogic.cryptocomply.fips.approved_only=true
java.arg.204=-Djdk.tls.trustNameService=true
java.arg.205=-Djdk.tls.ephemeralDHKeySize=2048
java.arg.206=-Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true
```

If NiFi fails with this error:

```text
java.security.NoSuchAlgorithmException: X.509 KeyManagerFactory not available
```

then the bootstrap module arguments are not being applied to the NiFi JVM. Recheck the `staging/bootstrap.conf.xml` safety valve and confirm the generated `bootstrap.conf` contains `java.arg.200` through `java.arg.206`.

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

## 13. Auto-TLS approach

This kit now includes an Auto-TLS utility workflow under:

```bash
utilities/tls
```

The top-level install scripts still handle the operating system, Java/FIPS runtime, PostgreSQL, Cloudera Manager, CSDs, parcels, and base service installation. The `utilities/tls` directory is a separate post-install utility area for enabling Cloudera Manager Auto-TLS after the manager and agent hosts are installed and visible in Cloudera Manager.

Use the top-level README for the full platform install. Use `utilities/tls/README.md` when you are ready to enable Auto-TLS.

### When to run Auto-TLS

Run Auto-TLS only after:

1. `RUN_MANAGER` has completed successfully on the manager host.
2. `RUN_AGENT` has completed successfully on the agent host.
3. The manager host and agent host both appear in Cloudera Manager.
4. Cloudera Manager is reachable on HTTP port `7180`.
5. The Cloudera Manager admin credentials work.
6. Passwordless SSH works from the manager host to every cluster host using the configured Auto-TLS SSH user.
7. The hostnames in `utilities/tls/hosts.csv` match the hostnames used by Cloudera Manager.

Do not run Auto-TLS before the CM agents are installed and communicating with the CM server.

### Auto-TLS utility files

The Auto-TLS utilities are in:

```bash
cd /root/cfm_fips_install/utilities/tls
```

Important files:

| File | Purpose |
|---|---|
| `README.md` | Detailed Auto-TLS utility instructions |
| `tls.env` | Local runtime configuration for the Auto-TLS scripts |
| `tls.env.example` | Example configuration template |
| `hosts.csv` | Host inventory used to generate certificates and payload entries |
| `hosts.csv.example` | Example host inventory |
| `00_prepare_dirs.sh` | Creates the Auto-TLS artifact directories |
| `01_generate_keys_csrs.sh` | Generates host private keys and CSRs |
| `02_create_demo_ca.sh` | Creates the local CA used by this utility flow |
| `03_sign_csrs_with_demo_ca.sh` | Signs the host CSRs |
| `04_build_pkcs12_stores.sh` | Builds PKCS12 keystores and truststores for validation/use |
| `05_validate_autotls_prereqs.sh` | Validates CM API access, DNS, SSH, filesystem paths, and artifacts |
| `06_validate_artifacts.sh` | Validates certificates, keys, SANs, and stores |
| `07_enable_autotls.sh` | Calls the Cloudera Manager `generateCmca` API |

`tls.env` and `hosts.csv` are local runtime files. They should normally not be committed with customer-specific hostnames, credentials, or passwords. Commit the `.example` files instead.

### Example `hosts.csv`

For a two-host manager plus agent environment:

```csv
host_id,ip_sans,dns_sans
ip-10-0-3-31.us-east-2.compute.internal,10.0.3.31,ip-10-0-3-31.us-east-2.compute.internal
ip-10-0-11-156.us-east-2.compute.internal,10.0.11.156,ip-10-0-11-156.us-east-2.compute.internal
```

The `host_id` must match the hostname Cloudera Manager knows for that host. The scripts use `host_id` to name generated key, CSR, and certificate files.

### Example `tls.env`

The current Auto-TLS artifact location is:

```bash
export AUTO_TLS_LOCATION="/opt/cloudera/AutoTLS"
export AUTO_TLS_WORKDIR="${AUTO_TLS_LOCATION}/artifacts"
```

The CM API settings should point to the manager host before Auto-TLS is enabled:

```bash
export CM_HOST="ip-10-0-3-31.us-east-2.compute.internal"
export CM_PORT="7180"
export CM_API_VERSION="v41"
export CM_USER="admin"
export CM_PASSWORD="admin"
```

The SSH settings should point to the user that can SSH from the manager host to every managed host:

```bash
export AUTO_TLS_SSH_USER="autotls"
export AUTO_TLS_SSH_PORT="22"
export AUTO_TLS_SSH_KEY_FILE="/home/autotls/.ssh/id_rsa"
```

The `autotls` user should have passwordless SSH and passwordless sudo on each host:

```bash
autotls ALL=(ALL) NOPASSWD:ALL
```

### Encrypted and unencrypted host key modes

The Auto-TLS utilities support both encrypted and unencrypted host private keys.

For customer/live environments, use encrypted host keys:

```bash
export AUTO_TLS_ENCRYPT_HOST_KEYS="true"
export AUTO_TLS_HOST_KEY_PASSWORD="ChangeMe12345"
```

In this mode:

- `01_generate_keys_csrs.sh` generates encrypted PEM host private keys.
- `07_enable_autotls.sh` validates those encrypted keys.
- `07_enable_autotls.sh` creates the per-host password files Cert Manager expects:

```text
/opt/cloudera/AutoTLS/hosts-key-store/<hostname>/cm-auto-host_key.pw
```

For lab or temporary testing only, unencrypted host keys can be used:

```bash
export AUTO_TLS_ENCRYPT_HOST_KEYS="false"
```

In this mode:

- `01_generate_keys_csrs.sh` generates unencrypted PEM host private keys.
- `07_enable_autotls.sh` does not create `cm-auto-host_key.pw` files.
- `07_enable_autotls.sh` removes stale per-host password files before calling Auto-TLS.

For customer work, encrypted mode is preferred.

### Auto-TLS execution sequence

On the manager host:

```bash
sudo -i
cd /root/cfm_fips_install/utilities/tls

source ./tls.env

rm -rf /opt/cloudera/AutoTLS/artifacts
rm -rf /opt/cloudera/AutoTLS/hosts-key-store
rm -rf /opt/cloudera/AutoTLS/trust-store
rm -rf /opt/cloudera/AutoTLS/private

./00_prepare_dirs.sh
./01_generate_keys_csrs.sh
./02_create_demo_ca.sh
./03_sign_csrs_with_demo_ca.sh
./04_build_pkcs12_stores.sh
./06_validate_artifacts.sh
./05_validate_autotls_prereqs.sh
./07_enable_autotls.sh
```

The order intentionally runs `06_validate_artifacts.sh` before `05_validate_autotls_prereqs.sh` in the final run so the prerequisite script can confirm the expected artifacts are already present.

### What `05_validate_autotls_prereqs.sh` checks

The prerequisite script validates:

- Required local commands are present.
- `tls.env` contains required variables.
- Password values meet the script requirements.
- `hosts.csv` exists and has at least one host.
- Each host resolves through local DNS or `/etc/hosts`.
- The Cloudera Manager API responds on `http://<CM_HOST>:7180/api/<version>/cm/version`.
- CM credentials are valid.
- Passwordless SSH works to every host using `AUTO_TLS_SSH_USER` and `AUTO_TLS_SSH_KEY_FILE`.
- `/opt/cloudera/AutoTLS` is readable and writable by `cloudera-scm`.
- CA, host certificate, and host key artifacts exist.

Do not run `07_enable_autotls.sh` until `05_validate_autotls_prereqs.sh` and `06_validate_artifacts.sh` both pass.

### What `07_enable_autotls.sh` does

`07_enable_autotls.sh` builds a payload for:

```text
http://<CM_HOST>:7180/api/<CM_API_VERSION>/cm/commands/generateCmca
```

The payload includes:

- Auto-TLS location
- CA certificate path
- CM host certificate path
- CM host private key path
- host certificate/key entries for every host
- keystore and truststore password file paths
- SSH user and SSH private key for host access
- `configureAllServices=true` when configured

For encrypted host private keys, `07_enable_autotls.sh` also writes:

```text
/opt/cloudera/AutoTLS/hosts-key-store/<hostname>/cm-auto-host_key.pw
```

This is required because Cloudera Cert Manager uses those files when converting encrypted host private keys into the Auto-TLS keystore format.

If Cert Manager logs show this error:

```text
No password file found for host ... cm-auto-host_key.pw
Assuming default in-cluster password
unable to load private key
bad decrypt
```

then the per-host password file is missing or the password does not match the encrypted host private key.

### After `07_enable_autotls.sh` succeeds

After the API call succeeds, watch the logs:

```bash
tail -f /var/log/cloudera-scm-server/cloudera-scm-server.log
tail -f /var/log/cloudera-scm-agent/certmanager.log
```

Then restart Cloudera Manager:

```bash
systemctl restart cloudera-scm-server
```

After CM returns, access the UI using HTTPS:

```text
https://<manager-host>:7183
```

Then restart the CM agent on every host:

```bash
systemctl restart cloudera-scm-agent
```

From the manager host, you can restart a remote agent with:

```bash
ssh -i /home/autotls/.ssh/id_rsa autotls@<agent-host> "sudo systemctl restart cloudera-scm-agent"
```

Finally, restart Cloudera Management Service and the cluster services from the Cloudera Manager UI.

### Post Auto-TLS notes for NiFi and NiFi Registry

After Auto-TLS, NiFi and NiFi Registry use the keystores and truststores produced by Cloudera Manager. In FIPS-enabled CFM environments, make sure the SafeLogic/BCTLS Java module arguments are applied to the CFM JVMs.

For NiFi, use the NiFi bootstrap safety valve described earlier in this README.

For NiFi Registry, if the service fails with:

```text
java.security.NoSuchAlgorithmException: X.509 KeyManagerFactory not available
```

set the Registry SSL manager algorithms to `PKIX`:

```properties
nifi.registry.security.keymanager.algorithm=PKIX
nifi.registry.security.trustmanager.algorithm=PKIX
```

If Cloudera Manager exposes these fields directly, configure them in the NiFi Registry service configuration. If not, add them to the NiFi Registry advanced configuration snippet for `nifi-registry.properties`.

Also verify the keystore and truststore type values match the stores assigned by Cloudera Manager:

```properties
nifi.registry.security.keystoreType=JKS
nifi.registry.security.truststoreType=JKS
```

or:

```properties
nifi.registry.security.keystoreType=PKCS12
nifi.registry.security.truststoreType=PKCS12
```

Use the generated process directory to confirm the effective Registry configuration:

```bash
grep -i 'keymanager\|trustmanager\|keystoreType\|truststoreType' \
  /var/run/cloudera-scm-agent/process/*-NIFI_REGISTRY-*/nifi-registry.properties 2>/dev/null
```

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

The scripts now install and validate Python 3.8 on both the manager and agent hosts, because the manager host also runs a local CM agent. The relevant configurable values are in `EXPORTS`:

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


## Update: Manager host also runs agent + supervisord

The Cloudera Manager server host must also be a managed host. That means the manager/server host needs both of these services running locally:

```bash
cloudera-scm-supervisord
cloudera-scm-agent
```

The updated `10_configure_cm_agent.sh` and `12_start_cm_services.sh` explicitly enable, restart, and validate both services. This applies to the manager/server host and to remote agent hosts.

Quick validation on any host:

```bash
systemctl status cloudera-scm-supervisord -l --no-pager
systemctl status cloudera-scm-agent -l --no-pager
/opt/cloudera/cm-agent/bin/python --version
```

Expected Python wrapper output is Python 3.8.x.
