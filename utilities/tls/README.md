# Manual TLS Utilities for CFM FIPS Installs

These utilities generate host private keys, CSRs, signed certificates, PKCS12 keystores, and PKCS12 truststores for manual TLS on Cloudera Flow Management hosts.

The default output format is **PKCS12**, not JKS. This matters for FIPS. Cloudera's CFM documentation states that JKS is not FIPS compliant by default, and NiFi/NiFi Registry TLS store types can be `PKCS12`, `JKS`, or `BCFKS`. Use `PKCS12` or `BCFKS` for FIPS-oriented deployments.

## Files

```text
utilities/tls/
  tls.env.example
  hosts.csv.example
  01_generate_keys_csrs.sh
  02_create_demo_ca.sh
  03_sign_csrs_with_demo_ca.sh
  04_build_pkcs12_stores.sh
  05_optional_convert_to_bcfks.sh
  06_validate_artifacts.sh
```

## Setup

Copy the examples:

```bash
cd /root/cfm_fips_install/utilities/tls
cp tls.env.example tls.env
cp hosts.csv.example hosts.csv
vi tls.env
vi hosts.csv
```

The `hosts.csv` format is:

```text
host_id,common_name,san_dns,san_ip
```

Use semicolons for multiple SANs:

```text
nifi-agent-1,ip-10-0-11-156.us-east-2.compute.internal,ip-10-0-11-156.us-east-2.compute.internal;localhost,10.0.11.156;127.0.0.1
```

## Enterprise CA flow

Use this flow when a real internal CA will sign your certificates.

```bash
./01_generate_keys_csrs.sh
```

Send the generated CSRs to your certificate team:

```text
$TLS_OUTPUT_DIR/csr/<host_id>.csr
```

When the CA returns signed certificates, place them here:

```text
$TLS_OUTPUT_DIR/signed/<host_id>.crt
```

Put the CA chain here:

```text
$TLS_CA_CHAIN_FILE
```

Default:

```text
/root/cfm_tls_artifacts/ca/ca-chain.pem
```

Then build stores:

```bash
./04_build_pkcs12_stores.sh
./06_validate_artifacts.sh
```

## Demo CA flow

Use this only for lab testing.

```bash
./01_generate_keys_csrs.sh
./02_create_demo_ca.sh
./03_sign_csrs_with_demo_ca.sh
./04_build_pkcs12_stores.sh
./06_validate_artifacts.sh
```

## Output per host

For each `host_id`, the utility creates:

```text
/root/cfm_tls_artifacts/private/<host_id>.key
/root/cfm_tls_artifacts/csr/<host_id>.csr
/root/cfm_tls_artifacts/signed/<host_id>.crt
/root/cfm_tls_artifacts/certs/<host_id>-fullchain.pem
/root/cfm_tls_artifacts/stores/<host_id>-keystore.p12
/root/cfm_tls_artifacts/stores/<host_id>-truststore.p12
/root/cfm_tls_artifacts/stores/<host_id>-passwords.txt
```

## CM values for NiFi

For a NiFi node, use the host-specific files:

```properties
nifi.security.keystore=/root/cfm_tls_artifacts/stores/<host_id>-keystore.p12
nifi.security.keystoreType=PKCS12
nifi.security.keystorePasswd=<TLS_KEYSTORE_PASSWORD>
nifi.security.keyPasswd=<TLS_KEYSTORE_PASSWORD>
nifi.security.truststore=/root/cfm_tls_artifacts/stores/<host_id>-truststore.p12
nifi.security.truststoreType=PKCS12
nifi.security.truststorePasswd=<TLS_TRUSTSTORE_PASSWORD>
nifi.security.needClientAuth=true
```

In Cloudera Manager, set these through the NiFi TLS/SSL fields if exposed, or through the NiFi `nifi.properties` safety valve if needed.

## CM values for NiFi Registry

For NiFi Registry, use the host-specific files:

```properties
nifi.registry.security.keystore=/root/cfm_tls_artifacts/stores/<host_id>-keystore.p12
nifi.registry.security.keystoreType=PKCS12
nifi.registry.security.keystorePasswd=<TLS_KEYSTORE_PASSWORD>
nifi.registry.security.keyPasswd=<TLS_KEYSTORE_PASSWORD>
nifi.registry.security.truststore=/root/cfm_tls_artifacts/stores/<host_id>-truststore.p12
nifi.registry.security.truststoreType=PKCS12
nifi.registry.security.truststorePasswd=<TLS_TRUSTSTORE_PASSWORD>
nifi.registry.security.needClientAuth=true
```

## Optional BCFKS

PKCS12 is the default because it is supported by NiFi/NiFi Registry and is easier to generate with standard tools. If you want to attempt BCFKS conversion, set this in `tls.env`:

```bash
export TLS_CREATE_BCFKS=true
```

Then run:

```bash
./05_optional_convert_to_bcfks.sh
```

This requires Java/keytool to support `BCFKS` with the configured SafeLogic provider modules. If conversion fails, continue with PKCS12 unless your security team specifically requires BCFKS.

## Notes

* Do not use JKS for a FIPS-oriented NiFi deployment.
* Keep private keys under `TLS_OUTPUT_DIR/private` protected. The scripts use `chmod 600`.
* Use the same CA chain in all truststores so NiFi nodes, NiFi Registry, and clients trust each other.
* Make sure each certificate has SAN entries for the exact hostnames used by browsers, Cloudera Manager, and service-to-service calls.
