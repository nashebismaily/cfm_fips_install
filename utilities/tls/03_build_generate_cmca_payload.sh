#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_root
require_cmd python3

mkdir -p "$AUTO_TLS_PAYLOAD_DIR"
OUT="${AUTO_TLS_PAYLOAD_DIR}/generateCmca.json"

python3 - "$OUT" <<'PY'
import csv, json, os, sys
out=sys.argv[1]
hosts_csv=os.environ.get('HOSTS_CSV','./hosts.csv')
keys_dir=os.environ['AUTO_TLS_KEYS_DIR']
certs_dir=os.environ['AUTO_TLS_CERTS_DIR']
key_suffix=os.environ.get('HOST_KEY_SUFFIX','-key.pem')
cert_suffix=os.environ.get('HOST_CERT_SUFFIX','.pem')
cm=os.environ['CM_HOST_FQDN']

def rows():
    with open(hosts_csv, newline='') as f:
        for row in csv.reader(line for line in f if line.strip() and not line.lstrip().startswith('#')):
            if len(row) < 1: continue
            h=row[0].strip()
            if h: yield h

host_certs=[]
for h in rows():
    host_certs.append({
        'hostname': h,
        'certificate': f'{certs_dir}/{h}{cert_suffix}',
        'key': f'{keys_dir}/{h}{key_suffix}',
    })

if not any(x['hostname'] == cm for x in host_certs):
    raise SystemExit(f'CM_HOST_FQDN {cm} is not present in hosts.csv. Add it because cmHostCert/cmHostKey and hostCerts must include the CM host.')

payload={
    'location': os.environ['AUTO_TLS_LOCATION'],
    'customCA': True,
    'interpretAsFilenames': True,
    'cmHostCert': f"{certs_dir}/{cm}{cert_suffix}",
    'cmHostKey': f"{keys_dir}/{cm}{key_suffix}",
    'caCert': os.environ['AUTO_TLS_CA_CHAIN_FILE'],
    'keystorePasswd': os.environ['AUTO_TLS_KEY_PASSWORD_FILE'],
    'truststorePasswd': os.environ['AUTO_TLS_TRUSTSTORE_PASSWORD_FILE'],
    'hostCerts': host_certs,
    'configureAllServices': os.environ.get('CONFIGURE_ALL_SERVICES','true'),
    'sshPort': int(os.environ.get('SSH_PORT','22')),
    'userName': os.environ.get('SSH_USER','root'),
}
trusted=os.environ.get('AUTO_TLS_TRUSTED_CA_CERTS_FILE','').strip()
if trusted:
    payload['trustedCaCerts']=trusted
ssh_pass=os.environ.get('SSH_PASSWORD','')
ssh_key_file=os.environ.get('SSH_PRIVATE_KEY_FILE','')
if ssh_pass:
    payload['password']=ssh_pass
elif ssh_key_file:
    with open(ssh_key_file) as f:
        payload['privateKey']=''.join(line.rstrip('\n')+'\\n' for line in f if line.strip())
else:
    raise SystemExit('Set SSH_PASSWORD or SSH_PRIVATE_KEY_FILE in tls.env')

with open(out,'w') as f:
    json.dump(payload, f, indent=2)
    f.write('\n')
print(out)
PY

chown cloudera-scm:cloudera-scm "$OUT" 2>/dev/null || true
chmod 600 "$OUT"
echo "[OK] Wrote generateCmca payload: $OUT"
