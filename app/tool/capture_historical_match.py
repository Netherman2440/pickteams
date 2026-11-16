"""Capture the real Flutter match reader/page with synthetic transport only.

Run under the shared validation lock and memory gate:
python tool/capture_historical_match.py BUILD_DIRECTORY OUTPUT_DIRECTORY
Starts a loopback-only static server and stops it and Chromium before exit.
"""
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
from threading import Thread
from urllib.parse import urlparse


def run(build, output):
    from playwright.sync_api import sync_playwright

    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)
    handler = functools.partial(SimpleHTTPRequestHandler, directory=str(Path(build).resolve()))
    server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    records = []
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            try:
                for unequal in (False, True):
                    case = 'unequal' if unequal else 'equal'
                    page = browser.new_page(viewport={'width': 1440, 'height': 1000})
                    errors = []
                    page.on('pageerror', lambda e: errors.append(str(e)))

                    def local_only(route):
                        url = route.request.url
                        if urlparse(url).hostname == '127.0.0.1':
                            route.continue_()
                        elif url.startswith('https://fonts.googleapis.com/'):
                            # Unused host HTML font CSS; Flutter uses bundled fonts.
                            route.fulfill(status=200, content_type='text/css', body='')
                        else:
                            route.abort()

                    page.route('**/*', local_only)
                    page.goto(f'http://127.0.0.1:{server.server_port}/?unequal={str(unequal).lower()}')
                    page.wait_for_function('window.historicalMatchMetrics && JSON.parse(historicalMatchMetrics()).panels.length > 0')
                    baseline = None
                    for stage in range(4):
                        page.wait_for_function('(stage) => JSON.parse(historicalMatchMetrics()).stage === stage', arg=stage)
                        # The provider reload finishes after the stage changes.
                        page.wait_for_function('JSON.parse(historicalMatchMetrics()).panels.length > 0')
                        banner = (
                            f'SYNTHETIC | {"3 vs 2 (x2/3)" if unequal else "2 vs 2"} | '
                            f'{["before result", "after result", "correction", "later current score"][stage]} | '
                            f'Current p0: {[40, 95, 15, 150][stage]:.2f}'
                        )
                        score = [['-', ':', '-'], ['3', ':', '1'], ['1', ':', '4'], ['1', ':', '4']][stage]
                        # advance() changes its mutable stage before the async
                        # writer and provider refresh finish. Wait for paragraphs
                        # from the new rendered tree, not just those mutable data.
                        page.wait_for_function('''({banner, score}) => {
                            const {labels, panels} = JSON.parse(historicalMatchMetrics());
                            const separator = labels.indexOf(':');
                            return panels.length > 0 && labels.includes(banner) &&
                                JSON.stringify(labels.slice(separator - 1, separator + 2)) === JSON.stringify(score);
                        }''', arg={'banner': banner, 'score': score})
                        metrics = page.evaluate('JSON.parse(historicalMatchMetrics())')
                        assert banner in metrics['labels'], metrics
                        separator = metrics['labels'].index(':')
                        assert metrics['labels'][separator - 1:separator + 2] == score, metrics
                        assert any('SYNTHETIC' in text for text in metrics['labels']), metrics
                        assert metrics['current'] == [40, 95, 15, 150][stage], metrics
                        panels = metrics['panels']
                        expected = [{'id': i, 'ranking': rank} for i, rank in (
                            [('p1', 60), ('p3', 70), ('p0', 40), ('p2', 50)]
                            + ([('p4', 30)] if unequal else []))]
                        assert panels == expected, panels
                        totals = [text for text in metrics['labels'] if text.startswith('Ranking:')]
                        assert totals == ['Ranking: 86.7' if unequal else 'Ranking: 100.0', 'Ranking: 120.0'], totals
                        if baseline is None:
                            baseline = (panels, totals)
                        assert (panels, totals) == baseline
                        image = out / f'{case}-{stage}.png'
                        page.screenshot(path=str(image))
                        assert not errors, errors
                        records.append({'case': case, 'stage': stage, 'image': image.name, **metrics, 'pageErrors': list(errors)})
                        if stage < 3:
                            # Banner controls sit outside Navigator semantics.
                            # At the fixed 1440x1000 viewport these are the visible
                            # button centers; use real mouse input, not state mutation.
                            page.mouse.click(1325, 16)  # Next state
                    page.mouse.click(1405, 16)  # Reload
                    page.wait_for_function('JSON.parse(historicalMatchMetrics()).panels.length > 0')
                    assert page.evaluate('JSON.parse(historicalMatchMetrics()).panels') == baseline[0]
                    page.close()
            finally:
                browser.close()
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
        (out / 'browser.json').write_text(json.dumps(records, indent=2))
    print('Captured and checked 8 SYNTHETIC Flutter frames; equal/unequal, four states, then reload.')


if __name__ == '__main__':
    run(*sys.argv[1:])
