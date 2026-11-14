"""Credential-free real-widget checks in touch-capable Chromium emulation.

Build tool/issue57_preview.dart and serve build/issue57-web on loopback port
8857. Run this script under the shared validation lock and memory gate.
Only CDP input, semantic reads and screenshots; no injected app state.
"""
import hashlib
import json
import re
from pathlib import Path
import sys
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
        || e.getAttribute('role') === 'button').map(e => ({text:e.innerText,
        rect:e.getBoundingClientRect().toJSON()}))''')
    result = {}
    for name in NAMES:
        matching = [n for n in nodes if name in n['text']]
        if matching:
            assert len(matching) == 1, (name, matching)
            result[name] = {'side': 'home' if matching[0]['rect']['x'] < width / 2 else 'away',
                            'rect': matching[0]['rect'], 'text': matching[0]['text']}
    return result


def sides(page, width):
    return {name: node['side'] for name, node in rows(page, width).items()}


def frame(page, record, name):
    path = OUT / (record['case'] + '-' + name + '.png')
    data = page.screenshot(path=str(path))
    assert page.evaluate('innerWidth') == record['width']
    assert page.evaluate('document.documentElement.scrollWidth') == record['width']
    record['frames'].append({'file': path.name, 'sha256': hashlib.sha256(data).hexdigest()})
    return data


def transfer(page, cdp, width, name, side, *, cancel=False, mouse=False, hover=None):
    row = rows(page, width)[name]['rect']
    start = (row['x'] + row['width'] / 2, row['y'] + row['height'] / 2)
    end = (width * (.25 if side == 'home' else .75), start[1])
    assert 110 < start[1] < page.viewport_size['height'] - 20, start
    if mouse:
        page.mouse.move(*start)
        page.mouse.down()
    else:
        cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{'x': start[0], 'y': start[1]}]})
        page.wait_for_timeout(600)  # Required hold, not a resource-gate wait.
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
        page.mouse.move(width - 2, 2)
    else:
        cdp.send('Input.dispatchTouchEvent', {'type': 'touchCancel' if cancel else 'touchEnd', 'touchPoints': []})
    page.wait_for_timeout(300)


def swipe(page, cdp, start, end):
    cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{'x': start[0], 'y': start[1]}]})
    for step in range(1, 9):
        cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{
            'x': start[0], 'y': start[1] + (end[1] - start[1]) * step / 8}]})
        page.wait_for_timeout(15)
    cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
    page.wait_for_timeout(350)


def edit(page):
    page.get_by_role('button', name='Akcje meczu', exact=True).tap()
    page.get_by_role('menuitem', name='Edytuj składy', exact=True).tap()
    page.get_by_text('Przytrzymaj gracza i przeciągnij do drugiej drużyny.', exact=True).wait_for()
    page.wait_for_timeout(200)


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=str(CHROME), args=['--disable-dev-shm-usage'])
    try:
        cases = [(page, width, theme, False, False) for page in ['match', 'results']
                 for width in [360, 430] for theme in ['light', 'dark']]
        cases += [('match', 390, 'dark', True, False), ('match', 390, 'light', False, True)]
        for screen, width, theme, empty, long in cases:
            case = f'{screen}-{width}-{theme}' + ('-empty' if empty else '') + ('-long' if long else '')
            record = {'case': case, 'browser': browser.version, 'width': width, 'checks': [], 'frames': [], 'errors': [], 'blockedRequests': 0}
            records.append(record)
            context = browser.new_context(viewport={'width': width, 'height': 800}, device_scale_factor=1,
                                          is_mobile=True, has_touch=True,
                                          user_agent='Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/145.0.0.0 Mobile Safari/537.36')
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
            page.goto(URL + '?' + urlencode({'page': screen, 'theme': theme, 'empty': int(empty), 'count': 8 if empty else 15, 'long': int(long)}))
            if screen == 'match':
                page.get_by_role('button', name='Akcje meczu', exact=True).wait_for()
                edit(page)
                page.get_by_role('button', name='Zmień kolor', exact=True).first.tap()
                page.get_by_role('button', name=re.compile('Kolor #FFFFFF')).wait_for()
                page.get_by_role('button', name=re.compile('Kolor #000000')).wait_for()
                frame(page, record, 'palette')
                page.get_by_role('button', name=re.compile('Kolor #FFFFFF')).tap()
                record['checks'].append('white and black palette choices available through real touch controls')
            else:
                page.get_by_role('button', name='Zakceptuj propozycję', exact=True).wait_for()
            page.wait_for_timeout(400)
            cdp = context.new_cdp_session(page)
            initial = sides(page, width)
            assert len(initial) == (8 if empty else 15), initial
            assert sum(s == 'home' for s in initial.values()) == (8 if empty else 7)
            before = frame(page, record, 'before')
            if long:
                first = rows(page, width)[NAMES[0]]['rect']
                y = first['y'] + first['height'] / 2
                swipe(page, cdp, (width * .25, y), (width * .25, 130))
                assert sides(page, width) == initial
                after = rows(page, width)[NAMES[0]]['rect']
                assert after['y'] < first['y'] - 30, (first, after)
                frame(page, record, 'scrolled')
                record['checks'].append('quick touch scroll changes position, not sides; full long identities remain in semantics')
                page.get_by_role('button', name='Anuluj', exact=True).tap()
                assert not record['errors'], record['errors']
                context.close()
                continue
            selected = NAMES[7] if empty else NAMES[0]
            hover_images = []
            transfer(page, cdp, width, selected, 'away', hover=lambda: hover_images.append(frame(page, record, 'highlight')))
            moved = sides(page, width)
            expected = dict(initial, **{selected: 'away'})
            assert moved == expected, (moved, expected)
            assert hover_images[0] != before, 'Drag must change rendered pixels'
            frame(page, record, 'moved')
            record['checks'].append('touch home to away changes exactly one of all identities; highlighted frame differs')
            back = selected if empty else NAMES[7]
            transfer(page, cdp, width, back, 'home')
            expected[back] = 'home'
            assert sides(page, width) == expected
            record['checks'].append('touch away to home preserves all identities')
            cancel_name = selected if not empty else NAMES[0]
            cancel_side = 'home' if expected[cancel_name] == 'away' else 'away'
            transfer(page, cdp, width, cancel_name, cancel_side, cancel=True)
            assert sides(page, width) == expected
            record['checks'].append('touchCancel over target changes no sides')
            if screen == 'match':
                page.get_by_role('button', name='Zapisz', exact=True).tap()
                page.wait_for_timeout(350)
                frame(page, record, 'saved')
                edit(page)
                assert sides(page, width) == expected
                record['checks'].append('fake save and reopen retain exact sides')
                transfer(page, cdp, width, cancel_name, cancel_side, mouse=True)
                changed = dict(expected, **{cancel_name: cancel_side})
                assert sides(page, width) == changed
                record['checks'].append('mouse drag works in a touch-capable browser')
                page.get_by_role('button', name='Anuluj', exact=True).tap()
                page.wait_for_timeout(250)
                edit(page)
                assert sides(page, width) == expected
                frame(page, record, 'cancel-restored')
                record['checks'].append('cancel editing restores saved sides')
            else:
                page.get_by_role('button', name='Zakceptuj propozycję', exact=True).tap()
                page.get_by_role('button', name='Akcje meczu', exact=True).wait_for()
                page.wait_for_timeout(350)
                frame(page, record, 'accepted')
                edit(page)
                assert sides(page, width) == expected
                record['checks'].append('fake acceptance opens details with transferred sides')
            assert not record['errors'], record['errors']
            context.close()
        print(f'PASS: {len(records)} browser cases; touch-capable Chromium emulation, not a physical Android device')
    finally:
        browser.close()
        (OUT / 'checks.json').write_text(json.dumps(records, indent=2, ensure_ascii=False))
