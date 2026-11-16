# Historical match display proof

Scope: issue #60, owner comment 6923475646. Display `ranking_history.ranking`
for the exact match/player. Do not add `change`. No writer, schema, generator,
roster, fallback policy or score formula changes.

The schema comment in
`supabase/migrations/20251201090900_create_ranking_history_table.sql` defines
`ranking` as the snapshot **before** the change. The existing
`SupabaseRankingRepository.updatePlayerRanking` changes `change` and the current
player `score`, not that snapshot. `GetMatchUseCase` maps the team repository
values into the DTO used by `MatchDetailsPage`. The page sorts those values and
uses them for totals. Its existing larger-side adjustment is `(m - 1) / m`.
The fix does not claim exact generator-time capture.

`test/features/matches/presentation/historical_match_display_test.dart` uses
real Supabase team/player/ranking repositories over the synthetic HTTP transport
in `test/fixtures/historical_match_data.dart`, plus the real read use case,
notifier and match page. Result/correction/manual-score states drive the existing
ranking writer. The fixture provides match metadata; it does not simulate the
full match scoring formula. Assertions cover rows, order, totals, current score,
delta, reload, no history, tournament history, and partial history. It replaces
two static rank-text assertions in the layout test; geometry assertions remain.

Capture entrypoint: `tool/historical_match_preview.dart`. It shares the same
transport and production page as the regression, never the production entrypoint.
Its visible SYNTHETIC banner shows state and current p0 score. The Flutter widget
metrics callback only reads the rendered tree. `tool/capture_historical_match.py`
checks values and captures four states each for 2 vs 2 and 3 vs 2, then reloads.
It serves only the built fixture on loopback and stops server/browser on exit.

Use the workflow's pinned Flutter 3.47.9 and locked dependencies. Every heavy
command must acquire nonblocking `flock -n -E75
/tmp/pickteams-flutter-validation.lock` then require `MemAvailable >= 2621440 KiB`.
Do not wait or poll on failed admission.

```sh
flutter test --no-pub --concurrency=1 test/features/matches/presentation/historical_match_display_test.dart
flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run --target=tool/historical_match_preview.dart
python tool/capture_historical_match.py BUILD_DIRECTORY OUTPUT_DIRECTORY
```

Candidate logs, build copies, screenshots, SHA and admission records are external:
`/home/agents/dev/pickteams/.limen/task-coordinators/issue-60/display-only/evidence/`.
These are synthetic browser fixtures, not production data or physical-device proof.
