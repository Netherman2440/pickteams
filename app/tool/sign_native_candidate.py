#!/usr/bin/env python3
"""Locally sign a CI artifact, then audit it without building or installing.

Use the existing image-tools Python (Pillow). This command acquires the shared
nonblocking flock itself. It never exports the unchanged local debug key.
"""
import argparse
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-sha', required=True)
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--base', required=True, type=Path)
    parser.add_argument('--public-root', required=True, type=Path)
    parser.add_argument('--worktree', default=Path.cwd(), type=Path)
    parser.add_argument('--lock-held', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    assert UI_SOURCE is not None, 'Await corrected coordinator-approved UI source pin'
    assert re.fullmatch(r'[0-9a-f]{40}', args.source_sha)
    if not args.lock_held:
        return subprocess.call(['flock', '-n', '-E75', '/tmp/pickteams-flutter-validation.lock', sys.executable, str(Path(__file__).resolve()), *sys.argv[1:], '--lock-held'])
    os.umask(0o077)
    base, evidence, source = args.base.resolve(), args.evidence.resolve(), args.worktree.resolve()
    candidate = base/'candidates'/('final-a-'+args.source_sha)
    apk = candidate/'pickteams-release.apk'
    remote = candidate/'remote/candidate.apk'
    assert candidate.stat().st_mode & 0o777 == 0o700
    assert remote.stat().st_mode & 0o777 == 0o600
    assert not apk.exists(), 'Never overwrite an existing candidate'
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
    metadata = json.loads((candidate/'remote/metadata.json').read_text())
    assert metadata['source_sha'] == args.source_sha and metadata['reviewed_ui_source'] == UI_SOURCE
    assert metadata['entrypoint'] == 'lib/main.dart'
    assert (metadata['build_name'], metadata['build_number']) == ('1.0.3', 2026111202)
    for path, expected in metadata['runtime_input_sha256'].items():
        assert digest(source/path) == expected, 'Runtime source differs from CI'
    config = json.loads((base/'client-config.json').read_text())
    assert {k: hashlib.sha256(v.encode()).hexdigest() for k, v in config.items()} == metadata['public_config_sha256'], 'CI public config differs from protected local config'
    assert digest(remote) == metadata['apk_sha256'] and remote.stat().st_size == metadata['apk_size']
    remote_signature = run('remote-signature', [bt/'apksigner', 'verify', '--verbose', '--print-certs', remote])
    assert 'Signer #1 certificate SHA-256 digest: '+metadata['ephemeral_certificate_sha256'] in remote_signature
    assert metadata['ephemeral_certificate_sha256'] != CERTIFICATE
    run('remote-zipalign', [bt/'zipalign', '-c', '-P', '16', '4', remote])
    run('local-signing', [bt/'apksigner', 'sign', '--ks', Path.home()/'.android/debug.keystore', '--ks-key-alias', 'androiddebugkey', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', apk, remote])
    apk.chmod(0o600)
    original, signed = payload(remote), payload(apk)
    assert original == signed, 'Signing changed non-signature ZIP payload'
    (evidence/'signing-payload-comparison.json').write_text(json.dumps({'equal': True, 'entries': len(original), 'payload_sha256': original, 'excluded_signature_metadata_regex': SIGNATURE_ENTRY.pattern}, indent=2)+'\n')
    run('branding-unit', ['python3', '-m', 'unittest', 'discover', '-s', source/'app/tool', '-p', 'test_android_branding.py', '-v'])
    run('source-branding', ['python3', source/'app/tool/check_android_branding.py'])
    run('source-oauth', ['python3', source/'app/tool/check_android_oauth.py'])
    run('branding', ['python3', source/'app/tool/check_android_branding.py', '--apk', apk, '--aapt', bt/'aapt2'])
    run('badging', [bt/'aapt2', 'dump', 'badging', apk])
    run('manifest-tree', [bt/'aapt2', 'dump', 'xmltree', apk, '--file', 'AndroidManifest.xml'])
    resources = run('resources', [bt/'aapt', 'dump', '--values', 'resources', apk])
    run('manifest', [analyzer, 'manifest', 'print', apk])
    run('signature', [bt/'apksigner', 'verify', '--verbose', '--print-certs', apk])
    run('zipalign', [bt/'zipalign', '-c', '-P', '16', '-v', '4', apk])
    run('permissions', [bt/'aapt2', 'dump', 'permissions', apk])
    section = resources.split('config anydpi-v26:', 1)[1]
    match = re.search(r'com.example.app:mipmap/ic_launcher:.*?\n\s+\(string8\) "([^"]+)"', section)
    assert match, 'Adaptive resource not found'
    run('adaptive', [analyzer, 'resources', 'xml', '--file', match[1], apk])
    checks = audit(apk, source, base, evidence)
    after = preserved(protected)
    assert after == baseline, 'Protected files changed during signing/audit'
    assert public_files == {p for p in args.public_root.resolve().rglob('*') if p.is_file()}
    (evidence/'preservation-after.json').write_text(json.dumps(after, indent=2)+'\n')
    assert not run('status-after', ['git', 'status', '--porcelain'])
    final = {'apk': str(apk), 'sha256': digest(apk), 'bytes': apk.stat().st_size, 'certificate_sha256': CERTIFICATE, 'source_sha': args.source_sha, 'version': '1.0.3', 'version_code': 2026111202, 'abis': metadata['abis'], 'remote_apk_sha256': digest(remote), 'ephemeral_certificate_sha256': metadata['ephemeral_certificate_sha256'], 'checks': checks, 'publication': 'Forbidden until coordinator accepts browser and independent native review'}
    (evidence/'local-signing.json').write_text(json.dumps(final, indent=2)+'\n')
    print('Final signed APK offline acceptance passed; independent review and publication gates remain.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
