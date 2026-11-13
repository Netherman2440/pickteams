#!/usr/bin/env python3
"""Locally sign a CI artifact, then audit it without building or installing.

Use the existing image-tools Python (Pillow). This command acquires the shared
nonblocking flock itself. It never exports the unchanged local debug key.
Signing is allowed only after the downloaded artifact ZIP is bound to a
successful GitHub run of the exact expected source, and the metadata source
map equals the tracked inputs of the local checkout. The signed file is
promoted to its final name only after every payload and offline check passes.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import zipfile

from audit_native_candidate import CERTIFICATE, audit, digest
from build_native_candidate import UI_SOURCE

SIGNATURE_ENTRY = re.compile(r'^META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC))$', re.I)
REPO = 'Netherman2440/pickteams'
WORKFLOW_PATH = '.github/workflows/private-native-candidate.yml'
ARTIFACT_PREFIX = 'native-candidate-'
ARTIFACT_FILES = ('candidate.apk', 'metadata.json')


def payload(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)), 'Duplicate ZIP entries'
        entries = {}
        with path.open('rb') as raw:
            for name in names:
                if SIGNATURE_ENTRY.fullmatch(name):
                    continue
                info = archive.getinfo(name)
                raw.seek(info.header_offset)
                header = raw.read(30)
                name_size, extra_size = struct.unpack_from('<HH', header, 26)
                raw.seek(info.header_offset+30+name_size+extra_size)
                compressed = raw.read(info.compress_size)
                assert len(compressed) == info.compress_size
                entries[name] = {'sha256': hashlib.sha256(archive.read(name)).hexdigest(), 'compressed_sha256': hashlib.sha256(compressed).hexdigest(), 'compression': info.compress_type, 'size': info.file_size, 'compressed_size': info.compress_size, 'crc32': info.CRC}
        return entries


def preserved(paths):
    return {str(p): {'sha256': digest(p), 'bytes': p.stat().st_size, 'mode': oct(p.stat().st_mode & 0o777)} for p in sorted(paths)}


def production_gh_api(endpoint):
    """Fetch one GitHub endpoint with the authenticated gh CLI; credentials never print."""
    result = subprocess.run(['gh', 'api', endpoint], capture_output=True, text=True)
    assert result.returncode == 0, 'gh api failed with exit {}: {}'.format(result.returncode, endpoint)
    return json.loads(result.stdout)


def normalized_digest(value):
    """GitHub reports artifact digests as 'sha256:<hex>'; accept bare hex too."""
    assert isinstance(value, str) and value, 'Missing artifact digest'
    return value.split(':', 1)[-1].lower()


def verify_remote_provenance(repo, source_sha, artifact_zip, metadata, gh_api):
    """Bind the downloaded artifact ZIP to a successful GitHub run of source_sha.

    gh_api is injectable so tests can verify this logic without network access.
    """
    run_id = metadata['run_id']
    run = gh_api('repos/{}/actions/runs/{}'.format(repo, run_id))
    assert run['status'] == 'completed', 'Run is not completed'
    assert run['conclusion'] == 'success', 'Run did not succeed'
    assert run['head_sha'] == source_sha, 'Run head differs from expected source'
    assert metadata['source_sha'] == source_sha, 'Metadata source differs from expected source'
    assert str(run['run_attempt']) == str(metadata['run_attempt']), 'Run attempt differs from metadata'
    assert run['path'] == WORKFLOW_PATH, 'Run used a different workflow'
    assert run['head_repository']['full_name'] == repo, 'Run head repository is foreign'
    listing = gh_api('repos/{}/actions/runs/{}/artifacts'.format(repo, run_id))
    matches = [a for a in listing['artifacts'] if a['name'] == ARTIFACT_PREFIX + source_sha]
    assert len(matches) == 1, 'Expected exactly one artifact named for this source'
    artifact = matches[0]
    assert artifact['expired'] is False, 'Artifact is expired'
    assert normalized_digest(artifact['digest']) == digest(artifact_zip), 'Artifact digest differs from downloaded ZIP'
    record = gh_api('repos/{}/actions/artifacts/{}'.format(repo, artifact['id']))
    assert record['name'] == artifact['name'], 'Artifact record name differs'
    assert normalized_digest(record['digest']) == normalized_digest(artifact['digest']), 'Artifact record digest differs'
    if record.get('workflow_run') is not None:
        assert record['workflow_run']['id'] == int(run_id), 'Artifact belongs to a different run'
    return {'run': run, 'artifact': artifact, 'record': record}


def validate_input_path(source, name):
    """A tracked-input key must be a relative path inside the approved app tree."""
    assert isinstance(name, str) and name, 'Empty input path'
    assert not name.startswith('/'), 'Absolute input path'
    parts = Path(name).parts
    assert parts and parts[0] == 'app', 'Input outside app tree'
    assert '..' not in parts, 'Parent-relative input path'
    resolved = (source / name).resolve()
    assert resolved.is_relative_to((source / 'app').resolve()), 'Input resolves outside app tree'
    assert resolved.is_file(), 'Missing tracked input'
    return resolved


def tracked_inputs(source):
    """Derive the authoritative tracked-input map from the local Git checkout."""
    listing = subprocess.check_output(['git', 'ls-files', '-z', '--', 'app'], cwd=source)
    tracked = {}
    for raw in listing.split(b'\0'):
        if raw:
            name = raw.decode()
            tracked[name] = digest(validate_input_path(source, name))
    assert tracked, 'No tracked inputs'
    return tracked


def verify_tracked_inputs(metadata_map, tracked):
    """The metadata map must equal the authoritative map exactly.

    Empty, partial, extra, absolute or escaping entries are all rejected.
    """
    assert isinstance(metadata_map, dict) and metadata_map, 'Empty source map'
    assert set(metadata_map) == set(tracked), 'Source map keys differ from checkout'
    for name, expected in tracked.items():
        assert metadata_map[name] == expected, 'Input digest differs: ' + name


@contextmanager
def atomic_candidate(final_path):
    """Sign to a protected temporary output; promote only after every check passes.

    Any failure deletes the owned temporary file and leaves no artifact that
    looks accepted.
    """
    # Keep an .apk suffix: apkanalyzer sniffs the file type from the extension.
    temp = final_path.parent / ('.' + final_path.stem + '-' + str(os.getpid()) + '.apk')
    temp.unlink(missing_ok=True)
    try:
        yield temp
        assert temp.is_file(), 'Signing produced no output'
        os.chmod(temp, 0o600)
        os.replace(temp, final_path)
    finally:
        temp.unlink(missing_ok=True)
        (final_path.parent / (temp.stem + '.idsig')).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-sha', required=True)
    parser.add_argument('--artifact-zip', required=True, type=Path, help='Downloaded GitHub artifact ZIP')
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--base', required=True, type=Path)
    parser.add_argument('--public-root', required=True, type=Path)
    parser.add_argument('--repo', default=REPO)
    parser.add_argument('--worktree', default=Path.cwd(), type=Path)
    parser.add_argument('--lock-held', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    assert UI_SOURCE is not None, 'Await corrected coordinator-approved UI source pin'
    assert re.fullmatch(r'[0-9a-f]{40}', args.source_sha)
    if not args.lock_held:
        return subprocess.call(['flock', '-n', '-E75', '/tmp/pickteams-flutter-validation.lock', sys.executable, str(Path(__file__).resolve()), *sys.argv[1:], '--lock-held'])
    os.umask(0o077)
    base, evidence, source = args.base.resolve(), args.evidence.resolve(), args.worktree.resolve()
    artifact_zip = args.artifact_zip.resolve()
    candidate = base/'candidates'/('final-a-'+args.source_sha)
    apk = candidate/'pickteams-release.apk'
    assert artifact_zip.is_file(), 'Artifact ZIP missing'
    assert not apk.exists(), 'Never overwrite an existing candidate'
    candidate.mkdir(parents=True, exist_ok=True, mode=0o700)
    assert candidate.stat().st_mode & 0o777 == 0o700
    remote_dir = candidate/'remote'
    remote_dir.mkdir(exist_ok=True, mode=0o700)
    assert remote_dir.stat().st_mode & 0o777 == 0o700
    evidence.mkdir(parents=True, exist_ok=True, mode=0o700)
    assert evidence.stat().st_mode & 0o777 == 0o700
    bt, analyzer = base/'sdk/build-tools/36.0.0', base/'sdk/cmdline-tools/19.0/bin/apkanalyzer'
    os.environ.update(JAVA_HOME=(base/'jdk-path.txt').read_text().strip(), ANDROID_HOME=str(base/'sdk'), ANDROID_SDK_ROOT=str(base/'sdk'), PYTHONDONTWRITEBYTECODE='1', JAVA_TOOL_OPTIONS='-Xmx512m')
    os.environ['PATH'] = os.environ['JAVA_HOME']+'/bin:'+os.environ['PATH']

    def run(name, command):
        command = list(map(str, command))
        with (evidence/'commands.jsonl').open('a') as out:
            out.write(json.dumps({'name': name, 'argv': command, 'cwd': str(source)})+'\n')
        result = subprocess.run(command, cwd=source, capture_output=True)
        (evidence/(name+'.stdout')).write_bytes(result.stdout)
        (evidence/(name+'.stderr')).write_bytes(result.stderr)
        (evidence/(name+'.exit')).write_text(str(result.returncode)+'\n')
        print(name+': exit '+str(result.returncode), flush=True)
        assert result.returncode == 0, name
        return result.stdout.decode()

    # 1. Bind the downloaded artifact ZIP to a successful GitHub run of this source.
    with zipfile.ZipFile(artifact_zip) as archive:
        names = sorted(archive.namelist())
        assert names == sorted(ARTIFACT_FILES), 'Unexpected artifact contents'
        extracted = {name: archive.read(name) for name in names}
    metadata = json.loads(extracted['metadata.json'])
    provenance = verify_remote_provenance(args.repo, args.source_sha, artifact_zip, metadata, production_gh_api)
    (evidence/'provenance.json').write_text(json.dumps(provenance, indent=2)+'\n')
    remote = remote_dir/'candidate.apk'
    for name, data in extracted.items():
        target = remote_dir/name
        if target.exists():
            assert digest(target) == hashlib.sha256(data).hexdigest(), 'Pre-placed file differs from verified artifact'
            assert target.stat().st_mode & 0o777 == 0o600, 'Pre-placed file is not private'
        else:
            target.write_bytes(data)
            target.chmod(0o600)

    public_files = {p for p in args.public_root.resolve().rglob('*') if p.is_file()}
    protected = public_files | {base/name for name in ('pickteams-release.apk', 'client-config.json', 'gradle/gradle.properties', 'build-version.txt', 'jdk-path.txt', 'signing-certificate.der')} | {Path.home()/'.android/debug.keystore'}
    baseline = preserved(protected)
    before = evidence/'preservation-before.json'
    if before.exists():
        # A coordinator can provide a wider baseline before the remote build.
        existing = json.loads(before.read_text())
        assert all(existing.get(k) == v for k, v in baseline.items()), 'Protected inputs changed since pre-build baseline'
        protected |= {Path(p) for p in existing}
        baseline = preserved(protected)
        assert existing == baseline
    else:
        before.write_text(json.dumps(baseline, indent=2)+'\n')
    (evidence/'lock-acquired.txt').write_text('flock -n -E75 /tmp/pickteams-flutter-validation.lock; only serial SDK signing/offline audits, no build or install.\n')
    assert run('head', ['git', 'rev-parse', 'HEAD']).strip() == args.source_sha
    assert not run('status-before', ['git', 'status', '--porcelain'])
    assert metadata['reviewed_ui_source'] == UI_SOURCE
    assert metadata['entrypoint'] == 'lib/main.dart'
    assert (metadata['build_name'], metadata['build_number']) == ('1.0.3', 2026111202)
    # 2. The metadata source map must equal the checkout's tracked inputs exactly.
    verify_tracked_inputs(metadata['runtime_input_sha256'], tracked_inputs(source))
    config = json.loads((base/'client-config.json').read_text())
    assert {k: hashlib.sha256(v.encode()).hexdigest() for k, v in config.items()} == metadata['public_config_sha256'], 'CI public config differs from protected local config'
    assert digest(remote) == metadata['apk_sha256'] and remote.stat().st_size == metadata['apk_size']
    remote_signature = run('remote-signature', [bt/'apksigner', 'verify', '--verbose', '--print-certs', remote])
    assert 'Signer #1 certificate SHA-256 digest: '+metadata['ephemeral_certificate_sha256'] in remote_signature
    assert metadata['ephemeral_certificate_sha256'] != CERTIFICATE
    run('remote-zipalign', [bt/'zipalign', '-c', '-P', '16', '4', remote])
    # 3. Sign to a protected temporary output; run every check before promotion.
    with atomic_candidate(apk) as signed:
        run('local-signing', [bt/'apksigner', 'sign', '--ks', Path.home()/'.android/debug.keystore', '--ks-key-alias', 'androiddebugkey', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', signed, remote])
        signed.chmod(0o600)
        assert signed.stat().st_mode & 0o777 == 0o600, 'Temporary signing output is not private'
        original, audited = payload(remote), payload(signed)
        assert original == audited, 'Signing changed non-signature ZIP payload'
        (evidence/'signing-payload-comparison.json').write_text(json.dumps({'equal': True, 'entries': len(original), 'payload_sha256': original, 'excluded_signature_metadata_regex': SIGNATURE_ENTRY.pattern}, indent=2)+'\n')
        run('branding-unit', ['python3', '-m', 'unittest', 'discover', '-s', source/'app/tool', '-p', 'test_android_branding.py', '-v'])
        run('source-branding', ['python3', source/'app/tool/check_android_branding.py'])
        run('source-oauth', ['python3', source/'app/tool/check_android_oauth.py'])
        run('branding', ['python3', source/'app/tool/check_android_branding.py', '--apk', signed, '--aapt', bt/'aapt2'])
        run('badging', [bt/'aapt2', 'dump', 'badging', signed])
        run('manifest-tree', [bt/'aapt2', 'dump', 'xmltree', signed, '--file', 'AndroidManifest.xml'])
        resources = run('resources', [bt/'aapt', 'dump', '--values', 'resources', signed])
        run('manifest', [analyzer, 'manifest', 'print', signed])
        run('signature', [bt/'apksigner', 'verify', '--verbose', '--print-certs', signed])
        run('zipalign', [bt/'zipalign', '-c', '-P', '16', '-v', '4', signed])
        run('permissions', [bt/'aapt2', 'dump', 'permissions', signed])
        section = resources.split('config anydpi-v26:', 1)[1]
        match = re.search(r'com.example.app:mipmap/ic_launcher:.*?\n\s+\(string8\) "([^"]+)"', section)
        assert match, 'Adaptive resource not found'
        run('adaptive', [analyzer, 'resources', 'xml', '--file', match[1], signed])
        checks = audit(signed, source, base, evidence)
        after = preserved(protected)
        assert after == baseline, 'Protected files changed during signing/audit'
        assert public_files == {p for p in args.public_root.resolve().rglob('*') if p.is_file()}
        (evidence/'preservation-after.json').write_text(json.dumps(after, indent=2)+'\n')
        assert not run('status-after', ['git', 'status', '--porcelain'])
        final = {'apk': str(apk), 'sha256': digest(signed), 'bytes': signed.stat().st_size, 'certificate_sha256': CERTIFICATE, 'source_sha': args.source_sha, 'version': '1.0.3', 'version_code': 2026111202, 'abis': metadata['abis'], 'remote_apk_sha256': digest(remote), 'ephemeral_certificate_sha256': metadata['ephemeral_certificate_sha256'], 'run_id': metadata['run_id'], 'run_attempt': metadata['run_attempt'], 'artifact_id': provenance['artifact']['id'], 'artifact_digest': provenance['artifact']['digest'], 'checks': checks, 'publication': 'Forbidden until coordinator accepts browser and independent native review'}
        (evidence/'local-signing.json').write_text(json.dumps(final, indent=2)+'\n')
    assert apk.stat().st_mode & 0o777 == 0o600, 'Final candidate is not private'
    print('Final signed APK offline acceptance passed; independent review and publication gates remain.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
