# Player profile goal comparisons (#59)

## Data contract

`matches` has no completed status. The existing score update use case writes
`home_score` and `away_score`; a normal completed match has both scores. This
feature reads all matches in the selected squad, including tournament matches,
with persisted `teams` and `team_players.player_id` snapshots. It does not join
current players or use player-only history. Reads use the existing authenticated
Supabase client and RLS. There are no writes or schema changes.

Eligible ordinary goals: `score_type` is null (the current score-entry convention)
or `regular`, and `score_meta` is null, empty, or contains only
`tournament_home_team_id` / `tournament_away_team_id`. The tournament creator
persists these non-scoring identifiers; the normal score writer changes only the
home/away goals and preserves them. These tournament matches use ordinary goals.
Cancelled, walkover, penalties and unknown score types are excluded, even with
known tournament metadata. Any other metadata key (including sets, penalty totals
or unknown fields), or a non-map metadata value, is excluded conservatively.
No goals are inferred from these records. Both-null
scores are unplayed and excluded. A partial or negative score on an otherwise
ordinary match makes the result unavailable, not a zero or a smaller sample.

An ordinary scored match needs exactly one home and one away side, two different
valid RGB colors, and nonempty, non-overlapping persisted membership on each side.
Incomplete scored snapshots make the comparison unavailable. Colors use the same
six-digit RGB format as match tiles: trim whitespace, remove optional `#`, fold
case. Invalid/missing colors are not replaced with display fallback grey.

A player appearance on either side excludes the entire match from N. Each
appearance counts once for a whole match. Each color uses its own absence mean;
weights use player occurrences only. An absent baseline for any played color makes
the entire comparison unavailable. Unplayed colors have weight zero. Results stay
signed, including conceded goals. The presentation rounds to two decimals once
for number, arrow, description and color; rounded zero is neutral.

## Seams and checks

- Pure calculation: `lib/features/players/domain/services/player_goal_comparison.dart`.
- Read-only, stable, 200-row pagination: `SupabaseGoalComparisonRepository`.
- Shared squad history and player-specific calculation: `playerGoalComparisonProvider`.
- Production section: `PlayerGoalComparisonSection`, above profile navigation.
- Refresh: returning from the profile's Matches or Tournaments pushed route
  invalidates the shared squad history. The profile stays mounted while those
  routes are open. Return always re-reads, including cancelled/failed edits, since
  multi-step saves can partly persist. A failed re-read uses the existing visible
  error/retry state rather than displaying a stale result.
- Route regression: `test/features/players/player_goal_comparison_refresh_test.dart`
  drives the production profile → PlayerMatchesPage → MatchDetailsPage routes and
  MatchDetailsNotifier score/membership/color actions, then returns twice.
  Only use-case persistence is synthetic. Successful edits replace visible
  values; rejected saves retain correct values after a fresh read. It replaces
  the weaker Matches destination-only check. It does not exercise editor controls
  or a production backend.
- Synthetic fixture: `test/fixtures/goal_comparison_data.dart`; default example has
  player colors 3:1, absence counts 2:7, and expected deltas +3.00 / -0.50.
- Tests: domain, application and infrastructure under `test/features/players/`;
  signs, unavailable states and 320/360/390/1440 widths at 1.6 text scale under
  `test/widgets/players/player_goal_comparison_test.dart`. Existing profile editing
  tests still cover real navigation and dialogs. The former route-only checks now
  also verify that the calculated tiles precede each navigation destination.

The tiles have natural heights, not a shared intrinsic height. Their signed numbers
stay on one line and scale down only when necessary; descriptions retain text
scaling. Missing-data tiles say `Brak danych`, with the specific reason once below
both tiles. Each tile has its own semantics group. Visual review at 320 px / 1.6x
must reject split numbers, text outside cards, and explanation overlap; VM widget
layout checks alone did not detect the earlier browser-only failure.

## Validation constraints

Use `/home/agents/.local/share/pickteams-f001-sdk/flutter/bin/flutter` (3.47.9).
Install with `flutter pub get --enforce-lockfile`. Run heavy validation serially
under `flock -n -E75 /tmp/pickteams-flutter-validation.lock`, with
`awk '/MemAvailable:/ {print; if ($2 < 2621440) exit 75}' /proc/meminfo`
before each heavy command. A lock/memory rejection is pending work, not a pass.
Flutter 3.47.9 automatically adds platform/build analyzer exclusions during pub
get. Record that generated diff, then restore the committed configuration before
analysis. Use `flutter analyze --no-pub`, `flutter test --no-pub --coverage` and
`--no-pub` builds so pub get cannot silently migrate it again. Verify its hash
before and after analysis. This is not permission to analyze with exclusions.
Only format changed Dart files. Analyze the exact committed configuration. Do not
add temporary analyzer exclusions. Report SDK/platform diagnostics separately;
analyzer errors are not a clean analysis result. Bounded lock waits are permitted;
a rejected lock is pending validation, not a pass.

Capture the real profile using `flutter build web --release --no-pub
--no-web-resources-cdn --no-wasm-dry-run --target tool/player_details_preview.dart`. The fixture replaces only data sources;
production profile, theme, section and calculation stay real. Query parameter
`comparison` selects `positive`, `negative`, `zero`, `rounded-zero`, `missing-color`,
`empty`, `no-absences`, `tournament` or `error`. The tournament fixture passes the
creator's persisted metadata through the real decoder and calculation: red 6–2
with the player and red 2–3 with total absence yield +4 scored and -1 conceded. The rounded-zero fixture computes +0.004 scored
and -0.004 conceded: both must show neutral zero, not favorable arrows.
These are synthetic data, not production data; browser mobile viewports are
emulation, not physical device checks.

Serve only the built fixture directory on loopback. Capture with
`playwright-local python tool/capture_goal_comparison.py http://127.0.0.1:18859 <proof>/frames`
under the shared lock and memory gate. The tool asserts expected rendered labels,
checks browser diagnostics and captures 36 section frames plus four profile frames.
Its unit checks run with
`python3 -m unittest discover -s tool -p test_capture_goal_comparison.py -v`.
Only the exact unused Google Fonts host-page stylesheet is fulfilled with empty
CSS. All Flutter fonts must load from unchanged bundled TTF assets. Other external
requests fail the capture. The no-CDN build serves CanvasKit locally. Omitting
`--no-web-resources-cdn` causes the capture's network guard to reject CanvasKit
before the app starts; this is a capture configuration error, not UI evidence.
Open the generated images before claiming visual evidence. The proof entry point
adds a synthetic-data banner; the production profile does not.

Preserve logs, the source SHA, captures and the built fixture outside the disposable
worktree under `/home/agents/dev/pickteams/.limen/proof/issue-59/<candidate-sha>/`.
The repair worker must not push, open a PR, merge or deploy. The parent feature
coordinator is authorized to publish the reviewed candidate and its visible PR
evidence; no new owner approval is required for that publication.
