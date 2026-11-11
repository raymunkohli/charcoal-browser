#!/usr/bin/env bash
# Use a persistent private release key so manual APK updates preserve the profile.
set -euo pipefail
umask 077
kit=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
version=160.0
unsigned=${1:-$kit/dist/CharcoalBrowser-$version-arm64-unsigned.apk}
[[ -f "$unsigned" ]] || { echo "Unsigned APK missing: $unsigned" >&2; exit 1; }
state=${MOZBUILD_STATE_PATH:-$HOME/.mozbuild}
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$state/android-sdk-linux}}
# Locate installed build tools with all three programs in the same version.
build_tools=
while IFS= read -r candidate; do
    if [[ -x "$candidate/apksigner" && -x "$candidate/zipalign" && -x "$candidate/aapt" ]]; then build_tools=$candidate; break; fi
done < <(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -Vr)
[[ -n "$build_tools" ]] || { echo 'Set ANDROID_HOME to the SDK containing Android Build Tools.' >&2; exit 1; }
jdk=${JAVA_HOME:-}
if [[ ! -x "$jdk/bin/keytool" || -z "$jdk" ]]; then
    jdk=$(find "$state/jdk" -mindepth 1 -maxdepth 1 -type d -name 'jdk-*' 2>/dev/null | sort -Vr | head -n 1) || true
fi
if [[ -n "$jdk" && -x "$jdk/bin/keytool" ]]; then
    export JAVA_HOME="$jdk" PATH="$jdk/bin:$PATH"
elif ! command -v keytool >/dev/null; then
    echo 'Java keytool is missing. Run the build first or set JAVA_HOME.' >&2; exit 1
fi
key_path=${CHARCOAL_KEYSTORE:-${XDG_DATA_HOME:-$HOME/.local/share}/charcoal-browser/release.p12}
key_dir=$(dirname -- "$key_path")
mkdir -p -- "$key_dir" "$kit/dist"
exec 8>"$key_path.lock"
flock -n 8 || { echo 'Another process is signing with this key.' >&2; exit 1; }
tmp=$(mktemp -d "$kit/dist/.sign.XXXXXXXX")
key_tmp=
cleanup() { rm -rf -- "$tmp"; if [[ -n "$key_tmp" ]]; then rm -rf -- "$key_tmp"; fi; }
trap cleanup EXIT
badging=$("$build_tools/aapt" dump badging "$unsigned")
[[ "$badging" == *"package: name='app.charcoal.browser'"* && "$badging" == *"versionName='$version'"* && "$badging" == *"native-code: 'arm64-v8a'"* ]] || { echo 'Unexpected package, version or CPU architecture.' >&2; exit 1; }
[[ "$badging" != *"application-debuggable"* ]] || { echo 'Expected a non-debuggable release.' >&2; exit 1; }
"$build_tools/aapt" dump xmltree "$unsigned" AndroidManifest.xml > "$tmp/manifest.txt"
if grep -Eq 'android:sharedUserId[(=]' "$tmp/manifest.txt"; then echo 'Unexpected shared UID.' >&2; exit 1; fi
"$build_tools/zipalign" -P 16 -f 4 "$unsigned" "$tmp/aligned.apk"
if [[ ! -f "$key_path" ]]; then
    key_tmp=$(mktemp -d "$key_dir/.create-key.XXXXXXXX")
    echo "Creating your private update key at $key_path. Choose and retain the keystore password."
    keytool -genkeypair -storetype PKCS12 -keystore "$key_tmp/release.p12" -alias charcoal -keyalg RSA -keysize 3072 -sigalg SHA256withRSA -validity 10000 -dname 'CN=Charcoal Browser'
    chmod 600 "$key_tmp/release.p12"
    mv -- "$key_tmp/release.p12" "$key_path"
fi
password_args=()
if [[ -n ${CHARCOAL_KEYSTORE_PASSWORD:-} ]]; then
    password_args=(--ks-pass env:CHARCOAL_KEYSTORE_PASSWORD --key-pass env:CHARCOAL_KEYSTORE_PASSWORD)
fi
"$build_tools/apksigner" sign --ks "$key_path" --ks-type PKCS12 --ks-key-alias charcoal "${password_args[@]}" --out "$tmp/signed.apk" "$tmp/aligned.apk"
"$build_tools/apksigner" verify --verbose --print-certs "$tmp/signed.apk"
"$build_tools/zipalign" -c -P 16 4 "$tmp/signed.apk"
output="$kit/dist/CharcoalBrowser-$version-arm64.apk"
mv -f -- "$tmp/signed.apk" "$output"
sha256sum "$output"
echo "Installable APK: $output"
