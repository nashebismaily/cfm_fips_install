# Cloudera Auto-TLS Use Case 3 Utilities

These utilities support Cloudera Manager Auto-TLS **Use Case 3: Enabling Auto-TLS with Existing Certificates**. This is the flow where certificates are signed by your existing CA, staged on the Cloudera Manager server, and enabled through the `generateCmca` API.

Everything is driven by variables in `tls.env` and host inventory in `hosts.csv`.

## What is configurable

`tls.env` controls:

- Auto-TLS work directory, default `/tmp/auto-tls`
- CM Auto-TLS location, default `/opt/cloudera/AutoTLS`
- CM API host, protocol, port, API version, username, and password
- SSH user, SSH password or SSH private key file
- keystore and truststore passwords
- CA chain path
- whether to generate keys/CSRs or use customer-provided artifacts
- key size, digest, and CSR subject values

`hosts.csv` controls any number of hosts. Use one row per host:

```text
hostname,cn,san_dns,san_ip
```

`san_dns` and `san_ip` can contain pipe-separated values.

## Two supported modes

### Mode A: Generate keys and CSRs here

Set:

```bash
export GENERATE_KEYS_AND_CSRS='true'
```

Run:

```bash
sudo -E ./00_prepare_dirs.sh
sudo -E ./01_generate_keys_csrs.sh
```

Send the CSRs from:

```text
/tmp/auto-tls/csrs/
```

Ask the CA to preserve SAN values and include both Extended Key Usage values:

```text
TLS Web Server Authentication
TLS Web Client Authentication
```

When the CA returns certs, place each cert here:

```text
/tmp/auto-tls/certs/<hostname>.pem
```

Place the CA chain here:

```text
/tmp/auto-tls/ca-certs/ca-chain.pem
```

### Mode B: Customer provides keys and certs

Set:

```bash
export GENERATE_KEYS_AND_CSRS='false'
```

Skip `01_generate_keys_csrs.sh`. Place files directly:

```text
/tmp/auto-tls/keys/<hostname>-key.pem
/tmp/auto-tls/certs/<hostname>.pem
/tmp/auto-tls/ca-certs/ca-chain.pem
```

The hostnames must match the first column in `hosts.csv`.

## Validate certs

Run:

```bash
sudo -E ./02_validate_signed_certs.sh
```

This checks:

- host key exists
- host cert exists
- CA chain exists
- cert includes serverAuth and clientAuth EKUs
- cert/key pair match
- hostname is present in DNS SAN, with warning if not found

## Build the generateCmca payload

Run:

```bash
sudo -E ./03_build_generate_cmca_payload.sh
cat /tmp/auto-tls/payload/generateCmca.json
```

The JSON includes:

- `location`
- `customCA=true`
- `interpretAsFilenames=true`
- `cmHostCert`
- `cmHostKey`
- `caCert`
- `keystorePasswd`
- `truststorePasswd`
- `hostCerts` for every host in `hosts.csv`
- `configureAllServices`
- SSH settings

## Run the API

Run:

```bash
sudo -E ./04_run_generate_cmca.sh
```

Or print the curl command:

```bash
./05_print_generate_cmca_curl.sh
```

The API endpoint is built from variables:

```text
${CM_API_SCHEME}://${CM_HOST_FQDN}:${CM_API_PORT}/api/${CM_API_VERSION}/cm/commands/generateCmca
```

For a fresh non-TLS CM install this is usually:

```text
http://<CM_FQDN>:7180/api/v41/cm/commands/generateCmca
```

For an existing TLS-enabled CM, use HTTPS and the TLS port.

## After the API succeeds

Restart CM Server and agents:

```bash
sudo -E ./06_post_autotls_restart.sh
```

Then restart agents on every other host:

```bash
systemctl restart cloudera-scm-supervisord cloudera-scm-agent
```

After Auto-TLS is active, CM UI/API should move to the TLS port.

## Notes

- Passwords must be more than 12 characters and should not contain special characters for this Cloudera flow.
- Every host in the cluster needs a cert/key entry in `hostCerts`, including the CM host.
- The CM host must also appear in `hosts.csv`.
- The CA chain must be consistent with the host certs. If intermediate CA chains vary, include the entire chain in each host certificate file.
- The SSH user must have NOPASSWD sudo across the cluster because CM cannot answer a sudo password prompt.
