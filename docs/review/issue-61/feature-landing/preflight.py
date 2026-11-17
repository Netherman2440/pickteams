"""Fresh read-only feature landing guards. Does not merge or change any rule."""
import json
from pathlib import Path
import subprocess

ROOT = Path('/home/agents/dev/pickteams')
OUT = Path(__file__).parent
HEAD = 'f0384d6e38673bf0f44423514e7749cb316c83d3'
BASE = '1377d580307959b8dc25594bff9e61370c539564'
TREE = '895778801a6d96e79462f2b5f1960a52f7171fec'
REPO = 'Netherman2440/pickteams'

def api(label, path):
    result = subprocess.run(['gh', 'api', 'repos/' + REPO + ('/' + path if path else '')], check=True, capture_output=True, timeout=30)
    parsed = json.loads(result.stdout)
    (OUT / (label + '.json')).write_text(json.dumps(parsed, indent=2) + '\n')
    return parsed

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, stderr=subprocess.PIPE).decode().strip()

pr = api('pr', 'pulls/66')
branch = api('main', 'branches/main')
protection = api('protection', 'branches/main/protection')
rules = api('rules', 'rules/branches/main')
repository = api('repository', '')
run = api('main-run', 'actions/runs/44100639905')
checks = api('checks', 'commits/' + HEAD + '/check-runs')
statuses = api('statuses', 'commits/' + HEAD + '/status')
assert pr['state'] == 'open' and pr['head']['sha'] == HEAD and pr['base']['sha'] == BASE
assert pr['head']['repo']['full_name'] == pr['base']['repo']['full_name'] == REPO
assert pr['mergeable'] is True and branch['commit']['sha'] == BASE
assert repository['allow_squash_merge'] is True and repository['default_branch'] == 'main'
policy = branch['protection']['required_status_checks']
assert policy['contexts'] == [] and policy['checks'] == [] and policy['enforcement_level'] == 'off'
assert not protection.get('required_status_checks')
assert protection['required_pull_request_reviews']['required_approving_review_count'] == 0
assert {rule['type'] for rule in rules} <= {'deletion', 'non_fast_forward'}
assert run['id'] == 44100639905 and run['head_sha'] == HEAD and run['run_attempt'] == 1
assert run['event'] == 'pull_request' and run['path'] == '.github/workflows/main.yml'
assert run['status'] == 'completed' and run['conclusion'] == 'success'
assert run['repository']['full_name'] == run['head_repository']['full_name'] == REPO
assert any(p['number'] == 66 and p['head']['sha'] == HEAD and p['base']['sha'] == BASE for p in run['pull_requests'])
by_name = {c['name']: c for c in checks['check_runs']}
for name in ('analyze', 'web-build'):
    assert by_name[name]['status'] == 'completed' and by_name[name]['conclusion'] == 'success'
assert all(c['conclusion'] in ('success', 'neutral', 'skipped') for c in checks['check_runs'] if c['name'] not in ('Vercel',))
assert any(s['context'] == 'Vercel' and s['state'] == 'failure' for s in statuses['statuses'])
assert git('rev-parse', HEAD + '^{tree}') == TREE
assert git('rev-parse', HEAD + ':app/lib') == 'c9408c84f695373e5bf874d81b08bd1e2b8ba1dc'
assert git('rev-parse', 'limen/github-issue-61-issue-61') == HEAD
assert subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, HEAD], cwd=ROOT, capture_output=True).returncode == 0
state = ROOT / '.limen/task-coordinators/issue-61'
assert (state / 'review-4/review.md').read_text().startswith('PASS ' + HEAD)
assert (state / 'review-5/review.md').read_text().startswith('PASS ' + HEAD)
assert (state / 'review-6/review.md').read_text().startswith('PASS 3047fd512bb3b729022e5b4140b87d4a597b6cb9')
owner = json.loads((state / 'actual-owner-operator-receipt.json').read_text())
assert owner['exactOwnerMessage'] == 'result wszystko true' and owner['doNotRerunOperatorSql']
probe = json.loads((state / 'post-operator-api/receipt.json').read_text())
assert probe['verified'] and probe['httpStatus'] == 200 and probe['returnedRows'] == 0
assert probe['canonicalProfileMatchesAuthenticatedCandidateCommitment'] and probe['protectedProfileUnchanged']
result = {'head': HEAD, 'base': BASE, 'expectedLandedTree': TREE, 'requiredContexts': [],
          'allProjectRequiredFeatureSourceCandidateSchemaApiGatesPassed': True,
          'vercelNonrequiredFailureRetained': True, 'vercelRawCauseProven': False,
          'statusOverrideOrRuleChangePermitted': False, 'squashAllowed': True,
          'mergePerformed': False, 'releaseComplete': False}
(OUT / 'decision-input.json').write_text(json.dumps(result, indent=2) + '\n')
print('PASS fresh exact f038/base1377/tree895, successful source/candidate/schema/API evidence and repository policy; nonrequired Vercel FAIL retained, no override or mutation')
