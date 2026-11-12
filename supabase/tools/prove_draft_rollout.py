#!/usr/bin/env python3
"""Prove only the operator wrapper on a NEW private PostgreSQL 16 cluster.

Usage: python3 supabase/tools/prove_draft_rollout.py --pg-bin /path/to/bin \
  --proof-dir /absolute/new/directory
No network, hosted access, RPC invocation, or production fixture is used.
"""

import argparse
import hashlib
import os
from pathlib import Path
import subprocess

import generate_draft_rollout as rollout


class Proof:
    def __init__(self, pg_bin: Path, directory: Path):
        self.bin = pg_bin.resolve()
        self.directory = directory.resolve()
        self.directory.mkdir(parents=True, exist_ok=False, mode=0o700)
        self.socket = self.directory / "socket"
        self.socket.mkdir(mode=0o700)
        self.cluster = self.directory / "cluster"
        self.env = dict({key: value for key, value in os.environ.items()
                         if not key.startswith("PG")},
                        PGHOST=str(self.socket), PGPORT="56123",
                        PGUSER="operator_test", PGDATABASE="postgres",
                        PGCONNECT_TIMEOUT="5", PGPASSFILE="/dev/null")
        # No ambient libpq service, password, hostaddr, or connection settings.
        self.counter = 0
        self.summary = self.directory / "checks.log"

    def run(self, tool, *args, sql=None, success=True):
        self.counter += 1
        result = subprocess.run([str(self.bin / tool), *map(str, args)],
                                input=sql, text=True, capture_output=True,
                                env=self.env, timeout=120)
        log = self.directory / f"{self.counter:03d}-{tool}.log"
        log.write_text(result.stdout + result.stderr + f"\nexit={result.returncode}\n")
        if (result.returncode == 0) != success:
            raise AssertionError(f"Unexpected exit {result.returncode}: {log}")
        return result.stdout, result.stderr

    def sql(self, database, sql, success=True):
        return self.run("psql", "-X", "-v", "ON_ERROR_STOP=1", "-A", "-t",
                        "-d", database, sql=sql, success=success)

    def passed(self, name):
        with self.summary.open("a") as log:
            log.write(f"PASS {name}\n")
        print(f"PASS {name}", flush=True)

    def snapshot(self, database):
        output, _ = self.run("pg_dump", "--no-owner", "-d", database)
        # New pg_dump releases randomize only these client safety markers.
        stable = "\n".join(line for line in output.splitlines()
                           if not line.startswith(("\\restrict ", "\\unrestrict ")))
        return hashlib.sha256(stable.encode()).hexdigest()

    def clone(self, name, history=None):
        self.sql("postgres", f"CREATE DATABASE {name} TEMPLATE fixture;")
        if history is not None:
            self.sql(name, "CREATE SCHEMA supabase_migrations; "
                     "CREATE TABLE supabase_migrations.schema_migrations "
                     f"(version text PRIMARY KEY{history}); "
                     "INSERT INTO supabase_migrations.schema_migrations(version) "
                     "VALUES ('20251201080000');")

    def reject_unchanged(self, name, artifact, expected_error):
        before = self.snapshot(name)
        _, error = self.sql(name, artifact, success=False)
        assert expected_error in error, error
        assert self.snapshot(name) == before, f"Partial changes in {name}"
        self.passed(f"{name}: expected failure, full database dump unchanged")

    def ready(self, name, artifact, history):
        output, _ = self.sql(name, artifact)
        expected = "t|t|t|t|t|" + ("t" if history else "f")
        assert output.strip().splitlines()[-1] == expected, output
        assert "COMMIT" in output, output
        # No acceptance RPC is invoked. All business tables remain empty.
        output, _ = self.sql(name, "SELECT (SELECT count(*) FROM public.matches) = 0 "
                             "AND (SELECT count(*) FROM public.match_draft_acceptances) = 0;")
        assert output.strip() == "t", output
        self.passed(f"{name}: committed, six readiness booleans, no match/ledger rows")

    def check_history(self, name, statements=False, named=False):
        source = rollout.SOURCE.read_text()
        query = ("SELECT count(*) = 2 AND count(*) FILTER (WHERE version = "
                 f"'{rollout.VERSION}') = 1 AND count(*) FILTER (WHERE version = "
                 "'20251201080000') = 1 FROM supabase_migrations.schema_migrations;")
        output, _ = self.sql(name, query)
        assert output.strip() == "t", output
        if statements:
            output, _ = self.sql(name,
                "SELECT statements = ARRAY[$expected$" + source + "$expected$]::text[] "
                "FROM supabase_migrations.schema_migrations "
                f"WHERE version = '{rollout.VERSION}';")
            assert output.strip() == "t", output
        if named:
            output, _ = self.sql(name,
                f"SELECT name = '{rollout.NAME}' FROM supabase_migrations.schema_migrations "
                f"WHERE version = '{rollout.VERSION}';")
            assert output.strip() == "t", output
        self.passed(f"{name}: one new version, old history retained, optional fields exact")

    def prove(self):
        version, _ = self.run("postgres", "--version")
        assert "PostgreSQL) 16." in version, version
        self.run("initdb", "-D", self.cluster, "-U", "operator_test", "-A", "trust",
                 "--no-locale", "--encoding=UTF8")
        try:
            self.run("pg_ctl", "-D", self.cluster, "-l", self.directory / "postgres.log",
                     "-o", f"-k {self.socket} -p 56123 -c listen_addresses='' "
                     "-c shared_buffers=32MB -c max_connections=12", "-w", "start")
            self.sql("postgres", "CREATE DATABASE fixture;")
            self.sql("fixture", (rollout.ROOT / "supabase/tests/fixtures/local_auth.sql").read_text())
            for path in sorted(rollout.SOURCE.parent.glob("*.sql")):
                if path.name < rollout.SOURCE.name:
                    self.sql("fixture", path.read_text())
            self.passed("fresh local_auth fixture and all predecessor canonical migrations")
            artifact = rollout.OUTPUT.read_text()
            assert rollout.OUTPUT.read_bytes() == rollout.generate(rollout.SOURCE.read_bytes())
            variants = {
                "standard": ", statements text[], name text",
                "version_only": "",
                "name_only": ", name text",
                "statements_only": ", statements text[]",
                "absent": None,
            }
            for name, columns in variants.items():
                self.clone(name, columns)
                self.ready(name, artifact, columns is not None)
                if columns is not None:
                    self.check_history(name, "statements" in columns, "name" in columns)
                else:
                    output, _ = self.sql(name, "SELECT to_regnamespace('supabase_migrations') IS NULL;")
                    assert output.strip() == "t", output
                    self.passed("absent: no invented history schema or baseline")
                self.reject_unchanged(name, artifact, "Draft acceptance objects already exist")

            self.clone("history_conflict", ", statements text[], name text")
            self.sql("history_conflict", "INSERT INTO supabase_migrations.schema_migrations "
                     f"VALUES ('{rollout.VERSION}', ARRAY['different source'], 'other');")
            self.reject_unchanged("history_conflict", artifact, "Migration version already recorded")

            self.clone("object_conflict")
            self.sql("object_conflict", "CREATE FUNCTION public.accept_match_draft(text) "
                     "RETURNS text LANGUAGE sql AS 'SELECT $1';")
            self.reject_unchanged("object_conflict", artifact, "Draft acceptance objects already exist")

            for name, columns in (("late_error", ", statements text[], name text"),
                                  ("late_error_absent", None)):
                self.clone(name, columns)
                injected = artifact.replace("NOTIFY pgrst, 'reload schema';",
                    "DO $injected$ BEGIN RAISE EXCEPTION 'deliberate late failure'; END $injected$;\n"
                    "NOTIFY pgrst, 'reload schema';")
                self.reject_unchanged(name, injected, "deliberate late failure")
                self.ready(name, artifact, columns is not None)
                self.passed(f"{name}: clean retry after rolled-back failure")

            self.clone("history_shape", ", required_unknown text")
            self.sql("history_shape", "UPDATE supabase_migrations.schema_migrations "
                     "SET required_unknown = 'sentinel'; ALTER TABLE "
                     "supabase_migrations.schema_migrations ALTER COLUMN required_unknown SET NOT NULL;")
            self.reject_unchanged("history_shape", artifact, 'null value in column "required_unknown"')

            self.clone("history_suppressed", "")
            self.sql("history_suppressed", "CREATE FUNCTION public.suppress_history() "
                     "RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END $$; "
                     "CREATE TRIGGER suppress_history BEFORE INSERT ON "
                     "supabase_migrations.schema_migrations FOR EACH ROW "
                     "EXECUTE FUNCTION public.suppress_history();")
            self.reject_unchanged("history_suppressed", artifact, "Migration history insert not retained")

            self.clone("history_view")
            self.sql("history_view", "CREATE SCHEMA supabase_migrations; "
                     "CREATE VIEW supabase_migrations.schema_migrations AS SELECT 'old'::text AS version;")
            self.reject_unchanged("history_view", artifact, "Unsupported migration history relation")

            self.clone("security_failure", ", statements text[], name text")
            weakened = artifact.replace("DO $verify$", "GRANT EXECUTE ON FUNCTION "
                "public.accept_match_draft(uuid, uuid, uuid, jsonb) TO anon;\nDO $verify$", 1)
            self.reject_unchanged("security_failure", weakened, "Draft acceptance metadata checks failed")
            self.passed("all wrapper checks complete; no hosted/cache/JWT assertion")
        finally:
            if (self.cluster / "postmaster.pid").exists():
                self.run("pg_ctl", "-D", self.cluster, "-m", "fast", "-w", "stop")
            assert not (self.cluster / "postmaster.pid").exists()
            self.passed("owned PostgreSQL stopped; no postmaster.pid")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg-bin", type=Path, required=True)
    parser.add_argument("--proof-dir", type=Path, required=True)
    args = parser.parse_args()
    Proof(args.pg_bin, args.proof_dir).prove()


if __name__ == "__main__":
    main()
