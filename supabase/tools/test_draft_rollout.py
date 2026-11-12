"""Standard-library checks; run: python3 -m unittest discover -s supabase/tools -v."""

import hashlib
import unittest
from unittest.mock import patch

import generate_draft_rollout as rollout


class GeneratorTest(unittest.TestCase):
    def test_checked_in_artifact_and_exact_source_span(self):
        source = rollout.SOURCE.read_bytes()
        artifact = rollout.generate(source)
        self.assertEqual(rollout.OUTPUT.read_bytes(), artifact)
        embedded = artifact.split(rollout.BEGIN_SOURCE, 1)[1].split(
            b"\n" + rollout.END_SOURCE, 1
        )[0]
        self.assertEqual(embedded, source)
        self.assertIn(hashlib.sha256(source).hexdigest().encode(), artifact)
        self.assertEqual(artifact.count(b"\nBEGIN;\n"), 1)
        self.assertEqual(artifact.count(b"\nCOMMIT;\n"), 1)
        self.assertLess(artifact.index(b"\nBEGIN;"), artifact.index(rollout.BEGIN_SOURCE))
        self.assertLess(artifact.index(b"\nNOTIFY pgrst"), artifact.index(b"\nCOMMIT;"))
        self.assertLess(artifact.index(b"DO $history$"), artifact.index(b"\nCOMMIT;"))
        self.assertNotIn(b"ON CONFLICT", artifact.split(b"DO $history$", 1)[1].split(
            b"-- No ON CONFLICT", 1)[0])

    def test_literal_and_byte_preservation(self):
        for source in (b"-- apostrophe ' and $$\r\n", b"-- no final newline"):
            with self.subTest(source=source):
                artifact = rollout.generate(source)
                self.assertIn(rollout.BEGIN_SOURCE + source + b"\n" + rollout.END_SOURCE,
                              artifact)
                self.assertIn(b"ARRAY[$canonical_history$" + source +
                              b"$canonical_history$]::text[]", artifact)

    def test_unsafe_delimiter_and_invalid_encoding_fail_closed(self):
        with self.assertRaises(ValueError):
            rollout.generate(b"-- $canonical_history$")
        with self.assertRaises(UnicodeDecodeError):
            rollout.generate(b"\xff")

    def test_check_rejects_stale_artifact_without_writing(self):
        with patch.object(rollout.OUTPUT.__class__, "read_bytes", return_value=b"stale"), \
             patch.object(rollout.OUTPUT.__class__, "exists", return_value=True), \
             patch.object(rollout.OUTPUT.__class__, "write_bytes") as write, \
             patch("sys.argv", ["generate_draft_rollout.py", "--check"]):
            with self.assertRaises(SystemExit) as error:
                rollout.main()
            self.assertEqual(error.exception.code, 1)
            write.assert_not_called()


if __name__ == "__main__":
    unittest.main()
