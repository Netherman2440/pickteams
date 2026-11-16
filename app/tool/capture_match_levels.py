"""Capture real Flutter screens with SYNTHETIC local HTTP fixtures only.

Run under the repository nonblocking lock and memory gate. No production access.
python tool/capture_match_levels.py BUILD_DIRECTORY OUTPUT_DIRECTORY
"""
import functools
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import sys
from threading import Thread
from urllib.parse import urlencode, urlparse


def run(build, output):
    from playwright.sync_api import sync_playwright
    build, out = Path(build).resolve(), Path(output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(SimpleHTTPRequestHandler, directory=str(build)))
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    records = []
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            try:
                cases = [
                    ('list', {'screen': 'list'}, 'Poziom meczu'),
                    ('details', {'screen': 'details'}, 'Poziom meczu'),
                    ('settings', {'screen': 'settings'}, 'Zmiana progów gwiazdek'),
                    ('thresholds', {'screen': 'stars'}, 'Automatyczne połówki'),
                    ('hidden-25', {'screen': 'list', 'completed': '25'}, 'ZIELONI'),
                    ('unconfigured', {'screen': 'stars', 'configured': 'false'}, 'Progi nie są skonfigurowane.'),
                    ('permission', {'screen': 'stars', 'guest': 'true'}, 'Brak uprawnień.'),
                    ('load-failure', {'screen': 'stars', 'failLoad': 'true'}, 'Nie udało się wczytać progów.'),
                ]
                for name, query, ready in cases:
                    if os.environ.get('MATCH_LEVEL_CASE') not in (None, name):
                        continue
                    page = browser.new_page(viewport={'width': 390, 'height': 1000}, device_scale_factor=1)
                    errors = []
                    page.on('pageerror', lambda e: errors.append(str(e)))
                    def local_only(route):
                        url = route.request.url
                        if urlparse(url).hostname == '127.0.0.1':
                            route.continue_()
                        elif url.startswith('https://fonts.googleapis.com/'):
                            route.fulfill(status=200, content_type='text/css', body='')
                        else:
                            route.abort()
                    page.route('**/*', local_only)
                    page.goto(f'http://127.0.0.1:{server.server_port}/?{urlencode(query)}')
                    try:
                        page.wait_for_function('(text) => window.matchLevelMetrics && JSON.parse(matchLevelMetrics()).labels.some(s => s.includes(text))', arg=ready)
                    except Exception:
                        page.screenshot(path=str(out / f'{name}-failed.png'))
                        (out / f'{name}-failed.json').write_text(json.dumps(page.evaluate('JSON.parse(matchLevelMetrics())'), indent=2, ensure_ascii=False))
                        raise
                    # Wait for the actual loaded provider rather than only match text.
                    if name == 'hidden-25':
                        page.wait_for_function('JSON.parse(matchLevelMetrics()).requests.includes("GET matches")')
                    metrics = page.evaluate('JSON.parse(matchLevelMetrics())')
                    assert any('SYNTHETIC' in label for label in metrics['labels'])
                    if name in ('list', 'details'):
                        assert metrics['ratings'] == [3.5], metrics
                    if name in ('hidden-25', 'permission'):
                        assert metrics['ratings'] == [], metrics
                    if name == 'thresholds':
                        assert len(metrics['fields']) == 5, metrics
                    image = out / f'{name}.png'
                    page.screenshot(path=str(image))
                    records.append({'case': name, 'query': query, 'image': image.name, 'sha256': hashlib.sha256(image.read_bytes()).hexdigest(), **metrics, 'pageErrors': list(errors)})
                    assert not errors, errors
                    if name == 'thresholds':
                        first = metrics['fields'][0]
                        page.mouse.click(first['x'], first['y'])
                        page.keyboard.press('Control+A')
                        page.keyboard.type('20')
                        page.wait_for_function('JSON.parse(matchLevelMetrics()).fields[0].text === "20"')
                        page.wait_for_function('JSON.parse(matchLevelMetrics()).labels.includes("Wpisz pięć skończonych wartości w kolejności rosnącej.")')
                        invalid = out / 'validation.png'
                        page.screenshot(path=str(invalid))
                        records.append({'case': 'validation', 'image': invalid.name, 'sha256': hashlib.sha256(invalid.read_bytes()).hexdigest(), **page.evaluate('JSON.parse(matchLevelMetrics())')})
                    page.close()
            finally:
                browser.close()
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
        (out / 'browser.json').write_text(json.dumps(records, indent=2, ensure_ascii=False))
    print('Captured and checked 9 SYNTHETIC mobile browser frames (390x1000).')


if __name__ == '__main__':
    run(*sys.argv[1:])
