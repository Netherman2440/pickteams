"""Real RootShell viewports. Read-only Flutter glyph metrics, no DOM layout edits.

Run with browser_proof.sh and tool/match_view_preview.dart. Failure frames and
metrics remain available, including errors outside the match presentation seam.
"""
import hashlib
import json
from pathlib import Path
import sys
import traceback
from urllib.parse import urlencode, urlparse

from capture_lineups import CHROMIUM, METRICS, check_viewport, png_size


def inside(inner, outer, tolerance=.1):
    x, y, w, h = inner
    a, b, c, d = outer
    return (x >= a - tolerance and y >= b - tolerance
            and x + w <= a + c + tolerance and y + h <= b + d + tolerance)


def check_panels(metrics):
    panels = metrics['panels']
    assert panels, 'No match panels'
    heights = [p['rect'][3] for p in panels]
    assert max(heights) - min(heights) < .1, heights
    for panel in panels:
        texts = panel['texts']
        name = next(t for t in texts if t['text'] == panel['name'])
        rank = next(t for t in texts if t['text'] == panel['ranking'])
        assert not name['exceeded'] and name['maxLines'] is None
        assert name['rect'][0] + name['rect'][2] < rank['rect'][0]
        cy = panel['rect'][1] + panel['rect'][3] / 2
        for text in [name, rank]:
            assert abs(text['rect'][1] + text['rect'][3] / 2 - cy) < .1
            for glyph in text['glyphs']:
                assert glyph['boxes'], glyph
                assert all(inside(box, panel['rect']) and box[2] > 0 and box[3] > 0
                           for box in glyph['boxes']), glyph
    assert metrics['footer'][1] >= max(p['rect'][1] + p['rect'][3] for p in panels)


def capture(url, output):
    from playwright.sync_api import sync_playwright
    origin = urlparse(url)
    assert origin.hostname in ('127.0.0.1', 'localhost', '::1')
    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)
    records = []
    cases = [(w, s, 11, True, False, None) for w in [320, 360, 390] for s in [1, 1.6]]
    cases += [(360, 1, 8, True, False, None), (320, 1.6, 8, True, False, None),
              (390, 1.6, 8, False, True, 5), (360, 1, 2, False, False, None),
              (1440, 1.6, 11, True, False, None)]
    with sync_playwright() as pw:
        browser = pw.chromium.launch(executable_path=str(CHROMIUM), args=['--disable-dev-shm-usage'])
        try:
            for width, scale, count, long, reader, away in cases:
                prefix = f'{width}-{scale}-{count}-{long}-{reader}-{away}'
                record = dict(case=prefix, frames=[], errors=[], blocked=[])
                records.append(record)
                page = browser.new_page(viewport=dict(width=width, height=640), device_scale_factor=1)
                page.set_default_timeout(10000)
                page.on('pageerror', lambda error: record['errors'].append(str(error)))

                def route(request):
                    parsed = urlparse(request.request.url)
                    if parsed.netloc == origin.netloc:
                        request.continue_()
                    elif parsed.netloc == 'fonts.googleapis.com' and parsed.path == '/css2':
                        request.fulfill(status=200, content_type='text/css', body='')
                    else:
                        record['blocked'].append(request.request.url)
                        request.abort()
                page.route('**/*', route)

                def frame(state):
                    page.wait_for_timeout(250)
                    path = out / f'{prefix}-{state}.png'
                    image = page.screenshot(path=str(path), full_page=False)
                    assert png_size(image) == (width, 640)
                    dom = page.evaluate(METRICS)
                    check_viewport(dom, (width, 640))
                    metrics = page.evaluate('JSON.parse(window.matchViewMetrics())')
                    record['frames'].append(dict(state=state, file=path.name,
                        sha256=hashlib.sha256(image).hexdigest(), metrics=metrics, dom=dom))
                    return metrics

                def wheel(delta):
                    page.mouse.move(width * .6, 480)
                    page.mouse.wheel(0, delta)
                    page.wait_for_timeout(300)

                def click(locator):
                    locator.click()
                    page.mouse.move(width - 2, 638)
                    page.wait_for_timeout(350)

                try:
                    params = dict(count=count, scale=scale, long=str(long).lower(), reader=str(reader).lower())
                    if away is not None:
                        params['away'] = away
                    if reader:
                        params['saved'] = 'false'
                    page.goto(url + '/?' + urlencode(params), wait_until='networkidle')
                    page.wait_for_function('typeof window.matchViewMetrics === "function"')
                    page.get_by_text('Niebiescy', exact=True).wait_for()
                    page.wait_for_timeout(800)
                    top = frame('expanded')
                    check_panels(top)
                    for side, name in [('home', 'Niebiescy'), ('away', 'Czerwoni')]:
                        badge = top['identities'][f'lineup-{side}-badge']
                        label = page.get_by_text(name, exact=True).bounding_box()
                        assert badge[2:] == [48, 48]
                        assert badge[1] + badge[3] <= label['y']
                        assert abs(badge[0] + 24 - label['x'] - label['width'] / 2) < .1
                    if reader:
                        assert page.get_by_role('button', name='Akcje meczu', exact=True).count() == 0
                    if count == 2:
                        assert abs(top['footer'][1] + top['footer'][3] - 632) < .1
                    else:
                        wheel(100)
                        collapsed = frame('collapsed')
                        assert collapsed['identities']['lineup-home-badge'][2:] == [16, 16]
                        seen = set()
                        for step in range(60):
                            metrics = frame(f'roster-{step}')
                            check_panels(metrics)
                            viewport = metrics['viewport']
                            badge = metrics['identities']['lineup-home-badge']
                            clear_top = max(viewport[1], badge[1] + badge[3] + 8)
                            clear = [viewport[0], clear_top, viewport[2], viewport[1] + viewport[3] - clear_top]
                            seen.update(p['id'] for p in metrics['panels'] if inside(p['rect'], clear))
                            if inside(metrics['footer'], viewport):
                                break
                            wheel(max(32, clear[3] - metrics['panels'][0]['rect'][3] - 16))
                        # Include the first rows before scrolling past them.
                        seen.update(p['id'] for p in top['panels'] if inside(p['rect'], top['viewport']))
                        assert seen == {p['id'] for p in top['panels']}, {'unreached': {p['id'] for p in top['panels']} - seen}
                        wheel(10000)
                        bottom = frame('bottom')
                        assert inside(bottom['footer'], bottom['viewport'])
                    if width == 360 and count == 8:
                        click(page.get_by_role('button', name='Akcje meczu', exact=True))
                        click(page.get_by_role('menuitem', name='Wprowadź wynik', exact=True))
                        frame('score-edit')
                        for field, value in [('Gospodarze', '17'), ('Goście', '6')]:
                            click(page.get_by_role('textbox', name=field, exact=True))
                            page.keyboard.press('Control+A')
                            page.keyboard.type(value)
                        click(page.get_by_role('button', name='Zapisz', exact=True))
                        page.get_by_text('17', exact=True).wait_for()
                        frame('score-saved')
                        click(page.get_by_role('button', name='Akcje meczu', exact=True))
                        click(page.get_by_role('menuitem', name='Edytuj składy', exact=True))
                        frame('teams-edit')
                        assert page.get_by_role('textbox').count() == 2
                        click(page.get_by_role('button', name='Anuluj', exact=True))
                        frame('teams-cancelled')
                    final = page.evaluate('JSON.parse(window.matchViewMetrics())')
                    assert not final['errors'], final['errors']
                    assert not record['errors'], record['errors']
                    assert not record['blocked'], record['blocked']
                    record['status'] = 'checks passed; open pixels before visual acceptance'
                except Exception as error:
                    record.update(status='failed', failure=str(error), traceback=traceback.format_exc())
                    try:
                        frame('failure')
                    except Exception as frame_error:
                        record['frameFailure'] = str(frame_error)
                finally:
                    page.close()
                    (out / 'results.json').write_text(json.dumps(records, indent=2))
        finally:
            browser.close()
    return 1 if any(r['status'] == 'failed' for r in records) else 0


if __name__ == '__main__':
    sys.exit(capture(sys.argv[1], sys.argv[2]))
