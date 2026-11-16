"""Offline regression tests for the production web build contract."""
import base64
from contextlib import redirect_stdout
from io import BytesIO, StringIO
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from release_contract import ANALYSIS_MIGRATION, VERSION, VERSION_CODE

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
        # Source policy has real Git positive/negative tests in test_release_contract.
        source = patch.object(release, 'verify_source', return_value='a' * 40)
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

    def test_provider_control_diagnostics_do_not_admit_any_mutation(self):
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
                    self.source.side_effect = AssertionError('Source mutation')
                    output = StringIO()
                    with patch.object(release, 'committed_web_config', side_effect=[head, app]), redirect_stdout(output):
                        with self.assertRaisesRegex(AssertionError, 'Source mutation'):
                            release.verify_source_stage(root, 'before-sdk')
                    report = json.loads(output.getvalue().split('Web control diagnostics: ')[1])
                    self.assertEqual(report['rootConfig']['classification'], classification)
                    self.assertEqual(report['projectMetadata']['rootDirectory'], 'app')
                    self.assertIn('buildCommand', report['projectMetadata']['settingsFields'])
                    for secret in ('private-project', 'private-org', 'private-command'):
                        self.assertNotIn(secret, output.getvalue())

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


if __name__ == "__main__":
    unittest.main()
