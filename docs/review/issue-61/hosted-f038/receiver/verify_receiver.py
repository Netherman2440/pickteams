"""Private receiver: data-only envelope validation, never executes artifact code.
Source/API constants below are receiver authority, not read from the candidate.
No download, compiler, configuration recovery, environment or client-secret read.
"""
import collections
import hashlib
import importlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import zipfile

os.umask(0o077)
sys.dont_write_bytecode = True
E = Path(__file__).resolve().parent
P = E.parent
ROOT = Path('/home/agents/dev/.pickteams-limen-worktrees/2026-11-16-issue-61-task-issue-61-8c93b1a9')
CI = P.parent / 'ci-run-44100639905'
HEAD = 'f0384d6e38673bf0f44423514e7749cb316c83d3'
BASE = '1377d580307959b8dc25594bff9e61370c539564'
CHECKOUT = 'b441ac4abfccd840b45b3f182f1c1c2a084795a8'
TREE = '895778801a6d96e79462f2b5f1960a52f7171fec'
ARCHIVE = '6987795f4ef31e7fbfdbe2f85a5c7c1d316d8755887d3ab10fe120e6bb28391e'
UI_TREE = 'c9408c84f695373e5bf874d81b08bd1e2b8ba1dc'
REPO = 'Netherman2440/pickteams'
SHA = re.compile(r'[a-f0-9]{64}')


def require(ok, message):
    if not ok:
        raise ValueError(message)


def strict(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'Duplicate JSON key')
            result[key] = value
        return result
    def constant(_):
        raise ValueError('Non-finite JSON constant')
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=constant)


def save(name, data):
    (E / name).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


def git(*args, cwd=ROOT):
    return subprocess.check_output(['git', *args], cwd=cwd, stderr=subprocess.DEVNULL)


def canonical(name):
    require(isinstance(name, str) and 0 < len(name) <= 512, 'Invalid ZIP/file-map path')
    require(PurePosixPath(name).as_posix() == name, 'Noncanonical path')
    require(all(re.fullmatch(r'[A-Za-z0-9_.-]+', p) and p not in ('.', '..')
                for p in name.split('/')), 'Unsafe path component')
    require(name in ('candidate.json', 'candidate.json.sha256') or name.startswith('web/'), 'Unknown envelope root')
    return name


def entries(infos):
    require(2 < len(infos) <= 2050, 'Archive entry-count limit')
    names = set()
    modes = collections.Counter()
    total = 0
    for info in infos:
        name = canonical(info.orig_filename)
        require(name == info.filename and name not in names, 'NUL alias or duplicate archive path')
        names.add(name)
        mode = info.external_attr >> 16
        require(not info.is_dir() and not info.external_attr & 0x10, 'Only regular-file ZIP entries allowed')
        require(stat.S_IFMT(mode) in (0, stat.S_IFREG) and not mode & 0o7111, 'Linked, special or executable ZIP mode')
        require(not info.flag_bits & 1 and info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), 'Encrypted/unsupported ZIP member')
        maximum = 1048576 if name == 'candidate.json' else 128 if name == 'candidate.json.sha256' else 67108864
        require(0 <= info.file_size <= maximum, 'ZIP member size limit')
        total += info.file_size
        require(total <= 269484160, 'Archive uncompressed-size limit')
        modes[f'{info.create_system}:{mode:o}'] += 1
    require({'candidate.json', 'candidate.json.sha256'} <= names, 'Incomplete envelope')
    for name in names:
        require(not any(str(parent) in names for parent in PurePosixPath(name).parents), 'File/ancestor alias')
    return names, total, dict(modes)


def rejected(label, fn, results):
    try:
        fn()
    except (ValueError, json.JSONDecodeError):
        results.append(label)
    else:
        raise ValueError('Receiver negative probe failed: ' + label)


def negative_checks():
    result = []
    for path in ('../x', '/web/x', 'web/../x', 'web/./x', 'web//x', 'web\\x', 'web/a\0b', 'web/a:x', 'config.json'):
        rejected('path-' + str(len(result)), lambda path=path: canonical(path), result)
    rejected('duplicate-json', lambda: strict('{"x":1,"x":2}'), result)
    rejected('nonfinite-json', lambda: strict('{"x":NaN}'), result)
    def info(name, mode=0):
        obj = zipfile.ZipInfo(name)
        obj.external_attr = mode << 16
        return obj
    good = [info('candidate.json'), info('candidate.json.sha256')]
    for label, bad in [('symlink', info('web/x', stat.S_IFLNK | 0o777)),
                       ('special', info('web/x', stat.S_IFREG | 0o4644)),
                       ('executable', info('web/x', stat.S_IFREG | 0o755)),
                       ('duplicate-member', info('candidate.json'))]:
        rejected(label, lambda bad=bad: entries(good + [bad]), result)
    oversized = info('web/x')
    oversized.file_size = 67108865
    rejected('oversized', lambda: entries(good + [oversized]), result)
    rejected('ancestor-file-alias', lambda: entries(good + [info('web/a'), info('web/a/x')]), result)
    # Same guards used on actual payload below, not claims of an adversarial producer audit.
    rejected('extra-payload', lambda: require({'web/index.html'} == {'web/index.html', 'web/extra'}, 'Payload set differs'), result)
    rejected('changed-payload', lambda: require(hashlib.sha256(b'changed').hexdigest() == hashlib.sha256(b'original').hexdigest(), 'Payload hash differs'), result)
    save('receiver-negative-probes.json', {'rejected': result, 'count': len(result)})


def main():
    os.chmod(E, 0o700)
    require(git('rev-parse', 'HEAD').decode().strip() == HEAD, 'Receiver source changed')
    require(git('status', '--porcelain').decode().strip() == 'M AGENTS.md', 'Unexpected source-worktree change')
    api = strict((E / 'artifact-api-fresh.json').read_bytes())
    run = strict((E / 'run-api-fresh.json').read_bytes())
    commit_api = strict((E / 'checkout-api.json').read_bytes())
    require(api['id'] == 14336672484 and api['digest'] == 'sha256:' + ARCHIVE and api['expired'] is False, 'Wrong authentic artifact metadata')
    require(api['name'] == f'unaccepted-web-candidate-{HEAD}-{CHECKOUT}', 'Wrong artifact name')
    require(api['workflow_run'] == {'id':44100639905, 'repository_id':1095300021, 'head_repository_id':1095300021,
                                    'head_branch':'limen/github-issue-61-issue-61', 'head_sha':HEAD}, 'Wrong artifact run binding')
    require((run['id'],run['run_attempt'],run['event'],run['path'],run['head_sha'],run['status'],run['conclusion']) ==
            (44100639905,1,'pull_request','.github/workflows/main.yml',HEAD,'completed','success'), 'Wrong trusted run')
    for key in ('repository', 'head_repository'):
        require((run[key]['id'],run[key]['full_name'],run[key]['fork']) == (1095300021, REPO, False), 'Wrong repository or fork')
    require(len(run['pull_requests']) == 1, 'Ambiguous run PR')
    pr = run['pull_requests'][0]
    require(pr['number'] == 66 and pr['base']['ref'] == 'main' and pr['base']['sha'] == BASE and pr['head']['sha'] == HEAD, 'Wrong authentic event graph')
    require(pr['head']['repo']['id'] == pr['base']['repo']['id'] == 1095300021, 'Cross-repository event')
    require(commit_api == {'sha':CHECKOUT,'tree':TREE,'parents':[BASE,HEAD]}, 'Wrong authentic checkout graph')
    archive_path = P / 'candidate.zip'
    require(archive_path.stat().st_size == api['size_in_bytes'] == 18473739, 'Archive size differs')
    require(hashlib.file_digest(archive_path.open('rb'), 'sha256').hexdigest() == ARCHIVE, 'Archive not authenticated')
    save('archive-authentication.json', {'archiveSha256':ARCHIVE,'artifactId':api['id'],'runId':run['id'],
         'matchesFreshExternalGitHubAPI':True,'archiveBytes':18473739,'downloadedAgain':False})
    negative_checks()
    with zipfile.ZipFile(archive_path) as archive:
        names, total, modes = entries(archive.infolist())
        raw = archive.read('candidate.json')
        manifest_hash = hashlib.sha256(raw).hexdigest()
        require(archive.read('candidate.json.sha256') == (manifest_hash + '  candidate.json\n').encode(), 'Detached manifest digest differs')
        m = strict(raw)
        expected_keys = {'schemaVersion','kind','payloadPolicy','promotable','productionAccepted','notice','source','version',
                         'entrypoint','flutter','flutterRevision','configurationSha256','files','payloadTreeSha256'}
        require(type(m) is dict and m.keys() == expected_keys, 'Unknown or missing manifest field')
        require(type(m['schemaVersion']) is int and m['schemaVersion'] == 1, 'Wrong schema')
        expected = {'kind':'pickteams-unaccepted-web-candidate','payloadPolicy':'flutter-3.47.9-dart2js-public-v1',
                    'promotable':False,'productionAccepted':False,
                    'notice':'UNACCEPTED CANDIDATE - NOT FOR PRODUCTION OR NATIVE PROMOTION', 'entrypoint':'lib/main.dart',
                    'flutter':'3.47.9','flutterRevision':'c197ca5199e9ee5661e865596c9c07294dfab51c'}
        require(all(type(m[k]) is type(v) and m[k] == v for k,v in expected.items()), 'Candidate contract differs')
        require(isinstance(m['configurationSha256'], str) and SHA.fullmatch(m['configurationSha256']), 'Malformed configuration commitment')
        require(type(m['files']) is dict and 0 < len(m['files']) <= 2048, 'Malformed files map')
        for name, digest in m['files'].items():
            require(canonical(name).startswith('web/') and isinstance(digest, str) and SHA.fullmatch(digest), 'Invalid file digest/map key')
        require(set(m['files']) == names - {'candidate.json','candidate.json.sha256'}, 'Payload omitted or extra')
        require({'web/index.html','web/main.dart.js'} <= m['files'].keys(), 'Missing runnable entrypoint')
        require(hashlib.sha256(json.dumps(m['files'],sort_keys=True,separators=(',',':')).encode()).hexdigest() == m['payloadTreeSha256'], 'Payload tree differs')
        require(git('rev-parse', '--is-shallow-repository').strip() == b'false', 'Incomplete local Git history')
        require(git('remote','get-url','origin').strip() in (b'https://github.com/Netherman2440/pickteams',b'https://github.com/Netherman2440/pickteams.git'), 'Wrong source origin')
        require(git('rev-list','--parents','-n','1',CHECKOUT).decode().split() == [CHECKOUT,BASE,HEAD], 'Wrong ordered Git parents')
        require(git('merge-tree','--write-tree',BASE,HEAD).decode().splitlines()[0] == TREE == git('rev-parse',CHECKOUT+'^{tree}').decode().strip(), 'Merge tree not independently reconstructed')
        subprocess.run(['git','merge-base','--is-ancestor',BASE,HEAD],cwd=ROOT,check=True)
        source = {'repository':REPO,'pullRequest':66,'headCommit':HEAD,'baseCommit':BASE,'checkoutCommit':CHECKOUT,
                  'headTree':git('rev-parse',HEAD+'^{tree}').decode().strip(), 'baseTree':git('rev-parse',BASE+'^{tree}').decode().strip(),
                  'runtimeTree':TREE,'mergeParents':[BASE,HEAD],'runId':str(run['id']),'runAttempt':str(run['run_attempt']),
                  'workflowRef':REPO+'/.github/workflows/main.yml@refs/pull/66/merge'}
        require(type(m['source']) is dict and m['source'] == source and type(m['source']['pullRequest']) is int, 'Manifest source binding differs')
        require(git('rev-parse',CHECKOUT+':app/lib').decode().strip() == UI_TREE == git('rev-parse','ec6630d:app/lib').decode().strip(), 'Reviewed UI tree differs')
        # Only trusted local producer modules, with exact immutable bytes checked.
        for name in ('build_web_release.py','build_native_candidate.py','release_contract.py'):
            require((ROOT/'app/tool'/name).read_bytes() == git('show',CHECKOUT+':app/tool/'+name), 'Verifier producer-module bytes differ')
        sys.path.insert(0,str(ROOT/'app/tool'))
        producer = importlib.import_module('build_web_release')
        require(producer._candidate_json(raw) == m, 'Producer/receiver strict JSON disagreement')
        checkout = E / 'source-checkout'
        # Reject unsafe Git modes/paths before materializing this owned checkout.
        records = [r.split(b'\t',1) for r in git('ls-tree','-rz',CHECKOUT).split(b'\0') if r]
        base_modes = {r.split(b'\t',1)[1]:r.split(b' ',1)[0] for r in git('ls-tree','-rz',BASE).split(b'\0') if r}
        for header,path in records:
            mode,kind,oid = header.split()
            require(kind == b'blob' and mode in (b'100644',b'100755') and mode == base_modes.get(path,b'100644'), 'Unsafe/changed source mode')
            require(not path.startswith(b'/') and all(p not in (b'',b'.',b'..') for p in path.split(b'/')), 'Unsafe source path')
        subprocess.run(['git','worktree','add','--quiet','--detach',str(checkout),CHECKOUT],cwd=ROOT,check=True)
        try:
            for header,path in records:
                mode,kind,oid = header.split()
                with (checkout/os.fsdecode(path)).open('rb') as file:
                    info = os.fstat(file.fileno())
                    require(stat.S_ISREG(info.st_mode) and not info.st_mode & 0o7000, 'Unsafe physical source mode')
                    require(bool(info.st_mode & stat.S_IXUSR) if mode == b'100755' else not info.st_mode & 0o111, 'Physical execute-mode mismatch')
                    digest = hashlib.sha1(b'blob '+str(info.st_size).encode()+b'\0')
                    while chunk := file.read(1048576):
                        digest.update(chunk)
                    require(digest.hexdigest().encode() == oid, 'Physical source bytes differ')
            require(git('write-tree',cwd=checkout).decode().strip() == TREE, 'Checkout index differs')
            require(not git('status','--porcelain=v1','-z','--untracked-files=all',cwd=checkout), 'Dirty source snapshot')
            allowed, source_hashes, revision = producer._candidate_public_payload(checkout/'app')
            require(revision == CHECKOUT, 'Public-policy source context differs')
            pubspec = git('show',CHECKOUT+':app/pubspec.yaml').decode()
            version = re.findall(r'^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$',pubspec,re.M)
            app_name = re.findall(r'^name:\s*([a-z_][a-z0-9_]*)\s*$',pubspec,re.M)
            require(version == [m['version']] and len(app_name) == 1, 'Version differs from immutable source')
            version_name, build_number = m['version'].split('+')
            expected_version = {'app_name':app_name[0],'package_name':app_name[0],'version':version_name,'build_number':build_number}
            asset_keys = frozenset(p[7:] for p in allowed if p.startswith('assets/'))
            manifests, references, rows = {}, set(), []
            payload_bytes = 0
            for name in sorted(m['files']):
                relative = name[4:]
                require(relative in allowed, 'Unapproved payload path')
                kind, source_digest = allowed[relative]
                # ZIP member and cumulative limits were checked BEFORE any extraction.
                content = archive.read(name)  # Also checks ZIP CRC and local/central name agreement.
                digest = hashlib.sha256(content).hexdigest()
                require(digest == m['files'][name], 'Payload hash differs')
                require(digest not in source_hashes and (source_digest is None or digest == source_digest), 'Private/copied source violation')
                producer._candidate_private_content(content, code=kind == 'code')
                metadata = producer._candidate_public_type(content,kind,asset_keys)
                if kind == 'version':
                    require(producer._candidate_json(content) == expected_version, 'Compiler version differs')
                if metadata is not None:
                    asset_manifest, refs = metadata
                    if asset_manifest is not None:
                        manifests[kind] = hashlib.sha256(asset_manifest).hexdigest()
                    references.update('web/assets/'+r for r in refs)
                payload_bytes += len(content)
                rows.append({'path':name,'sha256':digest,'bytes':len(content),'role':kind,'immutablePublicSourceMatched':source_digest is not None})
            require(len(set(manifests.values())) <= 1 and references <= m['files'].keys(), 'Inconsistent/missing public asset references')
            require(payload_bytes <= 268435456, 'Payload total size limit')
        finally:
            subprocess.run(['git','worktree','remove',str(checkout)],cwd=ROOT,check=True)
        # All receiver checks above precede extraction. Never archive.extract/extractall.
        destination = E / 'verified-envelope'
        destination.mkdir(mode=0o700)
        os.chmod(destination,0o700)
        for info in archive.infolist():
            target = destination / info.filename
            target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
            for parent in target.parents:
                if parent == E:
                    break
                os.chmod(parent,0o700)
            with target.open('xb') as file:
                os.chmod(target,0o600)
                with archive.open(info) as member:
                    size = 0
                    while chunk := member.read(1048576):
                        size += len(chunk)
                        require(size <= info.file_size, 'ZIP expanded beyond declared size')
                        file.write(chunk)
                    require(size == info.file_size, 'ZIP size mismatch')
        for row in rows:
            require(hashlib.file_digest((destination/row['path']).open('rb'),'sha256').hexdigest() == row['sha256'], 'Extracted payload differs')
        save('payload-files.json', rows)
        save('verified-manifest.json',m)
        save('receiver-verdict.json',{'verified':True,'archiveSha256':ARCHIVE,'manifestSha256':manifest_hash,
             'payloadTreeSha256':m['payloadTreeSha256'],'configurationSha256':m['configurationSha256'],
             'configurationIndependentlyRecoveredOrRecomputed':False,'configurationBinding':'Reviewed producer uses same validated in-process config for private0600 compiler JSON and manifest commitment; actual trusted hosted execution inspected separately.',
             'source':source,'uiTree':UI_TREE,'sourcePhysicalFilesVerified':len(records),'sourceCheckoutRemoved':True,
             'archiveEntries':len(names),'archiveUncompressedBytes':total,'archiveModes':modes,'payloadFiles':len(rows),'payloadBytes':payload_bytes,
             'publicAssetReferencesVerified':len(references),'assetManifestDigests':manifests,'publicSourceCopiesVerified':sum(r['immutablePublicSourceMatched'] for r in rows),
             'entrySafetyBeforeExtraction':True,'fullFileSetAndHashesVerified':True,'publicAndCompilerDataContractsVerified':True,
             'artifactCodeExecutedByVerifier':False,'promotable':False,'productionAccepted':False})
        print('PASS authenticated archive; exact envelope/source/files/public-metadata contracts; private extraction; candidate remains NONPROMOTABLE')
        print(json.dumps({'archiveEntries':len(names),'payloadFiles':len(rows),'payloadBytes':payload_bytes,'manifestSha256':manifest_hash,'payloadTreeSha256':m['payloadTreeSha256']}))


if __name__ == '__main__':
    main()
