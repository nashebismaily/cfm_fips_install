# Cloudera Auto-TLS Utilities

These utilities generate encrypted host private keys, CSRs, certificates, PKCS12 stores, validate prerequisites, and call the Cloudera Manager `generateCmca` API for Auto-TLS with a custom CA.

This version uses encrypted host private keys. The same value in `AUTO_TLS_HOST_KEY_PASSWORD` is used by `01_generate_keys_csrs.sh` to encrypt the host keys and by `07_enable_autotls.sh` to create the per-host password files Cert Manager expects:

```text
/opt/cloudera/AutoTLS/hosts-key-store/<hostname>/cm-auto-host_key.pw
```

## Files

```text
utilities/tls/
  tls.env.example
  hosts.csv.example
  00_prepare_dirs.sh
  01_generate_keys_csrs.sh
  02_create_demo_ca.sh
  03_sign_csrs_with_demo_ca.sh
  04_build_pkcs12_stores.sh
  05_validate_autotls_prereqs.sh
  06_validate_artifacts.sh
  07_enable_autotls.sh
```

## Configure

```bash
cd /root/cfm_fips_install/utilities/tls
cp tls.env.example tls.env
cp hosts.csv.example hosts.csv
vi tls.env
vi hosts.csv
```

The hosts file format is:

```csv
host_id,ip_sans,dns_sans
ip-10-0-3-31.us-east-2.compute.internal,10.0.3.31,ip-10-0-3-31.us-east-2.compute.internal
ip-10-0-11-156.us-east-2.compute.internal,10.0.11.156,ip-10-0-11-156.us-east-2.compute.internal
```

`host_id` must match the hostname Cloudera Manager knows for the host. The Cloudera Manager host must be included.

## Required SSH setup

Auto-TLS needs SSH access from the Cloudera Manager host to each host. The tested flow uses a dedicated user, for example `autotls`, with passwordless SSH and passwordless sudo.

```bash
export AUTO_TLS_SSH_USER="autotls"
export AUTO_TLS_SSH_KEY_FILE="/home/autotls/.ssh/id_rsa"
```

Validate SSH before calling Auto-TLS:

```bash
./05_validate_autotls_prereqs.sh
```

## Run sequence

```bash
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

After `07` succeeds:

```bash
tail -f /var/log/cloudera-scm-server/cloudera-scm-server.log
tail -f /var/log/cloudera-scm-agent/certmanager.log
systemctl restart cloudera-scm-server
systemctl restart cloudera-scm-agent
```

Then access Cloudera Manager at:

```text
https://<CM_HOST>:7183
```

Restart Cloudera Management Service and cluster services from the CM UI.

## Outputs

```text
/opt/cloudera/AutoTLS/artifacts/keys/<host_id>-key.pem
/opt/cloudera/AutoTLS/artifacts/csrs/<host_id>-csr.pem
/opt/cloudera/AutoTLS/artifacts/certs/<host_id>-cert.pem
/opt/cloudera/AutoTLS/artifacts/fullchains/<host_id>-fullchain.pem
/opt/cloudera/AutoTLS/artifacts/stores/<host_id>-keystore.p12
/opt/cloudera/AutoTLS/artifacts/stores/<host_id>-truststore.p12
/opt/cloudera/AutoTLS/artifacts/payload/generate_cmca_payload.json
```

## Real CA workflow

For a real customer CA, run only steps `00` and `01`, send the CSRs to the CA team, and place the returned certs in:

```text
/opt/cloudera/AutoTLS/artifacts/certs/<host_id>-cert.pem
```

Place the CA chain here:

```text
/opt/cloudera/AutoTLS/artifacts/ca/ca-chain.pem
```

Then continue with:

```bash
./04_build_pkcs12_stores.sh
./06_validate_artifacts.sh
./05_validate_autotls_prereqs.sh
./07_enable_autotls.sh
```


## Host private key mode

This utility set supports both encrypted and unencrypted host private keys.

For customer/live runs with encrypted host keys:

```bash
export AUTO_TLS_ENCRYPT_HOST_KEYS="true"
export AUTO_TLS_HOST_KEY_PASSWORD="ChangeMe12345"
```

In this mode, `01_generate_keys_csrs.sh` encrypts host private keys and `07_enable_autotls.sh` writes the per-host `cm-auto-host_key.pw` files required by Cloudera Cert Manager.

For unencrypted host keys:

```bash
export AUTO_TLS_ENCRYPT_HOST_KEYS="false"
```

In this mode, `01_generate_keys_csrs.sh` generates unencrypted host private keys, `04` and `06` do not use a private-key passphrase, and `07` removes stale per-host key password files before submitting the Auto-TLS command.
