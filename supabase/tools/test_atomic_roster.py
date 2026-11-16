#!/usr/bin/env python3
"""Disposable-local roster RPC and score-race proof. No rollout/remote access.

Run under the required nonblocking resource gate:
python3 supabase/tools/test_atomic_roster.py --pg-bin /path/to/bin \
  --proof-dir /absolute/new/directory
"""
import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin', type=Path, required=True)
    parser.add_argument('--proof-dir', type=Path, required=True)
    args = parser.parse_args()
    directory = args.proof_dir.resolve()
    directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    socket = directory / 'socket'
    socket.mkdir(mode=0o700)
    cluster = directory / 'cluster'
    env = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
    env.update(PGHOST=str(socket), PGPORT='56128', PGDATABASE='postgres',
               PGUSER='operator_test', PGCONNECT_TIMEOUT='5',
               PGPASSFILE=str(directory / 'no-password'))
    counter = 0

    def run(tool, *argv, text=None, code=0):
        nonlocal counter
        counter += 1
        result = subprocess.run([str(args.pg_bin / tool), *map(str, argv)],
                                input=text, text=True, capture_output=True,
                                env=env, timeout=120)
        log = directory / f'{counter:03d}-{tool}.log'
        log.write_text(result.stdout + result.stderr + f'\nexit={result.returncode}\n')
        assert result.returncode == code, f'Expected {code}, got {result.returncode}: {log}'
        return result.stdout

    def sql(text):
        return run('psql', '-X', '-v', 'ON_ERROR_STOP=1', '-A', '-t', text=text)

    def passed(name):
        with (directory / 'checks.log').open('a') as log:
            log.write(f'PASS {name}\n')
        print(f'PASS {name}', flush=True)

    run('initdb', '-D', cluster, '-U', 'operator_test', '-A', 'trust', '--no-locale', '--encoding=UTF8')
    started = False
    children = []
    try:
        # Local packaged PG lacks libLLVM-17; no production setting is changed.
        run('pg_ctl', '-D', cluster, '-l', directory / 'postgres.log', '-o',
            f"-k {socket} -p 56128 -c listen_addresses='' -c shared_buffers=16MB -c max_connections=8 -c jit=off", '-w', 'start')
        started = True
        sql((ROOT / 'supabase/tests/fixtures/local_auth.sql').read_text())
        for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
            sql(path.read_text())
        run('psql', '-X', '-v', 'ON_ERROR_STOP=1', '-f', ROOT / 'supabase/tests/atomic_preserved_roster_test.sql')
        passed('RPC rollback, partial addition, RLS, owner/admin, transfer/removal/re-addition, drift/replay, score guard')
        sql((ROOT / 'supabase/tests/fixtures/preserved_roster.sql').read_text())
        uid = '10000000-0000-0000-0000-000000000001'
        match = '40000000-0000-0000-0000-000000000001'
        prefix = '30000000-0000-0000-0000-'
        home = [prefix + f'{i:012d}' for i in (1, 2)]
        away = [prefix + f'{i:012d}' for i in (3, 4)]
        ranks = dict(zip(home + away, (90, 52, 53, 94)))
        command = f"select public.update_preserved_match_roster('{match}', '90000000-0000-0000-0000-000000000001', '{json.dumps(home)}', '{json.dumps(away)}', '{json.dumps(ranks)}', null);"
        baseline = sql(f"select (score_meta - '_roster_operation')::text from matches where match_id='{match}';")
        owner_env = dict(env, PGUSER='operator_test')

        def session(name):
            p = subprocess.Popen([str(args.pg_bin / 'psql'), '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-A', '-t'],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True, env=owner_env)
            children.append(p)
            return p

        scorer = session('scorer')
        scorer.stdin.write(f"begin; update matches set home_score=1 where match_id='{match}';\n\\echo SCORE_LOCKED\n")
        scorer.stdin.flush()
        selector = selectors.DefaultSelector()
        selector.register(scorer.stdout, selectors.EVENT_READ)
        lines = []
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            assert selector.select(10), 'Score session did not acquire lock'
            line = scorer.stdout.readline()
            lines.append(line)
            if 'SCORE_LOCKED' in line:
                break
        else:
            raise AssertionError('Score lock handshake timed out')
        selector.close()
        editor = session('editor')
        editor.stdin.write("set application_name='atomic_roster_edit'; set lock_timeout='10s'; set role authenticated; "
                           f"select set_config('request.jwt.claim.sub','{uid}',false); {command}\n")
        editor.stdin.flush()
        # This bounded DB-state observation tests a row-lock interleaving, not
        # capacity admission. There is no resource polling or retry loop.
        deadline = time.monotonic() + 5
        while True:
            waiting = sql("select count(*) from pg_stat_activity where application_name='atomic_roster_edit' and wait_event_type='Lock';").strip()
            if waiting == '1':
                break
            assert time.monotonic() < deadline, 'RPC did not wait for the scored match row'
        scorer.stdin.write('commit;\n')
        scorer.stdin.flush()
        score_out, score_err = scorer.communicate(timeout=10)
        edit_out, edit_err = editor.communicate(timeout=10)
        (directory / 'score-session.log').write_text(''.join(lines) + score_out + score_err + f'exit={scorer.returncode}\n')
        (directory / 'edit-session.log').write_text(edit_out + edit_err + f'exit={editor.returncode}\n')
        assert scorer.returncode == 0
        assert editor.returncode == 3 and 'match with score' in edit_err, edit_err
        assert sql(f"select (score_meta - '_roster_operation')::text from matches where match_id='{match}';") == baseline
        assert sql('select count(*) from team_players;').strip() == '2'
        assert sql('select count(*) from ranking_history;').strip() == '0'
        passed('concurrent score holds match lock; waiting roster edit rejects after score commit, no partial state')
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
                child.communicate(timeout=10)
        if started:
            run('pg_ctl', '-D', cluster, '-m', 'immediate', '-w', 'stop')
            passed('owned sessions and private PostgreSQL stopped; no production access')


if __name__ == '__main__':
    main()
