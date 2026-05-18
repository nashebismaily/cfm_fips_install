# Cloudera Manager 7.13.1 + CDP 7.3.1 + CFM 2.1.7 FIPS Install Kit

This install kit prepares a two-host Cloudera environment for:

- RHEL 8.10 with FIPS already enabled
- Cloudera Manager 7.13.1
- CDP Private Cloud Base / Runtime 7.3.1
- ZooKeeper from CDP Base
- CFM 2.1.7.1001 for NiFi and NiFi Registry
- Java 11
- PostgreSQL 14
- SafeLogic / Bouncy Castle FIPS jars copied into the activated CFM parcel
- CDP 7.3.1 using the same SafeLogic/FIPS jar bundle as CDP 7.1.9

The scripts do **not** enable Auto-TLS. This build assumes TLS with real enterprise certificates will be configured later through Cloudera Manager.

## Why these defaults

The defaults are based on the FIPS path discussed for this build:

- CDP 7.3.1 FIPS supports RHEL 8.10.
- PostgreSQL 14 is intentionally kept as the default because it works cleanly for this lab path and keeps the install consistent with the earlier 7.1.9 FIPS profile.
- CDP 7.3.1 uses the same SafeLogic/FIPS jar bundle as CDP 7.1.9 based on the guidance you received.
- CFM FIPS requires CDP Base installed with FIPS enabled, Java 11 FIPS-compliant build, CFM 2.x such as 2.1.7, and SafeLogic/Bouncy Castle crypto jars.
- Auto-TLS is recommended by Cloudera, but this kit intentionally leaves TLS for a later manual enterprise-cert phase.

## File inventory

```bash
EXPORTS
RUN_MANAGER
RUN_AGENT
lib/common.sh
00_check_connectivity.sh
01_bootstrap_repos.sh
02_install_common_packages.sh
03_configure_os.sh
04_install_java11_fips_runtime.sh
05_install_postgres.sh
06_configure_postgres_networking.sh
07_create_cm_and_registry_dbs.sh
08_add_cloudera_repos.sh
09_install_cm_packages.sh
10_configure_cm_agent.sh
11_prepare_cm_database.sh
12_start_cm_services.sh
13_install_cfm_csds.sh
14_install_cfm_fips_jars.sh
15_validate_ready_state.sh
```

## Required preconditions

Before running the scripts:

1. Use RHEL 8.10.
2. FIPS must already be enabled.
3. Use x86_64 instances.
4. Configure DNS or `/etc/hosts` so manager and agent can resolve each other.
5. Open security group / firewall access between nodes.
6. Have Cloudera archive credentials.
7. Have the SafeLogic/Bouncy Castle jars available on every host that will run CFM roles.

Validate FIPS manually:

```bash
cat /proc/sys/crypto/fips_enabled
fips-mode-setup --check
```

Expected:

```bash
1
FIPS mode is enabled.
```

## Network ports to allow between manager and agent

At minimum for this two-host lab:

- 7180 from your browser to manager for CM UI
- 7182 from agents to manager for SCM agent heartbeat
- 5432 from agent subnet to manager if external services need PostgreSQL access
- 2181 for ZooKeeper client access when deployed
- NiFi/NiFi Registry ports later depending on CM role configuration

For AWS security groups, allow the VPC CIDR or the specific manager/agent private IPs. Keep this tighter than `0.0.0.0/0`.

## Configure EXPORTS first

Edit `EXPORTS` before running anything:

```bash
vi EXPORTS
```

Required changes:

```bash
export CLOUDERA_REPO_USER='your-cloudera-archive-user'
export CLOUDERA_REPO_PASS='your-cloudera-archive-password'
export MANAGER_HOST='manager.private.dns.name'
export ALLOWED_CIDR='10.0.0.0/20'
```

Database passwords should also be changed:

```bash
export CM_DB_PASS='change-me'
export RM_DB_PASS='change-me'
export REG_DB_PASS='change-me'
```

## Version knobs

The goal is to make version changes centralized. These values live in `EXPORTS`.

### Cloudera Manager

```bash
export CM_VERSION='7.13.1.0'
export CM_MAJOR_REPO='cm7'
export CM_OS_REPO='redhat8'
export CM_REPO_BASE_URL="https://archive.cloudera.com/p/${CM_MAJOR_REPO}/${CM_VERSION}/${CM_OS_REPO}/yum/"
```

When moving CM versions, update `CM_VERSION` and confirm the repo path.

### CDP Runtime

```bash
export CDP_RUNTIME_VERSION='7.3.1'
export CDP_PARCEL_REPO_URL=''
```

These scripts do not deploy CDP services automatically. In Cloudera Manager, deploy CDP Base services first, including ZooKeeper. ZooKeeper comes from the CDP Runtime parcel, not from CFM.

For this update, CM remains on 7.13.1 and the SafeLogic jar variables stay pointed to the same jar bundle used for CDP 7.1.9. The runtime change is handled through the CDP Runtime version and the parcel repository you configure in Cloudera Manager.

### CFM

Default CFM hotfix build:

```bash
export CFM_STREAM='cfm2'
export CFM_VERSION='2.1.7.1001'
export CFM_OS_REPO='redhat8'
export CFM_PARCEL_REPO_URL="https://archive.cloudera.com/p/${CFM_STREAM}/${CFM_VERSION}/${CFM_OS_REPO}/yum/tars/parcel/"
export CFM_NIFI_CSD_JAR='NIFI-1.26.0.2.1.7.1001-5.jar'
export CFM_NIFIREGISTRY_CSD_JAR='NIFIREGISTRY-1.26.0.2.1.7.1001-5.jar'
export CFM_PARCEL_DIR_NAME='CFM-2.1.7.1001-5'
```

When moving CFM versions, update all of those CFM values together.

## SafeLogic / Bouncy Castle jar configuration

This is intentionally configurable, but for this profile the SafeLogic jar bundle does **not** change when moving from CDP 7.1.9 to CDP 7.3.1. Based on the guidance you received, CDP 7.3.1 uses the same FIPS jars as CDP 7.1.9.

Put the SafeLogic jars somewhere consistent on every host that will run NiFi or NiFi Registry, for example:

```bash
sudo mkdir -p /opt/cloudera/fips-jars/cdp-7.1.9
sudo cp /path/to/your/jars/*.jar /opt/cloudera/fips-jars/cdp-7.1.9/
sudo chmod 644 /opt/cloudera/fips-jars/cdp-7.1.9/*.jar
```

Then update `EXPORTS`:

```bash
export FIPS_JAR_SOURCE_DIR='/opt/cloudera/fips-jars/cdp-7.1.9'
export FIPS_BCTLS_JAR='bctls.jar'
export FIPS_CCJ_JAR='ccj-3.0.2.1.jar'
export FIPS_EXTRA_JARS=''
```

If your SafeLogic bundle uses different filenames, change the values. For example:

```bash
export FIPS_BCTLS_JAR='bctls-fips-1.0.19.jar'
export FIPS_CCJ_JAR='ccj-3.0.2.1.jar'
export FIPS_EXTRA_JARS='bc-fips-1.0.2.4.jar bcpkix-fips-1.0.7.jar'
```

Do not hard-code these names in the scripts. For this CDP 7.3.1 profile, leave the default pointing to the existing CDP 7.1.9 SafeLogic jar folder unless Cloudera gives you a newer jar bundle later. If the SafeLogic bundle changes in the future, only update `FIPS_JAR_SOURCE_DIR`, `FIPS_BCTLS_JAR`, `FIPS_CCJ_JAR`, and optionally `FIPS_EXTRA_JARS`.

## Manager install order

On the manager node:

```bash
source ./EXPORTS
sudo -E bash 00_check_connectivity.sh
sudo -E bash 01_bootstrap_repos.sh
sudo -E bash 02_install_common_packages.sh
sudo -E bash 03_configure_os.sh
sudo -E bash 04_install_java11_fips_runtime.sh
sudo -E bash 05_install_postgres.sh
sudo -E bash 06_configure_postgres_networking.sh
sudo -E bash 07_create_cm_and_registry_dbs.sh
sudo -E bash 08_add_cloudera_repos.sh
sudo -E bash 09_install_cm_packages.sh manager
sudo -E bash 10_configure_cm_agent.sh "${MANAGER_HOST:-$(hostname -f)}"
sudo -E bash 11_prepare_cm_database.sh
sudo -E bash 12_start_cm_services.sh
sudo -E bash 13_install_cfm_csds.sh
sudo -E bash 15_validate_ready_state.sh
```

Or review and run:

```bash
cat RUN_MANAGER
```

## Agent install order

On the agent node:

```bash
source ./EXPORTS
sudo -E bash 00_check_connectivity.sh
sudo -E bash 01_bootstrap_repos.sh
sudo -E bash 02_install_common_packages.sh
sudo -E bash 03_configure_os.sh
sudo -E bash 04_install_java11_fips_runtime.sh
sudo -E bash 08_add_cloudera_repos.sh
sudo -E bash 09_install_cm_packages.sh agent
sudo -E bash 10_configure_cm_agent.sh "${MANAGER_HOST}"
sudo -E bash 15_validate_ready_state.sh
```

Or review and run:

```bash
cat RUN_AGENT
```

## Cloudera Manager UI flow after scripts

After CM starts:

1. Log into CM at `http://<manager>:7180`.
2. Add the agent host if it has not appeared yet.
3. Configure the CDP Runtime parcel and deploy CDP Base services.
4. Deploy ZooKeeper from CDP Base.
5. Add the CFM parcel repository URL:

```text
https://archive.cloudera.com/p/cfm2/2.1.7.1001/redhat8/yum/tars/parcel/
```

6. Download, distribute, and activate the CFM parcel.
7. Add NiFi and NiFi Registry services.
8. Configure NiFi Registry to use the PostgreSQL database created by the scripts:

```text
Database type: PostgreSQL
Database host: <manager-host>
Database port: 5432
Database name: nifireg
Database user: nifireg
Database password: value of REG_DB_PASS
```

## Copy FIPS jars after CFM parcel activation

After the CFM parcel is activated on any host that will run NiFi or NiFi Registry:

```bash
source ./EXPORTS
sudo -E bash 14_install_cfm_fips_jars.sh
sudo -E bash 15_validate_ready_state.sh
```

This copies the configured jars from:

```bash
$FIPS_JAR_SOURCE_DIR
```

into:

```bash
$CFM_TOOLKIT_LIB_DIR
```

Default:

```bash
/opt/cloudera/parcels/CFM-2.1.7.1001-5/TOOLKIT/lib
```

If the activated parcel directory differs, update:

```bash
export CFM_PARCEL_DIR_NAME='actual-parcel-dir-name'
export CFM_PARCEL_ROOT="/opt/cloudera/parcels/${CFM_PARCEL_DIR_NAME}"
export CFM_TOOLKIT_LIB_DIR="${CFM_PARCEL_ROOT}/TOOLKIT/lib"
```

## Manual TLS later with real certs

This install kit intentionally does not enable Auto-TLS. Later, when using real enterprise certificates:

- Use node-specific certificates, not wildcard certs.
- Use BCFKS keystores/truststores for FIPS.
- Configure NiFi and NiFi Registry TLS through Cloudera Manager.
- Apply the FIPS bootstrap safety valve to both NiFi and NiFi Registry.

The CFM FIPS safety valve from Cloudera includes:

```xml
<property>
  <name>java.arg.modulepath</name>
  <value>--module-path=/tmp/jars</value>
</property>
<property>
  <name>java.arg.allowgcm</name>
  <value>-Dorg.bouncycastle.jsse.fips.allowGCMCiphers=true</value>
</property>
<property>
  <name>java.arg.truststoretype</name>
  <value>-Djavax.net.ssl.trustStoreType=bcfks</value>
</property>
```

Because this install uses real enterprise certs later, do not use the Auto-TLS truststore path from the example unless you intentionally change direction and enable Auto-TLS. For real certs, point the keystore/truststore values to your real BCFKS files.

## NiFi sensitive properties algorithm

Set the FIPS-compatible algorithm:

```properties
nifi.sensitive.props.algorithm=NIFI_PBKDF2_AES_GCM_256
nifi.sensitive.props.key=<at-least-12-characters>
```

The key should be a real secret, not the default placeholder in `EXPORTS`.

## Important boundaries

These scripts prepare the host and install CM/agent/CSD/database prerequisites. They do not fully automate CDP cluster creation in the CM UI.

What the scripts do:

- Validate RHEL 8.10 and FIPS
- Install common packages
- Configure OS tuning
- Install Java 11
- Install PostgreSQL 14
- Create CM, Reports Manager, and NiFi Registry databases
- Install CM server/agent packages
- Prepare CM database
- Start CM
- Install CFM CSDs
- Copy version-specific SafeLogic jars into the activated CFM parcel

What the scripts do not do:

- Enable OS FIPS after the fact
- Enable Auto-TLS
- Configure real certificate TLS
- Deploy CDP Base services in CM
- Deploy ZooKeeper automatically
- Deploy NiFi/NiFi Registry automatically
- Configure Kerberos/Ranger/LDAP

## Troubleshooting

Logs are written to:

```bash
/var/log/cloudera-bootstrap/
```

Useful checks:

```bash
cat /proc/sys/crypto/fips_enabled
java -version
systemctl status postgresql-14 --no-pager
systemctl status cloudera-scm-server --no-pager
systemctl status cloudera-scm-agent --no-pager
ss -plnt | egrep '5432|7180|7182'
ls -lh /opt/cloudera/csd
ls -lh /opt/cloudera/parcels/CFM-*/TOOLKIT/lib | egrep 'bctls|ccj|bc'
```

