"""Offline Flutter frames: playwright-local python tool/capture_match_lists.py URL OUT."""
import json
from pathlib import Path
import sys
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright

url, output = sys.argv[1:]
out = Path(output)
out.mkdir(parents=True, exist_ok=True)
records = []
with sync_playwright() as p:
    browser = p.chromium.launch()
    try:
        for width, height, scale in [(w, 640, s) for s in [1, 1.6] for w in [320, 360, 390]] + [(1440, 1000, 1)]:
            for screen in ['squad', 'player']:
                page = browser.new_page(viewport={'width': width, 'height': height}, device_scale_factor=1)
                errors, blocked = [], []
                page.on('pageerror', lambda error: errors.append(str(error)))

                def local_only(route):
                    if urlparse(route.request.url).netloc == urlparse(url).netloc:
                        route.continue_()
                    else:
                        blocked.append(route.request.url)
                        route.abort()

                page.route('**/*', local_only)
                page.goto(f'{url}/?page={screen}&scale={scale}&insets=android', wait_until='networkidle')
                page.wait_for_selector('flutter-view')
                page.wait_for_timeout(2000)
                for position, delta in [('top', 0), ('middle', 280), ('bottom', 10000)] if width < 600 else [('top', 0)]:
                    if delta:
                        page.mouse.move(width / 2, height / 2)
                        page.mouse.wheel(0, delta)
                        page.wait_for_timeout(700)
                    path = out / f'{screen}-{width}-scale{scale}-{position}.png'
                    page.screenshot(path=str(path))
                    records.append({'screen': screen, 'viewport': [width, height],
                        'textScale': scale, 'androidInsets': [24, 24], 'position': position,
                        'image': str(path), 'errors': list(errors), 'blockedExternalRequests': list(blocked),
                        'documentWidth': page.evaluate('document.documentElement.scrollWidth')})
                page.close()
    finally:
        browser.close()
(out / 'browser.json').write_text(json.dumps(records, indent=2))
assert all(not r['errors'] for r in records), records
assert all(r['documentWidth'] == r['viewport'][0] for r in records), records
# Distinct scroll frames are necessary evidence that lower rows were reached.
for screen in ['squad', 'player']:
    for scale in [1, 1.6]:
        for width in [320, 360, 390]:
            assert (out / f'{screen}-{width}-scale{scale}-top.png').read_bytes() != (out / f'{screen}-{width}-scale{scale}-bottom.png').read_bytes()
print(f'Captured {len(records)} real Flutter frames; no page errors or document overflow.')
