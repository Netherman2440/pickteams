"""Source-pinned real RootShell captures; normal pointer/wheel input only."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import traceback
from urllib.parse import urlencode, urlparse

from capture_lineups import CHROMIUM, IMAGE_PYTHON, METRICS, check_viewport, png_size

# Explicit CI overrides; preserve the prepared local runner's defaults.
CHROMIUM = Path(os.environ.get('MATCH_VIEW_CHROMIUM', CHROMIUM))
IMAGE_PYTHON = Path(os.environ.get('MATCH_VIEW_IMAGE_PYTHON', IMAGE_PYTHON))


def inside(inner, outer, tolerance=.1):
    x, y, w, h = inner
    a, b, c, d = outer
    return (x >= a - tolerance and y >= b - tolerance
            and x + w <= a + c + tolerance and y + h <= b + d + tolerance)


def identity(metrics):
    viewport = metrics['viewport']
    midpoint = viewport[0] + viewport[2] / 2
    return dict(teams=metrics['teams'], players=sorted(
        (p['id'], p['name'], p['ranking'], 'home' if p['rect'][0] < midpoint else 'away')
        for p in metrics['panels']))


def check_panels(metrics, scale):
    panels = metrics['panels']
    assert panels, 'No match panels'
    heights = [p['rect'][3] for p in panels]
    assert max(heights) - min(heights) < .1, heights
    assert min(heights) >= 14 * scale * 1.35 * 2 + 16 - .1
    for panel in panels:
        name = next(t for t in panel['texts'] if t['text'] == panel['name'])
        rank = next(t for t in panel['texts'] if t['text'] == panel['ranking'])
        assert not name['exceeded'] and name['maxLines'] is None
        assert name['rect'][0] + name['rect'][2] < rank['rect'][0]
        cy = panel['rect'][1] + panel['rect'][3] / 2
        for text, font in [(name, 14), (rank, 12)]:
            assert text['fontSize'] == font
            assert abs(text['scaledFontSize'] - font * scale) < .01
            assert abs(text['rect'][1] + text['rect'][3] / 2 - cy) < .1
            assert len(text['glyphs']) == len(''.join(text['text'].split()))
            for glyph in text['glyphs']:
                assert glyph['boxes'], glyph
                assert all(inside(box, panel['rect']) and box[2] > 0 and box[3] > 0
                           for box in glyph['boxes']), glyph
    assert metrics['footer'][1] >= max(p['rect'][1] + p['rect'][3] for p in panels)


def label(metrics, text):
    matches = [p['rect'] for p in metrics['labels'] if p['text'] == text]
    assert len(matches) == 1, (text, matches)
    return matches[0]


def label_rects(metrics, text):
    return [p['rect'] for p in metrics['labels'] if p['text'] == text]


def header_totals(metrics):
    return [p for p in metrics['labels'] if p['text'].startswith('Ranking:')]


def check_header(metrics, collapsed=False):
    """Team totals live in the expanded stacked header, never in the footer.

    Expanded: each column shows badge, name, then its 'Ranking: ' total,
    centered on the badge. Collapsed: only the pinned color badges remain.
    """
    viewport = metrics['viewport']
    teams = metrics['teams']
    assert teams, 'No teams'
    badges = {side: metrics['identities'][f'lineup-{side}-badge']
              for side in ['home', 'away']}
    names = {side: label_rects(metrics, teams[side]['name'])
             for side in ['home', 'away']}
    header_total = header_totals(metrics)
    if collapsed:
        assert not header_total, f'Totals must hide when collapsed: {header_total}'
        for side in ['home', 'away']:
            assert not names[side], f'Team name must hide when collapsed: {side}'
            assert badges[side][2:] == [16, 16], badges[side]
        return
    assert len(header_total) == 2, header_total
    geometry = metrics['headerGeometry']
    header_bottom = viewport[1] + geometry['paintExtent']
    ordered = sorted(header_total, key=lambda total: total['rect'][0])
    for side, total in zip(['home', 'away'], ordered):
        badge = badges[side]
        assert badge[2:] == [48, 48], badge
        assert len(names[side]) == 1, (side, names[side])
        name = names[side][0]
        assert total['rect'][1] >= name[1] + name[3] - .1, 'Total above its name'
        assert abs(total['rect'][0] + total['rect'][2] / 2
                   - (badge[0] + badge[2] / 2)) < .1, 'Total not centered in its column'
        assert total['rect'][1] + total['rect'][3] <= header_bottom + .1, 'Total outside the header'


def check_score(metrics, home, away):
    viewport = metrics['viewport']
    center = viewport[0] + viewport[2] / 2
    date = next(p['rect'] for p in metrics['labels'] if '10.11.2026' in p['text'])
    colon = label(metrics, ':')
    assert abs(date[0] + date[2] / 2 - center) < .5
    scores = [p['rect'] for p in metrics['labels'] if p['text'] in [home, away]]
    assert len(scores) == 2, scores
    left = min(p[0] for p in scores)
    right = max(p[0] + p[2] for p in scores)
    assert abs((left + right) / 2 - center) < .5
    assert left < colon[0] and colon[0] + colon[2] < right
    assert date[1] + date[3] <= min(p[1] for p in scores) + .1


def clear_region(metrics):
    viewport = metrics['viewport']
    header_bottom = viewport[1]
    if metrics.get('headerGeometry'):
        # Everything the pinned header paints is excluded, including the
        # totals that now live inside it and hide once it collapses.
        header_bottom = max(
            header_bottom,
            viewport[1] + metrics['headerGeometry']['paintExtent'],
        )
    if metrics['teams']:
        for team in metrics['teams'].values():
            for rect in label_rects(metrics, team['name']):
                header_bottom = max(header_bottom, rect[1] + rect[3] + 8)
    return [viewport[0], header_bottom, viewport[2], viewport[1] + viewport[3] - header_bottom]


def capture(url, output, case_filter=None):
    from playwright.sync_api import sync_playwright
    origin = urlparse(url)
    assert origin.hostname in ('127.0.0.1', 'localhost', '::1')
    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)
    records = []
    cases = [(w, s, n, long, False, None, False)
             for w in [320, 360, 390, 1440] for s in [1, 1.6]
             for n in [8, 11] for long in [False, True]]
    cases += [(320, 1.6, 8, True, True, None, True),
              (390, 1.6, 11, True, True, 5, False),
              (320, 1.6, 2, False, False, None, False),
              (360, 1, 2, False, False, None, False)]
    if case_filter:
        cases = [case for case in cases if '-'.join(map(str, case)) == case_filter]
        assert len(cases) == 1, f'Unknown development case: {case_filter}'
    scope = dict(mode='DEVELOPMENT ONLY - NOT ACCEPTANCE' if case_filter else 'FULL MATRIX',
                 caseFilter=case_filter, cases=len(cases))
    (out / 'scope.json').write_text(json.dumps(scope, indent=2))
    print(json.dumps(scope), flush=True)
    with sync_playwright() as pw:
        browser = pw.chromium.launch(executable_path=str(CHROMIUM), args=['--disable-dev-shm-usage'])
        try:
            for width, scale, count, long, reader, away, guest in cases:
                prefix = f'{width}-{scale}-{count}-{long}-{reader}-{away}-{guest}'
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

                def snapshot(state):
                    page.wait_for_timeout(200)
                    path = out / f'{prefix}-{state}.png'
                    image = page.screenshot(path=str(path), full_page=False)
                    assert png_size(image) == (width, 640)
                    dom = page.evaluate(METRICS)
                    metrics = page.evaluate('JSON.parse(window.matchViewMetrics())')
                    item = dict(state=state, file=path.name,
                        sha256=hashlib.sha256(image).hexdigest(), metrics=metrics, dom=dom)
                    record['frames'].append(item)
                    return item

                def frame(state, ink=True):
                    # Keep raw metrics even when the first assertion fails.
                    item = snapshot(state)
                    check_viewport(item['dom'], (width, 640))
                    metrics = item['metrics']
                    path = out / item['file']
                    if metrics['panels'] and ink:
                        metrics['clearRegion'] = clear_region(metrics)
                        pixels = subprocess.run([str(IMAGE_PYTHON),
                            str(Path(__file__).with_name('match_view_pixels.py')), str(path)],
                            input=json.dumps(metrics), text=True, capture_output=True)
                        item['inkExit'] = pixels.returncode
                        item['inkError'] = pixels.stderr
                        assert pixels.returncode == 0, pixels.stderr
                        item['ink'] = json.loads(pixels.stdout)
                    return metrics

                def wheel(delta):
                    page.mouse.move(width * .6, 480)
                    page.mouse.wheel(0, delta)
                    page.wait_for_timeout(250)

                def click(locator):
                    locator.click()
                    page.mouse.move(width - 2, 638)
                    page.wait_for_timeout(350)

                def open_menu():
                    click(page.get_by_role('button', name='Akcje meczu', exact=True))

                try:
                    params = dict(count=count, scale=scale, long=str(long).lower(),
                                  reader=str(reader).lower(), guest=str(guest).lower())
                    if away is not None:
                        params['away'] = away
                    if reader:
                        params['saved'] = 'false'
                    page.goto(url + '/?' + urlencode(params), wait_until='networkidle')
                    page.wait_for_function('typeof window.matchViewMetrics === "function"')
                    page.get_by_text('Niebiescy', exact=True).wait_for()
                    page.wait_for_timeout(600)
                    top = frame('expanded')
                    check_panels(top, scale)
                    check_header(top)
                    check_score(top, '-' if reader else '14', '-' if reader else '5')
                    original = identity(top)
                    assert len(original['players']) == count + (away if away is not None else count)
                    for side in ['home', 'away']:
                        badge = top['identities'][f'lineup-{side}-badge']
                        name = label(top, top['teams'][side]['name'])
                        assert badge[2:] == [48, 48]
                        assert badge[1] + badge[3] <= name[1]
                        assert abs(badge[0] + 24 - name[0] - name[2] / 2) < .1
                    # Genuine navigation interaction proves the menu stays reachable.
                    click(page.get_by_role('button', name='Otwórz nawigację', exact=True))
                    frame('navigation-open', ink=False)
                    click(page.get_by_role('button', name='Otwórz nawigację', exact=True))
                    if guest:
                        assert page.get_by_role('button', name='Zaloguj', exact=True).is_visible()
                    if reader:
                        assert page.get_by_role('button', name='Akcje meczu', exact=True).count() == 0
                    if count == 2:
                        assert abs(top['footer'][1] + top['footer'][3] - 632) < .1
                    else:
                        wheel(100)
                        collapsed = frame('collapsed')
                        check_header(collapsed, collapsed=True)
                        seen = {p['id'] for p in top['panels'] if inside(p['rect'], clear_region(top))}
                        for step in range(60):
                            metrics = frame(f'roster-{step}')
                            check_panels(metrics, scale)
                            check_header(metrics, collapsed=True)
                            clear = clear_region(metrics)
                            seen.update(p['id'] for p in metrics['panels'] if inside(p['rect'], clear))
                            if inside(metrics['footer'], metrics['viewport']):
                                break
                            wheel(max(32, clear[3] - metrics['panels'][0]['rect'][3] - 16))
                        assert seen == {p['id'] for p in top['panels']}, {'unreached': {p['id'] for p in top['panels']} - seen}
                        wheel(10000)
                        bottom = frame('bottom')
                        check_header(bottom, collapsed=True)
                        assert inside(bottom['footer'], bottom['viewport'])
                    if count == 11 and long and not reader and width in [320, 360]:
                        open_menu()
                        click(page.get_by_role('menuitem', name='Wprowadź wynik', exact=True))
                        frame('score-edit')
                        for field, value in [('Gospodarze', '17'), ('Goście', '6')]:
                            click(page.get_by_role('textbox', name=field, exact=True))
                            page.keyboard.press('Control+A')
                            page.keyboard.type(value)
                        click(page.get_by_role('button', name='Zapisz', exact=True))
                        page.get_by_text('17', exact=True).wait_for()
                        saved = frame('score-saved')
                        check_score(saved, '17', '6')
                        assert identity(saved) == original, 'Score save changed fixture identity'
                        check_panels(saved, scale)
                        # Saving swaps back to the view scrollable, which starts
                        # expanded: the totals must be back under the names.
                        check_header(saved)
                        open_menu()
                        click(page.get_by_role('menuitem', name='Edytuj składy', exact=True))
                        frame('teams-edit')
                        fields = page.get_by_role('textbox')
                        assert fields.count() == 2
                        boxes = fields.evaluate_all('(els)=>els.map(e=>e.getBoundingClientRect().toJSON())')
                        home = next(b for b in boxes if b['right'] < width / 2)
                        page.mouse.click(home['x'] + home['width'] / 2, home['y'] + home['height'] / 2)
                        page.wait_for_function("document.activeElement?.tagName === 'INPUT' && document.activeElement.value === 'Niebiescy'")
                        page.keyboard.press('Control+A')
                        page.keyboard.type('Changed team')
                        frame('team-name-changed')
                        click(page.get_by_role('button', name='Anuluj', exact=True))
                        cancelled = frame('teams-cancelled')
                        assert identity(cancelled) == original, 'Cancel changed fixture identity'
                        check_score(cancelled, '17', '6')
                        check_header(cancelled)
                        record['editChecks'] = '17:6 saved with same 22 full names/rankings/sides and team names/colors; changed team name cancelled'
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
                    # Independent diagnostics must still run after a strict
                    # endpoint failure. Never convert that failure to a pass.
                    if count != 2:
                        probe = dict(frames=[], errors=[])
                        record['collapseProbe'] = probe
                        try:
                            wheel(-10000)
                            start = page.evaluate('JSON.parse(window.matchViewMetrics())')
                            header = start['headerGeometry']
                            extent = header['maxExtent'] - header['minExtent']
                            assert abs(header['scrollOffset']) < .1, header
                            for fraction in [.25, .5, .75]:
                                current = page.evaluate('JSON.parse(window.matchViewMetrics())')
                                wheel(extent * fraction - current['headerGeometry']['scrollOffset'])
                                item = snapshot(f'collapse-{int(fraction * 100)}')
                                metrics = item['metrics']
                                header = metrics['headerGeometry']
                                actual = header['scrollOffset'] / extent
                                clip = [*metrics['viewport'][:3], header['paintExtent']]
                                clipped = []
                                for side in ['home', 'away']:
                                    # The header shows either the complete
                                    # identity or only badges; both must fit.
                                    items = [('badge', metrics['identities'][f'lineup-{side}-badge'])]
                                    items += [('name', rect)
                                              for rect in label_rects(metrics, metrics['teams'][side]['name'])]
                                    items += [('total', total['rect'])
                                              for total in header_totals(metrics)]
                                    for kind, rect in items:
                                        if not inside(rect, clip):
                                            clipped.append(dict(side=side, kind=kind, rect=rect))
                                probe['frames'].append(dict(file=item['file'], target=fraction,
                                    actual=actual, clip=clip, clipped=clipped))
                                try:
                                    check_viewport(item['dom'], (width, 640))
                                    assert abs(actual - fraction) < .02, (actual, fraction)
                                    assert not clipped, clipped
                                except Exception as error:
                                    probe['errors'].append(str(error))
                        except Exception:
                            probe['errors'].append(traceback.format_exc())
                        if probe['errors']:
                            record['status'] = 'failed'
                    page.close()
                    (out / 'results.json').write_text(json.dumps(records, indent=2))
        finally:
            browser.close()
    return 1 if any(r['status'] == 'failed' for r in records) else 0


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('url')
    parser.add_argument('output')
    parser.add_argument('--case', help='Development-only exact case; never full acceptance')
    args = parser.parse_args()
    sys.exit(capture(args.url, args.output, args.case))
