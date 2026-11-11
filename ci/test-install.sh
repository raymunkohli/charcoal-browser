#!/usr/bin/env bash
# Install the unpacked Actions artifact on an emulator that supports ARM64 apps.
set -euo pipefail
apk=$1
sdk=${ANDROID_HOME:?Android SDK missing}
export PATH="$sdk/platform-tools:$sdk/emulator:$sdk/cmdline-tools/latest/bin:$PATH"
image='system-images;android-35;google_apis;x86_64'
sdkmanager "$image" 'emulator' 'platform-tools' >/dev/null
printf 'no\n' | avdmanager create avd --name charcoal --package "$image" --force >/dev/null
sudo chmod a+rw /dev/kvm
emulator -avd charcoal -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect -cores 2 > "$RUNNER_TEMP/emulator.log" 2>&1 &
emu_pid=$!
trap 'kill "$emu_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 90); do
    alive=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
    [[ "$alive" == 1 ]] && break
    if ! kill -0 "$emu_pid" 2>/dev/null; then tail -40 "$RUNNER_TEMP/emulator.log"; exit 1; fi
    sleep 4
done
[[ $(adb shell getprop sys.boot_completed | tr -d '\r') == 1 ]]
abi=$(adb shell getprop ro.product.cpu.abilist | tr -d '\r'); echo "Emulator ABIs: $abi"
[[ $abi == *arm64-v8a* ]]
adb shell wm dismiss-keyguard || true
adb shell settings put system screen_off_timeout 600000
if python3 ci/official-apk.py "$RUNNER_TEMP/official.apk"; then
    adb install "$RUNNER_TEMP/official.apk"
    adb shell pm path org.mozilla.firefox | grep -F 'package:'
else
    echo 'Mozilla archive unavailable for the separate official-app installation.'
fi
adb install "$apk"
pkg=app.charcoal.browser
adb shell pm path "$pkg" | grep -F 'package:'
# A light system preference exercises the app's first-run dark default.
adb shell cmd uimode night no
for expected in 'fx_mobile_private_surface:#ff000000' 'fx_mobile_private_surface_container:#ff161616'; do
    role=${expected%%:*}; rgb=${expected#*:}
    if value=$(adb shell cmd overlay lookup "$pkg" "$pkg:color/$role" 2>/dev/null); then
        value=$(printf '%s' "$value" | tr -d '\r' | tr '[:upper:]' '[:lower:]')
        if [[ $value == \#* ]]; then
            [[ $value == "$rgb" ]] || { echo "Unexpected installed colour $role=$value" >&2; exit 1; }
            echo "Verified installed private colour $role=$value"
        fi
    fi
done
adb logcat -c
adb shell am start -W -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p "$pkg"
sleep 6
adb shell pidof "$pkg" | grep -E '[0-9]+'
adb shell dumpsys activity activities | grep -E 'ResumedActivity|topResumedActivity' | grep -F "$pkg" | head -2
adb shell am start -W -a org.mozilla.fenix.OPEN_PRIVATE_TAB -n "$pkg/org.mozilla.fenix.IntentReceiverActivity"
sleep 6
adb shell pidof "$pkg" | grep -E '[0-9]+'
adb shell dumpsys activity activities | grep -E 'ResumedActivity|topResumedActivity' | grep -F "$pkg" | head -2
adb logcat -b crash -d > "$RUNNER_TEMP/charcoal-crashes.txt"
if grep -F "$pkg" "$RUNNER_TEMP/charcoal-crashes.txt"; then exit 1; fi
if adb shell pm path org.mozilla.firefox | grep -q '^package:'; then echo 'Coexistence verified with official Firefox installed.'; fi
echo 'ARM64 release installed and launched, including the private-tab shortcut intent.'
