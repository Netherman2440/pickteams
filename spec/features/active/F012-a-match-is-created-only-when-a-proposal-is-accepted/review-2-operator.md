# Independent operator-package review

PASS 3deade38afb2070275afb3c38f30a110e77450b2 against f8d2b5f. No proven blocking defect found. This verdict covers five added deployment files, not production execution or APK publication.

## Independently executed checks

All ran against the exact candidate in the clean detached review worktree. No candidate file was edited.

- `git rev-parse HEAD`, `git status --porcelain=v1`, `git diff --name-status f8d2b5f HEAD`, `git show -s --format='%H %cI' HEAD`: exact SHA, clean tree, five additions, commit time 2026-11-12T00:12:28Z. See `source-checks.log`.
- `git diff --exit-code f8d2b5f HEAD -- supabase/migrations`: exit 0. Canonical migrations unchanged.
- `git diff --check f8d2b5f HEAD`: exit 0.
- `PYTHONDONTWRITEBYTECODE=1 python3 supabase/tools/generate_draft_rollout.py --check`: exit 0 (`generator.log`).
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s supabase/tools -v`: exit 0, four tests pass (`unit.log`). The printed stale-artifact diagnostic belongs to the expected negative test. Tests cover delimiter rejection, invalid UTF-8, byte preservation, and stale checks without writes.
- `PYTHONDONTWRITEBYTECODE=1 python3 /home/agents/dev/pickteams/.limen/proof/F012/operator-rollout/review-1/check_review.py`: exit 0 (`independent-checks.log`). Confirms canonical length 8,133 and SHA256 c1e9075286e1aed50ed7c450d1a2ba7bb81909df98d60323215f6dcec1e2a887; both executable and history copies match byte-for-byte. All six supplied artifact copies equal this candidate. Three Python files parse with `ast.parse`. Transaction order and lock/timeout declarations match. All 13 retained before/after dump pairs compare equal after removing only randomized pg_dump restriction-marker lines. It also confirms 24 predecessor migrations and the local_auth fixture, and records their hashes.
- Final `git status --porcelain=v1` and `git rev-parse HEAD`: clean, same SHA (`final-status.log`).

Only file reads, Git inspection, Python standard-library checks, and evidence/note writes were performed. No install, database tool, live request, RPC invocation, credential lookup, Flutter/JS/native lane, push, hosting, or source/spec/board edit occurred.

## Source and supplied-proof review

Read all five added files. The wrapper starts one transaction before preflight, uses transaction-scoped advisory locking and an exclusive history-table lock, and sets local lock/statement timeouts. It refuses any existing overload, ledger relation, recorded version, or unsupported history relation. History insertion handles optional name/statements columns, checks affected rows and version count, and does not create a missing baseline. Five non-null readiness flags guard before NOTIFY/COMMIT; the sixth reports history presence afterward. No top-level business-data or Auth-setting writes occur; the unchanged RPC body is defined, not called. PostgreSQL notification delivery remains conditional on commit.

The helper strips ambient PG settings, creates a new private directory/cluster/socket, disables TCP listening, and addresses startup/shutdown to that owned cluster. No existing service is selected. The operator procedure requires the whole approved Raw artifact, stops on errors, distinguishes unknown commit results from known rollback, forbids blind retries/history deletion, and states that post-COMMIT ROLLBACK cannot undo deployment.

Inspected supplied proof under `/home/agents/dev/pickteams/.limen/proof/F012/operator-rollout/3deade3/`: README, source-checks, unit, postgres-proof, postgres-proof.exit, artifact-equality, cleanup, and evidence-index logs. Inspected command logs `pg/032-psql.log`, `067`, `077`, `082`, `087`, `089`, `093`, `101`, `107`, `112`, `117`, and `119-pg_ctl.log`. Successful logs show NOTIFY, COMMIT, and the expected six booleans. Expected failures show preflight refusals, late errors after DDL/history, unknown history columns, suppressed inserts, unsupported view history, and restored anonymous privilege. These failures exit 3; the complete producer lane exits 0. Independent retained-dump comparisons corroborate rollback rather than merely trusting summary flags. Supplied evidence covers all five history variants and their repeats. The nonfatal PGPASSFILE=/dev/null warning is present, not hidden. Shutdown succeeds and the cluster/socket/extracted runtime are absent.

The earlier RPC-design review at `/home/agents/dev/pickteams/.limen/proof/F012/review-1/README.md` was read for the settled boundary only. Its older-commit transport tests are not current wrapper execution evidence. No settled function design was reopened.

## Limits and transplant dependencies

UNVERIFIED here: actual SQL Editor execution/result rendering; hosted schema, history, grants, cache, notification receipt, JWT/GoTrue/RLS request behavior; real RPC acceptance; UI/native/release acceptance. No PostgreSQL lane was repeated. Supplied PostgreSQL 16.15 proof uses a lightweight auth fixture, not full Supabase. The reported anonymous GET 404/PGRST202 is an unresolved route signal, not database introspection; this reviewer made no hosted request.

PROVEN dependency note: `supabase/tools/prove_draft_rollout.py` needs `supabase/tests/fixtures/local_auth.sql` plus all 24 predecessor SQL migrations. A backend-only transplant of just five files and the canonical migration is not a complete standalone proof checkout unless those dependencies are already present. Preserve/copy them unchanged and verify hashes; `independent-checks.log` is the manifest. Generator/unit checks alone need no PostgreSQL or auth fixture. Review does not cover the future transplant: verify its copy hashes and generator result separately.

No production execution or publication approval is given. Keep the old APK published until the separate gates pass. Missing history still requires reconciliation before CLI push; an unknown commit result requires metadata/history inspection, not retry.
