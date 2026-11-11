#!/usr/bin/env bash
set -euo pipefail
umask 077
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$repo"
version=160.0
unsigned="dist/CharcoalBrowser-$version-arm64-unsigned.apk"
[[ -s $unsigned ]] || { echo 'The unsigned build is missing.' >&2; exit 1; }
work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/charcoal-sign.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
export CHARCOAL_KEYSTORE="$work/release.p12"
if [[ -n ${CHARCOAL_KEYSTORE_B64:-} && -n ${CHARCOAL_KEYSTORE_PASSWORD:-} ]]; then
    printf '%s' "$CHARCOAL_KEYSTORE_B64" | base64 --decode > "$CHARCOAL_KEYSTORE"
elif [[ -n ${CHARCOAL_KEYSTORE_B64:-} || -n ${CHARCOAL_KEYSTORE_PASSWORD:-} ]]; then
    echo 'Both signing secrets must refer to the same PKCS12 keystore.' >&2; exit 1
elif [[ -f ci/bootstrap-recipient.pem && ! -e ci/signer.sha256 && ${GITHUB_EVENT_NAME:-} == push && ${GITHUB_RUN_ATTEMPT:-1} == 1 ]]; then
    # Only the initial release provisions a key. Its backup is encrypted before
    # any bytes leave the runner. The private recipient key is held offline.
    CHARCOAL_KEYSTORE_PASSWORD=$(openssl rand -hex 32)
    export CHARCOAL_KEYSTORE_PASSWORD
    echo "::add-mask::$CHARCOAL_KEYSTORE_PASSWORD"
    keytool -genkeypair -storetype PKCS12 -keystore "$CHARCOAL_KEYSTORE" -alias charcoal -keyalg RSA -keysize 3072 -sigalg SHA256withRSA -validity 10000 -dname 'CN=Charcoal Browser' -storepass:env CHARCOAL_KEYSTORE_PASSWORD
    printf '%s\n' "$CHARCOAL_KEYSTORE_PASSWORD" > "$work/keystore-password.txt"
    mkdir -p dist/recovery
    tar -C "$work" -cf - release.p12 keystore-password.txt | openssl cms -encrypt -binary -aes-256-gcm -outform DER -out dist/recovery/signing-key.cms -recip ci/bootstrap-recipient.pem -keyopt rsa_padding_mode:oaep -keyopt rsa_oaep_md:sha256
else
    mkdir -p dist/download
    cp -- "$unsigned" dist/download/
    (cd dist/download && sha256sum ./*-unsigned.apk > SHA256SUMS)
    echo 'Unsigned artifact ready for the existing offline signing key.'
    exit 0
fi
cert=$(keytool -exportcert -storetype PKCS12 -keystore "$CHARCOAL_KEYSTORE" -alias charcoal -storepass:env CHARCOAL_KEYSTORE_PASSWORD | sha256sum | cut -d' ' -f1)
if [[ -f ci/signer.sha256 && $(<ci/signer.sha256) != "$cert" ]]; then
    echo 'The supplied key differs from the existing Charcoal Browser release key.' >&2; exit 1
fi
bash sign.sh "$unsigned"
mkdir -p dist/download
cp -- "dist/CharcoalBrowser-$version-arm64.apk" dist/download/
(cd dist/download && sha256sum ./*.apk > SHA256SUMS)
echo "Release certificate SHA-256 $cert"
if [[ -f dist/recovery/signing-key.cms ]]; then
    # The encrypted envelope is also available through Actions logs, allowing
    # the offline recipient to recover the signing key without a binary transfer.
    echo CHARCOAL_CMS_START
    base64 -w64 dist/recovery/signing-key.cms
    echo CHARCOAL_CMS_END
fi
