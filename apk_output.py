"""Identify the ARM64 browser using its manifest and native payload."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
from zipfile import ZipFile


def find_aapt():
    default_sdk = Path(os.environ.get("MOZBUILD_STATE_PATH", Path.home() / ".mozbuild")) / "android-sdk-linux"
    for sdk in (os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT"), default_sdk):
        if sdk:
            tools = Path(sdk) / "build-tools"
            for candidate in sorted(tools.glob("*/aapt"), reverse=True):
                if os.access(candidate, os.X_OK):
                    return str(candidate)
    aapt = shutil.which("aapt")
    if not aapt:
        raise SystemExit("Android Build Tools aapt is required to read the packaged manifest.")
    return aapt


def select_apk(object_dir: Path, version: str) -> Path:
    matches = []
    aapt = find_aapt()
    outputs = sorted((object_dir / "gradle/build").glob("**/outputs/apk/release/*.apk"))
    if not outputs:
        raise SystemExit("No release APKs found under " + str(object_dir / "gradle/build"))
    for apk in outputs:
        result = subprocess.run([aapt, "dump", "badging", str(apk)], text=True, capture_output=True)
        if result.returncode:
            raise SystemExit(f"Cannot inspect manifest of {apk}: {result.stderr}")
        header = next((line for line in result.stdout.splitlines() if line.startswith("package: ")), "")
        fields = dict(re.findall(r"([A-Za-z]+)='([^']*)'", header))
        print(f"{apk}: {header}", file=sys.stderr)
        if fields.get("name") != "app.charcoal.browser" or fields.get("versionName") != version:
            continue
        if not fields.get("versionCode", "").isdigit() or int(fields["versionCode"]) <= 0:
            continue
        with ZipFile(apk) as package:
            sizes = {info.filename: info.file_size for info in package.infolist()}
        abis = {name.split("/")[1] for name in sizes
                if name.startswith("lib/") and name.endswith(".so") and name.count("/") == 2}
        print(f"  Packaged native ABIs: {sorted(abis)}", file=sys.stderr)
        if abis != {"arm64-v8a"}:
            continue
        needed = ["AndroidManifest.xml", "resources.arsc", "classes.dex", "lib/arm64-v8a/libxul.so"]
        if any(not sizes.get(name) for name in needed) or not any(
                size > 0 and name.endswith("omni.ja") for name, size in sizes.items()):
            continue
        matches.append(apk)
    if len(matches) != 1:
        raise SystemExit(f"Expected exactly one complete ARM64 release, found {len(matches)}.")
    return matches[0].resolve()


if __name__ == "__main__":
    print(select_apk(Path(sys.argv[1]), sys.argv[2]))
