#!/usr/bin/env bash
# Build the tagged Fenix release for a physical ARM64 Android phone.
set -euo pipefail
umask 077
version=160.0
release_tag=FIREFOX-ANDROID_160_0_RELEASE
release_commit=2887d9de1f69c0e9776413da80e7ba0d1225dd9b
firefox_repo=https://github.com/mozilla-firefox/firefox.git
mode=artifact
unsigned_only=false
for arg in "$@"; do
    case "$arg" in
        --from-source) mode=native ;;
        --unsigned) unsigned_only=true ;;
        --help|-h) echo 'Usage: bash build.sh [--from-source] [--unsigned]'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
kit=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
work=${CHARCOAL_WORKDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/charcoal-browser/$version}
mkdir -p -- "$work"
work=$(cd -- "$work" && pwd -P)
checkout=$work/firefox
exec 9>"$work/build.lock"
flock -n 9 || { echo 'A build is already using this work directory.' >&2; exit 1; }
if [[ ! -d "$checkout/.git" ]]; then
    if [[ -e "$checkout" ]]; then echo "Choose a different CHARCOAL_WORKDIR. $checkout already exists." >&2; exit 1; fi
    clone=$(mktemp -d "$work/clone.XXXXXXXX")
    trap 'rm -rf -- "$clone"' EXIT
    git -C "$clone" init -q
    git -C "$clone" remote add origin "$firefox_repo"
    git -C "$clone" fetch --no-tags --depth=1 origin "refs/tags/$release_tag"
    actual=$(git -C "$clone" rev-parse 'FETCH_HEAD^{commit}')
    [[ "$actual" == "$release_commit" ]] || { echo "Unexpected Mozilla revision: $actual" >&2; exit 1; }
    git -C "$clone" checkout -q --detach "$release_commit"
    mv -- "$clone" "$checkout"
    trap - EXIT
fi
cd -- "$checkout"
[[ $(git rev-parse HEAD) == "$release_commit" ]] || { echo 'Cached checkout has a different revision.' >&2; exit 1; }
[[ $(<mobile/android/version.txt) == "$version" ]] || { echo 'Firefox version mismatch.' >&2; exit 1; }
if git apply --reverse --check "$kit/charcoal.patch" 2>/dev/null; then
    echo 'Theme patch already applied.'
else
    git apply --check "$kit/charcoal.patch"
    git apply "$kit/charcoal.patch"
fi
object_dir="$checkout/obj-charcoal-$mode"
export MOZCONFIG="$work/mozconfig-$mode"
cat > "$MOZCONFIG" <<EOF
ac_add_options --enable-project=mobile/android
ac_add_options --target=aarch64-linux-android
ac_add_options --disable-debug
mk_add_options MOZ_OBJDIR=@TOPSRCDIR@/obj-charcoal-$mode
EOF
if [[ $mode == artifact ]]; then
    echo 'ac_add_options --enable-artifact-builds' >> "$MOZCONFIG"
    # Mozilla uses this small historical commit to identify a native Firefox Git
    # checkout. A depth-one release checkout initially contains only its tip.
    marker=2ca566cd74d5d0863ba7ef0529a4f88b2823eb43
    if ! git cat-file -e "$marker^{commit}" 2>/dev/null; then
        git fetch --no-tags --depth=1 origin "$marker:refs/charcoal/firefox-origin"
    fi
    export MOZ_ARTIFACT_REVISION="$release_commit"
    bootstrap_target=mobile_android_artifact_mode
else
    unset MOZ_ARTIFACT_REVISION
    bootstrap_target=mobile_android
fi
./mach --no-interactive bootstrap --no-agentic-tools --application-choice="$bootstrap_target"
export ORG_GRADLE_PROJECT_versionName="$version"
if ! ./mach build; then
    if [[ $mode == artifact ]]; then echo 'If Mozilla reports an expired or missing native artifact, retry with bash build.sh --from-source.' >&2; fi
    exit 1
fi
./mach gradle :fenix:assembleRelease -PdisableDebugSigning "-PversionName=$version"
# Check the installed manifest and actual Gecko libraries in the generated APKs.
apk=$(python3 "$kit/apk_output.py" "$object_dir" "$version")
dist="$kit/dist"
mkdir -p -- "$dist"
unsigned="$dist/CharcoalBrowser-$version-arm64-unsigned.apk"
staged=$(mktemp "$dist/.unsigned.XXXXXXXX")
trap 'rm -f -- "$staged"' EXIT
cp -- "$apk" "$staged"
mv -f -- "$staged" "$unsigned"
trap - EXIT
if [[ $unsigned_only == true ]]; then
    echo "Unsigned APK: $unsigned"
else
    bash "$kit/sign.sh" "$unsigned"
fi
