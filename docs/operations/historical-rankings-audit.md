# Historical input inventory: separate authorization required

No existing production operator/path is configured or verified. This document
is not authorization to run an inventory. Do not search for credentials, create
access, change privileges, or use the old rollout package. Issue #60 remains
blocked on scoped production inventory and owner review of legacy fidelity and
missing-input policy. An error for missing history is not an approved product
policy, and zero local fixture gaps prove nothing about production.

## Pinned artifact and private scope

The coordinator must request one separately authorized run of
`supabase/tools/audit_historical_rankings.sql`, pinned to the candidate commit
and SHA256 recorded in the repair handoff. Confirm both before use:

```sh
git rev-parse HEAD
sha256sum supabase/tools/audit_historical_rankings.sql
```

The owner must approve one squad and the expected existing authenticated caller
in a private authorization record. Use only the already authorized psql path.
The effective role must be `authenticated`, with a non-null matching `auth.uid()`
and existing squad membership. The audit rejects superuser/BYPASSRLS sessions,
including a privileged session behind `SET ROLE authenticated`, table ownership
(including inherited ownership), disabled RLS, and a missing/wrong scope.
A postgres/service-role SQL Editor connection is not this lane. If no suitable
existing path exists, stop. Do not manufacture one.

On that existing connection only, pass the two approved private UUIDs:

```sh
psql -X --set=ON_ERROR_STOP=1 \
  --set=authorized_squad_id='<approved-squad-uuid>' \
  --set=expected_caller_id='<approved-caller-uuid>' \
  --file=supabase/tools/audit_historical_rankings.sql
```

This command does not establish a connection or change its role/JWT. Use the
existing approved connection mechanism. Do not put connection secrets in shell
arguments or logs. Keep UUIDs in the private authorization record, not public
issue/PR output. Do not enable SQL echo or publish the invocation with UUIDs.

## What the audit does

The exact script uses a READ ONLY transaction, a 30-second statement timeout,
and ROLLBACK. It creates no functions, grants, roles, or schema objects. It
changes no JWTs or data. Every aggregate joins through the approved squad's
matches or tournaments and their drafts. The output contains counts only:

- Guard markers (numeric ones), visible/scored matches, explicit substitute
  options, and matches with stored input-vector objects.
- Match history entries, entries with deltas, and null inputs.
- Roster rows partitioned into match input, tournament-only input, and no input.
  New `score_meta.draft_rankings` vectors are authoritative; a partial new vector
  does not borrow older history. Legacy match inputs take precedence per player
  over tournament creation inputs (`match_id IS NULL`).
- Both match and tournament proposals, score objects, explicit options, and
  objects with numeric inputs for every listed player. Metadata rows are excluded.

`to_jsonb` checks work before the new match option column exists; no deployment
is required. Object counts do not establish complete inputs. Numeric-input
counts do not prove that an old snapshot equals an earlier generator input or
recover an absent explicit legacy substitute choice. Visibility is one squad
under the existing caller's RLS, not a global inventory.

A scope refusal prints STOP, rolls back, then issues a fixed division-by-zero
SELECT to give portable psql exit code 3. This is intentional: psql `\quit 3`
does not reliably return a nonzero code. Other SQL errors/timeouts stop execution;
disconnection rolls back the read-only transaction. Do not retry with a broader
role or scope. No successful counts may be published from a failed run.

## Return to the coordinator

Return the approved commit/hash, UTC run time, exit code, guard markers, counts
with column names, and ROLLBACK confirmation. Describe the authorized scope and
nonprivileged role category in words. Return errors without credentials or UUIDs.
Stop on guard refusal, timeout, schema mismatch, or unexpected raw output. Do not
repair or backfill anything. The coordinator and owner decide the next legacy
policy only after reviewing this inventory and remaining fidelity limits.

## Disposable-local proof

```sh
python3 supabase/tools/test_historical_rankings_audit.py \
  --pg-bin /path/to/postgresql/16/bin --proof-dir /absolute/new/private/directory
```

The runner removes ambient `PG*` settings, uses only its own private Unix socket,
loads `local_auth.sql` and canonical migrations in a fresh disposable cluster,
and tests both predecessor and current schemas. Fixture setup changes roles and
inserts synthetic data only locally; none of this setup is in the operator
artifact. It tests two RLS-visible squads plus foreign data, exact counts, wrong
and absent caller/scope, unsuitable role, privileged session, BYPASSRLS,
ownership, disabled RLS, and partial metadata. It then runs the repository SQL
regressions and stops its own server. It never imports or executes the rollout
package. The local packaged PostgreSQL lacks `libLLVM-17.so.1`; this runner sets
`jit=off` only on its disposable server. It does not change production settings.
