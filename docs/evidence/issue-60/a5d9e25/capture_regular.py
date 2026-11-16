"""Actual Flutter UI; synthetic HTTP fixture. No live backend evidence.
Run: playwright-local python capture.py http://127.0.0.1:18860 OUTPUT_DIR
"""
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright, expect

url, output = sys.argv[1:]
out = Path(output)
out.mkdir(parents=True, exist_ok=True)
records = []
with sync_playwright() as p:
    browser = p.chromium.launch()
    try:
        for equal in [False, True]:
            for substitutes in [False, True]:
                name = ('equal' if equal else 'unequal') + ('-substitutes-on' if substitutes else '-substitutes-off')
                page = browser.new_page(viewport={'width': 1100, 'height': 850}, device_scale_factor=1)
                errors, blocked = [], []
                page.on('pageerror', lambda error: errors.append(str(error)))
                def local_only(route):
                    if urlparse(route.request.url).netloc == urlparse(url).netloc:
                        route.continue_()
                    else:
                        blocked.append(route.request.url)
                        route.abort()
                page.route('**/*', local_only)
                expected_away = '110.8' if equal else ('111.5' if substitutes else '167.3')
                # Actual proposal page, not a recreated card. Same labeled fixture inputs.
                page.goto(f'{url}/?equal={int(equal)}&substitutes={"on" if substitutes else "off"}#/proposal', wait_until='networkidle')
                page.wait_for_selector('flutter-view')
                page.wait_for_timeout(1800)
                placeholder = page.locator('flt-semantics-placeholder')
                if placeholder.count(): placeholder.evaluate('node => node.click()')
                page.wait_for_timeout(500)
                proposal_semantics = page.locator('flt-semantics-host').aria_snapshot()
                assert 'Ranking: 105.0' in proposal_semantics, proposal_semantics
                assert f'Ranking: {expected_away}' in proposal_semantics, proposal_semantics
                assert re.search(r'Adam.*41\.25', proposal_semantics), proposal_semantics
                path = out / f'{name}-proposal.png'
                page.screenshot(path=str(path))
                records.append({'scenario': name, 'state': 'proposal', 'image': str(path), 'semantics': proposal_semantics, 'errors': list(errors), 'blockedExternalRequests': list(blocked)})
                page.goto(f'{url}/?equal={int(equal)}&substitutes={"on" if substitutes else "off"}', wait_until='networkidle')
                page.wait_for_selector('flutter-view')
                page.wait_for_timeout(1800)
                placeholder = page.locator('flt-semantics-placeholder')
                if placeholder.count(): placeholder.evaluate('node => node.click()')
                page.wait_for_timeout(500)
                expected_away = '110.8' if equal else ('111.5' if substitutes else '167.3')
                banners = {}
                for state in ['before', 'after-result', 'after-reload', 'after-correction']:
                    if state in ['after-result', 'after-correction']:
                        page.get_by_role('button', name='Akcje meczu').click()
                        page.get_by_role('menuitem', name='Wprowadź wynik', exact=True).click()
                        fields = page.get_by_role('textbox')
                        expect(fields).to_have_count(2)
                        for i, value in enumerate(['1', '0'] if state == 'after-result' else ['0', '1']):
                            field = fields.nth(i)
                            field.click()
                            page.wait_for_timeout(100)
                            field.press('ControlOrMeta+A')
                            field.press('Backspace')
                            page.wait_for_timeout(50)
                            field.press_sequentially(value, delay=50)
                            expect(field).to_have_value(value)
                        page.get_by_role('button', name='Zapisz', exact=True).click()
                        expect(page.get_by_role('textbox')).to_have_count(0)
                    elif state == 'after-reload':
                        # The fixture banner is outside Navigator's semantics scope.
                        # Click the real visible Reload match button at this viewport.
                        page.mouse.click(1030, 27)
                    page.mouse.move(1090, 840)
                    page.wait_for_timeout(500)
                    semantics = page.locator('flt-semantics-host').aria_snapshot()
                    assert 'Ranking: 105.0' in semantics, semantics
                    assert f'Ranking: {expected_away}' in semantics, semantics
                    assert ('Bartek' in semantics and 'Adam' in semantics), semantics
                    assert re.search(r'Bartek.*63\.75', semantics), semantics
                    assert re.search(r'Adam.*41\.25', semantics), semantics
                    assert re.search(r'Dawid.*72\.25', semantics), semantics
                    # Check the actual roster order, not just the fixture banner.
                    home = re.findall(r'button "(Bartek|Adam) [0-9.]+"', semantics)
                    assert home == ['Bartek', 'Adam'], (home, semantics)
                    away = re.findall(r'button "(Dawid|Emil|Cezary) [0-9.]+"', semantics)
                    assert away == (['Dawid', 'Cezary'] if equal else ['Dawid', 'Emil', 'Cezary']), (away, semantics)
                    banners[state] = page.screenshot(clip={'x': 0, 'y': 0, 'width': 900, 'height': 54})
                    if state == 'after-result': assert banners[state] != banners['before'], 'Current score banner did not change'
                    if state == 'after-reload': assert banners[state] == banners['after-result'], 'Reload changed current score banner'
                    if state == 'after-correction': assert banners[state] != banners['after-result'], 'Correction did not change current score banner'
                    path = out / f'{name}-{state}.png'
                    page.screenshot(path=str(path))
                    records.append({'scenario': name, 'state': state, 'image': str(path), 'semantics': semantics, 'errors': list(errors), 'blockedExternalRequests': list(blocked)})
                page.close()
    except BaseException:
        if 'page' in locals() and not page.is_closed():
            page.screenshot(path=str(out / 'failure.png'))
            (out / 'failure-semantics.txt').write_text(page.locator('flt-semantics-host').aria_snapshot())
        raise
    finally:
        browser.close()
(out / 'browser.json').write_text(json.dumps(records, indent=2))
assert len(records) == 20
assert all(not r['errors'] for r in records), records
print('PASS: 20 actual Flutter frames; proposal/match sums agree for equal/unequal substitutes on/off; fixed inputs and ordering across result/reload/correction; synthetic current scores change independently.')
