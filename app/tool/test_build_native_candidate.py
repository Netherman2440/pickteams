"""Adversarial export checks use synthetic configuration, never production values."""
from pathlib import Path
import base64
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import build_native_candidate

from build_native_candidate import ABIS, audit_apk, capture, digest
from sign_native_candidate import (
    ARTIFACT_PREFIX,
    WORKFLOW_PATH,
    atomic_candidate,
    payload,
    tracked_inputs,
    validate_input_path,
    verify_remote_provenance,
    verify_tracked_inputs,
)


def file_digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class ArtifactPrivacyTest(unittest.TestCase):
    config = {'SUPABASE_URL': 'https://synthetic.invalid', 'SUPABASE_ANON_KEY': 'synthetic-client-value'}

    def archive(self, extra=None, omitted=None):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / 'test.apk'
        with zipfile.ZipFile(path, 'w') as archive:
            for abi in ABIS:
                for library in ('libapp.so', 'libflutter.so'):
                    name = f'lib/{abi}/{library}'
                    if name != omitted:
                        data = '\0'.join(self.config.values()) if library == 'libapp.so' else 'engine'
                        archive.writestr(name, data)
            for name, data in (extra or {}).items():
                archive.writestr(name, data)
        return path

    def test_unapproved_source_stops_before_environment_or_sdk_access(self):
        with patch.object(build_native_candidate, 'UI_SOURCE', None):
            with self.assertRaisesRegex(AssertionError, 'Await corrected'):
                build_native_candidate.main()

    def test_encoded_defines_are_rejected(self):
        encoded = base64.b64encode(b'SUPABASE_URL=https://synthetic.invalid')
        with self.assertRaises(AssertionError):
            audit_apk(self.archive({'assets/innocent.bin': encoded}), self.config)

    def test_bootstrap_diagnostics_do_not_corrupt_machine_json(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            out, err = root / 'stdout', root / 'stderr'
            result = capture([sys.executable, '-c', 'import sys; print("Building tool", file=sys.stderr); print(\'{"version":"pinned"}\')'], root, out, err)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(json.loads(out.read_bytes()), {'version': 'pinned'})
            self.assertEqual(err.read_text(), 'Building tool\n')

    def test_compiled_public_config_is_allowed(self):
        self.assertEqual(len(audit_apk(self.archive(), self.config)), 6)

    def test_renamed_raw_config_is_rejected(self):
        for value in self.config.values():
            with self.subTest(value=value), self.assertRaises(AssertionError):
                audit_apk(self.archive({'assets/innocent.bin': value}), self.config)

    def test_forbidden_files_are_rejected(self):
        for name in ('assets/.env', 'assets/key.jks', 'assets/main.dart', 'assets/client-config.json'):
            with self.subTest(name=name), self.assertRaises(AssertionError):
                audit_apk(self.archive({name: 'unrelated'}), self.config)

    def test_renamed_key_is_rejected(self):
        with self.assertRaises(AssertionError):
            audit_apk(self.archive({'assets/innocent.bin': b'\xfe\xed\xfe\xedsecret'}), self.config)

    def test_renamed_source_is_rejected(self):
        source = b'void main() => runApp(const PrivateApp());'
        with self.assertRaises(AssertionError):
            audit_apk(self.archive({'assets/innocent.bin': source}), self.config, {digest(source)})

    def test_captured_callback_is_rejected(self):
        with self.assertRaises(AssertionError):
            audit_apk(self.archive({'assets/innocent.bin': 'pl.pickteams://auth/callback?code=syntheticCode1234'}), self.config)

    def test_reviewer_fragment_capture_is_rejected(self):
        # Reviewer's exact synthetic negative case from tooling-review-1.
        captured = 'pl.pickteams://auth/callback#access_token=syntheticToken1234&refresh_token=syntheticRefresh1234'
        with self.assertRaises(AssertionError):
            audit_apk(self.archive({'assets/capture.bin': captured}), self.config)

    def test_callback_query_positive_negative_pair(self):
        bare = 'pl.pickteams://auth/callback'
        # Positive: the bare compiled callback literal stays allowed.
        self.assertTrue(audit_apk(self.archive({'assets/route.bin': bare}), self.config))
        # Negative pair member: credential-bearing query is rejected.
        with self.assertRaises(AssertionError):
            audit_apk(self.archive({'assets/route.bin': bare + '?access_token=syntheticToken1234'}), self.config)
        # Negative pair member: credential-bearing fragment is rejected.
        with self.assertRaises(AssertionError):
            audit_apk(self.archive({'assets/route.bin': bare + '#refresh_token=syntheticRefresh1234'}), self.config)

    def test_signing_comparison_ignores_only_signature_metadata(self):
        first = self.archive({'META-INF/CERT.SF': 'old', 'META-INF/NOTICE': 'notice'})
        second = self.archive({'META-INF/CERT.SF': 'new', 'META-INF/NOTICE': 'notice'})
        self.assertEqual(payload(first), payload(second))
        changed = self.archive({'META-INF/CERT.SF': 'new', 'META-INF/NOTICE': 'tampered'})
        self.assertNotEqual(payload(first), payload(changed))
        changed_aot = self.archive({'lib/other/libapp.so': 'tampered'})
        self.assertNotEqual(payload(first), payload(changed_aot))

    def test_missing_abi_is_rejected(self):
        with self.assertRaises(AssertionError):
            audit_apk(self.archive(omitted='lib/arm64-v8a/libapp.so'), self.config)


class ProvenanceTest(unittest.TestCase):
    """Signing must trust only a verified successful run; gh api is mocked."""
    repo = 'Netherman2440/pickteams'
    source_sha = 'a' * 40
    run_id = '43210000001'

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.zip = Path(directory.name) / 'artifact.zip'
        self.zip.write_bytes(b'synthetic artifact bytes')
        self.metadata = {'source_sha': self.source_sha, 'run_id': self.run_id, 'run_attempt': '1'}

    def responses(self, run=None, artifact=None, record=None):
        complete = {'status': 'completed', 'conclusion': 'success', 'head_sha': self.source_sha,
                    'run_attempt': 1, 'path': WORKFLOW_PATH,
                    'head_repository': {'full_name': self.repo}}
        listed = {'id': 999, 'name': ARTIFACT_PREFIX + self.source_sha,
                  'digest': 'sha256:' + file_digest(self.zip), 'expired': False}
        by_id = {'name': listed['name'], 'digest': listed['digest'], 'workflow_run': {'id': int(self.run_id)}}
        complete.update(run or {})
        listed.update(artifact or {})
        by_id.update(record or {})
        return {
            f'repos/{self.repo}/actions/runs/{self.run_id}': complete,
            f'repos/{self.repo}/actions/runs/{self.run_id}/artifacts': {'total_count': 1, 'artifacts': [listed]},
            f'repos/{self.repo}/actions/artifacts/{listed["id"]}': by_id,
        }

    def verify(self, responses):
        fetch = lambda endpoint: responses[endpoint]
        return verify_remote_provenance(self.repo, self.source_sha, self.zip, self.metadata, fetch)

    def test_successful_binding_is_accepted(self):
        result = self.verify(self.responses())
        self.assertEqual(result['artifact']['id'], 999)
        self.assertEqual(result['run']['head_sha'], self.source_sha)

    def test_failed_run_is_rejected(self):
        with self.assertRaises(AssertionError):
            self.verify(self.responses(run={'conclusion': 'failure'}))

    def test_incomplete_run_is_rejected(self):
        with self.assertRaises(AssertionError):
            self.verify(self.responses(run={'status': 'in_progress'}))

    def test_wrong_head_is_rejected(self):
        with self.assertRaises(AssertionError):
            self.verify(self.responses(run={'head_sha': 'c' * 40}))

    def test_wrong_attempt_is_rejected(self):
        with self.assertRaises(AssertionError):
            self.verify(self.responses(run={'run_attempt': 2}))

    def test_wrong_workflow_is_rejected(self):
        with self.assertRaises(AssertionError):
            self.verify(self.responses(run={'path': '.github/workflows/main.yml'}))

    def test_foreign_repository_is_rejected(self):
        with self.assertRaises(AssertionError):
            self.verify(self.responses(run={'head_repository': {'full_name': 'someone/else'}}))

    def test_metadata_source_mismatch_is_rejected(self):
        metadata = dict(self.metadata, source_sha='c' * 40)
        with self.assertRaises(AssertionError):
            verify_remote_provenance(self.repo, self.source_sha, self.zip, metadata,
                                     lambda endpoint: self.responses()[endpoint])

    def test_artifact_name_mismatch_is_rejected(self):
        with self.assertRaises(AssertionError):
            self.verify(self.responses(artifact={'name': ARTIFACT_PREFIX + 'c' * 40}))

    def test_artifact_digest_mismatch_is_rejected(self):
        with self.assertRaises(AssertionError):
            self.verify(self.responses(artifact={'digest': 'sha256:' + 'd' * 64}))

    def test_expired_artifact_is_rejected(self):
        with self.assertRaises(AssertionError):
            self.verify(self.responses(artifact={'expired': True}))

    def test_duplicate_artifacts_are_rejected(self):
        responses = self.responses()
        listing = f'repos/{self.repo}/actions/runs/{self.run_id}/artifacts'
        first = responses[listing]['artifacts'][0]
        responses[listing] = {'total_count': 2, 'artifacts': [first, dict(first, id=998)]}
        with self.assertRaises(AssertionError):
            self.verify(responses)

    def test_record_digest_mismatch_is_rejected(self):
        with self.assertRaises(AssertionError):
            self.verify(self.responses(record={'digest': 'sha256:' + 'e' * 64}))

    def test_record_from_other_run_is_rejected(self):
        with self.assertRaises(AssertionError):
            self.verify(self.responses(record={'workflow_run': {'id': 42}}))


class TrackedInputsTest(unittest.TestCase):
    def make_repo(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        (root / 'app').mkdir()
        (root / 'app' / 'main.dart').write_text('void main() {}')
        (root / 'app' / 'tool').mkdir()
        (root / 'app' / 'tool' / 'run.dart').write_text('void tool() {}')
        subprocess.run(['git', 'init', '-q', str(root)], check=True)
        subprocess.run(['git', '-C', str(root), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(root), '-c', 'user.email=synthetic@invalid',
                        '-c', 'user.name=synthetic', 'commit', '-qm', 'synthetic'], check=True)
        return root

    def test_map_is_derived_authoritatively_from_git(self):
        root = self.make_repo()
        tracked = tracked_inputs(root)
        self.assertEqual(set(tracked), {'app/main.dart', 'app/tool/run.dart'})
        self.assertEqual(tracked['app/main.dart'], file_digest(root / 'app/main.dart'))
        verify_tracked_inputs(dict(tracked), tracked)

    def test_empty_map_is_rejected(self):
        root = self.make_repo()
        with self.assertRaises(AssertionError):
            verify_tracked_inputs({}, tracked_inputs(root))

    def test_partial_map_is_rejected(self):
        root = self.make_repo()
        tracked = tracked_inputs(root)
        partial = dict(list(tracked.items())[:-1])
        with self.assertRaises(AssertionError):
            verify_tracked_inputs(partial, tracked)

    def test_extra_entry_is_rejected(self):
        root = self.make_repo()
        tracked = tracked_inputs(root)
        with self.assertRaises(AssertionError):
            verify_tracked_inputs({**tracked, 'app/extra.dart': 'f' * 64}, tracked)

    def test_absolute_path_is_rejected(self):
        root = self.make_repo()
        outside = str(root / 'app' / 'main.dart')
        with self.assertRaises(AssertionError):
            verify_tracked_inputs({outside: 'f' * 64}, tracked_inputs(root))

    def test_parent_relative_path_is_rejected(self):
        root = self.make_repo()
        with self.assertRaises(AssertionError):
            verify_tracked_inputs({'../outside.txt': 'f' * 64}, tracked_inputs(root))

    def test_paths_outside_app_tree_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'app').mkdir()
            for name in ('outside.txt', '/etc/passwd', 'app/../../secret', ''):
                with self.subTest(name=name), self.assertRaises(AssertionError):
                    validate_input_path(root, name)

    def test_symlink_escape_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'app').mkdir()
            (root / 'secret.txt').write_text('outside')
            (root / 'app' / 'main.dart').write_text('void main() {}')
            (root / 'app' / 'link.dart').symlink_to(root / 'secret.txt')
            with self.assertRaises(AssertionError):
                validate_input_path(root, 'app/link.dart')

    def test_changed_input_is_detected(self):
        root = self.make_repo()
        tracked = tracked_inputs(root)
        (root / 'app' / 'main.dart').write_text('void main() { changed }')
        with self.assertRaises(AssertionError):
            verify_tracked_inputs(tracked, tracked_inputs(root))


class AtomicCandidateTest(unittest.TestCase):
    def test_failure_leaves_no_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            final = Path(directory) / 'pickteams-release.apk'
            with self.assertRaises(RuntimeError):
                with atomic_candidate(final) as temp:
                    temp.write_bytes(b'signed but unaudited')
                    raise RuntimeError('offline audit failed')
            self.assertFalse(final.exists())
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_promotion_happens_only_after_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            final = Path(directory) / 'pickteams-release.apk'
            with atomic_candidate(final) as temp:
                temp.write_bytes(b'signed')
            self.assertTrue(final.is_file())
            self.assertEqual(final.read_bytes(), b'signed')
            self.assertEqual(list(Path(directory).iterdir()), [final])


if __name__ == '__main__':
    unittest.main()
