"""Static data inspection ONLY: never import/execute candidate or tests."""
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path('/home/agents/dev/.pickteams-limen-worktrees/2026-11-16-issue-61-source-review-1-adf763fe')
OUT = Path(__file__).parent
EVIDENCE = OUT.parent / 'landed-release-descriptor'
HEAD = 'aa487948599e5ebd832d65c6ef5822a07c4a9db9'
BASE = '492f3f3eb1a19c380fd4f4066695423fcd506609'
FEATURE = 'f0384d6e38673bf0f44423514e7749cb316c83d3'
EXPECTED = {'app/pubspec.yaml', 'app/tool/release_contract.py',
            'app/tool/test_release_contract.py', 'app/tool/test_build_web_release.py'}

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

def blob(ref, path):
    return git('show', ref + ':' + path)

def tree(ref):
    rows = {}
    for entry in git('ls-tree', '-rz', ref).split(b'\0'):
        if entry:
            header, path = entry.split(b'\t', 1)
            rows[path.decode()] = tuple(header.decode().split())
    return rows

def dump(node):
    return ast.dump(node, include_attributes=False)

def method(module, cls, name):
    return next(m for c in module.body if isinstance(c, ast.ClassDef) and c.name == cls
                for m in c.body if isinstance(m, ast.FunctionDef) and m.name == name)

assert git('rev-parse', 'HEAD').decode().strip() == HEAD
assert not git('status', '--porcelain=v1', '--untracked-files=all')
assert subprocess.run(['git', 'symbolic-ref', '-q', 'HEAD'], cwd=ROOT,
                      capture_output=True).returncode == 1
assert git('show', '-s', '--format=%P', HEAD).decode().strip() == BASE
assert git('show', '-s', '--format=%P', BASE).decode().strip() == '1377d580307959b8dc25594bff9e61370c539564'
assert git('rev-parse', BASE + '^{tree}').decode().strip() == '895778801a6d96e79462f2b5f1960a52f7171fec'
assert git('rev-parse', BASE + '^{tree}') == git('rev-parse', FEATURE + '^{tree}')
subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, HEAD], cwd=ROOT, check=True)
assert subprocess.run(['git', 'merge-base', '--is-ancestor', FEATURE, BASE], cwd=ROOT).returncode == 1
old, new = tree(BASE), tree(HEAD)
assert old.keys() == new.keys()
changed = {p for p in new if old[p] != new[p]}
assert changed == EXPECTED
assert all(old[p][:2] == new[p][:2] == ('100644', 'blob') for p in changed)
assert all(old[p] == new[p] for p in new if p not in EXPECTED)

path = 'app/tool/release_contract.py'
prior, current = blob(BASE, path), blob(HEAD, path)
literals = {'ACCEPTED_SOURCE': ('4fe251fc2dadf5cd0e9abc70a25b2220096ded02', BASE),
            'VERSION': ('1.0.6', '1.0.7'), 'VERSION_CODE': (2026111602, 2026111701)}
normalized = ast.parse(current)
prior_ast = ast.parse(prior)
for name, (before, after) in literals.items():
    assignment = next(n for n in normalized.body if isinstance(n, ast.Assign)
                      and any(isinstance(t, ast.Name) and t.id == name for t in n.targets))
    assert ast.literal_eval(assignment.value) == after
    assignment.value = ast.Constant(before)
assert dump(normalized) == dump(prior_ast)
text = current
for before, after in literals.values():
    text = text.replace(str(after).encode(), str(before).encode())
assert text == prior
allowlist = next(n.value for n in prior_ast.body if isinstance(n, ast.Assign)
                 and any(isinstance(t, ast.Name) and t.id == 'RELEASE_FILES' for t in n.targets))
allowlist = ast.literal_eval(allowlist)
assert len(allowlist) == 10

pub = 'app/pubspec.yaml'
assert blob(HEAD, pub).replace(b'version: 1.0.7+2026111701', b'version: 1.0.6+2026111602') == blob(BASE, pub)
assert re.findall(rb'^version: (.+)$', blob(HEAD, pub), re.M) == [b'1.0.7+2026111701']
assert (1, 0, 7, 2026111701) > (1, 0, 6, 2026111602)

web_test = 'app/tool/test_build_web_release.py'
old_test, new_test = ast.parse(blob(BASE, web_test)), ast.parse(blob(HEAD, web_test))
old_method = method(old_test, 'CandidatePolicyTest', 'test_unaccepted_runtime_passes_only_the_bound_candidate_policy')
new_method = method(new_test, 'CandidatePolicyTest', old_method.name)
assert [dump(n) for n in new_method.body[:len(old_method.body)]] == [dump(n) for n in old_method.body]
added_statements = len(new_method.body) - len(old_method.body)
assert added_statements == 7
new_method.body = new_method.body[:len(old_method.body)]
assert dump(old_test) == dump(new_test)
# Parse every changed Python file and full unchanged production modules; never import them.
modules = ['app/tool/release_contract.py', 'app/tool/build_web_release.py',
           'app/tool/build_native_candidate.py', 'app/tool/sign_native_candidate.py',
           'app/tool/audit_native_candidate.py', 'app/tool/test_release_contract.py', web_test]
module_receipt = {}
for p in modules:
    current_ast = ast.parse(blob(HEAD, p))
    if p not in EXPECTED:
        assert blob(BASE, p) == blob(HEAD, p)
        assert dump(ast.parse(blob(BASE, p))) == dump(current_ast)
    module_receipt[p] = {'sha256': hashlib.sha256(blob(HEAD, p)).hexdigest(),
                         'fullAstParsed': True, 'identicalToBase': p not in EXPECTED}
for p in modules[1:5]:
    imports = [n for n in ast.parse(blob(HEAD, p)).body
               if isinstance(n, ast.ImportFrom) and n.module == 'release_contract']
    names = {a.name for n in imports for a in n.names}
    assert names >= ({'ACCEPTED_SOURCE'} if 'web_release' in p else {'VERSION', 'VERSION_CODE'})

source_hashes = {}
for p in sorted(EXPECTED):
    data = blob(HEAD, p)
    assert (ROOT / p).read_bytes() == data
    source_hashes[p] = hashlib.sha256(data).hexdigest()
pre = json.loads((EVIDENCE / 'pre-focused.json').read_text())
bound = json.loads((EVIDENCE / 'source-boundaries.json').read_text())
assert pre['head'] == BASE and pre['files'] == source_hashes == bound['sourceSha256']
assert bound['descriptorHead'] == HEAD

receipt = {'scope': 'STATIC SOURCE-SAFE DRAFT PUBLICATION ONLY; no candidate/test execution',
           'head': HEAD, 'soleParentAndPin': BASE,
           'tree': git('rev-parse', 'HEAD^{tree}').decode().strip(),
           'cleanDetached': True, 'changedFiles': sorted(changed),
           'sourceSha256': source_hashes, 'trackedEntries': len(new),
           'allOtherBlobAndModeEntriesEqual': len(new) - len(changed),
           'changedModesUnchanged': True, 'exactlyThreeContractLiteralChanges': True,
           'entireContractAstEqualAfterOnlyThreeLiteralNormalization': True,
           'releaseFilesUnchanged': allowlist, 'pubspecVersionOnly': True,
           'landedTreeEqualsAcceptedFeatureTree': True,
           'featureNotAncestorOfLandedPin': True,
           'existingWebTestAstIdenticalAfterRemovingSevenAppendedStatements': True,
           'fullProductionModuleAst': module_receipt,
           'deniedInputHashesEqualCommittedInputs': True,
           'focusedTestsExecuted': False, 'fullTestsExecuted': False}
(OUT / 'static-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
(OUT / 'exact.diff').write_bytes(git('diff', BASE, HEAD, '--'))
print(json.dumps(receipt, indent=2))
print('STATIC CHECKS PASS; no repository module imported, no test/fixture/source-policy function executed.')
