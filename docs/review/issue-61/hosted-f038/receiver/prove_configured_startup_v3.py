"""Run only the authenticated configured payload; no source build or login.
Only known public Google Fonts HTTPS reads are allowed outside loopback.
Production API/mutations remain blocked. This is startup, not live API proof.
"""
from collections import Counter
from functools import partial
from hashlib import sha256
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import sys
import threading
from urllib.parse import urlsplit

from playwright.sync_api import sync_playwright

os.umask(0o077)
E = Path(__file__).resolve().parent
OUT = E / 'browser-proof-v3'
OUT.mkdir(mode=0o700, exist_ok=True)
WEB = E / 'verified-envelope/web'
verdict = json.loads((E / 'receiver-verdict.json').read_text())
manifest = json.loads((E / 'verified-manifest.json').read_text())
assert verdict['verified'] and verdict['fullFileSetAndHashesVerified']
assert verdict['entrySafetyBeforeExtraction'] and not verdict['artifactCodeExecutedByVerifier']
assert manifest['promotable'] is False and manifest['productionAccepted'] is False
assert manifest['source']['headCommit'] == 'f0384d6e38673bf0f44423514e7749cb316c83d3'
assert manifest['source']['runId'] == '44100639905'
for name, expected in manifest['files'].items():
    assert sha256((E / 'verified-envelope' / name).read_bytes()).hexdigest() == expected


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def safe_error(error):
    text = str(error)
    return {'type': type(error).__name__, 'messageSha256': sha256(text.encode()).hexdigest(),
            'messageChars': len(text), 'operation': globals().get('stage', 'initialization')}


server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(WEB)))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
origin = f'http://127.0.0.1:{server.server_port}'
network = Counter()
page_errors = []
console_errors = []
result = {
    'kind': 'authenticated-configured-candidate-unauthenticated-startup',
    'head': manifest['source']['headCommit'], 'checkout': manifest['source']['checkoutCommit'],
    'runId': 44100639905, 'artifactId': 14336672484,
    'archiveSha256': verdict['archiveSha256'],
    'manifestSha256': verdict['manifestSha256'],
    'payloadTreeSha256': verdict['payloadTreeSha256'],
    'viewport': {'width': 390, 'height': 1000, 'deviceScaleFactor': 1},
    'freshEmptyProfile': True, 'serviceWorkersBlocked': True,
    'productionBackendRequestsBlocked': True, 'productionMutationPermitted': False,
    'publicFontReadHostsAllowed': ['fonts.googleapis.com', 'fonts.gstatic.com'],
    'credentialsReadOrEntered': False, 'headersOrConfigValuesRecorded': False,
    'schemaVisibilityProbePerformed': False,
    'schemaVisibilityReason': 'Production backend blocked; only source-declared public fonts allowed; no config recovery or live rows.',
    'productionDeployment': False, 'promotable': False,
}
passed = False
stage = 'launch-authenticated-payload'
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(
            executable_path='/home/agents/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome',
            headless=True, args=['--no-sandbox', '--disable-dev-shm-usage'],
        )
        try:
            context = browser.new_context(viewport={'width': 390, 'height': 1000},
                                          device_scale_factor=1, service_workers='block')
            def route_request(route):
                req = route.request
                url = urlsplit(req.url)
                local = url.scheme == 'http' and url.netloc == f'127.0.0.1:{server.server_port}'
                if local and req.method in ('GET', 'HEAD', 'OPTIONS'):
                    network['localStaticAllowed'] += 1
                    route.continue_()
                elif (url.scheme == 'https' and url.hostname in ('fonts.googleapis.com', 'fonts.gstatic.com')
                      and url.port in (None, 443) and req.method in ('GET', 'HEAD', 'OPTIONS')):
                    network['publicFontsAllowed_' + req.method] += 1
                    route.continue_()
                else:
                    network['blocked_' + req.method] += 1
                    route.abort('blockedbyclient')
            context.route('**/*', route_request)
            page = context.new_page()
            page.on('pageerror', lambda error: page_errors.append(safe_error(error)))
            def record_console(message):
                if message.type == 'error':
                    record = safe_error(message.text)
                    record['classification'] = ('expected-blocked-resource' if message.text.startswith(
                        'Failed to load resource: net::ERR_BLOCKED_BY_CLIENT') else 'other-sanitized-error')
                    console_errors.append(record)
            page.on('console', record_console)
            response = page.goto(origin + '/', wait_until='domcontentloaded', timeout=30000)
            assert response and response.status == 200
            # Real user gesture enables Flutter semantics; no app-state JS mutation.
            stage = 'enable-built-in-accessibility-control'
            placeholder = page.locator('flt-semantics-placeholder')
            placeholder.wait_for(state='attached', timeout=60000)
            result['accessibilityControlBounds'] = placeholder.bounding_box()
            result['semanticsActivation'] = 'DOM click on built-in accessibility control; no application-state assignment'
            # Flutter deliberately places this accessibility activation control
            # outside the pointer viewport. Click its real DOM control, not app state.
            placeholder.evaluate('(node) => node.click()')
            # The real router starts at LandingPage, not AuthPage. Navigate via UI.
            login_link = page.get_by_role('button', name='Zaloguj', exact=True).first
            login_link.wait_for(state='visible', timeout=60000)
            landing_frame = OUT / 'configured-unauthenticated-landing.png'
            page.screenshot(path=str(landing_frame), full_page=True)
            result['landingScreenshotSha256'] = sha256(landing_frame.read_bytes()).hexdigest()
            stage = 'real-landing-login-navigation'
            login_link.click()
            stage = 'observe-login-button'
            page.get_by_role('button', name='Zaloguj się', exact=True).wait_for(state='visible', timeout=60000)
            stage = 'observe-password-field'
            page.get_by_label('Hasło', exact=True).wait_for(state='visible', timeout=15000)
            stage = 'check-runtime-errors'
            assert not page_errors, 'Uncaught page errors'
            assert all(r['classification'] == 'expected-blocked-resource' for r in console_errors), 'Unexpected console error'
            frame = OUT / 'configured-unauthenticated-startup.png'
            page.screenshot(path=str(frame), full_page=True)
            result.update({
                'startupVerified': True, 'observedLoginText': 'Zaloguj się',
                'observedPasswordLabel': 'Hasło', 'urlPath': urlsplit(page.url).path,
                'queryOrFragmentPresent': bool(urlsplit(page.url).query or urlsplit(page.url).fragment),
                'screenshot': frame.name, 'screenshotSha256': sha256(frame.read_bytes()).hexdigest(),
                'browserVersion': browser.version,
                'scope': 'Real authenticated configured bundle boots landing then real UI login navigation; only public fonts read, all production backend/mutations blocked. Not live Auth/API/stars data or release.',
                'realLandingLoginButtonClicked': True,
            })
            context.close()
            passed = True
        except Exception:
            if 'page' in locals() and not page.is_closed():
                failure_frame = OUT / 'private-startup-failure.png'
                page.screenshot(path=str(failure_frame), full_page=True)
                result['privateFailureScreenshotSha256'] = sha256(failure_frame.read_bytes()).hexdigest()
            raise
        finally:
            browser.close()
except Exception as exc:
    result.update({'startupVerified': False, 'failure': safe_error(exc)})
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)
    result.update({'networkCounts': dict(network), 'uncaughtPageErrors': page_errors,
                   'consoleErrorsSanitized': console_errors, 'ownedServerStopped': True})
    (OUT / 'startup.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')

if passed:
    print('PASS actual authenticated configured candidate: landing and UI-navigation to login/password, fresh browser, only public fonts read, backend/mutations blocked; no live API/schema/release claim')
    print(json.dumps({'screenshotSha256': result['screenshotSha256'],
                      'networkCounts': result['networkCounts'], 'uncaughtPageErrors': len(page_errors),
                      'consoleErrors': len(console_errors), 'ownedServerStopped': True}))
    sys.exit(0)
print('FAIL configured browser startup; sanitized private startup.json records the result. No startup pass claimed.')
sys.exit(1)
