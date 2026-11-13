#!/usr/bin/env bash
# Retain the Fenix release APKs and their unmodified metadata for a packaging retry.
set -euo pipefail
obj="${CHARCOAL_WORKDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/charcoal-browser/160.0}/firefox/obj-charcoal-artifact"
python3 - "$obj" <<'PYTHON'
from pathlib import Path
import json
import shutil
import sys

build = Path(sys.argv[1]) / 'gradle/build'
out = Path('dist/recoverable-build')
for path in sorted(build.glob('**/outputs/apk/release/output-metadata.json')):
    meta = json.loads(path.read_text())
    if meta.get('applicationId') != 'app.charcoal.browser':
        continue
    out.mkdir(parents=True, exist_ok=True)
    print(path.read_text())
    shutil.copyfile(path, out / path.name)
    for apk in sorted(path.parent.glob('*.apk')):
        if apk.is_file():
            shutil.copyfile(apk, out / apk.name)
            print(f'Retained {apk.name} ({apk.stat().st_size} bytes)')
PYTHON
