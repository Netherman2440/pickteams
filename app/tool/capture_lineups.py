"""Real Chromium frames. Run under the shared Flutter validation lock."""
import hashlib
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlencode, urlparse
from playwright.sync_api import sync_playwright


def capture(url, output):
    origin = urlparse(url)
    if origin.hostname not in ('127.0.0.1', 'localhost', '::1'):
        raise ValueError('Loopback only')
    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)
    records = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch(executable_path=str(Path.home() / '.cache/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-linux64/chrome-headless-shell'), args=['--disable-dev-shm-usage'])
        try:
            cases = [
                (screen, width, count, scale, long, reader, saved)
                for screen in ['match', 'results']
                for width in [360, 1440]
                for count, scale, long in [(8, 1, False), (11, 1, False), (11, 1.6, True)]
                for reader, saved in [(False, True)]
            ] + [('match', width, 8, 1, False, True, False) for width in [360, 1440]]
            for screen, width, count, scale, long, reader, saved in cases:
                record = dict(screen=screen, width=width, height=640 if width == 360 else 1000, count=count, scale=scale, long=long, reader=reader, saved=saved, errors=[], blocked=[], frames=[])
                records.append(record)
                prefix = f'{screen}-{width}-{count}-{scale}-' + ('reader-missing' if reader else 'owner')
                page = browser.new_page(viewport=dict(width=width, height=record['height']), device_scale_factor=1)
                page.on('pageerror', lambda error: record['errors'].append(str(error)))
                page.on('console', lambda msg: record['errors'].append(msg.text) if msg.type == 'error' or re.search(r'F015_FLUTTER_ERROR|overflowed|RenderFlex', msg.text) else None)

                def local(route):
                    request = urlparse(route.request.url)
                    if request.netloc == origin.netloc:
                        route.continue_()
                    elif request.netloc == 'fonts.googleapis.com' and request.path == '/css2' and route.request.resource_type == 'stylesheet':
                        route.fulfill(status=200, content_type='text/css', body='')
                    else:
                        record['blocked'].append(route.request.url)
                        route.abort()
                page.route('**/*', local)

                def frame(state):
                    page.wait_for_timeout(500)
                    path = out / f'{prefix}-{state}.png'
                    image = page.screenshot(path=str(path), full_page=True)
                    semantics = page.locator('flt-semantics-host').evaluate("host => host.innerText + '\\n' + Array.from(host.querySelectorAll('[aria-label]')).map(n => n.getAttribute('aria-label')).join('\\n')")
                    record['frames'].append(dict(state=state, file=path.name, sha256=hashlib.sha256(image).hexdigest(), semantics=semantics))
                    assert page.evaluate('document.documentElement.scrollWidth') == width

                def wheel(delta):
                    page.mouse.move(width * .6, record['height'] * .75)
                    page.mouse.wheel(0, delta)
                    page.wait_for_timeout(500)
                try:
                    params = dict(page=screen, count=count, scale=scale, long=str(long).lower(), reader=str(reader).lower(), saved=str(saved).lower())
                    page.goto(url + '/?' + urlencode(params), wait_until='networkidle')
                    page.wait_for_selector('flt-semantics-host', state='attached')
                    page.wait_for_timeout(1500)
                    frame('expanded')
                    wheel(48 if screen == 'match' else 96)
                    frame('collapsed')
                    assert record['frames'][0]['sha256'] != record['frames'][1]['sha256'], 'Scroll did not change pixels'
                    wheel(3000)
                    frame('bottom')
                    if screen == 'match' and not reader and count == 8:
                        page.get_by_role('button', name='Akcje meczu', exact=True).click()
                        frame('menu')
                        page.get_by_text('Wprowadź wynik', exact=True).click()
                        frame('edit-score')
                        fields = page.get_by_role('textbox')
                        fields.nth(0).click()
                        page.keyboard.press('Control+A')
                        page.keyboard.type('17')
                        fields.nth(1).click()
                        page.keyboard.press('Control+A')
                        page.keyboard.type('6')
                        page.get_by_role('button', name='Zapisz', exact=True).click()
                        frame('saved-score')
                        page.get_by_role('button', name='Akcje meczu', exact=True).click()
                        page.get_by_text('Edytuj składy', exact=True).click()
                        frame('edit-teams')
                        page.get_by_role('button', name='Anuluj', exact=True).click()
                        frame('cancelled-teams')
                    assert not record['errors'], record['errors']
                    assert not record['blocked'], record['blocked']
                    record['status'] = 'captured; pixel inspection required'
                except Exception as error:
                    record['status'] = 'failed'
                    record['failure'] = str(error)
                    page.screenshot(path=str(out / f'{prefix}-failure.png'), full_page=True)
                finally:
                    page.close()
                    (out / 'browser.json').write_text(json.dumps(records, indent=2, ensure_ascii=False))
        finally:
            browser.close()
    failures = [r for r in records if r['status'] == 'failed']
    print(json.dumps(dict(cases=len(records), failures=len(failures))))
    for record in failures:
        print(record['screen'], record['width'], record.get('failure'))
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    capture(*sys.argv[1:])
