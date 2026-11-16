"""Offline regression tests for the production web build contract."""
import base64
from contextlib import redirect_stdout
from io import BytesIO, StringIO
import json
from pathlib import Path
import tempfile
import subprocess
import os
import unittest
from unittest.mock import patch

import build_native_candidate as native
import release_contract as contract
from release_contract import ANALYSIS_MIGRATION, VERSION, VERSION_CODE, verify_source

RELEASE_VERSION = f'{VERSION}+{VERSION_CODE}'
import build_web_release as release


def jwt(role):
    payload = base64.urlsafe_b64encode(json.dumps({"role": role}).encode()).decode().rstrip("=")
    return "test." + payload + ".signature"


def config():
    return {"SUPABASE_URL": "https://client.invalid", "SUPABASE_ANON_KEY": jwt("anon"),
            "VERCEL_GIT_COMMIT_SHA": "a" * 40, "PATH": "/usr/bin:/bin"}


class WebReleaseTest(unittest.TestCase):
    def setUp(self):
        # Build orchestration only. WebSourceBoundaryTest exercises real Git admission.
        source = patch.object(release, 'verify_web_source', return_value='a' * 40)
        self.source = source.start()
        self.addCleanup(source.stop)

    def test_public_client_keys_are_accepted(self):
        for key in (jwt("anon"), "sb_publishable_fixture"):
            with self.subTest(key_type=key.split(".")[0]):
                env = dict(config(), SUPABASE_ANON_KEY=key)
                self.assertEqual(release.client_config(env)["SUPABASE_ANON_KEY"], key)

    def test_missing_configuration_fails_before_sdk_install(self):
        with patch.dict(release.os.environ, {}, clear=True), patch.object(release, "install_flutter") as install:
            with self.assertRaisesRegex(ValueError, "SUPABASE_URL, SUPABASE_ANON_KEY"):
                release.main()
            install.assert_not_called()

    def test_private_keys_and_malformed_jwts_are_rejected_without_echo(self):
        for key in (jwt("service_role"), "sb_secret_fixture", "not-a-jwt", "test.!!!.sig", "test.bnVsbA.sig"):
            with self.subTest(key_type=key.split(".")[0]):
                with self.assertRaises(ValueError) as error:
                    release.client_config(dict(config(), SUPABASE_ANON_KEY=key))
                self.assertNotIn(key, str(error.exception))

    def test_invalid_client_urls_are_rejected_without_echo(self):
        for url in ("http://client.invalid", "https://user:password@client.invalid", "file:///tmp/config"):
            with self.subTest(scheme=url.split(":")[0]):
                with self.assertRaises(ValueError) as error:
                    release.client_config(dict(config(), SUPABASE_URL=url))
                self.assertNotIn(url, str(error.exception))

    def test_sdk_checks_both_version_and_full_revision(self):
        for version, revision, accepted in [(release.FLUTTER_VERSION, release.FLUTTER_REVISION, True),
                                             (release.FLUTTER_VERSION, "b" * 40, False),
                                             ("3.48.0", release.FLUTTER_REVISION, False)]:
            response = unittest.mock.Mock(stdout=json.dumps({"frameworkVersion": version, "frameworkRevision": revision}))
            with self.subTest(version=version, revision=revision), patch.object(release.subprocess, "run", return_value=response):
                if accepted:
                    self.assertEqual(release.verify_flutter(Path("/sdk"), {}), Path("/sdk/bin/flutter"))
                else:
                    with self.assertRaisesRegex(ValueError, "pinned"):
                        release.verify_flutter(Path("/sdk"), {})

    def test_corrupt_sdk_archive_is_rejected(self):
        metadata = {"releases": [{"hash": release.FLUTTER_REVISION, "version": release.FLUTTER_VERSION,
                                 "channel": "stable", "sha256": "0" * 64,
                                 "archive": f"stable/linux/flutter_linux_{release.FLUTTER_VERSION}-stable.tar.xz"}]}
        with tempfile.TemporaryDirectory() as home, patch.object(release.Path, "home", return_value=Path(home)), \
                patch.object(release, "urlopen", side_effect=[BytesIO(json.dumps(metadata).encode()), BytesIO(b"bad archive")]):
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                release.install_flutter({})
            self.assertFalse((Path(home) / ".cache/pickteams" / ("flutter-" + release.FLUTTER_REVISION)).exists())

    def test_build_uses_real_entrypoint_locked_dependencies_and_private_temp_config(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            (app / "pubspec.yaml").write_text(f"version: {RELEASE_VERSION}\n")
            (app / "analysis_options.yaml").write_text("include: package:flutter_lints/flutter.yaml\n")
            calls = []
            config_paths = []

            def execute(command, *, cwd, env):
                calls.append(command)
                self.assertEqual(cwd, app)
                if "get" in command:
                    analysis = app / 'analysis_options.yaml'
                    analysis.write_bytes(ANALYSIS_MIGRATION + analysis.read_bytes())
                if "build" in command:
                    self.assertEqual((app / 'analysis_options.yaml').read_text(),
                                     'include: package:flutter_lints/flutter.yaml\n')
                    option = next(arg for arg in command if str(arg).startswith("--dart-define-from-file="))
                    path = Path(str(option).split("=", 1)[1])
                    config_paths.append(path)
                    self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                    self.assertEqual(json.loads(path.read_text()), release.client_config(env))
                    self.assertNotIn(str(app / "build/web"), str(path))
                    output = app / "build/web"
                    output.mkdir(parents=True)
                    (output / "index.html").write_text("app")
                    (output / "main.dart.js").write_text("app")

            output = StringIO()
            with patch.object(release, "run", side_effect=execute), redirect_stdout(output):
                manifest = release.build(app, config(), Path("/sdk/bin/flutter"))
            self.assertIn("--enforce-lockfile", calls[0])
            self.assertIn("--no-pub", calls[1])
            self.assertIn("--target=lib/main.dart", calls[1])
            self.assertNotIn("issue57_preview", str(calls))
            self.assertEqual(manifest["commit"], "a" * 40)
            self.assertEqual(manifest["version"], RELEASE_VERSION)
            self.assertEqual(json.loads((app / "build/web/release.json").read_text()), manifest)
            self.assertTrue(all(not path.exists() for path in config_paths))
            stages = [line for line in output.getvalue().splitlines()
                      if line.startswith('Release source check:')]
            self.assertEqual(stages, [
                'Release source check: after-sdk-before-pub-get',
                'Release source check: after-pub-get-and-checked-analysis-restore',
                'Release source check: after-compiler-and-checked-analysis-restore',
            ])
            self.assertNotIn(config()["SUPABASE_ANON_KEY"], output.getvalue())
            self.assertNotIn("client.invalid", json.dumps(manifest))

    def test_provider_control_diagnostics_label_configs_without_disclosure(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            head = (release.APP.parent / 'vercel.json').read_bytes()
            app = (release.APP / 'vercel.json').read_bytes()
            (root / '.vercel').mkdir()
            settings = {'projectId': 'private-project', 'orgId': 'private-org',
                        'settings': {'rootDirectory': 'app', 'buildCommand': 'private-command'}}
            (root / '.vercel/project.json').write_text(json.dumps(settings))
            for content, classification in [
                (head, 'head-bytes'),
                (json.dumps(json.loads(head)).encode(), 'head-json'),
                (app, 'app-json'),
                (b'{"buildCommand":"private-command"}', 'different-json'),
                (b'{"buildCommand":"a","buildCommand":"b"}', 'invalid'),
                (b'not json', 'invalid'),
            ]:
                with self.subTest(classification=classification):
                    (root / 'vercel.json').write_bytes(content)
                    with patch.object(release, 'committed_web_config', side_effect=[head, app]):
                        report = release.web_control_diagnostics(root)
                    self.assertEqual(report['rootConfig']['classification'], classification)
                    self.assertEqual(report['projectMetadata']['rootDirectory'], 'app')
                    self.assertIn('buildCommand', report['projectMetadata']['settingsFields'])
                    for secret in ('private-project', 'private-org', 'private-command'):
                        self.assertNotIn(secret, json.dumps(report))

    def test_project_controls_compare_immutable_configs_without_disclosure(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / '.vercel').mkdir()
            (root / 'app').mkdir()
            head = (release.APP.parent / 'vercel.json').read_bytes()
            app = (release.APP / 'vercel.json').read_bytes()
            (root / 'vercel.json').write_bytes(head)
            (root / 'app/vercel.json').write_bytes(app)
            metadata = root / '.vercel/project.json'
            for name in ('buildCommand', 'installCommand', 'outputDirectory', 'framework', 'devCommand', 'commandForIgnoringBuildStep', 'rootDirectory'):
                for value, label in [(None, 'null'), ('', 'empty'), ('PRIVATE_VALUE', 'other'),
                                     (False, 'type-invalid'), (1, 'type-invalid'), (1.0, 'type-invalid'),
                                     ([], 'type-invalid'), ({}, 'type-invalid')]:
                    with self.subTest(control=name, label=label):
                        metadata.write_text(json.dumps({'settings': {name: value, 'PRIVATE_KEY': 'PRIVATE_VALUE'}}))
                        with patch.object(release, 'committed_web_config', side_effect=[head, app]):
                            report = release.web_control_diagnostics(root)
                        self.assertEqual(report['projectMetadata']['controls'][name]['classification'], label)
                        self.assertEqual(report['projectMetadata']['unknownSettingsFieldCount'], 1)
                        if name == 'rootDirectory' and label in ('other', 'type-invalid'):
                            self.assertEqual(report['projectMetadata']['repositoryRelativeSelection'], 'unknown')
                        self.assertNotIn('PRIVATE_', json.dumps(report))
            for directory, source in [('.', 'root'), ('app', 'app')]:
                settings = {key: value for key, value in json.loads(head if source == 'root' else app).items()
                            if key in ('buildCommand', 'installCommand', 'outputDirectory', 'framework')}
                settings['rootDirectory'] = directory
                metadata.write_text(json.dumps({'settings': settings}))
                with patch.object(release, 'committed_web_config', side_effect=[head, app]):
                    report = release.web_control_diagnostics(root)['projectMetadata']
                self.assertEqual(report['controls']['buildCommand']['classification'], 'equal-to-' + source)
                self.assertEqual(report['controls']['rootDirectory']['classification'], 'equal-to-' + source)
                self.assertEqual(report['selectedConfig']['completeConfigComparison'], 'equal-to-' + source)
                for key in ('buildCommand', 'installCommand', 'outputDirectory', 'framework'):
                    self.assertTrue(report['controls'][key]['equalsRoot' if source == 'root' else 'equalsApp'])
                    self.assertTrue(report['effectiveControls'][key]['equalsRoot' if source == 'root' else 'equalsApp'])
                self.assertEqual(report['controls']['devCommand']['classification'], 'absent')
            # Explicit null/empty controls also report whether they match source.
            self.assertTrue(report['controls']['framework']['equalsRoot'])
            self.assertTrue(report['controls']['installCommand']['equalsApp'])

    def test_effective_config_labels_catch_malicious_controls_and_keep_original_assertion(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / '.vercel').mkdir()
            (root / 'app').mkdir()
            head = (release.APP.parent / 'vercel.json').read_bytes()
            app = (release.APP / 'vercel.json').read_bytes()
            (root / 'vercel.json').write_bytes(head)
            metadata = {'settings': {'rootDirectory': 'app', 'buildCommand': 'PRIVATE_COMMAND',
                                     'outputDirectory': 'PRIVATE_OUTPUT'}}
            (root / '.vercel/project.json').write_text(json.dumps(metadata))
            original_error = AssertionError('Original source rejection')
            self.source.side_effect = original_error
            for mutation in ({}, {'buildCommand': 'PRIVATE_COMMAND'}, {'outputDirectory': 'PRIVATE_OUTPUT'},
                             {'headers': []}, {'rewrites': [{'source': '/PRIVATE_PATH', 'destination': 'PRIVATE_DEST'}]},
                             {'PRIVATE_KEY': 'PRIVATE_VALUE'}):
                config_data = dict(json.loads(app), **mutation)
                (root / 'app/vercel.json').write_text(json.dumps(config_data))
                output = StringIO()
                with patch.object(release, 'committed_web_config', side_effect=[head, app]), redirect_stdout(output):
                    with self.assertRaises(AssertionError) as error:
                        release.verify_source_stage(root, 'before-sdk')
                self.assertIs(error.exception, original_error)
                report = json.loads(output.getvalue().split('Web control diagnostics: ')[1])['projectMetadata']
                self.assertEqual(report['controls']['buildCommand']['classification'], 'other')
                self.assertEqual(report['selectedConfig']['completeConfigComparison'], 'different-json' if mutation else 'equal-to-app')
                self.assertNotIn('PRIVATE_', output.getvalue())
            # Missing local controls fall back to project settings, never to a guessed baseline.
            (root / 'app/vercel.json').write_text('{}')
            with patch.object(release, 'committed_web_config', side_effect=[head, app]):
                report = release.web_control_diagnostics(root)['projectMetadata']
            self.assertEqual(report['effectiveControls']['buildCommand']['classification'], 'other')

    def test_identifier_comparisons_are_only_presence_and_equality_booleans(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / '.vercel').mkdir()
            identifiers = {'projectId': 'PRIVATE_PROJECT', 'orgId': 'PRIVATE_ORG', 'projectName': 'PRIVATE_NAME'}
            names = {'projectId': 'VERCEL_PROJECT_ID', 'orgId': 'VERCEL_ORG_ID', 'projectName': 'VERCEL_PROJECT_NAME'}
            path = root / '.vercel/project.json'
            for mode in ('equal', 'different', 'unavailable', 'invalid', 'absent'):
                data = {} if mode == 'absent' else {key: [] if mode == 'invalid' else value for key, value in identifiers.items()}
                path.write_text(json.dumps(data))
                env = {} if mode == 'unavailable' else {names[key]: value if mode == 'equal' else 'PRIVATE_OTHER' for key, value in identifiers.items()}
                with patch.dict(release.os.environ, env, clear=True):
                    report = release.web_control_diagnostics(root)['projectMetadata']
                for key in identifiers:
                    self.assertEqual(report['identifiers'][key]['present'], mode != 'absent')
                    self.assertEqual(report['identifiers'][key]['environmentPresent'], mode != 'unavailable')
                    self.assertEqual(report['identifiers'][key]['equalsEnvironment'], mode == 'equal')
                    self.assertTrue(all(isinstance(value, bool) for value in report['identifiers'][key].values()))
                encoded = json.dumps(report)
                self.assertNotIn('PRIVATE_', encoded)
                for value in identifiers.values():
                    self.assertNotIn(release.hashlib.sha256(value.encode()).hexdigest(), encoded)

    def test_diagnostics_do_not_follow_links_or_read_unbounded_controls(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / 'private'
            target.mkdir()
            (target / 'project.json').write_text('{"secret":"private-value"}')
            (root / '.vercel').symlink_to(target, target_is_directory=True)
            (root / 'vercel.json').symlink_to(target / 'project.json')
            with patch.object(release, 'committed_web_config', return_value=b'{}'):
                report = release.web_control_diagnostics(root)
            self.assertEqual(report['rootConfig']['classification'], 'unsafe-or-missing')
            self.assertEqual(report['projectMetadata']['classification'], 'unsafe-or-missing')
            (root / 'vercel.json').unlink()
            (root / 'vercel.json').write_bytes(b' ' * (65536 + 1))
            with patch.object(release, 'committed_web_config', return_value=b'{}'):
                self.assertEqual(release.web_control_diagnostics(root)['rootConfig']['classification'], 'unsafe-or-missing')
            # Selected app config is subject to the same no-follow boundary.
            (root / '.vercel').unlink()
            (root / '.vercel').mkdir()
            (root / '.vercel/project.json').write_text('{"settings":{"rootDirectory":"app"}}')
            (root / 'app').symlink_to(target, target_is_directory=True)
            with patch.object(release, 'committed_web_config', return_value=b'{}'):
                self.assertEqual(release.web_control_diagnostics(root)['projectMetadata']['selectedConfig']['classification'], 'unsafe-or-missing')
            # Failed immutable comparisons and malformed metadata must not mask
            # the original rejection, including a partial Git-read failure.
            error = AssertionError('Original rejection')
            self.source.side_effect = error
            for metadata in ('{"settings":{}}', '{"settings":{},"settings":{}}', 'null'):
                (root / '.vercel/project.json').write_text(metadata)
                with patch.object(release, 'committed_web_config', side_effect=[b'{}', ValueError('PRIVATE_FAILURE')]), redirect_stdout(StringIO()) as output:
                    with self.assertRaises(AssertionError) as caught:
                        release.verify_source_stage(root, 'before-sdk')
                self.assertIs(caught.exception, error)
                self.assertNotIn('PRIVATE_', output.getvalue())

    def test_dirty_source_is_rejected_before_sdk_with_named_gate_and_diagnostics(self):
        output = StringIO()
        self.source.side_effect = AssertionError('Source mutation (status paths only): fixture')
        with patch.dict(release.os.environ, config(), clear=True), \
                patch.object(release, 'install_flutter') as install, redirect_stdout(output):
            with self.assertRaisesRegex(AssertionError, 'Source mutation'):
                release.main()
            install.assert_not_called()
        self.assertTrue(output.getvalue().startswith('Release source check: before-sdk\n'))
        self.assertIn('Web control diagnostics:', output.getvalue())

    def test_failed_build_cleans_up_temp_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            (app / "pubspec.yaml").write_text(f"version: {RELEASE_VERSION}\n")
            (app / "analysis_options.yaml").write_text("include: package:flutter_lints/flutter.yaml\n")
            paths = []

            def execute(command, **kwargs):
                if "build" in command:
                    paths.append(Path(next(arg for arg in command if str(arg).startswith("--dart-define-from-file=")).split("=", 1)[1]))
                    raise RuntimeError("compiler failed")

            with patch.object(release, "run", side_effect=execute), self.assertRaisesRegex(RuntimeError, "compiler failed"):
                release.build(app, config(), Path("/sdk/bin/flutter"))
            self.assertTrue(paths)
            self.assertTrue(all(not path.exists() for path in paths))
            self.assertFalse((app / "build/web/release.json").exists())

    def test_invalid_source_pin_is_rejected_before_build(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(release, "run") as execute:
            app = Path(temporary)
            (app / "pubspec.yaml").write_text(f"version: {RELEASE_VERSION}\n")
            with self.assertRaisesRegex(ValueError, "full Git commit"):
                release.build(app, dict(config(), VERCEL_GIT_COMMIT_SHA="main"), Path("/sdk/bin/flutter"))
            execute.assert_not_called()

    def test_wrong_checkout_is_rejected_before_pub_get(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(release, 'run') as execute:
            app = Path(temporary)
            (app / 'pubspec.yaml').write_text(f'version: {RELEASE_VERSION}\n')
            self.source.return_value = 'b' * 40
            with self.assertRaisesRegex(ValueError, 'differs from checked out'):
                release.build(app, config(), Path('/sdk/bin/flutter'))
            execute.assert_not_called()

    def test_vercel_configs_support_repository_and_app_project_roots(self):
        for root in (release.APP.parent, release.APP):
            data = json.loads((root / "vercel.json").read_text())
            self.assertTrue((root / data["buildCommand"].split()[1]).is_file())
            self.assertEqual((root / data["outputDirectory"]).resolve(), release.APP / "build/web")
            self.assertEqual(data["installCommand"], "")
            self.assertIsNone(data["framework"])
            self.assertIn({"source": "/release.json", "headers": [{"key": "Cache-Control", "value": "no-store"}]}, data["headers"])


class WebSourceBoundaryTest(unittest.TestCase):
    """Real-source clones with SYNTHETIC history/CLI data, not hosted evidence.

    CI's tool-test checkout is shallow. Build a local accepted ancestor from the
    real tracked tree, not a network fetch or a mock Git/status/config response.
    Actual pinned-source admission is also required on the candidate itself.
    """
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / 'source'
        subprocess.run(['git', 'clone', '-q', '--depth=1',
                        release.APP.parent.as_uri(), str(self.root)], check=True)
        self.assertEqual(self.git('rev-parse', '--is-shallow-repository'), b'true\n')
        self.git('remote', 'set-url', 'origin', 'https://github.com/Netherman2440/pickteams')
        pubspec = self.git('show', 'HEAD:app/pubspec.yaml')
        ignore = self.git('show', 'HEAD:app/.gitignore')
        self.git('checkout', '-q', '--orphan', 'synthetic-accepted')
        self.put('app/pubspec.yaml', pubspec.replace(RELEASE_VERSION.encode(), b'1.0.5+2026111501'))
        self.assertTrue(ignore.endswith(contract.WEB_OUTPUT_IGNORE))
        self.put('app/.gitignore', ignore[:-len(contract.WEB_OUTPUT_IGNORE)])
        self.fixture_commit()
        accepted = self.git('rev-parse', 'HEAD').decode().strip()
        for module in (contract, release):
            pin = patch.object(module, 'ACCEPTED_SOURCE', accepted)
            pin.start()
            self.addCleanup(pin.stop)
        self.put('app/pubspec.yaml', pubspec)
        self.put('app/.gitignore', ignore)
        self.fixture_commit()
        self.head = self.git('rev-parse', 'HEAD').decode().strip()
        self.app = json.loads(self.git('show', 'HEAD:app/vercel.json'))
        self.env = {'VERCEL': '1', 'VERCEL_ENV': 'preview', 'VERCEL_GIT_COMMIT_SHA': self.head,
                    'VERCEL_PROJECT_ID': 'prj_SYNTHETIC', 'VERCEL_ORG_ID': 'team_SYNTHETIC',
                    'VERCEL_PROJECT_NAME': 'synthetic-project'}
        self.metadata = {'projectId': self.env['VERCEL_PROJECT_ID'], 'orgId': self.env['VERCEL_ORG_ID'],
                         'settings': {'createdAt': 1700000000000, 'framework': None, 'devCommand': None,
                                      'installCommand': '', 'buildCommand': self.app['buildCommand'],
                                      'outputDirectory': self.app['outputDirectory'],
                                      'rootDirectory': 'app', 'nodeVersion': '24.x'}}

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, stderr=subprocess.PIPE)

    def put(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode())

    def materialize(self):
        self.put('vercel.json', json.dumps(self.app))
        self.put('.vercel/project.json', json.dumps(self.metadata))

    def check(self, env=None):
        return release.verify_web_source(self.root, self.env if env is None else env)

    def reject(self, env=None):
        with self.assertRaises((AssertionError, OSError, ValueError, subprocess.CalledProcessError)) as error:
            self.check(env)
        self.assertNotIn('SYNTHETIC_SECRET', str(error.exception))

    def reset_fixture(self):
        # This reset/clean is confined to a disposable test-owned clone.
        self.git('reset', '--hard', self.head)
        self.git('clean', '-fdxq')

    def fixture_commit(self):
        self.git('add', '.')
        self.git('-c', 'user.name=Synthetic', '-c', 'user.email=test@invalid', 'commit', '-qm', 'fixture')

    def commit(self):
        self.fixture_commit()
        self.env['VERCEL_GIT_COMMIT_SHA'] = self.git('rev-parse', 'HEAD').decode().strip()

    def test_observed_projection_passes_all_web_stages_but_not_generic_or_native(self):
        self.materialize()
        with patch.dict(os.environ, self.env, clear=True):
            report = release.web_control_diagnostics(self.root)
            self.assertEqual(report['rootConfig']['classification'], 'app-json')
            project = report['projectMetadata']
            self.assertEqual(project['settingsFields'], list(self.metadata['settings']))
            self.assertEqual(project['selectedConfig']['completeConfigComparison'], 'different-json')
            self.assertFalse(project['controls']['devCommand']['equalsApp'])
            self.assertFalse(project['identifiers']['projectName']['present'])
            for stage in ('before-sdk', 'after-sdk-before-pub-get',
                          'after-pub-get-and-checked-analysis-restore',
                          'after-compiler-and-checked-analysis-restore'):
                with redirect_stdout(StringIO()):
                    self.assertEqual(release.verify_source_stage(self.root, stage), self.head)
        with self.assertRaisesRegex(AssertionError, 'Source mutation'):
            verify_source(self.root)
        # The native builder imports this exact strict entry point.
        self.assertIs(native.verify_source, verify_source)
        with self.assertRaisesRegex(AssertionError, 'Source mutation'):
            native.verify_source(self.root)
        self.assertEqual(self.git('status', '--porcelain').decode(),
                         ' M vercel.json\n?? .vercel/\n')

    def test_clean_ci_and_generated_app_output_keep_strict_admission(self):
        self.assertEqual(release.verify_web_source(self.root, {}), self.head)
        self.assertEqual(verify_source(self.root), self.head)
        self.put('app/.vercel/output/builds.json', '{}')
        self.assertEqual(release.verify_web_source(self.root, {}), self.head)
        self.assertEqual(verify_source(self.root), self.head)
        for mutation in ('vercel.json', 'app/.vercel/project.json', 'app/lib/main.dart', 'unrelated'):
            with self.subTest(path=mutation):
                self.reset_fixture()
                self.put(mutation, 'SYNTHETIC_SECRET')
                self.reject({})
                with self.assertRaises(AssertionError):
                    verify_source(self.root)

    def test_every_root_config_field_and_unknown_routing_env_commands_reject(self):
        mutations = {'buildCommand': 'SYNTHETIC_SECRET', 'outputDirectory': 'elsewhere',
                     'framework': 'nextjs', 'installCommand': 'npm install', 'devCommand': None,
                     'ignoreCommand': '', 'rootDirectory': 'app', '$schema': 'elsewhere',
                     'headers': [], 'rewrites': [], 'redirects': [], 'routes': [],
                     'env': {}, 'build': {}, 'builds': [], 'functions': {}, 'unknown': True}
        self.materialize()
        for field, value in mutations.items():
            with self.subTest(field=field):
                self.put('vercel.json', json.dumps(dict(self.app, **{field: value})))
                self.reject()
        for field in self.app:
            with self.subTest(missing=field):
                self.put('vercel.json', json.dumps({key: value for key, value in self.app.items() if key != field}))
                self.reject()

    def test_metadata_schema_controls_and_bounded_nonexecution_fields(self):
        self.materialize()
        baseline = json.dumps(self.metadata)
        mutations = {'buildCommand': 'SYNTHETIC_SECRET', 'outputDirectory': 'elsewhere',
                     'rootDirectory': '.', 'framework': '', 'installCommand': None,
                     'devCommand': '', 'commandForIgnoringBuildStep': None, 'ignoreCommand': '',
                     'headers': [], 'rewrites': [], 'routes': [], 'env': {}, 'unknown': True,
                     'analyticsId': 'unobserved', 'nodeVersion': '24.x; SYNTHETIC_SECRET',
                     'createdAt': True}
        for field, value in mutations.items():
            with self.subTest(field=field):
                metadata = json.loads(baseline)
                metadata['settings'][field] = value
                self.put('.vercel/project.json', json.dumps(metadata))
                self.reject()
        for field in self.metadata['settings']:
            with self.subTest(missing=field):
                metadata = json.loads(baseline)
                del metadata['settings'][field]
                self.put('.vercel/project.json', json.dumps(metadata))
                self.reject()
        for field in ('createdAt', 'nodeVersion'):
            for value in (None, False, [], {}, '', -1, 1.5, 9007199254740992):
                with self.subTest(field=field, invalid=value):
                    metadata = json.loads(baseline)
                    metadata['settings'][field] = value
                    self.put('.vercel/project.json', json.dumps(metadata))
                    self.reject()
        for field in ('env', 'buildCommand', 'headers', 'routes', 'unknown'):
            with self.subTest(top=field):
                self.put('.vercel/project.json', json.dumps(dict(self.metadata, **{field: {}})))
                self.reject()
        for settings in (None, [], '', True):
            self.put('.vercel/project.json', json.dumps(dict(self.metadata, settings=settings)))
            self.reject()

    def test_identity_context_is_required_but_missing_optional_name_is_not_a_mismatch(self):
        self.materialize()
        self.assertEqual(self.check(), self.head)
        metadata = dict(self.metadata, projectName=self.env['VERCEL_PROJECT_NAME'])
        self.put('.vercel/project.json', json.dumps(metadata))
        self.assertEqual(self.check(), self.head)
        for field in ('projectId', 'orgId', 'projectName'):
            for value in (None, False, 1, [], {}, '', 'bad identity', 'SYNTHETIC_SECRET'):
                with self.subTest(field=field, value=value):
                    self.put('.vercel/project.json', json.dumps(dict(metadata, **{field: value})))
                    self.reject()
            if field != 'projectName':
                self.put('.vercel/project.json', json.dumps({key: value for key, value in metadata.items() if key != field}))
                self.reject()
        self.materialize()
        for field in ('VERCEL', 'VERCEL_ENV', 'VERCEL_GIT_COMMIT_SHA', 'VERCEL_PROJECT_ID', 'VERCEL_ORG_ID'):
            for value in (None, '', 'SYNTHETIC_SECRET'):
                with self.subTest(env=field, value=value):
                    env = dict(self.env)
                    if value is None:
                        del env[field]
                    else:
                        env[field] = value
                    self.reject(env)
        # IDs alone are neither source context nor provider authentication.
        self.reject({key: value for key, value in self.env.items() if key.endswith('_ID')})
        self.git('remote', 'set-url', 'origin', 'https://untrusted.invalid/repository')
        self.reject()

    def test_unrelated_source_staged_or_committed_changes_are_never_hidden(self):
        for path in ('app/lib/main.dart', 'app/vercel.json', 'unrelated', '.vercel/other.json'):
            for state in ('unstaged', 'staged', 'committed'):
                with self.subTest(path=path, state=state):
                    self.reset_fixture()
                    self.env['VERCEL_GIT_COMMIT_SHA'] = self.head
                    self.put(path, 'SYNTHETIC_SECRET')
                    if state == 'staged':
                        self.git('add', path)
                    elif state == 'committed':
                        self.commit()
                    self.materialize()
                    self.reject()
        for path in ('vercel.json', '.vercel/project.json'):
            for state in ('staged', 'committed'):
                with self.subTest(control=path, state=state):
                    self.reset_fixture()
                    self.env['VERCEL_GIT_COMMIT_SHA'] = self.head
                    self.materialize()
                    self.git('add', path)
                    if state == 'committed':
                        self.git('-c', 'user.name=Synthetic', '-c', 'user.email=test@invalid', 'commit', '-qm', 'control')
                        self.env['VERCEL_GIT_COMMIT_SHA'] = self.git('rev-parse', 'HEAD').decode().strip()
                    self.reject()

    def test_git_executable_checkouts_respect_umask(self):
        original_umask = os.umask(0o022)
        try:
            for mask, expected in ((0o022, 0o755), (0o002, 0o775),
                                   (0o027, 0o750), (0o077, 0o700)):
                with self.subTest(umask=oct(mask), mode=oct(expected)):
                    os.umask(mask)
                    fixture = WebSourceBoundaryTest('test_clean_ci_and_generated_app_output_keep_strict_admission')
                    try:
                        fixture.setUp()
                        entries = fixture.git('ls-tree', '-r', 'HEAD').decode().splitlines()
                        executables = [row.split('\t', 1)[1] for row in entries if row.startswith('100755 ')]
                        self.assertTrue(executables)
                        for path in executables:
                            self.assertEqual((fixture.root / path).stat().st_mode & 0o7777, expected)
                        self.assertEqual(fixture.git('status', '--porcelain'), b'')
                        self.assertEqual(fixture.check({}), fixture.head)
                        self.assertEqual(verify_source(fixture.root), fixture.head)
                        fixture.materialize()
                        self.assertEqual(fixture.check(), fixture.head)
                        with self.assertRaisesRegex(AssertionError, 'Source mutation'):
                            native.verify_source(fixture.root)
                    finally:
                        fixture.doCleanups()
        finally:
            os.umask(original_umask)

    def test_source_modes_reject_missing_owner_execute_any_nonexec_x_and_special_bits(self):
        self.git('config', 'core.fileMode', 'false')
        executable = '.specify/scripts/bash/check-prerequisites.sh'
        for path, modes in (
            (executable, (0o600, 0o644, 0o601, 0o610, 0o611, 0o4755, 0o2755, 0o1755)),
            ('app/lib/main.dart', (0o601, 0o610, 0o700, 0o711, 0o4644, 0o2644, 0o1644)),
        ):
            target = self.root / path
            original = target.stat().st_mode & 0o7777
            try:
                for mode in modes:
                    with self.subTest(path=path, mode=oct(mode)):
                        target.chmod(mode)  # One adversarial file, never fixture normalization.
                        self.assertEqual(target.stat().st_mode & 0o7777, mode)
                        self.assertEqual(self.git('status', '--porcelain'), b'')
                        with self.assertRaisesRegex(AssertionError, 'Source (special )?mode mutation'):
                            self.check({})
            finally:
                target.chmod(original)
        # A hidden tracked symlink must not pass the physical-file gate either.
        target = self.root / executable
        original = target.read_bytes()
        self.put('.git/source-copy', original)
        self.git('update-index', '--assume-unchanged', executable)
        target.unlink()
        target.symlink_to(self.root / '.git/source-copy')
        self.assertEqual(self.git('status', '--porcelain'), b'')
        with self.assertRaises(OSError):
            self.check({})

    def test_index_mode_changes_reject_even_when_physical_modes_are_unchanged(self):
        self.git('config', 'core.fileMode', 'false')
        for path, changed, original in (
            ('app/lib/main.dart', '+x', '-x'),
            ('.specify/scripts/bash/check-prerequisites.sh', '-x', '+x'),
        ):
            with self.subTest(path=path):
                physical = (self.root / path).stat().st_mode
                self.git('update-index', '--chmod=' + changed, path)
                self.assertEqual((self.root / path).stat().st_mode, physical)
                with self.assertRaisesRegex(AssertionError, 'Staged source mutation'):
                    self.check({})
                self.git('update-index', '--chmod=' + original, path)
        self.assertEqual(self.check({}), self.head)

    def test_full_bytes_and_index_do_not_depend_on_status_cache(self):
        for flag in ('--assume-unchanged', '--skip-worktree'):
            self.git('update-index', flag, 'app/lib/main.dart')
            self.put('app/lib/main.dart', 'SYNTHETIC_SECRET')
            self.assertEqual(self.git('status', '--porcelain'), b'')
            self.reject({})
            self.git('update-index', '--no-assume-unchanged', 'app/lib/main.dart')
            self.git('update-index', '--no-skip-worktree', 'app/lib/main.dart')
            self.reset_fixture()
        self.put('app/lib/main.dart', 'SYNTHETIC_SECRET')
        self.git('add', 'app/lib/main.dart')
        self.put('app/lib/main.dart', self.git('show', 'HEAD:app/lib/main.dart'))
        self.reject({})

    def test_links_modes_oversize_duplicate_json_and_ignored_metadata_reject(self):
        for path in ('vercel.json', '.vercel/project.json'):
            for mutation in ('symlink', 'owner-x', 'group-x', 'other-x', 'setuid',
                             'setgid', 'sticky', 'world-write', 'oversize', 'duplicate', 'nan'):
                with self.subTest(path=path, mutation=mutation):
                    self.reset_fixture()
                    self.materialize()
                    target = self.root / path
                    if mutation == 'symlink':
                        target.unlink()
                        target.symlink_to(self.root / 'app/vercel.json')
                    elif mutation in ('owner-x', 'group-x', 'other-x', 'setuid', 'setgid', 'sticky', 'world-write'):
                        bits = {'owner-x': 0o100, 'group-x': 0o010, 'other-x': 0o001,
                                'setuid': 0o4000, 'setgid': 0o2000, 'sticky': 0o1000, 'world-write': 0o002}
                        target.chmod((target.stat().st_mode & 0o7777) | bits[mutation])
                    elif mutation == 'oversize':
                        target.write_bytes(target.read_bytes() + b' ' * 65537)
                    elif mutation == 'duplicate':
                        # Last-wins JSON would otherwise be a valid projection.
                        field = 'framework' if path == 'vercel.json' else 'projectId'
                        target.write_text('{"' + field + '":"SYNTHETIC_SECRET",' + target.read_text()[1:])
                    else:
                        target.write_text('{"settings":NaN}')
                    self.reject()
        for hidden in ('.vercel/.env', 'app/.vercel/.env', 'app/.vercel/project.json'):
            with self.subTest(ignored_control=hidden):
                self.reset_fixture()
                self.materialize()
                self.put(hidden, 'SYNTHETIC_SECRET')
                self.put('.git/info/exclude', '/' + hidden + '\n')
                self.reject()
        self.reset_fixture()
        self.materialize()
        self.git('config', 'core.excludesFile', str(self.root / '.git/synthetic-ignore'))
        self.put('.git/synthetic-ignore', '.vercel/\n')
        self.reject()
        self.put('vercel.json', self.git('show', 'HEAD:vercel.json'))
        self.assertEqual(self.git('status', '--porcelain'), b'')
        self.reject({})
        # The directory itself cannot redirect traversal, even with clean status.
        (self.root / '.vercel/project.json').unlink()
        (self.root / '.vercel').rmdir()
        (self.root / '.vercel').symlink_to(self.root / 'app', target_is_directory=True)
        self.reject({})

    def test_each_stage_rechecks_controls_not_only_initial_admission(self):
        self.materialize()
        with patch.dict(os.environ, self.env, clear=True), redirect_stdout(StringIO()):
            self.assertEqual(release.verify_source_stage(self.root, 'before-sdk'), self.head)
            for stage in ('after-sdk-before-pub-get', 'after-pub-get-and-checked-analysis-restore',
                          'after-compiler-and-checked-analysis-restore'):
                self.metadata['settings']['buildCommand'] = 'SYNTHETIC_SECRET'
                self.materialize()
                with self.assertRaises(AssertionError):
                    release.verify_source_stage(self.root, stage)
                self.metadata['settings']['buildCommand'] = self.app['buildCommand']
                self.materialize()
                self.assertEqual(release.verify_source_stage(self.root, stage), self.head)


if __name__ == '__main__':
    unittest.main()
