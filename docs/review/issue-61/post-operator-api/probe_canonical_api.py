"""One bounded, read-only metadata request using the prior approved public profile.
No credential discovery, compiled-config recovery, user session, data rows or DDL.
"""
import ast
import base64
import hashlib
import json
from pathlib import Path
import stat
import subprocess
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, build_opener, HTTPRedirectHandler

ROOT = Path('/home/agents/dev/pickteams')
OUT = Path(__file__).parent
SOURCE = 'f0384d6e38673bf0f44423514e7749cb316c83d3'
PROFILE = Path('/home/agents/.local/share/pickteams-android-release/production/client-config.json')
MODULE = Path('/home/agents/.local/share/pickteams-validation/issue-61-schema-operator/app/tool/build_web_release.py')
EXPECTED = '4d0584fc34995743ef5a108403f5be976c29a564b0494a3d9a0a915aaa667ab6'

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, newurl):
        return None

report = {'kind': 'bounded-canonical-public-client-schema-metadata-read',
          'source': SOURCE, 'ownerReceiptAdoptedAsOwnerReport': True,
          'agentProductionDdlExecuted': False, 'productionMutations': 0,
          'userSessionsRead': False, 'compiledConfigurationRecovered': False,
          'privateValuesOrHeadersReported': False, 'liveAuthLoginProven': False,
          'wholeDatabaseRlsOrBaselineProven': False, 'httpRequestsAttempted': 0,
          'verified': False}
try:
    # Extract ONLY the previously reviewed public-input validator, not build code.
    module = MODULE.read_bytes()
    committed = subprocess.check_output(['git', 'show', SOURCE + ':app/tool/build_web_release.py'], cwd=ROOT)
    assert module == committed, 'Validator source changed'
    node = next(n for n in ast.parse(module).body if isinstance(n, ast.FunctionDef) and n.name == 'client_config')
    namespace = {'base64': base64, 'json': json, 'urlparse': urlparse}
    exec(compile(ast.Module(body=[node], type_ignores=[]), '<reviewed-public-client-validator>', 'exec'), namespace)
    before = PROFILE.stat()
    assert not PROFILE.is_symlink() and stat.S_ISREG(before.st_mode) and before.st_mode & 0o077 == 0
    raw = PROFILE.read_bytes()
    assert len(raw) < 65536
    config = namespace['client_config'](json.loads(raw))
    assert hashlib.sha256(json.dumps(config).encode()).hexdigest() == EXPECTED, 'Canonical profile/candidate commitment mismatch'
    manifest = json.loads((ROOT / '.limen/task-coordinators/issue-61/configured-artifact-f038/receiver-proof/verified-manifest.json').read_bytes())
    assert manifest['source']['headCommit'] == SOURCE and manifest['configurationSha256'] == EXPECTED
    parsed = urlparse(config['SUPABASE_URL'])
    assert parsed.scheme == 'https' and parsed.hostname and not parsed.username and not parsed.password
    assert parsed.path in ('', '/') and not parsed.query and not parsed.fragment and parsed.port in (None, 443)
    target = config['SUPABASE_URL'].rstrip('/') + '/rest/v1/squads?select=star_thresholds&limit=0'
    headers = {'apikey': config['SUPABASE_ANON_KEY'], 'Accept': 'application/json',
               'User-Agent': 'Pickteams-reviewed-schema-metadata-check'}
    if not config['SUPABASE_ANON_KEY'].startswith('sb_publishable_'):
        headers['Authorization'] = 'Bearer ' + config['SUPABASE_ANON_KEY']
    report['httpRequestsAttempted'] = 1
    with build_opener(NoRedirect()).open(Request(target, headers=headers, method='GET'), timeout=20) as response:
        assert response.status == 200 and response.geturl() == target
        body = response.read(4097)
        assert len(body) <= 4096 and json.loads(body) == [], 'Unexpected metadata response'
        report['httpStatus'] = response.status
    after = PROFILE.stat()
    assert (before.st_dev, before.st_ino, before.st_mode, before.st_size, before.st_mtime_ns) == (after.st_dev, after.st_ino, after.st_mode, after.st_size, after.st_mtime_ns)
    assert PROFILE.read_bytes() == raw
    report.update({'verified': True, 'canonicalProfileAuthority': 'same exact protected public profile used by accepted1.0.6 qualification',
                   'profileValidatedPublicOnly': True, 'canonicalProfileMatchesAuthenticatedCandidateCommitment': True,
                   'configurationSha256': EXPECTED, 'protectedProfileUnchanged': True,
                   'httpsSameCanonicalOriginNoRedirect': True, 'method': 'GET', 'relation': 'squads',
                   'selectedFields': ['star_thresholds'], 'limit': 0, 'returnedRows': 0,
                   'hostedStarThresholdColumnAndCacheVisibilityProven': True})
except Exception as error:
    report['failureType'] = type(error).__name__
    if isinstance(error, HTTPError):
        report['httpStatus'] = error.code
finally:
    (OUT / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS canonical public profile/candidate binding and live star_thresholds API/cache visibility; HTTP200/limit0/zero rows/no mutations' if report['verified'] else 'BLOCKED bounded canonical API check; sanitized receipt records class/status, no private values')
raise SystemExit(0 if report['verified'] else 1)
