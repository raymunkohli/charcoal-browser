#!/usr/bin/env bash
set -euo pipefail
# Firefox uses its own toolchain. Reclaim space on the disposable hosted runner.
if [[ ${GITHUB_ACTIONS:-} == true && ${RUNNER_OS:-} == Linux ]]; then
    df -h "$GITHUB_WORKSPACE"
    sudo rm -rf /usr/share/dotnet /usr/local/.ghcup /opt/ghc /usr/local/share/powershell /opt/hostedtoolcache/CodeQL
    if [[ ${ANDROID_HOME:-} == /usr/local/lib/android/sdk ]]; then
        sudo rm -rf "$ANDROID_HOME/ndk" "$ANDROID_HOME/system-images" "$ANDROID_HOME/emulator"
    fi
    df -h "$GITHUB_WORKSPACE"
fi
