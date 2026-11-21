"""Capture actual PlayerStatsPage/SquadStatsPage on the same synthetic fixture.

Build tool/role_goal_preview.dart with local web resources, serve build/web only
on loopback, then run (each heavy command needs its own lock and memory gate):
playwright-local python tool/capture_role_goals.py http://127.0.0.1:18869 OUTPUT
No DOM/image edits. Only real keyboard/click actions enable semantics and sort.
"""
import hashlib
import json
import re
from pathlib import Path
import sys
from urllib.parse import urlparse

from capture_goal_comparison import request_action, check_diagnostics

MEASURES = {
    'Gospodarze · strzelone': '+3,00',
    'Gospodarze · stracone': '-1,00',
    'Goście · strzelone': '+3,00',
    'Goście · stracone': '+2,00',
}


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(base, output):
    from playwright.sync_api import expect, sync_playwright

    parsed = urlparse(base)
    if parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost'):
        raise ValueError('Only a loopback fixture server is permitted')
    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)
    records = []
    with sync_playwright() as p:
        browser = p.chromium.launch()
        try:
            for screen in ('player', 'squad'):
                context = browser.new_context(
                    viewport={'width': 390, 'height': 1000},
                    device_scale_factor=1, service_workers='block')
                page = context.new_page()
                errors, console, blocked, css, requests, responses = [], [], [], [], [], []
                actions = ['Navigate to actual stats page', 'Enter on Flutter semantics placeholder']
                page.on('pageerror', lambda e: errors.append(str(e)))
                page.on('console', lambda m: console.append(m.text))
                page.on('response', lambda r: responses.append({'url': r.url, 'status': r.status}))

                def guard(route):
                    req = route.request
                    requests.append({'url': req.url, 'method': req.method, 'type': req.resource_type})
                    action = request_action(req.url, req.resource_type, base)
                    if action == 'local' and req.method in ('GET', 'HEAD'):
                        route.continue_()
                    elif action == 'unused-html-css' and req.method == 'GET':
                        css.append(req.url)
                        route.fulfill(status=200, content_type='text/css', body='')
                    else:
                        blocked.append({'url': req.url, 'method': req.method})
                        route.abort()

                page.route('**/*', guard)
                record = {'screen': screen, 'fixture': 'role_goal_app.dart v1, same three matches',
                          'viewport': {'width': 390, 'height': 1000, 'deviceScaleFactor': 1},
                          'browser': browser.version, 'executable': p.chromium.executable_path,
                          'executableSha256': sha256(p.chromium.executable_path),
                          'serviceWorkers': 'blocked', 'actions': actions,
                          'requests': requests, 'responses': responses, 'pageErrors': errors,
                          'console': console, 'blockedRequests': blocked, 'unusedHostCss': css}
                try:
                    url = base.rstrip('/') + '/?page=' + screen
                    record['url'] = url
                    page.goto(url, wait_until='networkidle')
                    page.locator('flt-semantics-placeholder').press('Enter')
                    (out / (screen + '-dom.html')).write_text(page.content())
                    record['ariaSnapshot'] = page.locator('body').aria_snapshot()
                    record['syntheticLabelCheck'] = 'Visible fixture banner; image must be opened. Banner is outside route semantics.'
                    snapshot = page.locator('body').aria_snapshot()
                    for label in ('Gole według strony', 'Z zawodnikiem: 1 · Bez zawodnika: 1',
                                  'Strzelone: +3,00 · Stracone: -1,00'):
                        assert label in snapshot, snapshot
                    if screen == 'player':
                        assert 'Strzelone: +3,00 · Stracone: +2,00' in snapshot, snapshot
                    else:
                        record['sortChecks'] = []
                        # The accessible dropdown is a Flutter semantics button.
                        for label, value in MEASURES.items():
                            page.get_by_role('button', name=re.compile('^Gole według strony')).click()
                            record['menuSnapshot'] = page.locator('body').aria_snapshot()
                            page.get_by_role('menuitem', name=label, exact=True).click()
                            expect(page.get_by_role('button', name=re.compile('^Gole według strony'))).to_have_attribute('aria-expanded', 'false')
                            row_text = page.locator('body').aria_snapshot()
                            assert row_text.index('Jan Testowy · ' + value) < row_text.index('Nowy bez występów · Brak danych'), row_text
                            record['sortChecks'].append({'measure': label, 'janValue': value, 'missingLast': True})
                            actions.append('Select ' + label)
                        page.get_by_role('button', name=re.compile('^Gole według strony')).click()
                        page.get_by_role('menuitem', name='Gospodarze · strzelone', exact=True).click()
                        actions.append('Select Gospodarze · strzelone for final capture; no scroll')
                    record['ariaSnapshot'] = page.locator('body').aria_snapshot()
                    (out / (screen + '-dom.html')).write_text(page.content())
                    section = (page.get_by_role('button', name=re.compile('^Gole według strony'))
                               if screen == 'squad' else page.get_by_text('Gole według strony', exact=False))
                    bounds = section.bounding_box()
                    assert bounds and bounds['y'] >= 0 and bounds['y'] + bounds['height'] <= 1000, bounds
                    record['sectionBounds'] = bounds
                    assert not blocked, blocked
                    assert all(r['status'] < 400 for r in responses), responses
                    fonts = [r for r in responses if '/fonts/' in r['url'] and r['url'].endswith('.ttf')]
                    assert fonts and all(r['status'] == 200 for r in fonts), fonts
                    check_diagnostics(errors, console, page.evaluate('document.documentElement.scrollWidth'), 390)
                    image = out / (screen + '-stats.png')
                    page.screenshot(path=str(image))
                    record.update(image=image.name, imageSha256=sha256(image), status='passed')
                except Exception as error:
                    record.update(status='failed', failure=str(error), failureSnapshot=page.locator('body').aria_snapshot())
                    (out / (screen + '-failure-dom.html')).write_text(page.content())
                    page.screenshot(path=str(out / (screen + '-failure.png')))
                    raise
                finally:
                    records.append(record)
                    (out / 'browser.json').write_text(json.dumps(records, indent=2, ensure_ascii=False))
                    context.close()
        finally:
            browser.close()
    print('Captured two actual running Flutter stats pages; checked four squad sort measures.')


if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2])
