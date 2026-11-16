# Player profile goal comparisons (#59)

## Data contract

`matches` has no completed status. The existing score update use case writes
`home_score` and `away_score`; a normal completed match has both scores. This
feature reads all matches in the selected squad, including tournament matches,
with persisted `teams` and `team_players.player_id` snapshots. It does not join
current players or use player-only history. Reads use the existing authenticated
Supabase client and RLS. There are no writes or schema changes.

Eligible ordinary goals: `score_type` is null (the current score-entry convention)
or `regular`, and `score_meta` is empty/null. Cancelled, walkover, penalties and
unknown score types are excluded. Nonempty metadata is excluded conservatively:
the repository has no established interpretation of sets, penalty totals or other
metadata as ordinary goals. No goals are inferred from these records. Both-null
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
- Synthetic fixture: `test/fixtures/goal_comparison_data.dart`; default example has
  player colors 3:1, absence counts 2:7, and expected deltas +3.00 / -0.50.
- Tests: domain, application and infrastructure under `test/features/players/`;
  signs, unavailable states and 320/360/390/1440 widths at 1.6 text scale under
  `test/widgets/players/player_goal_comparison_test.dart`. Existing profile editing
  tests still cover real navigation and dialogs.

## Validation constraints

Use `/home/agents/.local/share/pickteams-f001-sdk/flutter/bin/flutter` (3.47.9).
Install with `flutter pub get --enforce-lockfile`. Run heavy validation serially
under `flock -n -E75 /tmp/pickteams-flutter-validation.lock`, with
`awk '/MemAvailable:/ {print; if ($2 < 2621440) exit 75}' /proc/meminfo`
before each heavy command. A lock/memory rejection is a blocker, not a pass.
Only format changed Dart files. Restore the known SDK-only platform exclusions in
`analysis_options.yaml` after validation; do not commit them.

Capture the real profile using `flutter build web --release --no-pub
--target tool/player_details_preview.dart`. The fixture replaces only data sources;
production profile, theme, section and calculation stay real. Query parameter
`comparison` selects `positive`, `negative`, `zero`, `rounded-zero`, `missing-color`,
`empty`, `no-absences` or `error`. These are synthetic data, not production data;
browser mobile viewports are emulation, not physical device checks.

Preserve logs, the source SHA, captures and the built fixture outside the disposable
worktree under `/home/agents/dev/pickteams/.limen/proof/issue-59/<candidate-sha>/`.
The trusted handoff prohibits pushing, opening a PR, merging and deploying. Local
commits and a PR-ready handoff are the delivery boundary; opening a PR remains
blocked until a trusted coordinator changes that restriction.
