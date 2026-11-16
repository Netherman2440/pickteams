# Atomic preserved roster edits (issue #60, unshipped)

The coordinator may publish the reviewed PR through normal automatic preview
infrastructure. Workers do not push or edit PRs. This document does not authorize
live-backed preview visits, migration applies, merge, release or production runs.
Local synthetic fixture capture is separate from live runtime acceptance.
Legacy inventory, exact old-generation fidelity, and missing-input policy remain
unresolved. The approved counts-only audit bytes/interface are unchanged.

## Contract

`20261116130000_atomic_preserved_roster.sql` adds
`update_preserved_match_roster(p_match_id, p_request_id, p_home, p_away,
p_rankings, p_expected_version)`. The Flutter team repository calls this RPC
only for matches with authoritative `score_meta.draft_rankings`. The ordinary
match/history writer remains on its existing path.

The RPC uses SECURITY INVOKER and the caller's existing table RLS. It also
requires an authenticated squad owner/admin. The unshipped migration explicitly
revokes PUBLIC/anon execution and grants authenticated execution, matching the
existing draft RPC pattern. It creates no production operator/access path.
It locks the match row before validation. Score writes acquire that same row
lock, so a roster edit waiting behind a committed score must reject. Membership,
vector, receipt, and probability refresh either commit together or all roll back.
Team IDs, names/colors, explicit substitute options and unrelated metadata stay
intact. No tournament ranking-history events or current-ranking updates occur.
Inputs must be JSON numbers within +/- double.maxFinite (1.7976931348623157e308),
so accepted vectors remain readable by Flutter's strict finite-double reader.
Overflow rejects before mutation. Empty home/away lists remain valid, including
an entirely empty roster/vector, as in ordinary roster editing.

The command contains the complete intended roster and exact chosen inputs.
Retained players must keep their inputs. Newly added/re-added players use the
command's input, not a server re-read of today's score. Removal drops the input.
The client copies and freezes the command before submission. Duplicate in-flight
submissions share one operation. A failed response keeps that operation for
retry, including its UUID, version, memberships and addition inputs. A different
intent cannot replace an unresolved command.

Known PostgreSQL rollback errors are exposed as RosterEditRejected, distinct from
unknown/transport outcomes. A successful explicit MatchDetailsNotifier.refresh
or cancelRosterEdit discards only the confirmed rejected command captured before
that read. Failed reloads do not discard it. Discard checks the operation token
and rejects while an operation is in flight; stale recovery tokens cannot drop
newer commands. The user can then save the same intended membership as a NEW
operation with a new UUID/base and newly chosen addition inputs. The rejected
command is not silently rebased.

Unknown/lost responses survive reload AND cancel. The real match page exposes
an exact retry action, including after a read-only reload. retryRosterEdit sends
the frozen command before any new reads. New intents stay blocked until that
operation resolves. Ordinary unsaved cancel remains local; no legacy missing-
input fallback or policy is introduced.

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
duplicate submissions/caller-list mutation and a score race. The stronger
`app/test/features/matches/presentation/roster_recovery_test.dart` replaces the
standalone lost-response check with real notifier and widget reload/cancel/retry
flows, including same-membership conflict recovery, score drift, failed reads,
uncertain outcomes and in-flight/token races. None of these substitutes for SQL
transaction/RLS proof.

Run `supabase/tools/test_atomic_roster.py` against a disposable PostgreSQL 16
package, under the required immediate nonblocking resource gate. It loads the
real migrations and `atomic_preserved_roster_test.sql`, including metadata-write
and partial-insert failures, explicit ACLs, owner/admin versus member/foreign/anon,
finite-input/overflow boundaries, empty teams, replay and version conflicts. It then uses two authenticated local SQL sessions to prove
that an edit waits on a score lock and rejects after score commit without a
partial roster/vector. The runner uses a private Unix socket and local jit=off,
strips ambient PG settings, and stops its own sessions/server. Test roles/JWTs
are fixture-only; no production access or old rollout package is used.

The existing result/correction tests and new tournament-completion test verify
that arithmetic and experience counts stay unchanged. UI recovery controls now
call the actual notifier flow. Retained SHA605660a frames remain old synthetic
evidence, not proof of these controls; any new local captures must name their
new source SHA and remain clearly labeled fixtures.
