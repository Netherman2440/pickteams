"""Run with: playwright-local python tool/capture_player_lists.py URL OUTPUT_DIR."""
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
        for width, height in [(360, 640), (1440, 1000), (320, 640), (2560, 1000)]:
            for screen in ['selection', 'results', 'match']:
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
                page.goto(f'{url}/?page={screen}', wait_until='networkidle')
                page.wait_for_selector('flutter-view')
                page.wait_for_timeout(2500)
                path = out / f'{screen}-{width}x{height}.png'
                page.screenshot(path=str(path), full_page=False)
                records.append({'screen': screen, 'viewport': [width, height],
                    'deviceScaleFactor': 1, 'textScale': 1, 'image': str(path),
                    'errors': errors, 'blockedExternalRequests': blocked,
                    'documentWidth': page.evaluate('document.documentElement.scrollWidth')})
                page.close()
    finally:
        browser.close()
(out / 'browser.json').write_text(json.dumps(records, indent=2))
assert all(not r['errors'] for r in records), records
assert all(r['documentWidth'] == r['viewport'][0] for r in records), records
