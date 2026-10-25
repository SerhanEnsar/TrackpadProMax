#!/bin/sh
# Creates a self-signed "TrackpadProMax Local Signing" code-signing identity in
# the login keychain. build-app.sh uses it automatically.
#
# Why: ad-hoc signatures change on every build, and macOS ties the
# Accessibility permission to the signature, so each rebuild silently loses
# the permission. A stable certificate keeps the permission across rebuilds.
#
# Remove it any time in Keychain Access (search "TrackpadProMax Local Signing").
set -eu
NAME="TrackpadProMax Local Signing"
if security find-identity -p codesigning | grep -q "$NAME"; then
    echo "\"$NAME\" already exists."
    exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.conf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:tpm
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P tpm -T /usr/bin/codesign
echo "Created \"$NAME\"."
