"""Independent streaming receiver supplement. No extraction/code/config recovery.
Fresh external API metadata is fetched separately. Uses the existing ZIP only.
"""
import base64
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import subprocess
import zipfile

HERE = Path(__file__).parent
CANON = HERE.parent
ART = CANON / 'configured-artifact-f038'
RECEIVER = ART / 'receiver-proof'
HEAD = 'f0384d6e38673bf0f44423514e7749cb316c83d3'
BASE = '1377d580307959b8dc25594bff9e61370c539564'
MERGE = 'b441ac4abfccd840b45b3f182f1c1c2a084795a8'
TREE = '895778801a6d96e79462f2b5f1960a52f7171fec'
REPO = 'Netherman2440/pickteams'
DIGEST = '6987795f4ef31e7fbfdbe2f85a5c7c1d316d8755887d3ab10fe120e6bb28391e'
HEX64 = re.compile('[0-9a-f]{64}')

def git(*args):
    return subprocess.check_output(['git', *args], stderr=subprocess.PIPE)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def stream(file):
    digest = hashlib.sha256()
    count = 0
    while chunk := file.read(65536):
        digest.update(chunk)
        count += len(chunk)
    return digest.hexdigest(), count

def strict(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate key')
            result[key] = value
        return result
    def bad(_):
        raise ValueError('nonfinite JSON')
    def floating(text):
        value = float(text)
        assert math.isfinite(value)
        return value
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=bad, parse_float=floating)

def canonical(path):
    assert isinstance(path, str) and 0 < len(path) <= 512
    assert not path.startswith('/') and PurePosixPath(path).as_posix() == path
    assert all(re.fullmatch('[A-Za-z0-9_.-]+', part) and part not in ('.', '..') for part in path.split('/'))
    return path

def binary_assets(raw):
    # Data-only bounded Flutter StandardMessageCodec subset, not artifact code.
    position = 0
    nodes = 0
    def take(n):
        nonlocal position
        assert 0 <= n <= 1048576 and position + n <= len(raw)
        result = raw[position:position+n]
        position += n
        return result
    def read(depth=0):
        nonlocal nodes
        nodes += 1
        assert depth <= 16 and nodes <= 32768
        tag = take(1)[0]
        if tag in (3, 4):
            return int.from_bytes(take(4 if tag == 3 else 8), 'little', signed=True)
        if tag == 6:
            assert not any(take((-position) % 8))
            number = struct.unpack('<d', take(8))[0]
            assert math.isfinite(number)
            return number
        assert tag in (7, 12, 13)
        size = take(1)[0]
        if size >= 254:
            size = int.from_bytes(take(2 if size == 254 else 4), 'little')
        assert size <= 2048
        if tag == 7:
            return take(size).decode('utf-8')
        if tag == 12:
            return [read(depth+1) for _ in range(size)]
        result = {}
        for _ in range(size):
            key = read(depth+1)
            assert isinstance(key, str) and key not in result
            result[key] = read(depth+1)
        return result
    value = read()
    assert position == len(raw) and type(value) is dict
    return value

assert git('rev-parse', 'HEAD').decode().strip() == HEAD
assert not git('status', '--porcelain=v1', '--untracked-files=all')
api = strict((HERE / 'artifact-api.json').read_bytes())
run = strict((HERE / 'run-api.json').read_bytes())
checkout = strict((HERE / 'checkout-api.json').read_bytes())
jobs = strict((HERE / 'jobs-api.json').read_bytes())
assert api['id'] == 14336672484 and api['expired'] is False
assert api['digest'] == 'sha256:' + DIGEST
assert api['name'] == f'unaccepted-web-candidate-{HEAD}-{MERGE}'
assert api['workflow_run'] == {'id': 44100639905, 'repository_id':1095300021, 'head_repository_id':1095300021, 'head_branch':'limen/github-issue-61-issue-61', 'head_sha':HEAD}
assert (run['id'], run['run_attempt'], run['event'], run['path'], run['head_sha'], run['status'], run['conclusion']) == (44100639905, 1, 'pull_request', '.github/workflows/main.yml', HEAD, 'completed', 'success')
for field in ('repository', 'head_repository'):
    assert run[field] == {'id':1095300021, 'full_name':REPO, 'fork':False}
assert len(run['pull_requests']) == 1
pr = run['pull_requests'][0]
assert pr['number'] == 66 and pr['head']['sha'] == HEAD and pr['base']['sha'] == BASE and pr['base']['ref'] == 'main'
assert pr['head']['repo']['id'] == pr['base']['repo']['id'] == 1095300021
assert checkout == {'sha':MERGE, 'tree':TREE, 'parents':[BASE, HEAD]}
assert all(job['conclusion'] == 'success' for job in jobs['jobs'])
web_job = next(job for job in jobs['jobs'] if job['name'] == 'web-build')
steps = {step['name']: step['conclusion'] for step in web_job['steps']}
assert steps['Build NONPROMOTABLE configured PR candidate'] == steps['Preserve NONPROMOTABLE candidate bundle and provenance'] == 'success'
assert steps['Build configured production entrypoint with pinned SDK'] == 'skipped'
print('PASS fresh external GitHub artifact/run/commit/jobs API binding: repository, PR66, f038/base1377/merge b441, attempt1 and real candidate job success')
with (ART / 'candidate.zip').open('rb') as file:
    archive_hash, archive_size = stream(file)
assert archive_hash == DIGEST and archive_size == api['size_in_bytes'] == 18473739
print('PASS independently streamed existing archive:', archive_hash, archive_size, 'bytes; matches EXTERNAL GitHub digest (no download)')
assert git('rev-list', '--parents', '-n', '1', MERGE).decode().split() == [MERGE, BASE, HEAD]
assert git('rev-parse', MERGE + '^{tree}').decode().strip() == TREE
assert git('rev-parse', HEAD + '^{tree}').decode().strip() == TREE
subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, HEAD], check=True)
assert git('rev-parse', MERGE + ':app/lib').decode().strip() == 'c9408c84f695373e5bf874d81b08bd1e2b8ba1dc'
assert len([r for r in git('ls-tree', '-rz', MERGE).split(b'\0') if r]) == 812
for name in ['build_web_release.py', 'release_contract.py', 'build_native_candidate.py']:
    assert Path('app/tool', name).read_bytes() == git('show', MERGE + ':app/tool/' + name)
print('PASS external commit API agrees with local Git source/ordered parents/tree; base ancestry and approved UI tree; 812 committed files (physical fixture NOT repeated)')

with zipfile.ZipFile(ART / 'candidate.zip') as archive:
    infos = archive.infolist()
    assert len(infos) == 50
    names = []
    for info in infos:
        name = canonical(info.orig_filename)
        assert name == info.filename and name not in names
        assert name in ('candidate.json', 'candidate.json.sha256') or name.startswith('web/')
        assert not info.is_dir() and not info.external_attr & 0x10
        mode = info.external_attr >> 16
        assert info.create_system == 3 and mode == stat.S_IFREG | 0o644
        assert not info.flag_bits & 1 and info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
        assert info.file_size <= (1048576 if name == 'candidate.json' else 128 if name == 'candidate.json.sha256' else 67108864)
        names.append(name)
    assert sum(info.file_size for info in infos) == 48217956
    for name in names:
        assert not any(str(parent) in names for parent in PurePosixPath(name).parents)
    raw = archive.read('candidate.json')
    manifest_hash = sha(raw)
    assert manifest_hash == 'ed5388811156b2406124edb9c2a4c4c7e8e1027c90c8fe56f7426436a939b50b'
    assert archive.read('candidate.json.sha256') == (manifest_hash + '  candidate.json\n').encode()
    m = strict(raw)
    assert set(m) == {'schemaVersion','kind','payloadPolicy','promotable','productionAccepted','notice','source','version','entrypoint','flutter','flutterRevision','configurationSha256','files','payloadTreeSha256'}
    assert type(m['schemaVersion']) is int and m['schemaVersion'] == 1
    assert m['promotable'] is False and m['productionAccepted'] is False
    assert m['kind'] == 'pickteams-unaccepted-web-candidate' and m['payloadPolicy'] == 'flutter-3.47.9-dart2js-public-v1'
    assert m['notice'] == 'UNACCEPTED CANDIDATE - NOT FOR PRODUCTION OR NATIVE PROMOTION'
    assert m['entrypoint'] == 'lib/main.dart' and m['version'] == '1.0.6+2026111602'
    assert m['flutter'] == '3.47.9' and m['flutterRevision'] == 'c197ca5199e9ee5661e865596c9c07294dfab51c'
    expected_source = {'repository':REPO,'pullRequest':66,'headCommit':HEAD,'baseCommit':BASE,'checkoutCommit':MERGE,'headTree':TREE,'baseTree':git('rev-parse', BASE+'^{tree}').decode().strip(),'runtimeTree':TREE,'mergeParents':[BASE,HEAD],'runId':'44100639905','runAttempt':'1','workflowRef':REPO+'/.github/workflows/main.yml@refs/pull/66/merge'}
    assert m['source'] == expected_source and type(m['source']['pullRequest']) is int
    assert type(m['files']) is dict and len(m['files']) == 48
    assert set(m['files']) == set(names) - {'candidate.json', 'candidate.json.sha256'}
    assert all(canonical(name).startswith('web/') and type(value) is str and HEX64.fullmatch(value) for name, value in m['files'].items())
    tree_hash = sha(json.dumps(m['files'], sort_keys=True, separators=(',', ':')).encode())
    assert tree_hash == m['payloadTreeSha256'] == 'c3bdd48f9e5d60c6fcdcfbb2705ffca86be8415212a53f6a41c88ced7f97243b'
    assert m['configurationSha256'] == '4d0584fc34995743ef5a108403f5be976c29a564b0494a3d9a0a915aaa667ab6'
    payload_size = 0
    rows = []
    for name, expected in sorted(m['files'].items()):
        with archive.open(name) as file:
            digest, size = stream(file)  # CRC/local-header checks happen on full read.
        assert digest == expected and size == archive.getinfo(name).file_size
        served = RECEIVER / 'verified-envelope' / name
        assert not served.is_symlink() and stat.S_ISREG(served.stat().st_mode)
        with served.open('rb') as file:
            assert stream(file) == (digest, size)
        rows.append({'path':name,'sha256':digest,'bytes':size})
        payload_size += size
    assert payload_size == 48211398
    actual_served = {str(p.relative_to(RECEIVER / 'verified-envelope')) for p in (RECEIVER / 'verified-envelope/web').rglob('*') if p.is_file()}
    assert actual_served == set(m['files'])
    print('PASS 50 canonical unique regular ZIP members; strict manifest, detached hash, exact NONPROMOTABLE/source/version contract; all48 streamed hashes/48211398 bytes and served-byte equality; no extras/extraction/code execution')
    # Independently identify the 14 public source copies from the fixed source
    # declarations, not from the receiver's claimed count.
    pubspec = git('show', MERGE + ':app/pubspec.yaml').decode()
    declared = re.search(r'^  assets:\n((?:    - .+\n)+)', pubspec, re.M)[1]
    roots = re.findall(r'^    - (assets/[^\s]+/)$', declared, re.M)
    assert roots == ['assets/icons/', 'assets/fonts/']
    copied = []
    for path in git('ls-tree', '-r', '--name-only', MERGE, '--', 'app/web', 'app/assets').decode().splitlines():
        if path.startswith('app/web/'):
            relative = path[len('app/web/'):]
            if relative in ('index.html', 'flutter_bootstrap.js'):
                continue
            target = 'web/' + relative
        elif any(path.startswith('app/' + root) for root in roots):
            target = 'web/assets/' + path[len('app/'):]
        else:
            continue
        assert m['files'][target] == sha(git('show', MERGE + ':' + path))
        copied.append(target)
    assert len(copied) == 14
    assets = archive.read('web/assets/AssetManifest.bin')
    encoded = strict(archive.read('web/assets/AssetManifest.bin.json'))
    assert isinstance(encoded, str) and base64.b64decode(encoded, validate=True) == assets
    mapping = binary_assets(assets)
    references = set()
    for key, variants in mapping.items():
        assert 'web/assets/' + canonical(key) in m['files']
        assert isinstance(variants, list) and variants
        for variant in variants:
            assert set(variant) <= {'asset', 'dpr'} and 'asset' in variant
            references.add('web/assets/' + canonical(variant['asset']))
            if 'dpr' in variant:
                assert type(variant['dpr']) in (int,float) and 0 < variant['dpr'] <= 64
    fonts = strict(archive.read('web/assets/FontManifest.json'))
    for family in fonts:
        assert set(family) == {'family', 'fonts'}
        for font in family['fonts']:
            references.add('web/assets/' + canonical(font['asset']))
    assert references <= set(m['files']) and len(references) == 11
    version = strict(archive.read('web/version.json'))
    assert version == {'app_name':'app','package_name':'app','version':'1.0.6','build_number':'2026111602'}
    print('PASS independent source-copy14, binary/JSON asset equivalence, public-reference11 and generated version checks; raw client configuration NOT recovered or recomputed')

startup = strict((RECEIVER / 'browser-proof-v3/startup.json').read_bytes())
assert startup['startupVerified'] is True and startup['archiveSha256'] == DIGEST
assert startup['manifestSha256'] == manifest_hash and startup['payloadTreeSha256'] == tree_hash
assert startup['head'] == HEAD and startup['checkout'] == MERGE and startup['artifactId'] == 14336672484 and startup['runId'] == 44100639905
for file, field, expected in [('configured-unauthenticated-landing.png','landingScreenshotSha256','4fe64363ab285b8ccacce1d9dde8b3c3cc0b8f67461dff998b713ecfb5cbea6e'),('configured-unauthenticated-startup.png','screenshotSha256','7675c57b0d3ed8045bc512f83613e35770b9b558a280022cce461e89b8ea472d')]:
    image = (RECEIVER / 'browser-proof-v3' / file).read_bytes()
    assert sha(image) == startup[field] == expected
    assert image[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack('>II', image[16:24]) == (390,1000)
assert startup['networkCounts'] == {'blocked_GET':1,'blocked_HEAD':6,'localStaticAllowed':16,'publicFontsAllowed_GET':7}
assert not startup['uncaughtPageErrors'] and len(startup['consoleErrorsSanitized']) == 7
assert all(r['classification'] == 'expected-blocked-resource' for r in startup['consoleErrorsSanitized'])
assert startup['credentialsReadOrEntered'] is False and startup['headersOrConfigValuesRecorded'] is False and startup['schemaVisibilityProbePerformed'] is False
assert startup['ownedServerStopped'] is True and startup['productionMutationPermitted'] is False
print('PASS V3 two image hashes/dimensions, exact artifact binding and recorded privacy/error/network counts; browser NOT rerun')
assert not git('status', '--porcelain=v1', '--untracked-files=all')
(HERE / 'independent-payloads.json').write_text(json.dumps(rows, indent=2) + '\n')
print('PASS independent lightweight streaming supplement; source unchanged; no ZIP download, extraction, fixture, compiler, browser or configuration recovery')
