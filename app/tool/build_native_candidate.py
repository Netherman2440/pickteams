#!/usr/bin/env python3
"""Build an ephemeral-key APK; export only audited APK and structured provenance.

Run only on an ephemeral GitHub runner. Local signing is a separate operation.
Raw subprocess output and client configuration never leave RUNNER_TEMP.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

FRAMEWORK = 'c197ca5199e9ee5661e865596c9c07294dfab51c'
ENGINE = '89c39edfdfae2949f6806e4a315c0c08522238b7'
# The previous UI pin failed browser proof. The coordinator must replace this
# with the corrected reviewed commit before the next expensive build.
UI_SOURCE = '258c28b05174ff145fec0ef122fc23722f44386f'
ABIS = ('armeabi-v7a', 'arm64-v8a', 'x86_64')
# Credential-bearing callback query OR fragment is never allowed in an export;
# the bare compiled callback literal (no '?' or '#') stays allowed.
CALLBACK_CREDENTIALS = re.compile(
    rb'pl\.pickteams://auth/callback[?#][^\s\x00\"\']*(?:code|access_token|refresh_token)=[A-Za-z0-9_-]{8,}')
MIGRATION = '''analyzer:
  exclude:
    - build/**
    - android/**
    - ios/**
    - web/**
    - windows/**
    - macos/**
    - linux/**
'''.encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def audit_apk(path, config, forbidden_hashes=()):
    """Public values are expected in AOT, never as a raw configuration asset."""
    needles = [v.encode() for v in config.values()]
    encoded_defines = [base64.b64encode(f'{k}={v}'.encode()) for k, v in config.items()]
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)), 'Duplicate ZIP entries'
        for abi in ABIS:
            for library in ('libapp.so', 'libflutter.so'):
                assert f'lib/{abi}/{library}' in names, 'Missing ABI'
        for name in names:
            lower = name.lower()
            assert not any(part in lower for part in (
                '.env', '.keystore', '.jks', 'client.json', 'client-config',
                '.dart', '.gradle', '.kt', '.java', '.pem', '.key', '.p12',
                'callback-data', 'kernel_blob.bin',
            )), 'Forbidden archive filename'
            data = archive.read(name)
            assert digest(data) not in forbidden_hashes, 'Renamed source or private file'
            assert not any(value in data for value in encoded_defines), 'Raw encoded DartDefines'
            assert not CALLBACK_CREDENTIALS.search(data), 'Captured callback data'
            aot = name in [f'lib/{abi}/libapp.so' for abi in ABIS]
            if aot:
                assert all(v.encode() in data for v in config.values()), 'Missing AOT config'
            else:
                assert not any(n in data for n in needles), 'Raw configuration in archive'
            assert b'-----BEGIN PRIVATE KEY' not in data, 'Private key content'
            assert b'-----BEGIN RSA PRIVATE KEY' not in data, 'Private key content'
            assert not data.startswith((b'\xfe\xed\xfe\xed', b'\xce\xce\xce\xce')), 'Keystore content'
            assert not (b'SUPABASE_URL' in data and b'SUPABASE_ANON_KEY' in data and not aot), 'Renamed configuration'
    return sorted(names)


def capture(args, cwd, stdout, stderr):
    """Keep bootstrap diagnostics out of machine-readable stdout."""
    with stdout.open('wb') as out, stderr.open('wb') as err:
        return subprocess.run(args, cwd=cwd, stdout=out, stderr=err)


def main():
    os.umask(0o077)
    assert UI_SOURCE is not None, 'Await corrected coordinator-approved UI source pin'
    assert os.environ.get('GITHUB_ACTIONS') == 'true', 'Ephemeral CI only'
    root = Path.cwd()
    app = root / 'app'
    temp = Path(os.environ['RUNNER_TEMP'])
    export = temp / 'native-export'
    export.mkdir()
    raw = temp / 'native-private'
    raw.mkdir()
    steps = []

    def run(label, args, cwd=app):
        log = raw / (label + '.log')
        errors = raw / (label + '.stderr')
        result = capture(args, cwd, log, errors)
        steps.append({'step': label, 'exit': result.returncode, 'stdout_sha256': digest(log.read_bytes()), 'stderr_sha256': digest(errors.read_bytes())})
        print(f'{label}: exit {result.returncode}', flush=True)
        assert result.returncode == 0, f'{label} failed; no private log exported'
        return log.read_bytes()

    def source():
        status = run('source-status-' + str(len(steps)), ['git', 'status', '--porcelain'], root)
        assert not status, 'Source mutation'
        paths = subprocess.check_output(['git', 'ls-files', '-z', 'app'], cwd=root).split(b'\0')
        return {p.decode(): digest((root / p.decode()).read_bytes()) for p in paths if p}

    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root).decode().strip()
    assert head == os.environ['EXPECTED_HEAD'], 'Unexpected checkout'
    run('reviewed-runtime-equality', ['git', 'diff', '--exit-code', UI_SOURCE, 'HEAD', '--', 'app', ':!app/tool/build_native_candidate.py', ':!app/tool/test_build_native_candidate.py', ':!app/tool/sign_native_candidate.py', ':!app/tool/audit_native_candidate.py'], root)
    initial = source()
    config = {k: os.environ.pop(k) for k in ('SUPABASE_URL', 'SUPABASE_ANON_KEY')}
    assert all(config.values()), 'Missing production public configuration'
    client = temp / 'client.json'
    client.write_text(json.dumps(config))
    try:
        sdk = temp / 'flutter-pinned'
        run('flutter-clone', ['git', 'clone', '--depth', '1', '--branch', '3.47.9', 'https://github.com/flutter/flutter.git', str(sdk)], root)
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=sdk).decode().strip()
        assert revision == FRAMEWORK, 'Wrong framework'
        flutter = str(sdk / 'bin/flutter')
        run('flutter-version', [flutter, '--version', '--machine'])
        # First-start notices can precede JSON even on stdout. The fresh SDK
        # writes this canonical version file during that successful invocation.
        version = json.loads((sdk / 'bin/cache/flutter.version.json').read_text())
        assert version['frameworkRevision'] == FRAMEWORK
        assert version['engineRevision'] == ENGINE
        assert version['frameworkVersion'] == '3.47.9'
        run('flutter-precache', [flutter, 'precache', '--android'])
        gradle = temp / 'native-gradle'
        gradle.mkdir()
        os.environ['GRADLE_USER_HOME'] = str(gradle)
        (gradle / 'gradle.properties').write_text('org.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=768m -XX:+HeapDumpOnOutOfMemoryError\norg.gradle.workers.max=1\norg.gradle.parallel=false\n')
        analysis = app / 'analysis_options.yaml'
        original = analysis.read_bytes()

        def restore_known_migration():
            current = analysis.read_bytes()
            expected = original.replace(b'include: package:flutter_lints/flutter.yaml', MIGRATION + b'include: package:flutter_lints/flutter.yaml')
            assert current in (original, expected), 'Unknown analysis migration'
            analysis.write_bytes(original)
            assert source() == initial, 'Changed tracked runtime inputs'

        run('pub-get', [flutter, 'pub', 'get', '--enforce-lockfile'])
        restore_known_migration()
        # The source release signingConfig is debug; Android creates a disposable key.
        run('release-build', [flutter, 'build', 'apk', '--release', '--target', 'lib/main.dart', '--dart-define-from-file=' + str(client), '--build-name=1.0.3', '--build-number=2026111202', '--no-pub'])
        restore_known_migration()
        apk = app / 'build/app/outputs/flutter-apk/app-release.apk'
        forbidden = {value for name, value in initial.items() if Path(name).suffix in {'.dart', '.kt', '.java', '.kts', '.gradle', '.yaml', '.yml', '.json', '.env'}}
        forbidden.add(digest((Path.home() / '.android/debug.keystore').read_bytes()))
        forbidden.add(digest(client.read_bytes()))
        entries = audit_apk(apk, config, forbidden)
        tools = Path(os.environ['ANDROID_HOME']) / 'build-tools/36.0.0'
        signature = run('ephemeral-signature', [str(tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)]).decode()
        cert = next(line.split(': ', 1)[1] for line in signature.splitlines() if line.startswith('Signer #1 certificate SHA-256 digest:'))
        assert cert != 'b33c674d593a79cce25b7b98c78b2eedd4cfea49b93538f23c10d30059b31e18'
        run('zipalign', [str(tools / 'zipalign'), '-c', '-P', '16', '4', str(apk)])
        java = run('java-version', ['java', '--version']).decode().splitlines()[0]
        metadata = {
            'source_sha': head, 'reviewed_ui_source': UI_SOURCE,
            'run_id': os.environ['GITHUB_RUN_ID'], 'run_attempt': os.environ['GITHUB_RUN_ATTEMPT'],
            'entrypoint': 'lib/main.dart', 'build_name': '1.0.3', 'build_number': 2026111202,
            'abis': list(ABIS), 'flutter': version, 'java': java,
            'android': {'sdk': 36, 'build_tools': '36.0.0', 'ndk': '28.2.13676358', 'cli': 19},
            'cache': 'Fresh ephemeral Flutter clone and GRADLE_USER_HOME; no restored build cache',
            'source_status': 'clean', 'runtime_input_sha256': initial,
            'public_config_sha256': {k: digest(v.encode()) for k, v in config.items()},
            'apk_sha256': digest(apk.read_bytes()), 'apk_size': apk.stat().st_size,
            'ephemeral_certificate_sha256': cert, 'archive_entry_count': len(entries),
            'steps': steps, 'privacy': 'Allowlist audited; actual values confined to three AOT libraries',
            'distribution': 'DO NOT INSTALL: ephemeral signing; local signing and offline review required',
        }
        encoded = json.dumps(metadata, indent=2).encode()
        for key, value in config.items():
            assert value.encode() not in encoded
            assert base64.b64encode(f'{key}={value}'.encode()) not in encoded
        (export / 'metadata.json').write_bytes(encoded)
        shutil.copyfile(apk, export / 'candidate.apk')
        assert sorted(p.name for p in export.iterdir()) == ['candidate.apk', 'metadata.json']
        print('Artifact privacy audit passed; ephemeral APK requires local signing.')
    finally:
        client.unlink(missing_ok=True)
        shutil.rmtree(raw)


if __name__ == '__main__':
    main()
