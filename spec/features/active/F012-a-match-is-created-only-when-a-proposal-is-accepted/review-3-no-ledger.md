# Independent ledger-free acceptance review

PASS 3eba467180199e0fd4bd4214a44332b49a1bf33e against a709cd0. No blocking defect found. The accepted duplicate-match retry policy was not reopened. The earlier accepted operator review was read as the settled boundary, not reused as current execution evidence.

## Limits and notes

UNVERIFIED: hosted SQL Editor, API/cache, JWT/RLS transport, deployment, APK/native/Flutter/device behavior. None was attempted. No database lane was repeated. `confirm_match_draft` has no tracked definition or caller at either the candidate or base; compatibility with a separately hosted definition cannot be established from this repository. The candidate does not drop any existing table or function. Repository references to the removed ledger are only absence assertions, the legacy-object preflight refusal, its negative fixture, and operator documentation of that refusal.

PROVEN wording note: task.md says “five plus history”; the implementation returns five total: four function/security flags plus history presence. Removing the prior ledger flag accounts for this difference. `ledger_rls_enabled` survives only as a negative assertion in `supabase/tools/test_draft_rollout.py:23`, not as a readiness flag. No missing sixth flag or runtime dependency was found.

PROVEN board drift: `spec/build.md:17` still directs the operator to a8328b3, not this candidate. Coordinator must reconcile that instruction before rollout. No board/ticket edit was made; `app/` and `spec/` have zero delta. Evidence: /home/agents/dev/pickteams/.limen/proof/F012/no-ledger/review-1/final-status.log.

## Source conclusions

The canonical migration removes ledger DDL/policies/grant, its row variable, request-id validation/advisory lock/lookup/early return, and final ledger insert. Independent byte comparison proves every other function byte is unchanged. The four named parameters and UUID return remain compatible with the unchanged client RPC call. `p_request_id` appears only in the comment and signature, so null is accepted too.

Owner/Admin authorization with 42501, complete-team/proposal validation, identical-player checks, squad membership, new inserts, redraw row locking and score refusal, team upserts, roster rebuild, ranking-history conflict handling, probability refresh, draft/payload upserts, SECURITY INVOKER/search_path, and public/anonymous revocation remain unchanged. The updated SQL tests preserve late-write rollback and role/validation controls and add repeated redraw, duplicate new-match, changed-payload request reuse, and null-request assertions.

The executable canonical span and history literal both equal the 6,157 source bytes. Canonical SHA256 is 1a16e196b81bea88ab114416c3c90f92de968ac2a5b8e90ab3b6a31bc122c2dd; artifact SHA256 is 5a4a9d6b2c162965482838885c93de20a177166431465d76a793972b9b2e5d69. Generator output is deterministic and stale checks reject without writes. Polish operator text correctly separates retrying acceptance from retrying deployment, documents duplicate deletion with Usuń mecz, and does not claim deduplication or hosted readiness.

## Commands actually run

- `git rev-parse HEAD`, `git status --porcelain=v1`, `git diff --stat a709cd0 HEAD`, `git diff --name-status a709cd0 HEAD`, `git diff a709cd0 HEAD -- app/`, `git diff --check a709cd0 HEAD`: exact candidate, clean tree, eight SQL/tools/docs files, no app delta, no whitespace errors. Evidence: /home/agents/dev/pickteams/.limen/proof/F012/no-ledger/review-1/source-checks.log.
- `PYTHONDONTWRITEBYTECODE=1 python3 supabase/tools/generate_draft_rollout.py --check`: exit 0. Evidence: /home/agents/dev/pickteams/.limen/proof/F012/no-ledger/review-1/generator.log.
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s supabase/tools -v`: exit 0; four tests pass. The stale-artifact diagnostic is the expected negative control. Evidence: /home/agents/dev/pickteams/.limen/proof/F012/no-ledger/review-1/unit.log.
- `PYTHONDONTWRITEBYTECODE=1 python3 /home/agents/dev/pickteams/.limen/proof/F012/no-ledger/review-1/check_review.py`: exit 0. It checks preserved function bytes, deterministic output, both embedded canonical copies, SHA256, AST parsing of all three Python tools, all 33 retained artifact copies, and 15 retained before/after dump pairs. Only randomized pg_dump restriction markers are omitted. Evidence: /home/agents/dev/pickteams/.limen/proof/F012/no-ledger/review-1/independent-checks.log.
- `git grep` for ledger/readiness names, `confirm_match_draft` at HEAD and a709cd0, retry/idempotency claims, and match deletion: no stale runtime dependency; absent confirm RPC at both revisions; existing delete action found. Evidence: /home/agents/dev/pickteams/.limen/proof/F012/no-ledger/review-1/references.log and /home/agents/dev/pickteams/.limen/proof/F012/no-ledger/review-1/contracts.log.
- Final `git rev-parse HEAD`, `git status --porcelain=v1`, `git diff --exit-code a709cd0 HEAD -- app/ spec/`, and board-reference grep: same SHA, clean tree, diff exit 0; stale board instruction found. Evidence: /home/agents/dev/pickteams/.limen/proof/F012/no-ledger/review-1/final-status.log.

## Producer evidence inspected, not rerun

Read the producer README, source/generator/unit/candidate/proof/command/exit/final-status/cleanup records and numbered PG logs. Its committed candidate precedes its private PostgreSQL 16.15 run. All eight changed files, local_auth fixture and 24 predecessor migrations match this checkout byte-for-byte. Logs show five history variants commit; absent history reports false only for history. The legacy-table refusal, version/overload conflicts, late failures, incompatible/suppressed/view history and restored anonymous grant fail with exit 3. Fourteen failure dump pairs match. The RPC test exits 0, reaches its duplicate/null-ID assertions and ROLLBACK, and its fifteenth dump pair matches. Shutdown succeeds. The nonfatal /dev/null password-file warning is visible.

Selected raw evidence and every independent byte comparison are retained at /home/agents/dev/pickteams/.limen/proof/F012/no-ledger/review-1/independent-checks.log. Additional inspected successful variant logs were producer pg/042, pg/067, pg/094 and pg/100: each reaches COMMIT with four true function flags and the expected history flag.

Only reads, Git inspection, Python standard-library checks, and review evidence/required job-note writes occurred. No install, DB command, network/hosted request, Flutter/JS/native/device check, source edit, keeper, landing, push or deploy occurred.
