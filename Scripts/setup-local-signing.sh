#!/bin/zsh
set -euo pipefail

identity_name="LectureCaption Stable Local Signing"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/lecture-caption-signing.XXXXXX")"
trap 'rm -rf "${temporary_directory}"' EXIT

touch "${temporary_directory}/signing-probe"
if codesign --force --sign "${identity_name}" "${temporary_directory}/signing-probe" >/dev/null 2>&1; then
    print "Local signing identity already exists: ${identity_name}"
    exit 0
fi

export_password="$(openssl rand -hex 24)"

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "${temporary_directory}/key.pem" \
    -out "${temporary_directory}/certificate.pem" \
    -subj "/CN=${identity_name}" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    >/dev/null 2>&1

openssl pkcs12 -export \
    -inkey "${temporary_directory}/key.pem" \
    -in "${temporary_directory}/certificate.pem" \
    -out "${temporary_directory}/identity.p12" \
    -passout "pass:${export_password}" \
    >/dev/null 2>&1

login_keychain="$(security default-keychain -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
security import "${temporary_directory}/identity.p12" \
    -k "${login_keychain}" \
    -P "${export_password}" \
    -T /usr/bin/codesign \
    >/dev/null

codesign --force --sign "${identity_name}" "${temporary_directory}/signing-probe" >/dev/null
print "Created local signing identity: ${identity_name}"
