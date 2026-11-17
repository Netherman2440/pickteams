# Match-level stars: exact-candidate evidence

Current PR66 source is `f0384d6e38673bf0f44423514e7749cb316c83d3`, based on accepted main `1377d580307959b8dc25594bff9e61370c539564`. See [the real context-failure correction and independent executed SECURITY proof](context-f0384d6/README.md). Full local Python was denied before execution. [Actual hosted Main44100639905 passed the full suite and configured compiler](hosted-f038/README.md); the downloaded archive matches the external GitHub digest. Complete inner artifact verification, real browser startup and final artifact review remain open.

The prior [integrated source/security receipt](integration-7ed7651/README.md) applies to parent `7ed7651e52b3d5ec868e353ed20447e3bdf7f7cd`; its actual candidate admission failure is preserved in [candidate-ci-7ed7651](candidate-ci-7ed7651/blocker.md).

The UI/test candidate described below is `ec6630d6d732d3c9191ef74c5e5460bd3cc2f847`, source branch `limen/github-issue-61-issue-61`, old dependency base `4fe251fc2dadf5cd0e9abc70a25b2220096ded02`. The nine images retain that exact original provenance. Material equality with the integrated source is proved separately; these are not new-head captures.

This **evidence-only branch is not a merge candidate**. The source PR contains 25 stars files and no evidence-only commits. It does not revert later accepted release tooling.

The original independent reviewer passed scoped source and visual review at this exact candidate. Its report is preserved verbatim in `source-visual-review.md`. This is a continuation of the independent review session, separate from the implementation author, not a new cold reviewer. Configured production-entrypoint hosted CI was still pending when the report was written. Its actual final result is now **FAILURE**: analysis/tests passed, but the configured web step stopped before compilation at the frozen production-release source guard (`Unapproved source differences`). See `configured-ci-blocker.md`, `ci-result.json` and `ci-failed-steps.log`. Candidate and release validation need a bounded separation; the release guard was not weakened. PR66 remains draft and whole-feature verification remains open. Review and a draft PR do not authorize merge or rollout.

## Screens and artifact identity

All nine PNGs are actual Flutter renders in Chromium 156.0.8078.4 with Playwright 1.64.1 at 390×1000, device scale 1. Each has a visible **SYNTHETIC browser fixture — not production** banner. Worker, coordinator and reviewer opened all nine. They are not live Supabase, physical-device or assistive-technology-session validation.

- `list.png`: existing date, team colors/names and result, plus a separated footer, full/half/empty stars and numeric `3,5`.
- `details.png`: matching `3,5` below unchanged win probability, with a roster-strength explanation.
- `settings.png`: green “Zmiana progów gwiazdek” entry, description and chevron. No inline threshold editor.
- `thresholds.png`: separate editor and automatic half preview. Custom values `10/20/40/70/120` here and in the `3,5` views are **fixture-only**, not calibration.
- `baseline.png`: calibrated full thresholds `49.8/56.1/58.0/59.8/62.9` and exact midpoint halves `52.95/57.05/58.9/61.35`. NULL override applies this baseline without a write.
- `validation.png`: repeated thresholds disable Save and show validation.
- `hidden-25.png`: no rating or footer at 25 completed matches. The visible case uses 26.
- `permission.png`: guest cannot edit thresholds.
- `load-failure.png`: explicit load error and retry, not a hidden error or fabricated baseline.

`browser.json` contains rendered labels, fields, request metrics and PNG hashes. `provenance.json` binds the candidate/base, all 25 committed source hashes, the app/lib tree, all 48 copied fixture-build file hashes and all nine PNG hashes. The large build and tools remain in private operational evidence. Coordinator and reviewer independently checked these hashes and image dimensions. This binds retained bytes; it is not an independent build or suite rerun.

## Calibration

The owner supplied authorized aggregates in [comment 6941297324](https://github.com/Netherman2440/pickteams/issues/61#issuecomment-6941297324): dot's read-only public-RLS GET on 2026-11-16 at 19:14 UTC, for Politechnika Lubelska through 2026-11-13 inclusive. Dates use `created_at` in Europe/Warsaw; `played_at` is NULL.

Reported input: 54 completed matches, 791 participants and 791 matching `ranking_history.ranking` values, with no missing, duplicate or nonfinite values. It excludes `change`, current score and tournament fallback. Each player has equal weight inside a match; each match has equal weight across the distribution.

Mean: 58.1409. Population SD: 2.85331. Observed range: 49.8–62.926. Normalize the normal CDF between its observed endpoint CDFs, then invert at full levels 1–5. One-decimal anchors are **49.8 / 56.1 / 58.0 / 59.8 / 62.9**. Half anchors are exact decimal midpoints, not separate calibration fields.

The implementation tool, coordinator's NormalDist calculation and reviewer's independent erf/bisection calculation agree. `owner-input.json`, `calculation.json` and committed `docs/features/match-level-calibration.md` preserve source and method. Counts and read provenance remain **owner-supplied**. Agents did not repeat a production read or independently audit individual records. These aggregates support the parametric calculation, not historical generator/acceptance identity; that audit remains deferred.

## Local checks

All nine `candidate-*.log` files identify exact `ec6630d` and end `EXIT=0`. The supplied working tree had only the byte-preserved, uncommitted AGENTS coordination overlay. It is excluded from source hashes. Do not describe these as independently rerun clean-tree tests.

| Command/lane | Recorded result |
|---|---|
| Scoped `dart format --output=none --set-exit-if-changed` | 13 files, 0 changes |
| `flutter analyze --no-pub` | No issues |
| Focused stars suites | 41 passed |
| `flutter test --no-pub --concurrency=1 --coverage` | 535 passed, 1 existing skip |
| `python -m unittest discover -s tool -p 'test_*.py'` | 102 passed |
| Chrome auth regression suite | 10 passed |
| Synthetic fixture release build | Passed; existing secure-storage Wasm dry-run warnings remain |
| Committed browser capture | 9 frames captured and asserted |
| Disposable PostgreSQL 16.15 | Migrations, constraints and owner/admin/guest RLS checks passed; rollback and server stop |

Coverage is 4953/12793 lines (38.72%). Historical source `356f6bf` had 38.48%; this is a changed-source comparison, not a new CI baseline. Six accepted profile-refresh regressions remain and passed. SQL used a disposable local auth fixture, not live Supabase/Auth. Supabase CLI/db lint was not run. Auth tests use synthetic sessions, not production tokens.

Heavy commands used immediate nonblocking shared flock, then `MemAvailable >= 2621440 KiB`. No capacity polling or lower admission gate was used. Prior failures and superseded frames remain privately preserved, not relabeled as passes.

## Reproduction and rollout boundary

Use pinned Flutter 3.47.9/c197ca5 and locked packages at the exact source. Build the fixture with:

```
flutter build web --release --no-pub --no-web-resources-cdn \
  -t tool/match_level_preview.dart --output build/stars-preview
```

Then run committed `app/tool/capture_match_levels.py` with that build and an output directory under a supported Python/Playwright runtime. Apply the lock and memory gate before every heavy command. Raw logs record actual commands and paths; restore private tooling paths rather than assuming they exist elsewhere.

Configured production-entrypoint proof is a separate hosted-CI gate. Fixture success does not replace it. Migration `20261116120000_add_squad_star_thresholds.sql` is repository code only; no production schema/data rollout occurred. NULL means the calibrated baseline; saved arrays are squad overrides. Owner-only management remains unchanged. Production needs an explicitly reviewed schema rollout during a later authorized release. No stars merge, manual deployment, production write, release64 inclusion or Play Store operation occurred.
