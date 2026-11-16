#!/usr/bin/env python3
"""Local PostgreSQL proof. No remote credentials or connections.

python3 supabase/tools/prove_snapshot_rankings.py --pg-bin /path/to/bin \
  --proof-dir /absolute/new/directory
"""
import argparse
from pathlib import Path

from prove_draft_rollout import Proof

ROOT = Path(__file__).resolve().parents[2]
NEW = '20261116120000_preserve_draft_rankings.sql'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin', required=True, type=Path)
    parser.add_argument('--proof-dir', required=True, type=Path)
    args = parser.parse_args()
    proof = Proof(args.pg_bin, args.proof_dir)
    proof.run('initdb', '-D', proof.cluster, '-U', 'operator_test', '-A', 'trust',
              '--no-locale', '--encoding=UTF8')
    try:
        proof.run('pg_ctl', '-D', proof.cluster, '-l', proof.directory / 'postgres.log',
                  '-o', f'-k {proof.socket} -p 56124 -c listen_addresses=\'\' '
                  '-c shared_buffers=16MB -c max_connections=8', '-w', 'start')
        proof.env['PGPORT'] = '56124'
        proof.sql('postgres', (ROOT / 'supabase/tests/fixtures/local_auth.sql').read_text())
        for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
            if path.name != NEW:
                proof.sql('postgres', path.read_text())
        test = (ROOT / 'supabase/tests/accept_match_draft_test.sql').read_text()
        _, error = proof.sql('postgres', test, success=False)
        assert 'Generation A survives current B' in error, error
        proof.passed('baseline reproduces generation A replaced with acceptance B')
        proof.sql('postgres', (ROOT / 'supabase/migrations' / NEW).read_text())
        proof.sql('postgres', (ROOT / 'supabase/tools/audit_historical_rankings.sql').read_text())
        proof.passed('read-only audit syntax on the disposable fixture (not production inventory)')
        for path in sorted((ROOT / 'supabase/tests').glob('*.sql')):
            proof.sql('postgres', path.read_text())
            proof.passed(path.name)
    finally:
        proof.run('pg_ctl', '-D', proof.cluster, '-m', 'immediate', '-w', 'stop')


if __name__ == '__main__':
    main()
