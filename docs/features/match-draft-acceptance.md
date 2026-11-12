# Match draft acceptance

New proposals use `/squads/:squadId/matches/preview`, without a match ID. Generation, browsing, failure and departure do not write draft or match data. Stored match draft lookup and fallback generation are also read-only. The back arrow and system back return new/redrawn previews to selection with IDs, rules and the substitute setting. Archived lookup returns to match details.

Acceptance uses `accept_match_draft`, never the sequential match/team/draft APIs. One transaction writes teams, pending ranking snapshots, the existing win-probability calculation, every proposal and the matrix. Redraw locks the match, rejects scored matches, retains team IDs/metadata and existing ranking snapshots. It does not update player scores. The existing tournament APIs are unchanged.

The client keeps one request UUID and an immutable payload for retries. It rejects concurrent submission and waits for the RPC before navigation. After the first submission, proposal editing is locked: the client retries the same payload after an uncertain response. The UI shows a retry message on failure. Back is disabled while acceptance is pending. Generation can finish after departure, but it has no persistence path and cannot replace a newer session's state.

The function keeps the four-parameter signature `accept_match_draft(p_request_id uuid, p_squad_id uuid, p_match_id uuid, p_payload jsonb)`. It accepts and ignores `p_request_id`, including null, so the existing APK needs no rebuild. There is no acceptance ledger or server-side request deduplication. The client lock handles rapid double-clicks, but a lost-response retry can create a second match when `p_match_id` is null. The owner accepted this risk on 2026-11-12; the user removes a duplicate with **Usuń mecz**. Redraw still locks the specified match and uses the ranking-history unique index with `ON CONFLICT DO NOTHING` to avoid duplicate snapshots on re-run.

## Rollout gate

Apply only `supabase/migrations/20261111120000_accept_match_draft.sql` through the reviewed [operator package](../operations/accept-match-draft.md), before releasing this client. The package reports five metadata flags only: function presence, authenticated execute permission, denied anonymous execute permission, invoker mode and migration-history presence. These flags do not prove hosted API readiness. No migration was deployed by this work. Missing RPC is a blocking acceptance error; there is no unsafe fallback. The function is SECURITY INVOKER. The caller must be an Owner/Admin of the requested squad, and existing table RLS applies to every statement. Member/guest/foreign-squad mutations are rejected. No old empty matches are removed.

Run the SQL checks on a disposable migrated Supabase database before rollout, then test the actual authenticated PostgREST RPC as Owner/Admin and rejected roles. Local SQL evidence uses PostgreSQL 16 and `supabase/tests/fixtures/local_auth.sql`, not a full Supabase stack. That fixture supplies only `auth.users`, `auth.uid()`, API roles and normal table grants. It cannot prove JWT transport, API schema-cache refresh or hosted deployment grants.

For a fresh disposable PostgreSQL database, run `psql -X -v ON_ERROR_STOP=1 -f supabase/tests/fixtures/local_auth.sql`, every `supabase/migrations/*.sql` in filename order, then `psql -X -v ON_ERROR_STOP=1 -f supabase/tests/accept_match_draft_test.sql`. The SQL test rolls back its synthetic data. Never run the fixture on an existing environment.

## Integration seams

- `draft_selection_page.dart`: optional `playWithSubstitute` constructor argument, initialization, `_generateWithoutRelations`; imports only outside those regions. No body/layout or row changes.
- `draft_against_relations_page.dart`: `_generateDraft` and unused imports only. No body/layout changes.
- `draft_results_page.dart`: session lifecycle, back handling, PopScope, acceptance button and pointer lock. Roster/header appearance is unchanged; the new wrappers cause formatting changes.
- `app_router.dart`: `draftPreview` route and selection substitute extra decoding. Existing route names and widget constructor arguments stay compatible.
- `DraftSessionNotifier`: removes all persistence, rejects stale asynchronous results after cancel/new load. Algorithms, scoring and limits are unchanged.
- `app/test/fixtures/player_lists_app.dart`: add the new route names and replace the sequential create/save fake with the atomic acceptance fake. Existing responsive drag/accept checks now count acceptance calls. Coordinate this small fixture change with the shared-row work.

The navigation checks use the actual router configuration and RootShell with fake repositories. They replace the old rule-forwarding-only widget check. Backend checks inject a payload-write failure after match/team/ranking writes to prove transaction rollback, including redraw, rather than merely rejecting invalid input before writes.
