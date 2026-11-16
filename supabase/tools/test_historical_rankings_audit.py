#!/usr/bin/env python3
"""Disposable-local audit regression. Never uses ambient PostgreSQL access.

python3 supabase/tools/test_historical_rankings_audit.py --pg-bin /path/to/bin \
  --proof-dir /absolute/new/directory
The fixture alone creates roles/data. The audited artifact does not do so.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
NEW = '20261116120000_preserve_draft_rankings.sql'


def uid(prefix, n):
    return f'{prefix}0000000-0000-0000-0000-{n:012d}'


def seed():
    statements = []
    proposal = {'teams': [[uid(3, 1)], [uid(3, 2)]],
                'rankings': {uid(3, 1): 41.25, uid(3, 2): 56.5},
                'play_with_substitute': False}
    partial = dict(proposal, rankings={uid(3, 1): 41.25})
    legacy = {'teams': proposal['teams']}
    for i in (1, 2, 3):
        statements.append(f"""
insert into auth.users(id,email) values ('{uid(1,i)}','fixture{i}@example.test');
insert into squads(squad_id,owner_id,name,visibility) values
 ('{uid(2,i)}','{uid(1,i)}','Synthetic {i}','private');
insert into user_squads(user_id,squad_id,role) values ('{uid(1,i)}','{uid(2,i)}','owner');
insert into tournaments(tournament_id,squad_id) values ('{uid(5,i)}','{uid(2,i)}');
insert into matches(match_id,squad_id,tournament_id,home_score,away_score) values
 ('{uid(4,i)}','{uid(2,i)}','{uid(5,i)}',1,0);
insert into drafts(draft_id,squad_id,match_id) values ('{uid(6,i)}','{uid(2,i)}','{uid(4,i)}');
insert into draft_payloads(draft_id,proposals) values
 ('{uid(6,i)}','{json.dumps([{'_meta': {'seed': 42}}, proposal, partial, legacy])}');
insert into tournament_drafts(tournament_draft_id,squad_id,tournament_id) values
 ('{uid(7,i)}','{uid(2,i)}','{uid(5,i)}');
insert into tournament_draft_payloads(tournament_draft_id,proposals) values
 ('{uid(7,i)}','{json.dumps([proposal])}');
""")
    statements.append(f"""
-- Caller can see two squads, but the approved audit must count only squad 1.
insert into user_squads(user_id,squad_id,role) values ('{uid(1,1)}','{uid(2,2)}','member');
insert into matches(match_id,squad_id) values ('{uid(4,4)}','{uid(2,1)}');
insert into players(player_id,squad_id,name,base_score,score)
 select ('30000000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid,
 '{uid(2,1)}','Synthetic ' || i,50,90 from generate_series(1,3) i;
insert into teams(team_id,match_id,side,color) values ('{uid(8,1)}','{uid(4,1)}','home','#FFFFFF');
insert into team_players(match_id,team_id,player_id)
 select '{uid(4,1)}','{uid(8,1)}',player_id from players;
insert into ranking_history(player_id,match_id,ranking,change) values
 ('{uid(3,1)}','{uid(4,1)}',41.25,5),
 ('{uid(3,3)}','{uid(4,2)}',12,0);
insert into ranking_history(player_id,tournament_id,ranking) values ('{uid(3,2)}','{uid(5,1)}',56.5);
""")
    return '\n'.join(statements)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin', type=Path, required=True)
    parser.add_argument('--proof-dir', type=Path, required=True)
    args = parser.parse_args()
    directory = args.proof_dir.resolve()
    directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    socket = directory / 'socket'
    socket.mkdir(mode=0o700)
    cluster = directory / 'cluster'
    env = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
    env.update(PGHOST=str(socket), PGPORT='56127', PGUSER='operator_test',
               PGDATABASE='postgres', PGCONNECT_TIMEOUT='5', PGPASSFILE=str(directory / 'no-password'))
    counter = 0

    def run(tool, *argv, sql=None, code=0, extra=None):
        nonlocal counter
        counter += 1
        result = subprocess.run([str(args.pg_bin / tool), *map(str, argv)],
                                input=sql, text=True, capture_output=True,
                                env=dict(env, **(extra or {})), timeout=120)
        path = directory / f'{counter:03d}-{tool}.log'
        path.write_text(result.stdout + result.stderr + f'\nexit={result.returncode}\n')
        assert result.returncode == code, f'Expected {code}, got {result.returncode}: {path}'
        return result.stdout

    def sql(text, **kwargs):
        return run('psql', '-X', '-v', 'ON_ERROR_STOP=1', '-A', '-t', sql=text, **kwargs)

    def passed(name):
        with (directory / 'checks.log').open('a') as log:
            log.write(f'PASS {name}\n')
        print(f'PASS {name}', flush=True)

    audit_path = ROOT / 'supabase/tools/audit_historical_rankings.sql'
    audit = audit_path.read_text()
    (directory / 'audit.sha256').write_text(hashlib.sha256(audit_path.read_bytes()).hexdigest() + '\n')
    run('initdb', '-D', cluster, '-U', 'operator_test', '-A', 'trust', '--no-locale', '--encoding=UTF8')
    started = False
    try:
        # The packaged local PostgreSQL has no libLLVM-17. Disable JIT only on
        # this disposable server, not in the operator artifact or production.
        run('pg_ctl', '-D', cluster, '-l', directory / 'postgres.log', '-o',
            f"-k {socket} -p 56127 -c listen_addresses='' -c shared_buffers=16MB -c max_connections=8 -c jit=off", '-w', 'start')
        started = True
        sql((ROOT / 'supabase/tests/fixtures/local_auth.sql').read_text())
        for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
            if path.name != NEW:
                sql(path.read_text())
        # Local fixture access only. No role or JWT setup occurs in the audit.
        sql('alter role authenticated login; alter role anon login;')
        sql(seed())
        (directory / 'fixture.sql').write_text(seed())
        member = dict(PGUSER='authenticated', PGOPTIONS=f'-c request.jwt.claim.sub={uid(1,1)}')
        scope = ['-v', f'authorized_squad_id={uid(2,1)}', '-v', f'expected_caller_id={uid(1,1)}']

        def audit_run(label, *, extra=None, variables=None, ok=False, explicit=0, preamble=None, metadata=0, roster='3|1|1|1'):
            out = run('psql', '-X', '-v', 'ON_ERROR_STOP=1', '-A', '-t',
                      *(scope if variables is None else variables),
                      *(['-c', preamble] if preamble else []), '-f', audit_path,
                      code=0 if ok else 3, extra=member if extra is None else extra)
            assert 'ROLLBACK' in out, out
            if ok:
                rows = [line for line in out.splitlines() if '|' in line]
                assert rows == ['1|1|1|1', f'2|1|{explicit}|{metadata}', '1|1|0', roster, '4|3|3|2'], rows
                assert not any(uid(p, i) in out for p in range(1,9) for i in range(1,5)), out
            else:
                assert 'STOP:' in out and '|' not in out, out
            passed(label)

        for phase in ('original', 'current'):
            if phase == 'current':
                sql((ROOT / 'supabase/migrations' / NEW).read_text())
                sql(f"update matches set play_with_substitute = false where squad_id='{uid(2,1)}';")
            explicit = 0 if phase == 'original' else 2
            audit_run(f'{phase}: correct exact single-squad counts despite two visible squads and foreign data', ok=True, explicit=explicit)
            audit_run(f'{phase}: absent scope rejected', variables=[])
            audit_run(f'{phase}: absent caller scope rejected', variables=scope[:2])
            audit_run(f'{phase}: invalid private scope rejected without echo', variables=['-v','authorized_squad_id=invalid-private','-v',f'expected_caller_id={uid(1,1)}'])
            audit_run(f'{phase}: wrong caller rejected', variables=['-v',f'authorized_squad_id={uid(2,1)}','-v',f'expected_caller_id={uid(1,2)}'])
            audit_run(f'{phase}: foreign squad rejected', variables=['-v',f'authorized_squad_id={uid(2,3)}','-v',f'expected_caller_id={uid(1,1)}'])
            audit_run(f'{phase}: absent auth caller rejected', extra=dict(PGUSER='authenticated'))
            audit_run(f'{phase}: unsuitable role rejected', extra=dict(PGUSER='anon', PGOPTIONS=member['PGOPTIONS']))
            audit_run(f'{phase}: superuser rejected', extra=dict(PGUSER='operator_test', PGOPTIONS=member['PGOPTIONS']))
            audit_run(f'{phase}: superuser session behind authenticated role rejected', extra=dict(PGUSER='operator_test', PGOPTIONS=member['PGOPTIONS']), preamble='set role authenticated;')
            sql('alter role authenticated bypassrls;')
            audit_run(f'{phase}: BYPASSRLS rejected')
            sql('alter role authenticated nobypassrls; alter table matches owner to authenticated;')
            audit_run(f'{phase}: table-owner bypass rejected')
            # ALTER OWNER drops the former owner's explicit ACL entry locally.
            sql('alter table matches owner to operator_test; grant select, insert, update, delete on matches to authenticated;')
            sql('alter table matches disable row level security;')
            audit_run(f'{phase}: disabled RLS rejected')
            sql('alter table matches enable row level security;')
            audit_run(f'{phase}: restored fixture counts unchanged', ok=True, explicit=explicit)
            vector = {uid(3, i): 90 for i in (1, 2, 3)}
            sql(f"update matches set score_meta = '{json.dumps({'draft_rankings': vector})}' where match_id='{uid(4,1)}';")
            audit_run(f'{phase}: new match vector counts override creation history', ok=True, explicit=explicit, metadata=1, roster='3|3|0|0')
            vector.pop(uid(3, 2))
            sql(f"update matches set score_meta = '{json.dumps({'draft_rankings': vector})}' where match_id='{uid(4,1)}';")
            audit_run(f'{phase}: partial new vector is not mixed with tournament history', ok=True, explicit=explicit, metadata=1, roster='3|2|0|1')
            sql(f"update matches set score_meta = '{{}}' where match_id='{uid(4,1)}';")
        # Run the repository's native SQL/RLS lane only on this local cluster.
        sql('delete from matches; delete from tournament_draft_payloads; delete from tournaments; delete from drafts; delete from user_squads; delete from squads; delete from auth.users;')
        for path in sorted((ROOT / 'supabase/tests').glob('*.sql')):
            sql(path.read_text())
            passed(path.name)
    finally:
        if started:
            run('pg_ctl', '-D', cluster, '-m', 'immediate', '-w', 'stop')
            passed('owned PostgreSQL stopped; no remote connection or rollout package used')


if __name__ == '__main__':
    main()
