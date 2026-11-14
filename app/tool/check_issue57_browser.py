"""Real widget evidence with CDP touch input, synthetic data and in-memory writes.

Serve build/issue57-web on 127.0.0.1:8857. Run under the shared validation
lock and memory gate. Text scale comes from MediaQuery, not browser zoom.
"""
import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlencode, urlparse

from playwright.sync_api import sync_playwright

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
URL = 'http://127.0.0.1:8857/'
CHROME = Path.home() / '.cache/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-linux64/chrome-headless-shell'
NAMES = ['Michał Kowalski', 'Łukasz Wiśniewski', 'Paweł Zieliński',
         'Krzysztof Wójcik', 'Tomasz Kamiński', 'Jakub Lewandowski',
         'Piotr Nowak', 'Bartosz Mazur', 'Adam Dąbrowski', 'Marcin Kaczmarek',
         'Mateusz Szymański', 'Rafał Woźniak', 'Wojciech Kozłowski',
         'Grzegorz Jankowski', 'Marek Wojciechowski']
records = []


def rows(page, width):
    nodes = page.locator('flt-semantics-host').evaluate('''host =>
      Array.from(host.querySelectorAll('flt-semantics')).filter(e =>
        e.children.length === 1 && e.firstElementChild.tagName === 'SPAN'
        || e.getAttribute('role') === 'button'
        || e.getAttribute('role') === 'group' && e.hasAttribute('aria-label')).map(e => ({text:e.getAttribute('aria-label') || e.innerText,
        rect:e.getBoundingClientRect().toJSON()}))''')
    result = {}
    for name in NAMES:
        matching = [n for n in nodes if name in n['text']]
        if matching:
            assert len(matching) == 1, (name, matching)
            result[name] = {'side': 'home' if matching[0]['rect']['x'] < width / 2 else 'away',
                            'rect': matching[0]['rect']}
    return result


def sides(page, width):
    return {name: node['side'] for name, node in rows(page, width).items()}


def handle(page, name):
    # Bounds come from the actual 16px grip semantics, not a row-center estimate.
    grip = page.locator(f'[flt-semantics-identifier="transfer-handle-p{NAMES.index(name)}"]')
    return grip.bounding_box() if grip.count() else None


def frame(page, record, name):
    path = OUT / (record['case'] + '-' + name + '.png')
    data = page.screenshot(path=str(path))
    assert page.evaluate('innerWidth') == record['width']
    assert page.evaluate('document.documentElement.scrollWidth') == record['width']
    record['frames'].append({'file': path.name, 'sha256': hashlib.sha256(data).hexdigest()})
    return data


def totals(page, record, expected, *, snapshot):
    labels = page.get_by_text(re.compile(r'^Ranking:'))
    labels.first.wait_for(state='attached')
    assert labels.count() == 2, labels.all_inner_texts()
    values = {}
    rects = {}
    for label in labels.all():
        rect = label.bounding_box()
        side = 'home' if rect['x'] + rect['width'] / 2 < record['width'] / 2 else 'away'
        values[side] = float(label.inner_text().split(':')[1].strip())
        rects[side] = rect
        assert rect['x'] >= 0 and rect['x'] + rect['width'] <= record['width'], rect
    for side in ['home', 'away']:
        ids = [NAMES.index(n) for n, s in expected.items() if s == side]
        opponent = len(expected) - len(ids)
        value = sum(60.25 - i / 2 - (10.125 if snapshot else 0) for i in ids)
        if len(ids) > opponent:
            value *= (len(ids) - 1) / len(ids)
        assert abs(values[side] - value) <= .051, (side, values, value)
    record['totals'].append(values)
    return rects


def swipe(page, cdp, start, end):
    cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{'x': start[0], 'y': start[1]}]})
    for step in range(1, 9):
        cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{
            'x': start[0], 'y': start[1] + (end[1] - start[1]) * step / 8}]})
        page.wait_for_timeout(15)
    cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
    page.wait_for_timeout(350)
    # Wait for real scroll inertia to stop before aiming at a 16px grip.
    page.evaluate('''() => new Promise((resolve, reject) => {
      let last = '', stable = 0, count = 0;
      const timer = setInterval(() => {
        const now = JSON.stringify(Array.from(document.querySelectorAll('flt-semantics')).map(e => {
          const r = e.getBoundingClientRect(); return [r.x.toFixed(1), r.y.toFixed(1)];
        }));
        stable = now === last ? stable + 1 : 0; last = now;
        if (stable >= 3) { clearInterval(timer); resolve(); }
        else if (++count > 40) { clearInterval(timer); reject('scroll did not settle'); }
      }, 100);
    })''')


def scroll_top(page, cdp, width):
    def positions():
        return {name: round(node['rect']['y'], 1) for name, node in rows(page, width).items()}
    for _ in range(24):
        before = positions()
        swipe(page, cdp, (width / 2, 250), (width / 2, 700))
        after = positions()
        if before and before == after:
            return
    raise AssertionError('could not return to top')


def all_sides(page, cdp, width, count):
    # Flutter culls offscreen semantics after layout changes. Sweep the real
    # scroll view instead of treating absent accessibility nodes as lost players.
    found = sides(page, width)
    if len(found) == count:
        return found
    scroll_top(page, cdp, width)
    found = {}
    for _ in range(24):
        for name, side in sides(page, width).items():
            assert name not in found or found[name] == side, (name, found, side)
            found[name] = side
        if len(found) == count:
            scroll_top(page, cdp, width)
            return found
        swipe(page, cdp, (width / 2, 650), (width / 2, 200))
    raise AssertionError(('incomplete roster after scroll sweep', found, count))


def reach_handle(page, cdp, width, name):
    for _ in range(8):
        box = handle(page, name)
        if box is None:
            swipe(page, cdp, (width / 2, 600), (width / 2, 250))
            continue
        y = box['y'] + box['height'] / 2
        if 120 < y < 690:
            return box
        swipe(page, cdp, (width / 2, 600 if y > 690 else 250),
              (width / 2, 250 if y > 690 else 600))
    raise AssertionError(('unreachable handle', name, box))


def transfer(page, cdp, record, name, side, *, cancel=False, mouse=False, hover=None):
    box = reach_handle(page, cdp, record['width'], name)
    start = (box['x'] + box['width'] / 2, box['y'] + box['height'] / 2)
    end = (record['width'] * (.25 if side == 'home' else .75), start[1])
    record['handleStarts'].append({'name': name, 'rect': box, 'point': start, 'mouse': mouse})
    if mouse:
        page.mouse.move(*start)
        page.mouse.down()
    else:
        cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{'x': start[0], 'y': start[1]}]})
        page.wait_for_timeout(600)  # Recognizer hold, not a resource-gate wait.
    for step in range(1, 9):
        x = start[0] + (end[0] - start[0]) * step / 8
        if mouse:
            page.mouse.move(x, end[1])
        else:
            cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{'x': x, 'y': end[1]}]})
        page.wait_for_timeout(20)
    page.wait_for_timeout(100)
    if hover:
        hover()
    if mouse:
        page.mouse.up()
        page.mouse.move(record['width'] - 2, 2)
    else:
        cdp.send('Input.dispatchTouchEvent', {'type': 'touchCancel' if cancel else 'touchEnd', 'touchPoints': []})
    page.wait_for_timeout(300)


def edit(page):
    page.get_by_role('button', name='Akcje meczu', exact=True).tap()
    page.get_by_role('menuitem', name='Edytuj składy', exact=True).tap()
    page.get_by_role('button', name='Zapisz', exact=True).wait_for()
    page.wait_for_timeout(200)


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=str(CHROME), args=['--disable-dev-shm-usage'])
    try:
        cases = [(screen, width, scale, 'light' if scale == 1 else 'dark', False, False)
                 for screen in ['match', 'results'] for width in [320, 360, 430] for scale in [1, 1.6]]
        cases += [(screen, 320, 3, 'light', False, False) for screen in ['match', 'results']]
        cases += [('match', 360, 1, 'dark', True, False)]
        cases += [(screen, 360, 1.6, 'dark', False, True) for screen in ['match', 'results']]
        cases += [(screen, 1440, 1, 'light', False, False) for screen in ['match', 'results']]
        for screen, width, scale, theme, empty, long in cases:
            case = f'{screen}-{width}-{theme}-x{scale}' + ('-empty' if empty else '') + ('-long' if long else '')
            if len(sys.argv) > 2 and not re.search(sys.argv[2], case):
                continue
            record = {'case': case, 'browser': browser.version, 'width': width, 'height': 800, 'textScale': scale,
                      'checks': [], 'frames': [], 'totals': [], 'handleStarts': [], 'errors': [], 'blockedRequests': 0}
            records.append(record)
            context = browser.new_context(viewport={'width': width, 'height': 800}, device_scale_factor=1,
                                          is_mobile=width < 1000, has_touch=True)
            page = context.new_page()
            page.set_default_timeout(10000)
            page.on('pageerror', lambda error, r=record: r['errors'].append(str(error)))

            def local(route):
                if urlparse(route.request.url).netloc == '127.0.0.1:8857':
                    route.continue_()
                else:
                    record['blockedRequests'] += 1
                    route.abort()
            page.route('**/*', local)
            page.goto(URL + '?' + urlencode({'page': screen, 'theme': theme, 'scale': scale,
                                            'empty': int(empty), 'count': 8 if empty else 15, 'long': int(long)}))
            if screen == 'match':
                page.get_by_role('button', name='Akcje meczu', exact=True).wait_for()
            else:
                page.get_by_role('button', name='Zakceptuj propozycję', exact=True).wait_for()
            page.wait_for_timeout(400)
            cdp = context.new_cdp_session(page)
            count = 8 if empty else 15
            initial = all_sides(page, cdp, width, count)
            assert len(initial) == count, initial
            assert sum(s == 'home' for s in initial.values()) == (8 if empty else 7)
            totals(page, record, initial, snapshot=screen == 'match')
            frame(page, record, 'view')
            if scale == 3:
                prefix = 'Szansa na wygraną:' if screen == 'match' else 'Szansa wygranej propozycji'
                label = page.locator(f'[role="group"][aria-label^="{prefix}"]')
                limit = 792 if screen == 'match' else page.get_by_role('button', name='Zakceptuj propozycję', exact=True).bounding_box()['y']
                for _ in range(40):
                    box = label.first.bounding_box() if label.count() else None
                    if box and 100 < box['y'] and box['y'] + box['height'] <= limit:
                        break
                    swipe(page, cdp, (width / 2, 640), (width / 2, 200))
                else:
                    raise AssertionError(('3x probability labels not reachable', box, limit, label.count()))
                accessible = label.get_attribute('aria-label')
                assert re.search(r'Gospodarze\s+52%', accessible), accessible
                assert re.search(r'Goście\s+48%', accessible), accessible
                box = label.bounding_box()
                assert box['x'] >= 0 and box['x'] + box['width'] <= width, box
                frame(page, record, 'probability-3x')
                record['checks'].append('320px/3x full-scale probability labels wrap within width and remain reachable')
                # The reported 3x case is a layout/label check. Reload the
                # unchanged fixture rather than sweeping the long roster twice.
                page.reload()
                control = 'Akcje meczu' if screen == 'match' else 'Zakceptuj propozycję'
                page.get_by_role('button', name=control, exact=True).wait_for()
                page.wait_for_timeout(400)
            if screen == 'match':
                edit(page)
                if width == 360 and scale == 1:
                    page.get_by_role('button', name='Zmień kolor', exact=True).first.tap()
                    page.get_by_role('button', name=re.compile('Kolor #FFFFFF')).wait_for()
                    page.get_by_role('button', name=re.compile('Kolor #000000')).wait_for()
                    frame(page, record, 'palette')
                    page.get_by_role('button', name=re.compile('Kolor #FFFFFF')).tap()
                    record['checks'].append('real touch palette exposes white and black')
            rects = totals(page, record, initial, snapshot=screen == 'match')
            current_rows = rows(page, width)
            for side in ['home', 'away']:
                first = min(n['rect']['y'] for n in current_rows.values() if n['side'] == side) if any(n['side'] == side for n in current_rows.values()) else float('inf')
                assert rects[side]['y'] + rects[side]['height'] <= first, (rects, first)
            record['checks'].append('both exact effective totals are above players and inside viewport width')
            before = frame(page, record, 'before')
            if scale == 3:
                record['checks'].append('3x proposal/match/edit layout only; transfer matrix runs at 1x and 1.6x')
                record['passed'] = True
                context.close()
                continue
            if long:
                box = reach_handle(page, cdp, width, NAMES[0])
                y = box['y'] + box['height'] / 2
                swipe(page, cdp, (box['x'] + 8, y), (box['x'] + 8, y - 130))
                assert handle(page, NAMES[0])['y'] < box['y'] - 30
                frame(page, record, 'scrolled')
                assert all_sides(page, cdp, width, count) == initial
                record['checks'].append('quick vertical swipe ON HANDLE scrolls without transfer')
                assert not record['errors'], record['errors']
                context.close()
                record['passed'] = True
                continue
            selected = NAMES[7] if empty else NAMES[0]
            hover_images = []
            transfer(page, cdp, record, selected, 'away', hover=lambda: hover_images.append(frame(page, record, 'highlight')))
            expected = dict(initial, **{selected: 'away'})
            actual = all_sides(page, cdp, width, count)
            assert actual == expected, (actual, expected)
            assert hover_images[0] != before
            totals(page, record, expected, snapshot=screen == 'match')
            frame(page, record, 'moved')
            record['checks'].append('hold ON HANDLE transfers exactly one identity and updates both exact totals')
            back = selected if empty else NAMES[7]
            transfer(page, cdp, record, back, 'home')
            expected[back] = 'home'
            actual = all_sides(page, cdp, width, count)
            assert actual == expected, (actual, expected)
            totals(page, record, expected, snapshot=screen == 'match')
            cancel_name = selected if not empty else NAMES[0]
            cancel_side = 'home' if expected[cancel_name] == 'away' else 'away'
            transfer(page, cdp, record, cancel_name, cancel_side, cancel=True)
            assert all_sides(page, cdp, width, count) == expected
            record['checks'].append('reverse transfer and touchCancel preserve every identity')
            if screen == 'match':
                page.get_by_role('button', name='Zapisz', exact=True).tap()
                page.wait_for_timeout(350)
                totals(page, record, expected, snapshot=True)
                frame(page, record, 'saved')
                edit(page)
                assert all_sides(page, cdp, width, count) == expected
                transfer(page, cdp, record, cancel_name, cancel_side, mouse=True)
                assert all_sides(page, cdp, width, count) == dict(expected, **{cancel_name: cancel_side})
                page.get_by_role('button', name='Anuluj', exact=True).tap()
                page.wait_for_timeout(250)
                totals(page, record, expected, snapshot=True)
                edit(page)
                assert all_sides(page, cdp, width, count) == expected
                frame(page, record, 'cancel-restored')
                record['checks'].append('fake save/reopen and cancel restore exact totals and sides; mouse handle drag works')
            else:
                page.get_by_role('button', name='Zakceptuj propozycję', exact=True).tap()
                page.get_by_role('button', name='Akcje meczu', exact=True).wait_for()
                page.wait_for_timeout(350)
                totals(page, record, expected, snapshot=True)
                frame(page, record, 'accepted')
                edit(page)
                assert all_sides(page, cdp, width, count) == expected
                record['checks'].append('fake acceptance opens details with exact transferred sides and snapshot totals')
            assert not record['errors'], record['errors']
            context.close()
            record['passed'] = True
        print(f'PASS: {len(records)} cases; Chromium touch EMULATION; in-memory fakes, not physical Android/live DB')
    except BaseException:
        if records:
            frame(page, records[-1], 'failure')
            (OUT / 'failure-dom.html').write_text(page.locator('flt-semantics-host').inner_html())
        raise
    finally:
        browser.close()
        (OUT / 'checks.json').write_text(json.dumps(records, indent=2, ensure_ascii=False))
