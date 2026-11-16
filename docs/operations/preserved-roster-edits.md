# Atomic preserved roster edits (issue #60, unshipped)

Publication is on HOLD. This document does not authorize a migration, preview,
PR update, deployment, or production run. Legacy inventory, exact old-generation
fidelity, and missing-input policy remain unresolved. The separately reviewed
counts-only audit and its operator interface are unchanged.

## Contract

`20261116130000_atomic_preserved_roster.sql` adds
`update_preserved_match_roster(p_match_id, p_request_id, p_home, p_away,
p_rankings, p_expected_version)`. The Flutter team repository calls this RPC
only for matches with authoritative `score_meta.draft_rankings`. The ordinary
match/history writer remains on its existing path.

The RPC uses SECURITY INVOKER and the caller's existing table RLS. It also
requires an authenticated squad owner/admin. It adds no grants or access paths.
It locks the match row before validation. Score writes acquire that same row
lock, so a roster edit waiting behind a committed score must reject. Membership,
vector, receipt, and probability refresh either commit together or all roll back.
Team IDs, names/colors, explicit substitute options and unrelated metadata stay
intact. No tournament ranking-history events or current-ranking updates occur.

The command contains the complete intended roster and exact chosen inputs.
Retained players must keep their inputs. Newly added/re-added players use the
command's input, not a server re-read of today's score. Removal drops the input.
The client copies and freezes the command before submission. Duplicate in-flight
submissions share one operation. A failed response keeps that operation for
retry, including its UUID, version, memberships and addition inputs.

`score_meta._roster_operation` stores one bounded receipt and version, not an
unbounded operation ledger. An exact replay of the last committed command is a
no-op, including after score entry. Reusing its UUID with different inputs fails.
A different edit must match the current version. An old replay after a newer
edit conflicts instead of silently restoring obsolete membership or scores.
A retry does not automatically rebase a stale operation. This is not durable
client-side offline queuing or exactly-once replay of arbitrary old operations.

## Proof

`app/test/features/matches/application/atomic_roster_retry_test.dart` exercises
real use-case/repository HTTP serialization over a labeled synthetic transport:
rollback response, readable retry, two frozen additions with score drift,
duplicate submissions/caller-list mutation, lost response, and a score race.
It does not substitute for the SQL transaction proof.

Run `supabase/tools/test_atomic_roster.py` against a disposable PostgreSQL 16
package, under the required immediate nonblocking resource gate. It loads the
real migrations and `atomic_preserved_roster_test.sql`, including metadata-write
and partial-insert failures, owner/admin versus member/foreign/anon, replay and
version conflicts. It then uses two authenticated local SQL sessions to prove
that an edit waits on a score lock and rejects after score commit without a
partial roster/vector. The runner uses a private Unix socket and local jit=off,
strips ambient PG settings, and stops its own sessions/server. Test roles/JWTs
are fixture-only; no production access or old rollout package is used.

The existing result/correction tests and new tournament-completion test verify
that arithmetic and experience counts stay unchanged. No UI or preview-fixture
source changes are required for this repair; retained captures remain evidence
of their original SHA, not fresh runtime proof of the new RPC.
