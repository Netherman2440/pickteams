"""Independent source/hash and retained-proof inspection; no PostgreSQL run."""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
sys.dont_write_bytecode = True
OUT = Path(__file__).parent
E = OUT.parent / 'schema-operator-preparation'
HEAD = '3047fd512bb3b729022e5b4140b87d4a597b6cb9'
BASE = 'f0384d6e38673bf0f44423514e7749cb316c83d3'
CANON = '02cfb0ff0c766c77e76c75be115a981960a32db551b3cb5733f623ff61b4f35a'
OPERATOR = 'f26b6a1b597e83c9a989bc73f6ae6bf1302370ddbf1bfe25d90a5dfa09c7cfba'
def git(*args):
    return subprocess.check_output(['git', *args])
assert git('rev-parse', 'HEAD').decode().strip() == HEAD
assert not git('status', '--porcelain=v1', '--untracked-files=all')
subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, HEAD], check=True)
subprocess.run(['git', 'diff', '--check', BASE, HEAD], check=True)
assert git('rev-list', '--reverse', BASE+'..'+HEAD).decode().splitlines() == ['bc7275dfa63f29d7259981181d8bc3184586e26b', '1309711d78052eb7c5c23ea49c27f3c0e6f5281a', HEAD]
changed = git('diff', '--name-status', BASE, HEAD).decode().splitlines()
assert len(changed) == 6 and all(line.startswith('A\t') for line in changed)
for path in ['app','supabase/migrations','supabase/tests']:
    assert git('rev-parse', BASE+':'+path) == git('rev-parse', HEAD+':'+path)
source = Path('supabase/migrations/20261116120000_add_squad_star_thresholds.sql').read_bytes()
operator = Path('supabase/tools/squad_star_thresholds_operator.sql').read_bytes()
assert hashlib.sha256(source).hexdigest() == CANON
assert hashlib.sha256(operator).hexdigest() == OPERATOR
assert source == (E / 'canonical-20261116120000.sql').read_bytes()
assert operator == (E / 'squad_star_thresholds_operator.sql').read_bytes()
assert operator.split(b'-- BEGIN CANONICAL MIGRATION\n', 1)[1].split(b'\n-- END CANONICAL MIGRATION\n', 1)[0] == source
spec = importlib.util.spec_from_file_location('independent_generator_check', 'supabase/tools/generate_stars_rollout.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert module.generate(source) == operator
for altered in [source + b'\n', source.replace(b'immutable', b'stable')]:
    try:
        module.generate(altered)
    except ValueError as error:
        assert 'reviewed SHA256' in str(error)
    else:
        raise AssertionError('Changed canonical bytes admitted')
print('PASS exact clean detached delivery3047/basef038; three commits/six additions only; full app/migration/test trees unchanged')
print('PASS canonical', CANON)
print('PASS generated operator', OPERATOR)
print('PASS independent canonical-boundary/hash/fresh generation check; modified canonical bytes reject without rehash')
proof = E / 'postgres-proof-v3'
checks = (proof / 'checks.log').read_text().splitlines()
expected_failures = [line for line in checks if ': expected failure, full database dump unchanged' in line]
errors = []
for path in sorted(proof.glob('*-psql.log')):
    text = path.read_text()
    if not text.rstrip().endswith('exit=0'):
        match = re.search(r'^ERROR:\s+(.+)$', text, re.M)
        assert match and text.rstrip().endswith('exit=3'), path
        errors.append({'file':path.name, 'error':match[1]})
assert len(errors) == len(expected_failures), (len(errors), len(expected_failures))
for expected, error in zip(expected_failures, errors):
    error['case'] = expected.split(':', 1)[0].removeprefix('PASS ')
    assert 'permission denied for schema auth' not in error['error']
    print('RETAINED NEGATIVE', error['case'], error['file'], error['error'])
dumps = sorted(proof.glob('*-pg_dump.log'))
assert len(dumps) % 2 == 0
pairs = []
def normalize(path):
    text = path.read_text()
    assert text.rstrip().endswith('exit=0')
    return '\n'.join(line for line in text.splitlines() if not line.startswith(('\\restrict ', '\\unrestrict ')))
for before, after in zip(dumps[::2], dumps[1::2]):
    assert normalize(before) == normalize(after), (before.name, after.name)
    pairs.append({'before':before.name,'after':after.name,'sha256':hashlib.sha256(normalize(before).encode()).hexdigest()})
assert len(pairs) == len(errors) + 1  # RLS/vector transaction is also dump-equal.
identity = json.loads((proof / 'identity.json').read_text())
assert identity['canonicalSha256'] == CANON and identity['operatorSha256'] == OPERATOR
assert identity['thresholdVectors'] == {'validConstraintWrites':4,'invalidFunctionAndConstraintVectors':30}
print('PASS independent retained inspection:', len(errors), 'named intended negative SQL errors;', len(pairs), 'full dump pairs equal after excluding only randomized pg_dump restrict markers')
print('RETAINED final PostgreSQL', identity['postgresVersion'], '; four valid writes/30 invalid vectors; no execution repeated by this check')
(OUT / 'retained-proof-checks.json').write_text(json.dumps({'negativeErrors':errors,'equalDumpPairs':pairs}, indent=2)+'\n')
