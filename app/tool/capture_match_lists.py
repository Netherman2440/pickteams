"""Capture and measure real Flutter RootShell lists. Run via playwright-local.

Usage: python tool/capture_match_lists.py URL OUT
The preview exports actual RenderParagraph selection boxes, not HTML font metrics.
"""
import json
from pathlib import Path
import sys
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

URL, OUTPUT = sys.argv[1:]
OUT = Path(OUTPUT)
OUT.mkdir(parents=True, exist_ok=True)
HTML_FONT_CSS = ('https://fonts.googleapis.com/css2?family=Nunito:wght@600;700;800'
                 '&family=Open+Sans:wght@400;500;600;700&display=swap')
SCORES = {
    'original-match': ['14', '5'], 'reverse': ['8', '16'],
    'zero': ['0', '2'], 'draw': ['0', '0'],
    'long-score': ['12345', '67890'], 'partial': ['-', '-'],
    'long': ['8', '16'], 'pending': ['-', '-'], 'empty': [],
}
records = []


def check_card(card):
    paragraphs = card['paragraphs']
    scores = [p for p in paragraphs if p['fontSize'] == 18]
    assert [p['text'] for p in scores] == SCORES[card['id']], card
    for p in paragraphs:
        assert not p['exceededMaxLines'], p
        for glyph in p['glyphs']:
            if glyph['character'].isspace():
                continue
            assert -.5 <= glyph['left'] <= glyph['right'] <= p['width'] + .5, p
            assert -.5 <= glyph['top'] <= glyph['bottom'] <= p['height'] + .5, p
    names = [p for p in paragraphs if p['fontSize'] == 16]
    assert len(names) == 2, card
    date = next(p for p in paragraphs if p['text'] == '02.01')
    assert date['x'] + date['width'] < min(p['x'] for p in names), card
    assert names[0]['y'] + names[0]['height'] < names[1]['y'], card
    edges = []
    for score, name in zip(scores, names):
        # Do NOT merge selection boxes: that hid the original stacked digits.
        lines = {(round(g['top'], 3), round(g['bottom'], 3)) for g in score['glyphs']}
        assert len(lines) == 1, f"Multiline score: {card['id']} {score}"
        assert len(score['glyphs']) == len(score['text']), score
        assert abs(score['height'] - score['unwrappedHeight']) <= .5, score
        assert score['width'] + .5 >= score['unwrappedWidth'], score
        assert abs(score['y'] + score['height'] / 2 - name['y'] - name['height'] / 2) <= .5, card
        left = score['x'] + min(g['left'] for g in score['glyphs'])
        assert left > name['x'] + name['width'], card
        edges.append(score['x'] + max(g['right'] for g in score['glyphs']))
    if edges:
        assert max(edges) - min(edges) <= .5, card
        assert abs(scores[0]['height'] - scores[1]['height']) <= .5, card


with sync_playwright() as playwright:
    browser = playwright.chromium.launch()
    try:
        for width, height in [(360, 640), (768, 900), (1440, 1000)]:
            for scale in [1, 1.6]:
                for screen in ['squad', 'player']:
                    page = browser.new_page(viewport={'width': width, 'height': height}, device_scale_factor=1)
                    errors, blocked, console_errors, console, fulfilled_css, font_assets = [], [], [], [], [], []
                    page.on('pageerror', lambda error: errors.append(str(error)))

                    def log_console(message):
                        console.append(message.text)
                        if message.type == 'error':
                            console_errors.append(message.text)

                    page.on('console', log_console)

                    def local_only(route):
                        request = route.request
                        if urlparse(request.url).netloc == urlparse(URL).netloc:
                            route.continue_()
                        elif request.url == HTML_FONT_CSS and request.resource_type == 'stylesheet':
                            # Only the unused CanvasKit host-page CSS. Flutter's
                            # actual fonts must load from the bundled assets.
                            fulfilled_css.append(request.url)
                            route.fulfill(status=200, content_type='text/css', body='')
                        else:
                            blocked.append(request.url)
                            route.abort()

                    def response_received(response):
                        if '/fonts/' in response.url and response.url.endswith('.ttf'):
                            font_assets.append({'url': response.url, 'status': response.status})

                    page.route('**/*', local_only)
                    page.on('response', response_received)
                    page.goto(f'{URL}/?page={screen}&scale={scale}&insets=android', wait_until='networkidle')
                    page.wait_for_function('typeof matchListMetrics === "function" && JSON.parse(matchListMetrics()).length > 0')
                    page.wait_for_timeout(800)
                    seen = set()
                    for target in SCORES:
                        if target in seen:
                            continue
                        for attempt in range(25):
                            cards = json.loads(page.evaluate('matchListMetrics()'))
                            card = next((c for c in cards if c['id'] == target), None)
                            if card and card['y'] >= 136 - .5 and card['y'] + card['height'] <= height - 24 + .5:
                                break
                            delta = card['y'] - 144 if card else (height - 160) / 2
                            page.mouse.move(width / 2, height / 2)
                            page.mouse.wheel(0, delta)
                            page.wait_for_timeout(250)
                        else:
                            raise AssertionError(f'Full card not visible: {screen} {width} {scale} {target}: {cards}')
                        visible = [c for c in cards if c['y'] >= 136 - .5 and c['y'] + c['height'] <= height - 24 + .5]
                        image = OUT / f'{screen}-{width}-scale{scale}-{target}.png'
                        page.screenshot(path=str(image))
                        record = {
                            'screen': screen, 'viewport': [width, height], 'textScale': scale,
                            'image': str(image), 'cards': visible, 'errors': list(errors),
                            'blockedExternalRequests': list(blocked), 'fulfilledOptionalStylesheets': list(fulfilled_css),
                            'fontAssets': list(font_assets), 'consoleErrors': list(console_errors), 'console': list(console),
                            'documentWidth': page.evaluate('document.documentElement.scrollWidth'),
                        }
                        records.append(record)
                        (OUT / 'browser.json').write_text(json.dumps(records, indent=2))
                        assert not errors and not blocked and not console_errors, record
                        assert not any('overflowed' in line or 'EXCEPTION CAUGHT' in line for line in console), record
                        assert record['documentWidth'] == width, record
                        assert font_assets and all(f['status'] == 200 for f in font_assets), record
                        for visible_card in visible:
                            check_card(visible_card)
                            seen.add(visible_card['id'])
                    assert seen == set(SCORES), (screen, width, scale, seen)
                    page.close()
    finally:
        browser.close()
print(f'Captured {len(records)} real Flutter frames. All 9 cards fully visible and measured in each of 12 viewport/list/text-scale combinations; single-line score paint, local fonts and traffic checks passed.')
