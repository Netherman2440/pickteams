"""Real profile proof: same-page pointer edits, no DOM hit-test bypass.

Run: playwright-local python tool/capture_player_details.py URL OUTPUT_DIR
Coordinates come from semantics, but mouse clicks go through the browser's real
pointer pipeline. Flutter's semantic siblings can fail Playwright locator hit
checks even when Flutter correctly routes the pointer. Every click therefore
requires a subsequent observable state assertion. No force/dispatch/style edits.
"""
import json
from pathlib import Path
import re
import sys
import time
from urllib.parse import urlparse

from playwright.sync_api import expect, sync_playwright


def run(url, output):
    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)
    records, interactions, diagnostics = [], [], []
    page = None
    case = 'startup'

    def persist():
        (out / 'browser.json').write_text(json.dumps(records, indent=2))
        (out / 'interactions.json').write_text(json.dumps(interactions, indent=2))
        (out / 'diagnostics.json').write_text(json.dumps(diagnostics, indent=2))

    with sync_playwright() as p:
        browser = p.chromium.launch()
        try:
            for width, height in [(360, 640), (1440, 1000)]:
                for scale in [1, 1.6]:
                    for role in ['owner', 'viewer']:
                        case = f'profile-{width}-{scale}-{role}'
                        page = browser.new_page(
                            viewport={'width': width, 'height': height},
                            device_scale_factor=1,
                        )
                        page.set_default_timeout(10000)
                        errors, console, requests, blocked = [], [], [], []
                        diagnostics.append({'case': case, 'pageErrors': errors,
                                            'console': console, 'failedRequests': requests,
                                            'blockedExternal': blocked})
                        page.on('pageerror', lambda error: errors.append(str(error)))
                        page.on('console', lambda msg: console.append({
                            'type': msg.type, 'text': msg.text, 'location': msg.location}))
                        page.on('requestfailed', lambda request: requests.append({
                            'url': request.url, 'failure': request.failure,
                            'controlledFontBlock': urlparse(request.url).hostname in
                            ['fonts.googleapis.com', 'fonts.gstatic.com']}))

                        def local_only(route):
                            if urlparse(route.request.url).netloc == urlparse(url).netloc:
                                route.continue_()
                            else:
                                blocked.append(route.request.url)
                                route.abort()

                        page.route('**/*', local_only)
                        page.goto(f'{url}/?long=true&scale={scale}&role={role}&fail=true',
                                  wait_until='networkidle')
                        page.wait_for_selector('flutter-view')
                        # Keyboard activation of Flutter's accessibility entry point.
                        page.locator('flt-semantics-placeholder').press('Enter')
                        expect(page.get_by_text('Ranking: 59.36', exact=True)).to_be_attached()

                        def button(label):
                            return page.get_by_role('button', name=label, exact=True)

                        def dialog():
                            return page.get_by_role('alertdialog')

                        def settled_box(target):
                            """Wait for route/scroll animations, using observed geometry."""
                            expect(target).to_be_visible()
                            deadline = time.monotonic() + 10
                            previous, stable = None, 0
                            while time.monotonic() < deadline:
                                box = target.bounding_box()
                                stable = stable + 1 if box == previous else 0
                                if box and stable >= 3:
                                    return box
                                previous = box
                                page.wait_for_timeout(80)
                            raise AssertionError('Target did not settle')

                        def reveal(target):
                            # Natural wheel scrolling, not DOM scroll/style mutation.
                            for _ in range(30):
                                box = settled_box(target)
                                if box['y'] >= 120 and box['y'] + box['height'] <= height - 8:
                                    return box
                                direction = 180 if box['y'] + box['height'] > height - 8 else -180
                                page.mouse.move(width - 24, height / 2)
                                page.mouse.wheel(0, direction)
                                page.wait_for_timeout(100)
                            raise AssertionError('Could not reveal target by scrolling')

                        def pointer(target, action, scroll=True):
                            box = reveal(target) if scroll else settled_box(target)
                            x, y = box['x'] + box['width'] / 2, box['y'] + box['height'] / 2
                            assert 0 <= x < width and 0 <= y < height, box
                            hit = page.evaluate('''([x,y]) => {
                              const n = document.elementFromPoint(x,y);
                              return n ? {tag:n.tagName,id:n.id,role:n.getAttribute('role')} : null;
                            }''', [x, y])
                            interactions.append({'case': case, 'action': action,
                                                 'method': 'mouse.click', 'center': [x, y],
                                                 'target': target.evaluate('(n) => n.id'), 'hit': hit})
                            persist()
                            page.mouse.click(x, y)

                        def capture(state):
                            assert not errors, errors
                            unexpected = [r for r in requests if not r['controlledFontBlock']]
                            assert not unexpected, unexpected
                            render_errors = [m for m in console if re.search(
                                r'overflowed|RenderFlex|EXCEPTION CAUGHT|Uncaught|Error:', m['text'])]
                            assert not render_errors, render_errors
                            document_width = page.evaluate('document.documentElement.scrollWidth')
                            assert document_width == width, (document_width, width)
                            image = out / f'{case}-{state}.png'
                            page.screenshot(path=str(image))
                            records.append({'case': case, 'state': state, 'width': width,
                                            'height': height, 'scale': scale, 'role': role,
                                            'image': str(image), 'documentWidth': document_width})
                            persist()

                        capture('view')
                        if role == 'owner':
                            expect(button('Edytuj gracza')).to_have_count(1)
                            pointer(button('Edytuj gracza'), 'enter edit')
                            expect(button('Gotowe')).to_be_visible()
                            expect(button('Edytuj gracza')).to_have_count(0)
                            capture('edit')
                            for label, field in [('Edytuj nazwę', 'name'),
                                                 ('Edytuj ranking', 'ranking'),
                                                 ('Edytuj pozycję', 'position')]:
                                target = page.get_by_role('button', name=re.compile('^' + label))
                                pointer(target, f'open {field}')
                                expect(dialog()).to_have_count(1)
                                expect(page.get_by_text(label, exact=True)).to_be_visible()
                                settled_box(button('Zapisz'))
                                capture(field)
                                pointer(button('Zapisz'), f'save {field}', scroll=False)
                                # A still-open ordinary dialog is NOT a failed-save frame.
                                message = 'Fixture save failed'
                                # SelectableText exposes its text as a disabled textarea
                                # value, unlike the name TextField's error decoration.
                                error = (page.get_by_text(message, exact=True) if field == 'name'
                                         else dialog().locator('textarea[disabled]'))
                                expect(error).to_be_visible()
                                if field != 'name':
                                    # Read-only SelectableText keeps its passive semantic
                                    # textarea empty. A real tap activates text selection
                                    # and exposes the rendered string in its semantics.
                                    pointer(error, f'select {field} error text', scroll=False)
                                    expect(error).to_have_value(message)
                                expect(dialog()).to_have_count(1)
                                settled_box(button('Anuluj'))
                                capture(f'{field}-error')
                                pointer(button('Anuluj'), f'cancel {field}', scroll=False)
                                expect(dialog()).to_have_count(0)
                                expect(error).to_have_count(0)
                                expect(button('Gotowe')).to_be_attached()
                                expect(page.get_by_role('button', name=re.compile(
                                    r'^Edytuj ranking.*Ranking: 59\.36', re.S))).to_be_attached()
                            pointer(button('Gotowe'), 'exit edit')
                            expect(button('Edytuj gracza')).to_be_visible()
                            for label in ['Edytuj nazwę', 'Edytuj ranking', 'Edytuj pozycję']:
                                expect(page.get_by_role('button', name=re.compile('^' + label))).to_have_count(0)
                            capture('done')
                        else:
                            expect(button('Edytuj gracza')).to_have_count(0)
                            expect(button('Usuń gracza')).to_have_count(0)
                            pointer(page.get_by_text('Ranking: 59.36', exact=True), 'denied field click')
                            expect(dialog()).to_have_count(0)
                            expect(button('Gotowe')).to_have_count(0)

                        # The graph is real canvas output; populated state is also checked
                        # in widget tests. Scroll naturally to expose graph and footer.
                        expect(page.get_by_text('Brak zmian rankingu', exact=True)).to_have_count(0)
                        heading = page.get_by_text('Historia rankingu', exact=True)
                        previous = None
                        for _ in range(12):
                            box = settled_box(heading)
                            if abs(box['y'] - 130) < 3 or box == previous:
                                break
                            previous = box
                            page.mouse.move(width - 24, height / 2)
                            page.mouse.wheel(0, box['y'] - 130)
                            page.wait_for_timeout(100)
                        settled_box(heading)
                        capture('graph')
                        def footer_text(label):
                            # Desktop navigation also has a Stats button. The profile's
                            # footer labels are text spans beside its icon buttons.
                            return page.locator('flt-semantics span').filter(
                                has_text=re.compile('^' + label + '$'))

                        footer = footer_text('Statystyki')
                        reveal(footer)
                        settled_box(footer)
                        capture('footer')
                        for label in ['Mecze', 'Turnieje', 'Statystyki']:
                            expect(footer_text(label)).to_be_visible()
                        page.close()
                        page = None
        except Exception as error:
            (out / 'failure.txt').write_text(f'{case}\n{type(error).__name__}: {error}\n')
            if page is not None:
                page.screenshot(path=str(out / f'{case}-terminal.png'))
                (out / f'{case}-terminal.html').write_text(page.content())
            raise
        finally:
            persist()
            browser.close()


if __name__ == '__main__':
    run(*sys.argv[1:])
