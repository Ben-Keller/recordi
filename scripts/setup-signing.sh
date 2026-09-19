#!/bin/bash
# One-time local signing identity. Private key lives only in the user's login Keychain.
set -euo pipefail
IDENTITY='Recordi Local Code Signing'
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
SUPPORT="$HOME/Library/Application Support/Recordi/signing"
mkdir -p "$SUPPORT"
if /usr/bin/security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$SUPPORT/certificate.pem" 2>/dev/null; then
  echo 'Reusing the existing Recordi signing certificate.'
else
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/recordi-signing.XXXXXX")"
  chmod 700 "$WORK"
  trap 'rm -rf "$WORK"' EXIT
  umask 077
  cat > "$WORK/certificate.cnf" <<'CONF'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = Recordi Local Code Signing
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONF
  /usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 \
    -config "$WORK/certificate.cnf" -keyout "$WORK/private.pem" -out "$WORK/certificate.pem" 2> "$WORK/openssl.log"
  cat "$WORK/private.pem" "$WORK/certificate.pem" > "$WORK/identity.pem"
  /usr/bin/security import "$WORK/identity.pem" -k "$KEYCHAIN" -f pemseq -t agg -x -T /usr/bin/codesign
  cp "$WORK/certificate.pem" "$SUPPORT/certificate.pem"
fi
# This stores only a public certificate fingerprint, never the private key.
/usr/bin/openssl x509 -in "$SUPPORT/certificate.pem" -noout -fingerprint -sha1 \
  | /usr/bin/sed 's/.*=//; s/://g' > "$SUPPORT/identity.txt"
printf 'Local signing identity: %s\n' "$IDENTITY"
