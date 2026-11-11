"""Find Mozilla's ARM64 Android release within its official archive directory."""
from collections import deque
from html.parser import HTMLParser
from pathlib import Path
import shutil
import sys
from urllib.parse import urljoin
from urllib.request import urlopen


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []

    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            self.hrefs.append(dict(attrs).get('href', ''))


base = 'https://archive.mozilla.org/pub/fenix/releases/160.0/'
queue = deque([base]); seen = {base}
while queue and len(seen) < 25:
    directory = queue.popleft()
    with urlopen(directory, timeout=30) as response:
        links = Links(); links.feed(response.read().decode())
    for href in links.hrefs:
        url = urljoin(directory, href)
        if not url.startswith(base) or any(cpu in url for cpu in ('x86', 'armeabi-v7a')):
            continue
        if url.endswith('.apk') and 'arm64-v8a' in url:
            with urlopen(url, timeout=90) as response, Path(sys.argv[1]).open('wb') as out:
                shutil.copyfileobj(response, out)
            print('Downloaded the ARM64 Firefox 160.0 release from Mozilla.')
            sys.exit(0)
        if url.endswith('/') and url not in seen:
            seen.add(url); queue.append(url)
raise SystemExit('ARM64 release APK was not found in the Mozilla archive.')
