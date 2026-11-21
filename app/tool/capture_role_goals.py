"""Capture actual PlayerStatsPage/SquadStatsPage on the same synthetic fixture.

Build tool/role_goal_preview.dart with local web resources, serve build/web only
on loopback, then run (each heavy command needs its own lock and memory gate):
playwright-local python tool/capture_role_goals.py http://127.0.0.1:18869 OUTPUT
No DOM/image edits. Only real keyboard/click actions enable semantics and sort.
"""
import hashlib
import json
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
                    expect(page.get_by_text('SYNTHETIC DATA', exact=False)).to_be_attached()
                    expect(page.get_by_text('Gole według strony', exact=True)).to_be_attached()
                    expect(page.get_by_text('Z zawodnikiem: 1 · Bez zawodnika: 1', exact=True).first).to_be_attached()
                    expect(page.get_by_text('Strzelone: +3,00 · Stracone: -1,00', exact=True)).to_be_attached()
                    if screen == 'player':
                        expect(page.get_by_text('Strzelone: +3,00 · Stracone: +2,00', exact=True)).to_be_attached()
                    else:
                        record['sortChecks'] = []
                        # The accessible dropdown is a Flutter semantics button.
                        for label, value in MEASURES.items():
                            page.get_by_role('button', name='Gospodarze · strzelone' if not record['sortChecks'] else record['sortChecks'][-1]['measure'], exact=True).click()
                            page.get_by_text(label, exact=True).last.click()
                            expect(page.get_by_text('Jan Testowy · ' + value, exact=True)).to_be_attached()
                            jan = page.get_by_text('Jan Testowy · ' + value, exact=True).bounding_box()
                            missing = page.get_by_text('Nowy bez występów · Brak danych', exact=True).bounding_box()
                            assert jan and missing and jan['y'] < missing['y'], (jan, missing)
                            record['sortChecks'].append({'measure': label, 'janValue': value, 'missingLast': True})
                            actions.append('Select ' + label)
                        page.get_by_role('button', name='Goście · stracone', exact=True).click()
                        page.get_by_text('Gospodarze · strzelone', exact=True).last.click()
                        actions.append('Select Gospodarze · strzelone for final capture; no scroll')
                    record['semanticsText'] = page.locator('flt-semantics-host').inner_text()
                    for label in ['SYNTHETIC DATA', 'Gole według strony', 'Strzelone: +3,00 · Stracone: -1,00']:
                        bounds = page.get_by_text(label, exact=False).first.bounding_box()
                        assert bounds and bounds['y'] >= 0 and bounds['y'] + bounds['height'] <= 1000, (label, bounds)
                    assert not blocked, blocked
                    assert all(r['status'] < 400 for r in responses), responses
                    fonts = [r for r in responses if '/fonts/' in r['url'] and r['url'].endswith('.ttf')]
                    assert fonts and all(r['status'] == 200 for r in fonts), fonts
                    check_diagnostics(errors, console, page.evaluate('document.documentElement.scrollWidth'), 390)
                    image = out / (screen + '-stats.png')
                    page.screenshot(path=str(image))
                    record.update(image=image.name, imageSha256=sha256(image), status='passed')
                except Exception as error:
                    record.update(status='failed', failure=str(error))
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
