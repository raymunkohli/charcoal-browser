"""Select the release Fenix APK for the requested CPU and check native payloads."""
import json
from pathlib import Path
import sys
from zipfile import ZipFile


def select_apk(object_dir: Path, version: str) -> Path:
    matches = []
    for metadata in object_dir.glob('gradle/build/**/outputs/apk/release/output-metadata.json'):
        build = json.loads(metadata.read_text())
        if build.get('applicationId') != 'app.charcoal.browser' or build.get('variantName') != 'release':
            continue
        for output in build['elements']:
            abis = [it.get('value') or it.get('identifier') for it in output['filters'] if it['filterType'] == 'ABI']
            if abis == ['arm64-v8a'] and output['versionName'] == version and output['versionCode'] > 0:
                matches.append(metadata.parent / output['outputFile'])
    if len(matches) != 1:
        raise SystemExit(f'Expected one ARM64 Charcoal release, found {len(matches)} in {object_dir}.')
    apk = matches[0]
    with ZipFile(apk) as package:
        for resource in ['classes.dex', 'resources.arsc', 'AndroidManifest.xml', 'lib/arm64-v8a/libxul.so']:
            if package.getinfo(resource).file_size == 0:
                raise SystemExit(f'Empty component {resource} in {apk}.')
        if not any(name.endswith('omni.ja') for name in package.namelist()):
            raise SystemExit(f'Missing the Gecko runtime archive in {apk}.')
    return apk.resolve()


if __name__ == '__main__':
    print(select_apk(Path(sys.argv[1]), sys.argv[2]))
