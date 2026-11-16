"""Real Git boundary tests; no production config, SDK, or network access."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import release_contract as release


class ReleaseContractTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.git('init', '-q')
        self.put('app/pubspec.yaml', 'name: app\nversion: 1.0.5+2026111501\n')
        self.put('app/.gitignore', '/build/\n')
        self.put('app/lib/main.dart', 'accepted runtime\n')
        self.put('supabase/unchanged.sql', '-- no changes\n')
        self.commit()
        self.accepted = self.git('rev-parse', 'HEAD').strip()
        pin = patch.object(release, 'ACCEPTED_SOURCE', self.accepted)
        pin.start()
        self.addCleanup(pin.stop)
        self.put('app/pubspec.yaml', f'name: app\nversion: {release.VERSION}+{release.VERSION_CODE}\n')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, stderr=subprocess.PIPE).decode()

    def put(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self):
        self.git('add', '.')
        self.git('-c', 'user.name=Synthetic', '-c', 'user.email=test@invalid', 'commit', '-qm', 'fixture')

    def test_runtime_platform_database_workflow_and_arbitrary_tool_changes_are_rejected(self):
        for name in ('app/lib/main.dart', 'app/android/build.gradle.kts',
                     'supabase/unchanged.sql', '.github/workflows/untrusted.yml',
                     'app/tool/arbitrary.py', 'docs/unrelated.md'):
            with self.subTest(path=name):
                self.git('reset', '--hard', self.accepted)
                self.git('clean', '-fdq')
                self.put('app/pubspec.yaml', f'name: app\nversion: {release.VERSION}+{release.VERSION_CODE}\n')
                self.put(name, 'unaccepted change\n')
                self.commit()
                with self.assertRaisesRegex(AssertionError, 'Unapproved source differences'):
                    release.verify_source(self.root)

    def test_pubspec_dependency_change_is_rejected(self):
        with (self.root / 'app/pubspec.yaml').open('a') as out:
            out.write('dependencies: changed\n')
        self.commit()
        with self.assertRaisesRegex(AssertionError, 'Non-version pubspec change'):
            release.verify_source(self.root)

    def test_wrong_version_or_code_is_rejected(self):
        for version in ('1.0.4+2026111301', '1.0.5+2026111501',
                        '1.0.6+2026111601', '1.0.7+2026111602'):
            with self.subTest(version=version):
                self.put('app/pubspec.yaml', 'name: app\nversion: ' + version + '\n')
                self.commit()
                with self.assertRaisesRegex(AssertionError, 'Release version mismatch'):
                    release.verify_source(self.root)

    def allow_web_output(self):
        # Exact reviewed append, not a directory-wide .vercel exclusion.
        with (self.root / 'app/.gitignore').open('ab') as out:
            out.write(b'\n# Generated Vercel Build Output API artifacts (not project settings).\n/.vercel/output/\n')
        self.commit()

    def test_cli_output_passes_but_settings_unknown_files_and_tracked_mutations_fail(self):
        self.allow_web_output()
        expected = self.git('rev-parse', 'HEAD').strip()
        self.put('app/.vercel/output/builds.json', 'generated provider output\n')
        self.put('app/.vercel/output/diagnostics/cli_traces.json', 'generated diagnostics\n')
        self.assertEqual(release.verify_source(self.root), expected)
        for name in ('app/.vercel/project.json', 'app/.vercel/unexpected',
                     'app/untracked', 'app/lib/main.dart'):
            with self.subTest(path=name):
                path = self.root / name
                original = path.read_bytes() if path.exists() else None
                self.put(name, 'PRIVATE_CONTENT_MUST_NOT_APPEAR\n')
                with self.assertRaisesRegex(AssertionError, 'Source mutation') as error:
                    release.verify_source(self.root)
                self.assertIn(name, str(error.exception))
                self.assertNotIn('PRIVATE_CONTENT_MUST_NOT_APPEAR', str(error.exception))
                if original is None:
                    path.unlink()
                else:
                    path.write_bytes(original)
        self.assertEqual(release.verify_source(self.root), expected)

    def test_every_other_ignore_file_edit_is_rejected_even_when_committed(self):
        original = self.git('show', self.accepted + ':app/.gitignore')
        allowed = '\n# Generated Vercel Build Output API artifacts (not project settings).\n/.vercel/output/\n'
        for content in (original + '/.vercel/\n', original + allowed + '/lib/\n',
                        original.replace('/build/', '/lib/') + allowed,
                        original + allowed.replace('/.vercel/output/', '/.vercel/')):
            with self.subTest(content=content):
                self.put('app/.gitignore', content)
                self.commit()
                with self.assertRaisesRegex(AssertionError, 'Unapproved web output ignore change'):
                    release.verify_source(self.root)

    def test_executable_or_symlink_ignore_file_is_rejected(self):
        self.allow_web_output()
        path = self.root / 'app/.gitignore'
        path.chmod(0o755)
        self.commit()
        with self.assertRaisesRegex(AssertionError, 'Unapproved web output ignore mode'):
            release.verify_source(self.root)
        content = path.read_bytes()
        path.unlink()
        self.put('app/tool/release_contract.py', content.decode())
        path.symlink_to('tool/release_contract.py')
        self.commit()
        with self.assertRaisesRegex(AssertionError, 'Unapproved web output ignore change'):
            release.verify_source(self.root)

    def test_dirty_ignore_file_is_not_restored_or_accepted(self):
        self.allow_web_output()
        path = self.root / 'app/.gitignore'
        content = path.read_bytes() + b'/lib/\n'
        path.write_bytes(content)
        with self.assertRaisesRegex(AssertionError, 'Source mutation'):
            release.verify_source(self.root)
        self.assertEqual(path.read_bytes(), content)

    def test_committed_build_affecting_provider_metadata_is_rejected(self):
        self.allow_web_output()
        self.put('app/.vercel/project.json', '{}\n')
        self.commit()
        with self.assertRaisesRegex(AssertionError, 'Unapproved source differences'):
            release.verify_source(self.root)

    def test_named_release_tools_pass_only_with_accepted_ancestor_in_clone(self):
        for name in release.RELEASE_FILES:
            self.put(name, 'reviewed release tool or documentation\n')
        self.commit()
        expected = self.git('rev-parse', 'HEAD').strip()
        with tempfile.TemporaryDirectory() as temporary:
            # A bounded platform clone is sufficient only if it retains the
            # accepted ancestor; full history avoids depending on its distance.
            for name, options in (('shallow', ['--depth=1']),
                                  ('bounded', ['--depth=2']), ('full', [])):
                with self.subTest(clone=name):
                    clone = Path(temporary) / name
                    subprocess.run(['git', 'clone', '-q', *options,
                                    self.root.as_uri(), str(clone)], check=True)
                    self.assertEqual(subprocess.check_output(
                        ['git', 'rev-parse', 'HEAD'], cwd=clone).decode().strip(), expected)
                    self.assertEqual(subprocess.check_output(
                        ['git', 'rev-parse', '--is-shallow-repository'], cwd=clone),
                        b'true\n' if options else b'false\n')
                    if name == 'shallow':
                        with self.assertRaises(subprocess.CalledProcessError) as error:
                            release.verify_source(clone)
                        self.assertEqual(error.exception.returncode, 128)
                        self.assertIn('merge-base', error.exception.cmd)
                    else:
                        self.assertEqual(release.verify_source(clone), expected)

    def test_source_verifying_workflow_jobs_bind_exact_source_with_full_history(self):
        # Inspect only each job's initial checkout, not an unrelated fetch-depth.
        # Keep this stdlib-only: the workflow has two-space job indentation.
        workflows = {
            'main.yml': ('web-build',),
            'private-native-candidate.yml': ('native',),
        }
        root = Path(__file__).resolve().parents[2]
        for workflow, jobs in workflows.items():
            text = (root / '.github/workflows' / workflow).read_text()
            for job in jobs:
                with self.subTest(workflow=workflow, job=job):
                    section = text.split(f'\n  {job}:\n', 1)[1]
                    section = re.split(r'\n  [a-zA-Z_][\w-]*:', section, maxsplit=1)[0]
                    checkout = section.split('uses: actions/checkout@', 1)[1]
                    checkout = re.split(r'\n      - ', checkout, maxsplit=1)[0]
                    self.assertIn('\n        with:\n', checkout)
                    self.assertEqual(re.findall(r'^          fetch-depth: (.+)$', checkout, re.M), ['0'])
                    if workflow == 'private-native-candidate.yml':
                        self.assertIn('ref: ${{ github.event.pull_request.head.sha }}', checkout)
                        self.assertIn('persist-credentials: false', checkout)
                        self.assertIn('verify_source(Path.cwd())', section)
                        self.assertIn('EXPECTED_HEAD: ${{ github.event.pull_request.head.sha }}', section)
                        self.assertIn('python3 app/tool/build_native_candidate.py', section)
                    else:
                        self.assertIn('python3 tool/build_web_release.py', section)

    def test_non_descendant_is_rejected(self):
        self.commit()
        self.git('checkout', '--orphan', 'unrelated')
        self.commit()
        with self.assertRaises(subprocess.CalledProcessError):
            release.verify_source(self.root)

    def test_native_metadata_binds_version_source_and_entrypoint(self):
        metadata = dict(reviewed_ui_source=self.accepted, build_name=release.VERSION,
                        build_number=release.VERSION_CODE, entrypoint='lib/main.dart')
        release.validate_metadata(metadata)
        for field, value in (('reviewed_ui_source', 'f' * 40), ('build_name', '1.0.4'),
                             ('build_number', 2026111301), ('build_number', str(release.VERSION_CODE)),
                             ('entrypoint', 'tool/preview.dart')):
            with self.subTest(field=field, value=value), self.assertRaises(AssertionError):
                release.validate_metadata(dict(metadata, **{field: value}))

    def test_only_known_sdk_analysis_migration_is_restored(self):
        path = self.root / 'analysis_options.yaml'
        original = b'include: package:flutter_lints/flutter.yaml\n'
        for content in (original, release.ANALYSIS_MIGRATION + original):
            path.write_bytes(content)
            release.restore_analysis(path, original)
            self.assertEqual(path.read_bytes(), original)
        path.write_bytes(b'analyzer:\n  exclude: [lib/**]\n' + original)
        with self.assertRaisesRegex(AssertionError, 'Unknown analysis migration'):
            release.restore_analysis(path, original)


class AcceptedDisplayReleaseTest(unittest.TestCase):
    def test_shared_version_and_runtime_pin_replace_old_native_contract(self):
        import audit_native_candidate
        import build_native_candidate
        import sign_native_candidate

        self.assertEqual(release.ACCEPTED_SOURCE, '4fe251fc2dadf5cd0e9abc70a25b2220096ded02')
        self.assertEqual((release.VERSION, release.VERSION_CODE), ('1.0.6', 2026111602))
        for module in (audit_native_candidate, build_native_candidate, sign_native_candidate):
            self.assertEqual((module.VERSION, module.VERSION_CODE), (release.VERSION, release.VERSION_CODE))
        self.assertEqual(build_native_candidate.UI_SOURCE, release.ACCEPTED_SOURCE)
        # Old prepared APK metadata must not be accepted as the new runtime.
        with self.assertRaisesRegex(AssertionError, 'Unaccepted runtime source'):
            release.validate_metadata(dict(reviewed_ui_source='01f03757c48c44a5fd9b49d7ce393ebf91a61e96',
                                           build_name='1.0.6', build_number=2026111601,
                                           entrypoint='lib/main.dart'))
        with self.assertRaisesRegex(AssertionError, 'Release version mismatch'):
            release.validate_metadata(dict(reviewed_ui_source=release.ACCEPTED_SOURCE,
                                           build_name='1.0.6', build_number=2026111601,
                                           entrypoint='lib/main.dart'))


if __name__ == '__main__':
    unittest.main()
