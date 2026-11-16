"""Capture production profile widgets with synthetic data, never a live backend.

Run under the shared validation lock:
playwright-local python tool/capture_goal_comparison.py LOOPBACK_URL OUTPUT
Mobile dimensions are browser viewports, not physical device evidence.
"""
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlencode, urlparse

SCENARIOS = {
    'positive': ['+3,00', '−0,50', 'więcej strzelonych', 'mniej straconych'],
    'negative': ['−2,00', '+3,00', 'mniej strzelonych', 'więcej straconych'],
    'zero': ['Brak różnicy'],
    'rounded-zero': ['Brak różnicy'],
    'missing-color': ['Brak kompletnych danych porównawczych.'],
    'empty': ['Brak rozegranych meczów zawodnika.'],
    'no-absences': ['Brak meczów bez zawodnika.'],
    'error': ['Nie udało się pobrać danych.'],
}
VIEWPORTS = [(320, 740, 1), (390, 844, 1), (320, 900, 1.6), (1440, 1000, 1)]
HTML_FONT_CSS = ('https://fonts.googleapis.com/css2?family=Nunito:wght@600;700;800'
                 '&family=Open+Sans:wght@400;500;600;700&display=swap')


def request_action(url, resource_type, base):
    if urlparse(url).netloc == urlparse(base).netloc:
        return 'local'
    if url == HTML_FONT_CSS and resource_type == 'stylesheet':
        return 'unused-html-css'
    return 'blocked'


def fixture_url(base, scenario, scale):
    parsed = urlparse(base)
    if parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost'):
        raise ValueError('Only a loopback fixture server is permitted')
    if scenario not in SCENARIOS:
        raise ValueError('Unknown fixture')
    return base.rstrip('/') + '/?' + urlencode({
        'comparison': scenario, 'scale': scale, 'role': 'viewer',
    })


def check_diagnostics(errors, console, document_width, viewport_width):
    if errors:
        raise AssertionError(errors)
    failures = [message for message in console if re.search(
        r'overflowed|RenderFlex|EXCEPTION CAUGHT|Uncaught|Error:', message)]
    if failures:
        raise AssertionError(failures)
    if document_width != viewport_width:
        raise AssertionError((document_width, viewport_width))


def run(base, output):
    from playwright.sync_api import expect, sync_playwright

    fixture_url(base, 'positive', 1)
    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)
    records = []
    with sync_playwright() as p:
        browser = p.chromium.launch()
        try:
            for width, height, scale in VIEWPORTS:
                for scenario, labels in SCENARIOS.items():
                    case = f'{scenario}-{width}-{scale}'
                    page = browser.new_page(viewport={'width': width, 'height': height})
                    errors, console, blocked, fulfilled_css, font_assets = [], [], [], [], []
                    page.on('pageerror', lambda error: errors.append(str(error)))
                    page.on('console', lambda message: console.append(message.text))

                    def local_only(route):
                        action = request_action(route.request.url, route.request.resource_type, base)
                        if action == 'local':
                            route.continue_()
                        elif action == 'unused-html-css':
                            # Host-page CSS is unused by CanvasKit; actual Flutter
                            # fonts must load from the unchanged bundled TTF assets.
                            fulfilled_css.append(route.request.url)
                            route.fulfill(status=200, content_type='text/css', body='')
                        else:
                            blocked.append(route.request.url)
                            route.abort()

                    def font_response(response):
                        if '/fonts/' in response.url and response.url.endswith('.ttf'):
                            font_assets.append({'url': response.url, 'status': response.status})

                    page.on('response', font_response)

                    page.route('**/*', local_only)
                    try:
                        page.goto(fixture_url(base, scenario, scale), wait_until='networkidle')
                        page.locator('flt-semantics-placeholder').press('Enter')
                        heading = page.get_by_text('Drużyna z tym zawodnikiem', exact=True)
                        expect(heading).to_be_attached()
                        for label in labels:
                            expect(page.get_by_text(label, exact=False).first).to_be_attached()
                        if scenario == 'positive':
                            page.screenshot(path=str(out / f'{case}-profile.png'))
                        # Real wheel input reveals the section; no DOM or CSS mutation.
                        for _ in range(25):
                            box = heading.bounding_box()
                            label_boxes = [page.get_by_text(label, exact=False).first.bounding_box()
                                           for label in labels]
                            if (box and box['y'] >= 85 and
                                    all(b and b['y'] + b['height'] < height - 40
                                        for b in label_boxes)):
                                break
                            assert box, 'Missing production section'
                            page.mouse.move(width - 30, height / 2)
                            page.mouse.wheel(0, box['y'] - 110)
                            page.wait_for_timeout(150)
                        box = heading.bounding_box()
                        assert box and 70 <= box['y'] < height - 120, box
                        for label in labels:
                            box = page.get_by_text(label, exact=False).first.bounding_box()
                            assert box and 0 <= box['y'] and box['y'] + box['height'] <= height, box
                        image = out / f'{case}-section.png'
                        assert not blocked, blocked
                        assert font_assets and all(font['status'] == 200 for font in font_assets), font_assets
                        check_diagnostics(errors, console, page.evaluate(
                            'document.documentElement.scrollWidth'), width)
                        page.screenshot(path=str(image))
                        records.append({
                            'scenario': scenario, 'width': width, 'height': height,
                            'textScale': scale, 'image': image.name,
                            'data': 'synthetic squad match fixtures',
                            'device': 'Chromium browser viewport emulation; not a physical phone',
                            'widgets': 'production PlayerDetailsPage and PlayerGoalComparisonSection',
                            'expectedLabels': labels, 'pageErrors': errors,
                            'console': console, 'blockedExternalRequests': blocked,
                            'fulfilledUnusedHtmlCss': fulfilled_css, 'bundledFontAssets': font_assets,
                        })
                    except Exception as error:
                        page.screenshot(path=str(out / f'{case}-failure.png'))
                        records.append({'scenario': scenario, 'width': width,
                                        'failure': str(error), 'pageErrors': errors,
                                        'console': console, 'blockedExternalRequests': blocked})
                        raise
                    finally:
                        (out / 'browser.json').write_text(json.dumps(records, indent=2, ensure_ascii=False))
                        page.close()
        finally:
            browser.close()
    assert len(records) == len(VIEWPORTS) * len(SCENARIOS)
    print(f'Captured and checked {len(records)} section frames plus {len(VIEWPORTS)} profile frames')


if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2])
