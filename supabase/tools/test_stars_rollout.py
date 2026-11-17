"""Focused standard-library contract checks for the stars operator package."""
import hashlib
import unittest
from unittest.mock import patch

import generate_stars_rollout as stars


class StarsGeneratorTest(unittest.TestCase):
    def test_exact_source_and_reproducible_package(self):
        source = stars.SOURCE.read_bytes()
        artifact = stars.generate(source)
        self.assertEqual(hashlib.sha256(source).hexdigest(), stars.SOURCE_SHA256)
        self.assertEqual(artifact, stars.OUTPUT.read_bytes())
        self.assertEqual(artifact.split(stars.BEGIN_SOURCE, 1)[1].split(b'\n' + stars.END_SOURCE, 1)[0], source)
        self.assertIn(b'ARRAY[$stars_source$' + source + b'$stars_source$]::text[]', artifact)
        self.assertNotIn(b'@@', artifact)

    def test_any_changed_source_is_refused_not_rehashed(self):
        source = stars.SOURCE.read_bytes()
        for changed in (source + b'\n', source.replace(b'immutable', b'stable'), b'-- $stars_source$', b'\xff'):
            with self.subTest(changed=changed[:30]), self.assertRaises(ValueError):
                stars.generate(changed)

    def test_transaction_reservation_history_and_receipt_order(self):
        sql = stars.generate(stars.SOURCE.read_bytes()).decode()
        self.assertEqual(sql.count('\nBEGIN;'), 1)
        self.assertEqual(sql.count('\nCOMMIT;'), 1)
        markers = ['BEGIN;', 'DO $preflight$', 'CREATE FUNCTION public.valid_star_thresholds',
                   '-- BEGIN CANONICAL MIGRATION', 'DO $history$', 'DO $verify$',
                   "NOTIFY pgrst, 'reload schema';", '\nCOMMIT;\n', 'DELETE FROM pg_temp.stars_operator_receipt RETURNING *;']
        self.assertEqual([sql.index(x) for x in markers], sorted(sql.index(x) for x in markers))
        self.assertIn("SET LOCAL lock_timeout = '5s';", sql)
        self.assertIn("SET LOCAL statement_timeout = '60s';", sql)
        for forbidden in ('GRANT ', 'REVOKE ', 'CREATE TABLE IF NOT EXISTS', 'ADD COLUMN IF NOT EXISTS', 'ON CONFLICT', 'accept_match_draft',
                          'INSERT INTO public.', 'UPDATE public.', 'DELETE FROM public.'):
            self.assertNotIn(forbidden, sql.upper() if forbidden.isupper() else sql)

    def test_check_refuses_stale_package_without_write(self):
        source = stars.SOURCE.read_bytes()
        with patch.object(stars.OUTPUT.__class__, 'read_bytes', side_effect=[source, b'stale']), \
             patch.object(stars.OUTPUT.__class__, 'exists', return_value=True), \
             patch.object(stars.OUTPUT.__class__, 'write_bytes') as write, \
             patch('sys.argv', ['generate_stars_rollout.py', '--check']):
            with self.assertRaises(SystemExit) as result:
                stars.main()
            self.assertEqual(result.exception.code, 1)
            write.assert_not_called()

    def test_no_default_backfill_or_new_policy(self):
        source = stars.SOURCE.read_text().lower()
        self.assertNotIn('default', source.split('alter table', 1)[1])
        self.assertNotIn('create policy', source)
        self.assertNotIn('update public.', source)
        self.assertIn('null;', source)
        sql = stars.generate(stars.SOURCE.read_bytes()).decode()
        for contract in ('prosecdef', 'provolatile', 'proconfig', 'prosrc', 'pg_depend',
                         'relrowsecurity', 'rolbypassrls', 'history privileges missing',
                         'unsupported history shape', 'prior_history_unchanged'):
            self.assertIn(contract, sql)


if __name__ == '__main__':
    unittest.main()
