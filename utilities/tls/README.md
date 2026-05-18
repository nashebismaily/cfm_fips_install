# Manual TLS Utilities for CFM / NiFi / NiFi Registry

This folder generates host-specific private keys, CSRs, certificates, PKCS12 keystores, and PKCS12 truststores for a manual TLS deployment.

This is not Cloudera Auto-TLS.

## Files

```text
utilities/tls/
  tls.env.example
  hosts.csv.example
  lib.sh
  00_prepare_dirs.sh
  01_generate_keys_csrs.sh
  02_create_demo_ca.sh
  03_sign_csrs_with_demo_ca.sh
  04_build_pkcs12_stores.sh
  06_validate_artifacts.sh
```

## Configure

```bash
cd /root/cfm_fips_install/utilities/tls
cp tls.env.example tls.env
cp hosts.csv.example hosts.csv
vi tls.env
vi hosts.csv
```

For two hosts:

```csv
host_id,cn,dns_sans,ip_sans
manager,ip-10-0-3-31.us-east-2.compute.internal,ip-10-0-3-31.us-east-2.compute.internal;ip-10-0-3-31,10.0.3.31
agent,ip-10-0-11-156.us-east-2.compute.internal,ip-10-0-11-156.us-east-2.compute.internal;ip-10-0-11-156,10.0.11.156
```

## Generate CSRs for a real CA

```bash
source ./tls.env
./00_prepare_dirs.sh
./01_generate_keys_csrs.sh
```

Send these files to the CA team:

```text
/root/cfm_tls_artifacts/csrs/manager-csr.pem
/root/cfm_tls_artifacts/csrs/agent-csr.pem
```

When the CA returns certs, save them as:

```text
/root/cfm_tls_artifacts/certs/manager-cert.pem
/root/cfm_tls_artifacts/certs/agent-cert.pem
```

Save the issuing CA chain as:

```text
/root/cfm_tls_artifacts/ca/ca-chain.pem
```

Then build stores:

```bash
./04_build_pkcs12_stores.sh
./06_validate_artifacts.sh
```

## Demo CA flow

For a lab/demo only:

```bash
source ./tls.env
./00_prepare_dirs.sh
./01_generate_keys_csrs.sh
./02_create_demo_ca.sh
./03_sign_csrs_with_demo_ca.sh
./04_build_pkcs12_stores.sh
./06_validate_artifacts.sh
```

## Outputs

```text
/root/cfm_tls_artifacts/keys/<host_id>-key.pem
/root/cfm_tls_artifacts/csrs/<host_id>-csr.pem
/root/cfm_tls_artifacts/certs/<host_id>-cert.pem
/root/cfm_tls_artifacts/fullchains/<host_id>-fullchain.pem
/root/cfm_tls_artifacts/stores/<host_id>-keystore.p12
/root/cfm_tls_artifacts/stores/<host_id>-truststore.p12
```

Use `PKCS12` in CM for keystore/truststore type.
