"""Adversarial export checks use synthetic configuration, never production values."""
from pathlib import Path
import base64
import json
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import build_native_candidate

from build_native_candidate import ABIS, audit_apk, capture, digest
from sign_native_candidate import payload


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


if __name__ == '__main__':
    unittest.main()
