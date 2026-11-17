"""Original independent SQL probes. Run only via admit-pg.sh.
No author test harness. Reuses canonical predecessor/local_auth fixture only.
All connections use a new private UNIX socket; no TCP or ambient libpq settings.
"""
from pathlib import Path
import hashlib
import json
import os
import select
import shutil
import subprocess
import tempfile
import time

ROOT = Path.cwd()
OUT = Path(__file__).parent
TOOLS = OUT.parent / 'continuation-owner-aggregates/runtime-tools/root/usr'
BIN = TOOLS / 'lib/postgresql/16/bin'
HEAD = '3047fd512bb3b729022e5b4140b87d4a597b6cb9'
BASE = 'f0384d6e38673bf0f44423514e7749cb316c83d3'
CANON = ROOT / 'supabase/migrations/20261116120000_add_squad_star_thresholds.sql'
OP = ROOT / 'supabase/tools/squad_star_thresholds_operator.sql'
RECEIPT = 't|t|t|t|t|t|t|t|t'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def git(*args):
    return subprocess.check_output(['git', *args])

class DB:
    def __init__(self):
        self.directory = OUT / 'independent-pg'
        self.directory.mkdir(mode=0o700)
        self.home = self.directory / 'home'
        self.home.mkdir(mode=0o700)
        self.socket = Path(tempfile.mkdtemp(prefix='pt-r6-', dir='/tmp'))
        self.data = self.directory / 'data'
        self.passfile = self.home / 'empty-passfile'
        self.passfile.touch(mode=0o600)
        self.port = '56417'
        self.env = {'PATH':str(BIN)+':/usr/bin:/bin','HOME':str(self.home),'LC_ALL':'C','LANG':'C',
                    'LD_LIBRARY_PATH':str(TOOLS/'lib/x86_64-linux-gnu'),
                    'PGPASSFILE':str(self.passfile),'PGCONNECT_TIMEOUT':'3'}
        assert not any(k.startswith('PG') and k not in ('PGPASSFILE','PGCONNECT_TIMEOUT') for k in self.env)
        self.counter = 0
        self.results = []
        self.sessions = []
    def run(self, tool, *args, sql=None):
        self.counter += 1
        result = subprocess.run([str(BIN/tool), *map(str,args)], input=sql, text=True, capture_output=True,
                                env=self.env, timeout=120)
        (self.directory / f'{self.counter:03d}-{tool}.log').write_text(result.stdout+result.stderr+f'\nEXIT={result.returncode}\n')
        return result
    def args(self, db):
        return ['-X','--no-password','-h',str(self.socket),'-p',self.port,'-U','review_sql','-d',db,
                '-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose']
    def sql(self, db, text, expected=None):
        result = self.run('psql', *self.args(db), sql=text)
        if expected is None:
            assert result.returncode == 0, result.stderr
        else:
            assert result.returncode == 3 and expected in result.stderr, (expected,result.returncode,result.stderr)
        return result.stdout
    def dump(self, db):
        result = self.run('pg_dump','-h',self.socket,'-p',self.port,'-U','review_sql','--no-password','--no-owner','-d',db)
        assert result.returncode == 0, result.stderr
        return '\n'.join(l for l in result.stdout.splitlines() if not l.startswith(('\\restrict ','\\unrestrict '))).encode()
    def case(self, label, **data):
        row = {'case':label,**data}
        self.results.append(row)
        print('PASS',label,json.dumps(data,sort_keys=True),flush=True)
    def clone(self, db, history=True):
        self.sql('postgres',f'CREATE DATABASE {db} TEMPLATE fixture;')
        if history:
            self.sql(db,"CREATE SCHEMA supabase_migrations; CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,name text,statements text[]); INSERT INTO supabase_migrations.schema_migrations VALUES ('old-baseline','unchanged',ARRAY['synthetic predecessor']);")
    def reject_unchanged(self, db, script, error):
        before = self.dump(db)
        self.sql(db,script,expected=error)
        after = self.dump(db)
        assert before == after, db
        return sha(before)
    def start(self):
        version = self.run('postgres','--version')
        assert version.returncode == 0 and 'PostgreSQL) 16.' in version.stdout
        print('ACTUAL',version.stdout.strip(),flush=True)
        result = self.run('initdb','-D',self.data,'-U','review_sql','-A','trust','--no-locale','--encoding=UTF8','-L',TOOLS/'share/postgresql/16')
        assert result.returncode == 0, result.stderr
        result = self.run('pg_ctl','-D',self.data,'-l',self.directory/'postgres.log','-o',
                          f"-k {self.socket} -p {self.port} -c listen_addresses='' -c shared_buffers=16MB -c max_connections=12",'-w','start')
        assert result.returncode == 0, result.stderr
        self.sql('postgres','CREATE DATABASE fixture;')
        self.sql('fixture',(ROOT/'supabase/tests/fixtures/local_auth.sql').read_text())
        for path in sorted(CANON.parent.glob('*.sql')):
            if path.name < CANON.name:
                self.sql('fixture',path.read_text())
        self.sql('fixture',"INSERT INTO auth.users(id,email) VALUES ('10000000-0000-0000-0000-000000000001','review-local@example.invalid'); INSERT INTO public.squads(squad_id,owner_id,name) VALUES ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Independent sentinel');")
        assert self.sql('fixture',"SELECT current_setting('listen_addresses')='' AND inet_server_addr() IS NULL;").strip() == 't'
        self.case('owned socket-only PG16 fixture; canonical predecessors and synthetic sentinel',socket=str(self.socket),port=self.port)
    def stop(self):
        try:
            for session in self.sessions:
                if session.process.poll() is None:
                    try:
                        session.finish('\nROLLBACK;\n')
                    except (BrokenPipeError, OSError):
                        pass  # Server cleanup below still owns every connection.
        finally:
            if (self.data/'postmaster.pid').exists():
                result = self.run('pg_ctl','-D',self.data,'-m','fast','-w','stop')
                assert result.returncode == 0, result.stderr
            assert not (self.data/'postmaster.pid').exists()
            self.socket.rmdir()
            self.case('owned server stopped and private socket removed')

class Session:
    def __init__(self, db, name, label):
        self.db,self.label = db,label
        self.process = subprocess.Popen([str(BIN/'psql'),*db.args(name)], stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT,env=db.env)
        self.output = b''
        db.sessions.append(self)
    def barrier(self, script):
        marker = b'INDEPENDENT_SQL_BARRIER_READY'
        self.process.stdin.write(script.encode()+b'\n\\echo '+marker+b'\n')
        self.process.stdin.flush()
        buffer = b''
        deadline = time.monotonic()+12
        while marker+b'\n' not in buffer:
            remaining = deadline-time.monotonic()
            assert remaining > 0, 'SQL protocol barrier timed out'
            ready,_,_ = select.select([self.process.stdout],[],[],remaining)
            assert ready, 'SQL protocol barrier did not reply'
            chunk = os.read(self.process.stdout.fileno(),65536)
            assert chunk, buffer.decode(errors='replace')
            buffer += chunk
        self.output += buffer
    def finish(self, script=''):
        if self.process.stdin is not None:
            self.process.stdin.write(script.encode())
            self.process.stdin.close()
            self.process.stdin = None
        rest,_ = self.process.communicate(timeout=30)
        self.output += rest
        (self.db.directory/(self.label+'.log')).write_bytes(self.output+b'\nEXIT='+str(self.process.returncode).encode()+b'\n')
        return self.output.decode(),self.process.returncode

STATE = """SELECT jsonb_build_object('owner',c.relowner,'acl',c.relacl::text,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,
'cols',(SELECT jsonb_agg(jsonb_build_array(attnum,attname,attacl::text) ORDER BY attnum) FROM pg_attribute WHERE attrelid=c.oid AND attnum>0 AND NOT attisdropped AND attname<>'star_thresholds'),
'policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY policyname) FROM pg_policies p WHERE schemaname='public' AND tablename='squads'))::text FROM pg_class c WHERE c.oid='public.squads'::regclass;
SELECT jsonb_agg(to_jsonb(s)-'star_thresholds' ORDER BY squad_id)::text FROM public.squads s;
"""

def main():
    os.umask(0o077)
    assert git('rev-parse','HEAD').decode().strip() == HEAD and not git('status','--porcelain=v1')
    raw = OP.read_bytes()
    assert sha(raw) == 'f26b6a1b597e83c9a989bc73f6ae6bf1302370ddbf1bfe25d90a5dfa09c7cfba'
    assert sha(CANON.read_bytes()) == '02cfb0ff0c766c77e76c75be115a981960a32db551b3cb5733f623ff61b4f35a'
    (OUT/'reviewed-operator.sql').write_bytes(raw)
    (OUT/'reviewed-canonical.sql').write_bytes(CANON.read_bytes())
    operator = raw.decode()
    db = DB()
    try:
        db.start()
        # Positive exact full-file execution; hostile public helper names cannot
        # redirect qualified pg_temp state or the empty-search-path validator.
        db.clone('positive')
        db.sql('positive','CREATE TABLE public.stars_operator_state(marker text); INSERT INTO public.stars_operator_state VALUES (\'untouched\'); CREATE TABLE public.stars_operator_receipt(marker text); INSERT INTO public.stars_operator_receipt VALUES (\'untouched\');')
        before = db.sql('positive',STATE)
        output = db.sql('positive',"SET search_path=public,pg_temp;\n"+operator+"\nSELECT to_regclass('pg_temp.stars_operator_state') IS NULL AND (SELECT count(*) FROM pg_temp.stars_operator_receipt)=0; SELECT marker FROM public.stars_operator_state; SELECT marker FROM public.stars_operator_receipt;")
        assert output.splitlines().count(RECEIPT) == 1 and output.index('COMMIT') < output.index(RECEIPT)
        assert output.splitlines().count('untouched') == 2
        assert db.sql('positive',STATE) == before
        assert db.sql('positive',"SELECT count(*)=1 AND bool_and(star_thresholds IS NULL) FROM public.squads;").strip() == 't'
        assert db.sql('positive',"SELECT name='unchanged' AND statements=ARRAY['synthetic predecessor']::text[] FROM supabase_migrations.schema_migrations WHERE version='old-baseline';").strip() == 't'
        db.case('exact full-file commit then nine booleans; public helper shadowing ineffective; existing rows/policies/ACL preserved')
        # NULL, numeric extremes and direct owner/other/guest behavior; all writes
        # roll back and any invalid-vector error must be the CHECK, not a grant.
        rls = """BEGIN;
DO $$ BEGIN ASSERT public.valid_star_thresholds(NULL); ASSERT NOT public.valid_star_thresholds(ARRAY[1,2,NULL,4,5]::float8[]); ASSERT NOT public.valid_star_thresholds(ARRAY[1,2,3,4,'NaN'::float8]); ASSERT NOT public.valid_star_thresholds('[0:4]={1,2,3,4,5}'::float8[]); ASSERT public.valid_star_thresholds(ARRAY['-1e308'::float8,-1,0,1,'1e308'::float8]); END $$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
DO $$ DECLARE n int; BEGIN UPDATE public.squads SET star_thresholds=ARRAY[1,2,3,4,5]; GET DIAGNOSTICS n=ROW_COUNT; ASSERT n=1; BEGIN UPDATE public.squads SET star_thresholds=ARRAY[1,2,2,4,5]; RAISE EXCEPTION 'Invalid accepted'; EXCEPTION WHEN check_violation THEN NULL; END; END $$;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
DO $$ DECLARE n int; BEGIN UPDATE public.squads SET star_thresholds=ARRAY[2,3,4,5,6]; GET DIAGNOSTICS n=ROW_COUNT; ASSERT n=0; END $$;
RESET ROLE; SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub','',true);
DO $$ DECLARE n int; BEGIN ASSERT (SELECT count(*) FROM public.squads)=1; UPDATE public.squads SET star_thresholds=ARRAY[2,3,4,5,6]; GET DIAGNOSTICS n=ROW_COUNT; ASSERT n=0; ASSERT has_function_privilege(current_user,'public.valid_star_thresholds(float8[])','EXECUTE'); END $$;
ROLLBACK;
"""
        snapshot = db.dump('positive')
        db.sql('positive',rls)
        assert db.dump('positive') == snapshot
        db.case('own NULL/extreme/shape probes and owner/nonowner/guest RLS checks; full dump unchanged',dumpSha256=sha(snapshot))
        for name,history in [('absent',False),('late_history',True),('late_absent',False)]:
            db.clone(name,history)
            if name == 'absent':
                output = db.sql(name,operator)
                assert '|'.join(['t']*6+['f','t','t']) in output
                assert db.sql(name,"SELECT to_regnamespace('supabase_migrations') IS NULL AND (SELECT bool_and(star_thresholds IS NULL) FROM public.squads);").strip() == 't'
                db.case('absent history remains absent; false history flag is limitation, not fabricated baseline')
            else:
                broken = operator.replace("NOTIFY pgrst, 'reload schema';", "NOTIFY pgrst, 'reload schema';\nDO $$ BEGIN RAISE EXCEPTION 'INDEPENDENT LATE ABORT'; END $$;")
                digest = db.reject_unchanged(name,broken,'INDEPENDENT LATE ABORT')
                assert db.sql(name,"SELECT to_regprocedure('public.valid_star_thresholds(float8[])') IS NULL AND NOT EXISTS(SELECT FROM pg_attribute WHERE attrelid='public.squads'::regclass AND attname='star_thresholds' AND NOT attisdropped);").strip() == 't'
                db.case(name+': late fault after NOTIFY rolls back canonical DDL/stub/history',dumpSha256=digest)
        db.clone('advisory_lock')
        before = db.dump('advisory_lock')
        holder = Session(db,'advisory_lock','advisory-holder')
        holder.barrier('BEGIN; SELECT pg_advisory_xact_lock(20261116,120000);')
        db.sql('advisory_lock',operator,expected='concurrent operator; stop for review')
        holder.finish('ROLLBACK;\n')
        assert db.dump('advisory_lock') == before
        db.case('competing advisory operator refuses at intended immediate guard; dump unchanged')
        db.clone('relation_lock')
        before = db.dump('relation_lock')
        holder = Session(db,'relation_lock','relation-holder')
        holder.barrier('BEGIN; LOCK TABLE public.squads IN SHARE MODE;')
        db.sql('relation_lock',operator,expected='canceling statement due to lock timeout')
        holder.finish('ROLLBACK;\n')
        assert db.dump('relation_lock') == before
        db.case('independent relation-lock contention hits package 5-second timeout; dump unchanged')
        # Interleave a second creator after the REAL preflight and before the
        # REAL plain CREATE. No edited production/operator file is published.
        db.clone('namespace_race')
        before = db.dump('namespace_race')
        prefix,suffix = operator.split('-- Reserve the signature',1)
        session = Session(db,'namespace_race','namespace-race')
        session.barrier(prefix)
        db.sql('namespace_race',"CREATE FUNCTION public.valid_star_thresholds(v float8[]) RETURNS boolean LANGUAGE sql AS 'SELECT true';")
        output,rc = session.finish('-- Reserve the signature'+suffix)
        assert rc == 3 and 'already exists with same argument types' in output
        assert db.sql('namespace_race',"SELECT prosrc='SELECT true' FROM pg_proc WHERE oid='public.valid_star_thresholds(float8[])'::regprocedure;").strip() == 't'
        db.sql('namespace_race','DROP FUNCTION public.valid_star_thresholds(float8[]);')
        assert db.dump('namespace_race') == before
        db.case('concurrent exact-signature creation after absence check survives unmodified; plain CREATE refuses, no OR REPLACE hijack')
        db.clone('stub_reserved')
        prefix,suffix = operator.split('-- BEGIN CANONICAL MIGRATION',1)
        session = Session(db,'stub_reserved','stub-reserved')
        session.barrier(prefix)
        db.sql('stub_reserved',"SET lock_timeout='200ms'; CREATE FUNCTION public.valid_star_thresholds(v float8[]) RETURNS boolean LANGUAGE sql AS 'SELECT true';",expected='canceling statement due to lock timeout')
        output,rc = session.finish('-- BEGIN CANONICAL MIGRATION'+suffix)
        assert rc == 0 and RECEIPT in output
        assert db.sql('stub_reserved',"SELECT public.valid_star_thresholds(NULL) AND NOT public.valid_star_thresholds(ARRAY[1,1,2,3,4]::float8[]);").strip() == 't'
        db.case('uncommitted plain-CREATE stub reserves exact signature; second creator cannot commit through it; canonical body replaces own stub only')
        db.clone('receipt_collision')
        digest = db.reject_unchanged('receipt_collision','CREATE TEMP TABLE stars_operator_receipt(x int);\n'+operator,'receipt already exists; no blind rerun')
        db.case('same-session temporary receipt collision refuses, no persistent changes',dumpSha256=digest)
        db.clone('unknown_commit')
        committed = operator.split('-- Consume only our temporary metadata row',1)[0]
        db.sql('unknown_commit',committed)
        assert db.sql('unknown_commit',"SELECT EXISTS(SELECT FROM supabase_migrations.schema_migrations WHERE version='20261116120000') AND to_regprocedure('public.valid_star_thresholds(float8[])') IS NOT NULL;").strip() == 't'
        digest = db.reject_unchanged('unknown_commit',operator,'target object already exists; no blind rerun')
        db.case('commit without receipt retrieval is still applied; blind replay refuses without changing state',dumpSha256=digest)
        assert not git('status','--porcelain=v1')
    finally:
        db.stop()
        (OUT/'independent-pg-outcomes.json').write_text(json.dumps(db.results,indent=2)+'\n')
    print('EXECUTED PASS',len(db.results),'independent SQL case groups; no shared or production connection',flush=True)

if __name__ == '__main__':
    main()
