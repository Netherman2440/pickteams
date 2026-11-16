"""Local actual Flutter recovery UI over labeled synthetic HTTP, not Supabase."""
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright, expect

url, directory = sys.argv[1:]
assert urlparse(url).hostname == '127.0.0.1', 'Local synthetic build only'
out = Path(directory)
out.mkdir(parents=True, exist_ok=False)
records = []
pattern = re.compile(r'RPC (\d+) id=(\S+) base=(\S+) pending=(true|false) state=(loaded|error|loading)')

with sync_playwright() as p:
    browser = p.chromium.launch()
    try:
        for scenario in ('conflict', 'uncertain'):
            page = browser.new_page(viewport={'width': 1100, 'height': 1000}, device_scale_factor=1)
            errors, blocked = [], []
            page.on('pageerror', lambda error: errors.append(str(error)))
            def local_only(route):
                if urlparse(route.request.url).netloc == urlparse(url).netloc:
                    route.continue_()
                else:
                    blocked.append(route.request.url)
                    route.abort()
            page.route('**/*', local_only)
            page.goto(f'{url}/?recovery={scenario}', wait_until='networkidle')
            page.wait_for_selector('flutter-view')
            placeholder = page.locator('flt-semantics-placeholder')
            if placeholder.count(): placeholder.evaluate('node => node.click()')
            save = page.get_by_role('button', name='Synthetic roster save', exact=True)
            expect(save).to_be_enabled(timeout=20000)

            def capture(state, count, pending, ui_state):
                expect(page.get_by_text(re.compile(f'RPC {count} .*pending={str(pending).lower()} state={ui_state}'))).to_be_visible(timeout=10000)
                semantics = page.locator('flt-semantics-host').aria_snapshot()
                match = pattern.search(semantics)
                assert match, semantics
                record = dict(zip(('count','id','base','pending','state'), match.groups()))
                record.update(scenario=scenario, step=state, semantics=semantics,
                              errors=list(errors), blocked=list(blocked))
                image = out / f'{scenario}-{state}.png'
                page.screenshot(path=str(image))
                record['image'] = str(image)
                records.append(record)
                assert not errors, errors
                return record

            before = capture('before',0,False,'loaded')
            assert 'Ranking: 105.0' in before['semantics'] and 'Ranking: 167.3' in before['semantics']
            save.click()
            expect(page.get_by_role('button', name='Wczytaj ponownie', exact=True)).to_be_visible()
            failed = capture('rejected' if scenario=='conflict' else 'lost-reply',1,True,'error')
            # Flutter exposes SelectableText as a disabled textbox without its
            # value in aria_snapshot. Check the real recovery choices instead;
            # inspect the saved frame for the visible error text.
            expect(page.get_by_role('button', name='Ponów zapis składów', exact=True)).to_have_count(0 if scenario=='conflict' else 1)
            page.get_by_role('button', name='Wczytaj ponownie', exact=True).click()
            expect(page.get_by_role('button', name='Akcje meczu')).to_be_visible()
            reloaded = capture('reloaded',1,scenario=='uncertain','loaded')
            assert reloaded['id']==failed['id'] and reloaded['base']=='initial'
            if scenario=='conflict':
                assert 'Ranking: 63.8' in reloaded['semantics'] and 'Ranking: 208.5' in reloaded['semantics']
                save.click()  # same intended membership, now a NEW operation
            else:
                assert 'Ranking: 79.8' in reloaded['semantics'] and 'Ranking: 192.5' in reloaded['semantics']
                page.get_by_role('button', name='Ponów zapis składów', exact=True).click()
            final = capture('new-save' if scenario=='conflict' else 'exact-retry',2,False,'loaded')
            assert 'Ranking: 79.8' in final['semantics'] and 'Ranking: 192.5' in final['semantics']
            assert re.search(r'Adam.*41\.25',final['semantics']), final['semantics']
            if scenario=='conflict':
                assert final['id']!=failed['id'] and final['base']=='synthetic-other-operation', final
            else:
                assert final['id']==failed['id'] and final['base']=='initial', final
            assert Path(failed['image']).read_bytes()!=Path(final['image']).read_bytes(), 'Required UI transition did not change frame'
            page.close()
    except BaseException:
        if 'page' in locals() and not page.is_closed():
            page.screenshot(path=str(out/'failure.png'))
            (out/'failure-semantics.txt').write_text(page.locator('flt-semantics-host').aria_snapshot())
        raise
    finally:
        browser.close()
(out/'browser.json').write_text(json.dumps(records,indent=2))
assert len(records)==8
print('PASS: 8 actual Flutter fixture frames; explicit conflict reload/new UUID/base and uncertain reload/exact retry; preserved player inputs and expected roster sums. No live backend or preview visited.')
