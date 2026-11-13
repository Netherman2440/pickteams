"""Capture real viewport pixels and genuine Flutter interactions on loopback.

Run under the shared validation lock. Pixel measurements use the installed
private Pillow interpreter; no app dependencies or DOM styles are changed.
"""
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import subprocess
import sys
import traceback
from urllib.parse import urlencode, urlparse

IMAGE_PYTHON = Path.home() / '.local/share/pickteams-image-tools/bin/python'
CHROMIUM = Path.home() / '.cache/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-linux64/chrome-headless-shell'

# Read-only diagnostics. Invisible semantics text can extend body.scrollWidth
# while the document, Flutter surface, and painted viewport retain their size.
METRICS = r'''() => {
  const box = e => ({rect:e.getBoundingClientRect().toJSON(),
    client:[e.clientWidth,e.clientHeight], scroll:[e.scrollWidth,e.scrollHeight]});
  const overflowText=[];
  const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
  while(walker.nextNode()) {
    const n=walker.currentNode;
    if(!n.textContent.trim()) continue;
    const range=document.createRange(); range.selectNodeContents(n);
    const r=range.getBoundingClientRect();
    if(r.right<=innerWidth || r.bottom<=0 || r.top>=innerHeight) continue;
    const ancestors=[];
    for(let e=n.parentElement;e;e=e.parentElement) {
      const s=getComputedStyle(e);
      ancestors.push({tag:e.tagName,id:e.id,filter:s.filter,
        opacity:s.opacity,color:s.color,overflow:s.overflow});
    }
    overflowText.push({text:n.textContent,rect:r.toJSON(),ancestors});
  }
  return {viewport:[innerWidth,innerHeight],document:box(document.documentElement),
    body:box(document.body),flutter:box(document.querySelector('flutter-view')),
    canvases:Array.from(document.querySelectorAll('canvas')).map(box),overflowText};
}'''


def png_size(data):
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'Not a PNG'
    return struct.unpack('>II', data[16:24])


def check_viewport(metrics, size):
    width, height = size
    assert metrics['viewport'] == [width, height]
    assert metrics['document']['scroll'][0] == width, 'Document horizontal overflow'
    rect = metrics['flutter']['rect']
    assert [rect['x'], rect['y'], rect['width'], rect['height']] == [0, 0, width, height]
    for canvas in metrics['canvases']:
        r = canvas['rect']
        assert r['left'] >= 0 and r['right'] <= width, 'Paint surface outside viewport'
    for text in metrics['overflowText']:
        assert any(a['filter'] in ('opacity(0)', 'opacity(0%)')
                   and a['tag'] == 'FLT-SEMANTICS'
                   for a in text['ancestors']), f'Visible text overflow: {text}'
    body_width = metrics['body']['scroll'][0]
    if body_width > width:
        right = max((t['rect']['right'] for t in metrics['overflowText']), default=width)
        # CSSOM scrollWidth is rounded to an integer, while Range bounds keep
        # subpixels (e.g. 400.015625 becomes 400, not 401). All contributing
        # text must still have the invisible semantics ancestor checked above.
        assert math.floor(right + .5) == body_width, 'Unexplained body overflow'


def semantic_nodes(page):
    return page.locator('flt-semantics-host').evaluate(r'''host =>
      Array.from(host.querySelectorAll('flt-semantics, input')).map(e=>({
        role:e.getAttribute('role') || (e.tagName==='INPUT'?'textbox':null),
        label:e.getAttribute('aria-label'),text:e.innerText || '',
        value:e.value, rect:e.getBoundingClientRect().toJSON()
      })).filter(e=>e.label || e.role)''')


def roster_snapshot(nodes, midpoint):
    rows = [n for n in nodes if n['role'] == 'button'
            and re.search(r' \d+\.\d{2}$', n['text'])]
    return sorted((n['text'], 'home' if n['rect']['x'] < midpoint else 'away') for n in rows)


def check_badges(badges, expected, midpoint):
    for side, badge in badges.items():
        # A fractional logical edge can cover one extra physical pixel.
        assert abs(badge['width'] - expected) <= 1, badge
        assert abs(badge['height'] - expected) <= 1, badge
        assert (badge['x'] < midpoint) == (side == 'home'), badge


def capture(url, output):
    from playwright.sync_api import sync_playwright
    origin = urlparse(url)
    if origin.hostname not in ('127.0.0.1', 'localhost', '::1'):
        raise ValueError('Loopback only')
    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)
    records = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch(executable_path=str(CHROMIUM), args=['--disable-dev-shm-usage'])
        try:
            cases = [(screen, width, count, scale, long, False, True)
                     for screen in ['match', 'results'] for width in [360, 1440]
                     for count, scale, long in [(8, 1, False), (11, 1, False), (11, 1.6, True)]]
            cases += [('match', width, 8, 1, False, True, False) for width in [360, 1440]]
            for screen, width, count, scale, long, reader, saved in cases:
                height = 640 if width == 360 else 1000
                record = dict(screen=screen, width=width, height=height, count=count,
                              scale=scale, long=long, reader=reader, saved=saved,
                              errors=[], blocked=[], frames=[], checks=[])
                records.append(record)
                prefix = f'{screen}-{width}-{count}-{scale}-' + ('reader-missing' if reader else 'owner')
                page = browser.new_page(viewport=dict(width=width, height=height), device_scale_factor=1)
                page.set_default_timeout(10000)
                page.on('pageerror', lambda error: record['errors'].append(str(error)))
                page.on('console', lambda msg: record['errors'].append(msg.text)
                        if msg.type == 'error' or re.search(r'F015_FLUTTER_ERROR|overflowed|RenderFlex', msg.text) else None)

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

                def click(locator):
                    locator.click()
                    # Normal pointer departure dismisses hover tooltips. Flutter
                    # aria-owns can otherwise add tooltip text to a button name.
                    # Avoid the left edge: RootShell expands its rail on hover.
                    page.mouse.move(width - 2, height - 2)
                    page.wait_for_timeout(400)

                def frame(state, identity=False):
                    page.wait_for_timeout(400)
                    path = out / f'{prefix}-{state}.png'
                    image = page.screenshot(path=str(path), full_page=False)
                    assert png_size(image) == (width, height)
                    metrics = page.evaluate(METRICS)
                    check_viewport(metrics, (width, height))
                    nodes = semantic_nodes(page)
                    item = dict(state=state, file=path.name, sha256=hashlib.sha256(image).hexdigest(),
                                pngSize=list(png_size(image)), metrics=metrics, nodes=nodes)
                    record['frames'].append(item)
                    if identity:
                        names = ['Niebiescy', 'Czerwoni'] if screen == 'match' else ['Gospodarze', 'Goście']
                        colors = [[30, 136, 229], [229, 57, 53]] if screen == 'match' else [[129, 182, 76], [164, 200, 138]]
                        # The stacked match header hides its team names once it
                        # collapses; only the color badges stay pinned. The
                        # draft results header keeps its inline names at every
                        # extent. Edit flows return to a fresh expanded view.
                        hidden = screen == 'match' and state in ('collapsed', 'bottom')
                        identities = {}
                        for side, name, color in zip(['home', 'away'], names, colors):
                            locator = page.get_by_text(name, exact=True)
                            assert locator.count() == (0 if hidden else 1), (screen, state, name, locator.count())
                            identities[side] = dict(name=name, color=color,
                                                   label=None if hidden else locator.bounding_box(),
                                                   midpoint=width / 2)
                        result = subprocess.run([str(IMAGE_PYTHON), str(Path(__file__).with_name('lineup_pixels.py')), str(path)],
                                                input=json.dumps(identities), text=True, capture_output=True, check=True)
                        item['identities'] = identities
                        item['badges'] = json.loads(result.stdout)
                    return item

                def wheel(delta):
                    page.mouse.move(width * .6, height * .75)
                    page.mouse.wheel(0, delta)
                    page.wait_for_timeout(500)

                def open_menu():
                    click(page.get_by_role('button', name='Akcje meczu', exact=True))
                    items = page.get_by_role('menuitem').evaluate_all('(els)=>els.map(e=>e.getAttribute("aria-label"))')
                    assert items == ['Edytuj składy', 'Wprowadź wynik', 'Podgląd propozycji', 'Rewanż', 'Usuń mecz'], items
                    return items

                try:
                    params = dict(page=screen, count=count, scale=scale, long=str(long).lower(), reader=str(reader).lower(), saved=str(saved).lower())
                    page.goto(url + '/?' + urlencode(params), wait_until='networkidle')
                    page.wait_for_selector('flt-semantics-host', state='attached')
                    page.wait_for_timeout(1200)
                    top = frame('expanded', identity=True)
                    check_badges(top['badges'], 48, width / 2)
                    if reader:
                        assert page.get_by_role('button', name='Akcje meczu', exact=True).count() == 0
                        assert page.get_by_role('button', name='Zapisz', exact=True).count() == 0
                        assert page.get_by_role('textbox').count() == 0
                        assert page.get_by_text('-', exact=True).count() == 2
                        record['checks'].append('read-only: no management controls; missing score shows two dashes')
                    wheel(48 if screen == 'match' else 96)
                    collapsed = frame('collapsed', identity=True)
                    check_badges(collapsed['badges'], 16, width / 2)
                    assert top['sha256'] != collapsed['sha256']
                    for side in ['home', 'away']:
                        assert top['badges'][side]['color'] == collapsed['badges'][side]['color']
                    record['checks'].append('pixel badge bounds shrink 48 to 16 (+/-1 raster edge), colors and home/away sides unchanged')
                    wheel(3000)
                    frame('bottom', identity=True)
                    if screen == 'match' and not reader and count == 8:
                        record['menuItems'] = open_menu()
                        frame('menu')
                        click(page.get_by_role('menuitem', name='Wprowadź wynik', exact=True))
                        home = page.get_by_role('textbox', name='Gospodarze', exact=True)
                        away = page.get_by_role('textbox', name='Goście', exact=True)
                        home.wait_for(state='visible'); away.wait_for(state='visible')
                        assert page.get_by_role('menuitem').count() == 0
                        frame('edit-score')
                        for field, value in [(home, '17'), (away, '6')]:
                            click(field)
                            page.keyboard.press('Control+A')
                            page.keyboard.type(value)
                            assert page.locator('input:focus').input_value() == value
                        click(page.get_by_role('button', name='Zapisz', exact=True))
                        assert page.get_by_role('textbox').count() == 0
                        for score in ['17', '6']:
                            page.get_by_text(score, exact=True).wait_for(state='visible')
                        assert page.get_by_text(':', exact=True).is_visible()
                        saved_frame = frame('saved-score', identity=True)
                        record['checks'].append('named inputs accepted keyboard entry; Save returned visible 17 : 6')
                        before = roster_snapshot(saved_frame['nodes'], width / 2)
                        assert len(before) == 16
                        open_menu()
                        click(page.get_by_role('menuitem', name='Edytuj składy', exact=True))
                        assert page.get_by_role('textbox').count() == 2
                        frame('edit-teams')
                        # Existing team-name inputs have no accessible label.
                        # Select the sole home-side input by its real bounds,
                        # not its DOM order, and use a genuine pointer click.
                        fields = page.get_by_role('textbox').evaluate_all(
                            '(els)=>els.map(e=>e.getBoundingClientRect().toJSON())')
                        home_fields = [r for r in fields if r['right'] < width / 2]
                        assert len(home_fields) == 1, fields
                        r = home_fields[0]
                        page.mouse.click(r['x'] + r['width']/2, r['y'] + r['height']/2)
                        # Flutter replaces the semantics input with the native
                        # editor asynchronously. Do not send Ctrl+A to the old
                        # proxy before the existing value has reached the editor.
                        page.wait_for_function("document.activeElement?.tagName === 'INPUT' && document.activeElement.value === 'Niebiescy'")
                        page.wait_for_timeout(400)
                        page.keyboard.press('Control+A')
                        page.keyboard.type('Changed team')
                        assert page.locator('input:focus').input_value() == 'Changed team'
                        frame('changed-team-name')
                        click(page.get_by_role('button', name='Anuluj', exact=True))
                        assert page.get_by_role('textbox').count() == 0
                        after = frame('cancelled-teams', identity=True)
                        assert roster_snapshot(after['nodes'], width / 2) == before
                        assert after['identities'] == saved_frame['identities']
                        assert after['badges'] == saved_frame['badges']
                        assert page.get_by_text('Changed team', exact=True).count() == 0
                        record['checks'].append('Cancel discarded changed name and restored identical roster sides, names and badge paint')
                    assert not record['errors'], record['errors']
                    assert not record['blocked'], record['blocked']
                    record['status'] = 'captured; pixel inspection required'
                except Exception as error:
                    record['status'] = 'failed'
                    record['failure'] = str(error)
                    record['traceback'] = traceback.format_exc()
                    image = page.screenshot(path=str(out / f'{prefix}-failure.png'), full_page=False)
                    assert png_size(image) == (width, height)
                    (out / f'{prefix}-failure.html').write_text(page.content())
                finally:
                    page.close()
                    (out / 'browser.json').write_text(json.dumps(records, indent=2, ensure_ascii=False))
        finally:
            browser.close()
    failures = [r for r in records if r['status'] == 'failed']
    print(json.dumps(dict(cases=len(records), failures=len(failures))), flush=True)
    for record in failures:
        print(record['screen'], record['width'], record.get('failure'), flush=True)
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    capture(*sys.argv[1:])
