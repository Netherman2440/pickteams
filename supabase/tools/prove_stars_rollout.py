#!/usr/bin/env python3
"""Stars package proof on a NEW private PostgreSQL16 cluster. No hosted access."""
import argparse
import hashlib
import json
import os
from pathlib import Path

import generate_stars_rollout as stars
from prove_draft_rollout import Proof


class StarsProof(Proof):
    def __init__(self, pg_bin, directory, socket):
        super().__init__(pg_bin, directory)
        self.socket.rmdir()  # Empty directory just created by the shared harness.
        self.socket = socket.resolve()
        if len(str(self.socket / '.s.PGSQL.56123').encode()) >= 108:
            raise ValueError('Private socket path is too long')
        self.socket.mkdir(mode=0o700)
        self.env['PGHOST'] = str(self.socket)

    def ready(self, name, artifact, history):
        rows_query = "SELECT md5(jsonb_agg(to_jsonb(s)-'star_thresholds' ORDER BY squad_id)::text) FROM public.squads s;"
        before, _ = self.sql(name, rows_query)
        output, _ = self.sql(name, artifact)
        receipt = '|'.join(['t'] * 6 + ['t' if history else 'f', 't', 't'])
        assert output.splitlines().count(receipt) == 1, output
        assert output.index('COMMIT') < output.index(receipt), output
        after, _ = self.sql(name, rows_query)
        assert before == after, 'Existing squads changed beyond the new nullable column'
        output, _ = self.sql(name,
            "SELECT NOT EXISTS (SELECT FROM public.squads WHERE star_thresholds IS NOT NULL) "
            "AND has_function_privilege('authenticated','public.valid_star_thresholds(double precision[])','EXECUTE') "
            "AND has_function_privilege('anon','public.valid_star_thresholds(double precision[])','EXECUTE');")
        assert output.strip() == 't', output
        if not history:
            output, _ = self.sql(name, "SELECT to_regnamespace('supabase_migrations') IS NULL;")
            assert output.strip() == 't', output
        else:
            output, _ = self.sql(name,
                "SELECT count(*)=2 AND count(*) FILTER (WHERE version='20251201080000')=1 "
                "AND count(*) FILTER (WHERE version='20261116120000')=1 "
                "FROM supabase_migrations.schema_migrations;")
            assert output.strip() == 't', output
        self.passed(f'{name}: COMMIT then exact nine-boolean receipt; no backfill or extra history')

    def vectors(self):
        # Reuse the existing role checks and add all-position constraint writes.
        original = (stars.ROOT / 'supabase/tests/squad_star_thresholds_test.sql').read_text()
        valid = ['NULL', 'ARRAY[-10,0,1,2,3]::float8[]', 'ARRAY[49.8,56.1,58,59.8,62.9]::float8[]',
                 "ARRAY['-1.7976931348623157e308'::float8,-1,0,1,'1.7976931348623157e308'::float8]"]
        invalid = ['ARRAY[]::float8[]', 'ARRAY[1,2,3,4]::float8[]', 'ARRAY[1,2,3,4,5,6]::float8[]',
                   "'[0:4]={1,2,3,4,5}'::float8[]", "'{{1,2,3,4,5}}'::float8[]"]
        for value in ('NULL', "'NaN'::float8", "'Infinity'::float8", "'-Infinity'::float8"):
            for index in range(5):
                row = [str(i + 1) for i in range(5)]
                row[index] = value
                invalid.append('ARRAY[' + ','.join(row) + ']::float8[]')
        for index in range(4):
            row = [str(i + 1) for i in range(5)]
            row[index+1] = row[index]
            invalid.append('ARRAY[' + ','.join(row) + ']::float8[]')
        invalid.append('ARRAY[5,4,3,2,1]::float8[]')
        sql = 'RESET ROLE;\n'
        for value in valid:
            sql += f"UPDATE public.squads SET star_thresholds={value} WHERE name='Stars';\n"
        for value in invalid:
            sql += f"""DO $vector$ BEGIN
              ASSERT NOT public.valid_star_thresholds({value});
              BEGIN
                UPDATE public.squads SET star_thresholds={value} WHERE name='Stars';
                RAISE EXCEPTION 'Invalid vector accepted';
              EXCEPTION WHEN check_violation THEN NULL; END;
            END $vector$;\n"""
        assert original.count('rollback;') == 1
        before = self.snapshot('standard')
        self.sql('standard', original.replace('rollback;', sql + 'rollback;'))
        assert self.snapshot('standard') == before
        self.passed('owner writes; admin and guest cannot write; guest reads; all finite/shape/order/null vectors; full dump unchanged')
        return {'validConstraintWrites': len(valid), 'invalidFunctionAndConstraintVectors': len(invalid)}

    def history_privileges(self, artifact):
        self.clone('history_privileges','')
        self.sql('history_privileges','CREATE ROLE history_owner NOLOGIN; ALTER TABLE supabase_migrations.schema_migrations OWNER TO history_owner; CREATE ROLE schema_operator NOLOGIN; ALTER TABLE public.squads OWNER TO schema_operator; GRANT USAGE,CREATE ON SCHEMA public TO schema_operator; GRANT USAGE ON SCHEMA auth,supabase_migrations TO schema_operator;')
        self.reject_unchanged('history_privileges','SET ROLE schema_operator;\n'+artifact,'history privileges missing')

    def prove(self, case='all'):
        os.umask(0o077)
        source = stars.SOURCE.read_bytes()
        artifact = stars.generate(source)
        assert stars.OUTPUT.read_bytes() == artifact
        artifact = artifact.decode()
        version, _ = self.run('postgres', '--version')
        assert 'PostgreSQL) 16.' in version, version
        self.run('initdb','-D',self.cluster,'-U','operator_test','-A','trust',
                 '--no-locale','--encoding=UTF8','-L',self.bin.parents[3]/'share/postgresql/16')
        try:
            self.run('pg_ctl','-D',self.cluster,'-l',self.directory/'postgres.log',
                     '-o',f"-k {self.socket} -p 56123 -c listen_addresses='' -c shared_buffers=32MB -c max_connections=12",'-w','start')
            self.sql('postgres','CREATE DATABASE fixture;')
            self.sql('fixture',(stars.ROOT/'supabase/tests/fixtures/local_auth.sql').read_text())
            for path in sorted(stars.SOURCE.parent.glob('*.sql')):
                if path.name < stars.SOURCE.name:
                    self.sql('fixture',path.read_text())
            self.sql('fixture', "INSERT INTO auth.users(id,email) VALUES ('30000000-0000-0000-0000-000000000001','schema-sentinel@example.test'); INSERT INTO public.squads(squad_id,owner_id,name) VALUES ('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Schema sentinel');")
            self.passed('real canonical predecessors and existing local_auth fixture; pre-existing squad sentinel; no hosted connection')
            if case == 'existing-squads':
                self.clone('existing_squads', ', name text, statements text[]')
                self.ready('existing_squads', artifact, True)
                return
            if case == 'history-privileges':
                self.history_privileges(artifact)
                return
            variants = {'standard':', name text, statements text[]','version_only':'',
                        'name_only':', name text','statements_only':', statements text[]','absent':None}
            for name, columns in variants.items():
                self.clone(name,columns)
                self.ready(name,artifact,columns is not None)
                self.reject_unchanged(name,artifact,'target object already exists')
            collisions = {
                'column_collision': 'ALTER TABLE public.squads ADD COLUMN star_thresholds text;',
                'function_collision': "CREATE FUNCTION public.valid_star_thresholds(text) RETURNS boolean LANGUAGE sql AS 'SELECT true';",
                'signature_collision': "CREATE FUNCTION public.valid_star_thresholds(float8[]) RETURNS boolean LANGUAGE sql AS 'SELECT true';",
                'constraint_collision': 'ALTER TABLE public.squads ADD CONSTRAINT squads_star_thresholds_valid CHECK (true);',
            }
            for name, setup in collisions.items():
                self.clone(name,'')
                self.sql(name,setup)
                self.reject_unchanged(name,artifact,'target object already exists')
            self.clone('version_collision','')
            self.sql('version_collision',"INSERT INTO supabase_migrations.schema_migrations VALUES ('20261116120000');")
            self.reject_unchanged('version_collision',artifact,'migration version already recorded')
            bad_history = {
                'unknown_column': 'ALTER TABLE supabase_migrations.schema_migrations ADD COLUMN extra text;',
                'required_column': "ALTER TABLE supabase_migrations.schema_migrations ADD COLUMN extra text NOT NULL DEFAULT 'x';",
                'wrong_type': 'ALTER TABLE supabase_migrations.schema_migrations ALTER COLUMN version TYPE varchar(32);',
                'missing_pk': 'ALTER TABLE supabase_migrations.schema_migrations DROP CONSTRAINT schema_migrations_pkey;',
                'history_default': "ALTER TABLE supabase_migrations.schema_migrations ALTER COLUMN version SET DEFAULT 'x';",
                'extra_index': 'CREATE INDEX extra_history ON supabase_migrations.schema_migrations(version);',
            }
            for name, setup in bad_history.items():
                self.clone(name,'')
                self.sql(name,setup)
                self.reject_unchanged(name,artifact,'unsupported history shape')
            self.clone('history_view')
            self.sql('history_view',"CREATE SCHEMA supabase_migrations; CREATE VIEW supabase_migrations.schema_migrations AS SELECT 'old'::text AS version;")
            self.reject_unchanged('history_view',artifact,'unsupported history relation')
            self.clone('history_rls','')
            self.sql('history_rls','ALTER TABLE supabase_migrations.schema_migrations ENABLE ROW LEVEL SECURITY;')
            self.reject_unchanged('history_rls',artifact,'unsupported history relation')
            self.clone('history_trigger','')
            self.sql('history_trigger',"CREATE FUNCTION public.history_trigger() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END $$; CREATE TRIGGER reject BEFORE INSERT ON supabase_migrations.schema_migrations FOR EACH ROW EXECUTE FUNCTION public.history_trigger();")
            self.reject_unchanged('history_trigger',artifact,'unsupported history relation')
            for name, setup, error in [
                ('rls_disabled','ALTER TABLE public.squads DISABLE ROW LEVEL SECURITY;','unexpected squads RLS state'),
                ('rls_forced','ALTER TABLE public.squads FORCE ROW LEVEL SECURITY;','unexpected squads RLS state'),
                ('unknown_policy','CREATE POLICY unexpected ON public.squads FOR UPDATE USING (true);','unexpected squads policies'),
                ('missing_update','REVOKE UPDATE ON public.squads FROM authenticated;','expected existing API permissions missing'),
                ('nullable_owner','ALTER TABLE public.squads ALTER COLUMN owner_id DROP NOT NULL;','unexpected owner column'),
            ]:
                self.clone(name,'')
                self.sql(name,setup)
                self.reject_unchanged(name,artifact,error)
            self.clone('limited_operator','')
            self.sql('limited_operator','CREATE ROLE limited_operator NOLOGIN;')
            self.reject_unchanged('limited_operator','SET ROLE limited_operator;\n'+artifact,'existing administrator privileges required')
            self.history_privileges(artifact)
            self.clone('bad_defaults','')
            self.sql('bad_defaults','ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;')
            self.reject_unchanged('bad_defaults',artifact,'metadata verification failed')
            for name, columns in [('late_failure',', name text, statements text[]'),('late_absent',None)]:
                self.clone(name,columns)
                broken = artifact.replace("NOTIFY pgrst, 'reload schema';", "DO $fault$ BEGIN RAISE EXCEPTION 'deliberate late failure'; END $fault$;\nNOTIFY pgrst, 'reload schema';")
                self.reject_unchanged(name,broken,'deliberate late failure')
                self.ready(name,artifact,columns is not None)
            self.clone('wrong_validator','')
            broken = artifact.replace('returns boolean language sql immutable','returns boolean language sql immutable security definer',1)
            assert broken != artifact
            self.reject_unchanged('wrong_validator',broken,'metadata verification failed')
            self.clone('wrong_column','')
            broken = artifact.replace('add column star_thresholds double precision[] null;', 'add column star_thresholds double precision[] default array[1,2,3,4,5];',1)
            self.reject_unchanged('wrong_column',broken,'metadata verification failed')
            self.clone('changed_acl','')
            broken = artifact.replace('DO $verify$', 'GRANT UPDATE ON public.squads TO PUBLIC;\nDO $verify$',1)
            self.reject_unchanged('changed_acl',broken,'metadata verification failed')
            self.clone('changed_old_history',', name text, statements text[]')
            broken = artifact.replace('DO $verify$', "UPDATE supabase_migrations.schema_migrations SET name='changed' WHERE version='20251201080000';\nDO $verify$",1)
            self.reject_unchanged('changed_old_history',broken,'metadata verification failed')
            counts = self.vectors()
            # Global role changes are confined to this owned cluster; restore afterward.
            self.clone('bypass_role','')
            self.sql('bypass_role','ALTER ROLE authenticated BYPASSRLS;')
            try:
                self.reject_unchanged('bypass_role',artifact,'unexpected API role privileges')
            finally:
                self.sql('bypass_role','ALTER ROLE authenticated NOBYPASSRLS;')
            (self.directory/'identity.json').write_text(json.dumps({
                'canonicalSha256':hashlib.sha256(source).hexdigest(),
                'operatorSha256':hashlib.sha256(stars.OUTPUT.read_bytes()).hexdigest(),
                'postgresVersion':version.strip(), 'thresholdVectors':counts,
                'hostedOrCacheReadinessClaimed':False,
            },indent=2)+'\n')
        finally:
            if (self.cluster/'postmaster.pid').exists():
                self.run('pg_ctl','-D',self.cluster,'-m','fast','-w','stop')
            assert not (self.cluster/'postmaster.pid').exists()
            self.socket.rmdir()
            self.passed('owned PostgreSQL stopped; socket directory removed; no postmaster.pid')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin',type=Path,required=True)
    parser.add_argument('--proof-dir',type=Path,required=True)
    parser.add_argument('--socket-dir',type=Path,required=True)
    parser.add_argument('--case',choices=('all','history-privileges','existing-squads'),default='all')
    args = parser.parse_args()
    StarsProof(args.pg_bin,args.proof_dir,args.socket_dir).prove(args.case)


if __name__ == '__main__':
    main()
