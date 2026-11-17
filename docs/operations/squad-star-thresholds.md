# Stars schema: one reviewed SQL Editor operation

This package is preparation, not permission to run it. The coordinator must first
accept the configured candidate artifact and obtain independent SQL/security
review plus local PostgreSQL proof for the exact published package hash. Owner
feature and conditional rollout approval already exists; it does not replace
these technical gates. The worker does not have administrator access.

## Operator action, only after the coordinator says the gates passed

1. Open the coordinator's exact reviewed **Raw**
   [`squad_star_thresholds_operator.sql`](../../supabase/tools/squad_star_thresholds_operator.sql).
   Use the reviewed delivery commit and SHA256, not the application branch or
   an edited copy. Do not concatenate migration files.
2. In the correct Supabase project, open **SQL Editor → New query** in the existing
   administrator session. Paste the **whole file** and execute it **once**.
   Do not send anyone a password, token, connection string or dashboard image.
3. Report absence of errors for the **whole execution**, acknowledgement of
   `COMMIT`, and the nine booleans below. Do not return user rows, IDs or URLs.

The operation adds only the optional `squads.star_thresholds` column, its pure
validator and its constraint. It does not set numeric defaults, backfill data,
change policies/grants, apply earlier migrations or repair history. The exact
canonical migration is `20261116120000_add_squad_star_thresholds.sql`, SHA256
`02cfb0ff0c766c77e76c75be115a981960a32db551b3cb5733f623ff61b4f35a`.
The separate delivery commit does not change the accepted application source.

## Expected receipt

All flags must be `true`, except `migration_history_present` can be `false`.
A row without a confirmed error-free execution and COMMIT is not success.

| Flag | What it proves in this transaction |
| --- | --- |
| `canonical_source_sha256_matches` | Embedded source identity matches the pinned hash. External reviewed file hash still authenticates the complete package. |
| `column_contract` | Nullable `double precision[]`, no default/generated value/column grant. |
| `validator_contract` | Exact canonical SQL body, immutable boolean invoker, empty search path, expected signature and default public execution. |
| `constraint_contract` | Validated canonical check depends on that exact validator object and column. |
| `owner_update_rls_contract` | Expected direct squads policies, RLS and existing API role/permission checks pass. |
| `policies_acl_unchanged` | Squads ownership, policies, table ACL and previous column ACLs are unchanged. |
| `migration_history_present` | A compatible history table existed; `false` preserves absence, not an invented baseline. |
| `migration_record_exact_or_absent` | Exactly this version was inserted with exact optional name/statements, or no history exists. |
| `prior_history_unchanged` | Previous history rows are unchanged. No older version was added or repaired. |

This does **not** prove all database security, indirect RPC access, hosted JWT
behavior, migration baseline consistency, PostgREST cache refresh or application
readiness. `NOTIFY pgrst, 'reload schema'` is delivered only on successful commit;
it is not a live API test. The coordinator checks the actual API separately.
No production release follows from these flags alone.

## Refusal and failure handling

- The package requires the reviewed ordinary squads table and exact four existing
  policies, non-bypass API roles, existing SELECT/UPDATE permissions and an
  administrator with the required existing DDL/history rights. It adds no rights.
- Any target column, named constraint, validator overload or migration version
  already present causes refusal. The operator lock is immediate; relation locks
  time out after 5 seconds, each SQL statement after 60 seconds. A plain CREATE
  reserves the absent function signature before canonical CREATE OR REPLACE,
  so a racing creation cannot be silently replaced. No stub can commit unless
  exact canonical verification succeeds.
- History, if present, must be an ordinary persistent table with a single
  nondeferrable version primary key and no other indexes/constraints, triggers,
  rules, inheritance or RLS. Live columns must be `version text` and optionally
  `name text` / `statements text[]`, with no defaults, identity or generated
  values. Other shapes or missing privileges fail. The package never creates
  history. An absent table, including an absent history schema, is preserved.
- The new pure validator follows PostgreSQL's default public EXECUTE model.
  Authenticated and anonymous execution are checked, not revoked. Ambient
  function ACLs are preserved across the guarded canonical replacement.
  If default privileges prevent expected execution, the transaction fails;
  the package does not add grants to make it pass. This is not the privileged
  draft-acceptance RPC and must not use that RPC's anonymous-execution rules.
- On **any error**, stop. If the session is still in a transaction, run only
  `ROLLBACK;`. Send the sanitized error category for review. Do not run fragments,
  change conditions to `IF NOT EXISTS`, replace objects, delete history or retry.
- If the response or connection is lost, the commit outcome is unknown. Do not
  rerun. The coordinator must inspect exact current metadata/history first.
  `ROLLBACK` cannot undo a successful commit. There is no destructive automatic
  post-commit rollback. A failed API check is not permission to run DDL again.

All permanent changes and the conditional new history row are in one transaction.
Temporary helper tables hold only catalog snapshots and booleans; the state is
removed at commit and the post-commit receipt row is consumed when returned.
The empty receipt table lasts only for that SQL session.

**Do not use `supabase db push`.** Neither an absent history table nor inserting
one new version proves the older baseline. A separate baseline audit is still
required before any bulk push. Do not apply the unrelated `20261111120000`
SQL Editor package for this feature.

## Local reproduction, not hosted proof

Generator and tests use only the Python standard library:

```sh
python3 supabase/tools/generate_stars_rollout.py --check
python3 -m unittest discover -s supabase/tools -p test_stars_rollout.py -v
python3 supabase/tools/prove_stars_rollout.py \
  --pg-bin /path/to/postgresql/16/bin \
  --proof-dir /absolute/new/private/proof \
  --socket-dir /absolute/new/short/private/socket
```

Use the normal immediate nonblocking validation lock and memory gate before each
heavy fixture invocation. The proof starts only its own PostgreSQL16 server,
disables TCP, clears ambient libpq connection settings, uses the existing local
auth fixture and canonical predecessors, and stops its server in `finally`.
All users and rows are synthetic. It tests compatible/absent history, collisions,
wrong shapes/permissions, metadata corruption, late failure with full dump
comparisons, unchanged role behavior and threshold boundary vectors. This is not
Supabase Auth, PostgREST, a production connection or a claim that the operator
step has been applied.
