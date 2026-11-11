"""Capture real Flutter profile frames. Run through playwright-local python."""
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
        for width, height in [(360, 640), (1440, 1000)]:
            for scale, role in [(1, 'owner'), (1.6, 'owner'), (1.6, 'viewer')]:
                page = browser.new_page(viewport={'width': width, 'height': height}, device_scale_factor=1)
                errors = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.route('**/*', lambda route: route.continue_() if urlparse(route.request.url).netloc == urlparse(url).netloc else route.abort())
                page.goto(f'{url}/?long=true&scale={scale}&role={role}&fail=true', wait_until='networkidle')
                page.wait_for_selector('flutter-view')
                page.wait_for_timeout(2000)
                page.locator('flt-semantics-placeholder').evaluate('node => node.click()')
                page.wait_for_timeout(300)

                def capture(state):
                    path = out / f'profile-{width}-{scale}-{role}-{state}.png'
                    page.screenshot(path=str(path))
                    records.append({'state': state, 'width': width, 'height': height,
                                    'scale': scale, 'role': role, 'image': str(path),
                                    'errors': list(errors),
                                    'documentWidth': page.evaluate('document.documentElement.scrollWidth')})

                capture('view')
                if role == 'owner':
                    page.get_by_role('button', name='Edytuj gracza', exact=True).click()
                    page.wait_for_timeout(300)
                    capture('edit')
                    for label, field in [('Edytuj nazwę', 'name'), ('Edytuj ranking', 'ranking'), ('Edytuj pozycję', 'position')]:
                        target = page.get_by_role('button', name=label)
                        target.click()
                        page.wait_for_timeout(300)
                        capture(field)
                        page.get_by_role('button', name='Zapisz', exact=True).click()
                        page.wait_for_timeout(300)
                        capture(f'{field}-error')
                        page.get_by_role('button', name='Anuluj', exact=True).click()
                        page.wait_for_timeout(300)
                    page.get_by_role('button', name='Gotowe', exact=True).click()
                    page.wait_for_timeout(300)
                    capture('done')
                else:
                    assert page.get_by_role('button', name='Edytuj gracza').count() == 0
                page.close()
    finally:
        browser.close()
(out / 'browser.json').write_text(json.dumps(records, indent=2))
assert all(not record['errors'] for record in records), records
assert all(record['documentWidth'] == record['width'] for record in records), records
