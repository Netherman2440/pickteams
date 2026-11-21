# Home/away goal comparison proof (issue 69)

## Source and scope

Base: `dc4f2a490e8ebeb70c8ad764de56719cba112c1f`. The assigned isolated branch
`limen/github-issue-69-7060773773` fast-forwarded from `1377d58` after `git fetch
origin main` and `git ls-remote origin refs/heads/main` agreed on that base.
The primary checkout stayed at `1377d580307959b8dc25594bff9e61370c539564` with its
intentional uncommitted `AGENTS.md` overlay. No branch 68 work was included.

Build/native source: `b32584a5d4bc10f721e287706513e9cae4b503d8`, tree
`d84380dd5c19c5b188f9741cfd2a3234f4214c19`.
Capture source: `bd4b76c3a8ba63ce28cb5e84d3a246d1f7491789`, tree
`ccc6f16ea19b6e6482e4a0f7eb6c44e70a5318b8`.
The only intervening change was the Python capture tool's handling of Flutter's
merged semantics. Application, tests, fixture, preview, assets, lockfile, and
analyzer configuration bytes are identical. All capture source hashes were
checked against the capture source commit. This document does not claim that a
later documentation commit was the build source.

## Calculation and UI seams

- `comparePlayerRoleGoals` uses persisted home/away membership. It never reads
  colors. An opposite-role appearance is neither a same-role appearance nor an
  absence. Both scored and conceded baselines use that same role in absent matches.
- Both providers use the existing paged `squadGoalHistoryProvider`. Squad sorting
  makes one roster read, not one backend request per player. Both pages call the
  same canonical calculation. Shared history invalidation refreshes both results.
- Unplayed matches (both scores null) and ineligible non-ordinary scores are
  ignored. Missing sides, empty sides, overlapping membership, partial scores,
  and negative scores in otherwise eligible scored history invalidate both
  deltas. Counts include valid ordinary scored matches only; the UI also says
  `Niekompletna historia meczów.` Missing samples show `Brak danych`, not zero.
- `GoalMeasure` and `compareGoalMeasure` implement all four measures. Scored sorts
  descending and conceded ascending by default. Reverse never moves missing
  results ahead of numeric results. Ties use ascending player IDs in both orders.
- New sections appear on the real `PlayerStatsPage` and `SquadStatsPage`; old
  statistics remain below. `PlayerDetailsPage`, its TWO combined tiles, and
  `comparePlayerGoals` are unchanged. Legacy color-based tests remain necessary;
  role tests do not supersede that different behavior.

## Checks actually run

Evidence root (outside the disposable worktree):
`/home/agents/dev/pickteams/.limen/task-coordinators/issue-69/worker-evidence/bd4b76c3a8ba63ce28cb5e84d3a246d1f7491789/`

- `flutter pub get --offline --enforce-lockfile`: passed using the existing SDK
  and cache. No SDK/browser/tool install or download commands were used. Flutter's automatic
  analyzer-options additions were restored precisely from HEAD before analysis;
  before/after SHA256 files match. No dependency/config changes remain.
- First focused math/provider run: 15 passed, 1 failed. The test enabled history
  failure after its read had already started. The test now invalidates that read
  before expecting failure; no production workaround was added.
- `flutter test --no-pub test/features/players test/widgets/players`: 161 passed.
  This includes exact `5:2`, `4:6`, `2:3` arithmetic, color independence, missing
  samples, malformed history, all four beneficial/reverse sort orders, missing
  last, ties, shared reads, provider failures/retry, actual-page consistency and
  pull refresh, narrow large text, and the old combined-tile regressions.
- Scoped `flutter analyze --no-pub`: no issues after adding missing flow-control
  braces flagged by the initial analysis (one info). Exact scope is in
  `checks/analyze.command`; committed analyzer config was used.
- Scoped `dart format --output=none --set-exit-if-changed`: 11 files, zero changes.
  An earlier check found one unformatted preview file; it was formatted before
  the clean check, native run, and build.
- ONE `flutter test --no-pub --coverage`, tool timeout **900 seconds**: exit 0,
  **556 passed, 1 skipped**, 2m28s. The existing password-reset regression has
  `skip: !kIsWeb`. Native coverage is `lcov.info`: 5268/12962 DA records hit
  (40.64%); this is whole-suite coverage, not a new-feature-only percentage.
- `python3 -m unittest discover -s app/tool -p test_capture_goal_comparison.py -v`:
  four reused network/diagnostic helper contract checks passed.
  `python3 -m py_compile app/tool/capture_role_goals.py`: passed.
- `git diff --check`: passed.

Each Flutter, Dart, build, and browser invocation separately took immediate
`flock -n -E75 /tmp/pickteams-flutter-validation.lock`, then checked
`MemAvailable >= 2621440 KiB`. Admission values are first lines in the saved logs.
There was no denial, waiting, memory polling, capacity helper, or parallel lane.

## Actual running Flutter screenshots

Both images were opened after the successful capture. They are unedited browser
screenshots of the production pages on **the same** marked synthetic fixture
`app/test/fixtures/role_goal_app.dart` version 1. Jan Testowy plays home in 5:2,
away in 4:6, and neither side in 2:3. Colors swap and are absent in the fixture.
Jan's home deltas are +3 scored / -1 conceded; away deltas are +3 / +2. Both
samples have one match per role. Other synthetic roster rows demonstrate missing
results and counts. Legacy statistics are repository stubs for page rendering;
unspecified legacy fields default to zero and are not calculated from this
history. Only the new comparison providers consume the three-match history. No account, backend initialization, credentials, or live data
were used. The real theme, widgets, providers, repository interface, and
calculation execute in the compiled Flutter app.

- `checks/frames/player-stats.png`: player statistics, both roles/counts visible,
  no scroll; SHA256 `556a8c745ca2eedb731739bf7622826b049d50d9fc93c82688665ad57873948e`.
- `checks/frames/squad-stats.png`: squad statistics, `Gospodarze · strzelone`
  selected, Jan first and missing results below; no scroll;
  SHA256 `3f0bd32efa9f508649cb4589902a1c7fec82d662219b6cb944093f902e43aae5`.

Both images visibly say `SYNTHETIC DATA · issue 69 · v1` and show the same match
summary. The banner sits outside route semantics, so its label is verified by
opening the images, not by claiming a DOM text match. The capture reads the
actual merged ARIA snapshot and raw DOM for role deltas/counts and all four
selected sort measures. It verifies missing-last order for each measure. Four
earlier capture attempts failed on exact-text selectors, merged ARIA labels, or
menu selectors; their logs and failure images remain in `checks/capture-attempt*`.
The successful tool uses real keyboard/click input and menuitem roles. It does
not edit the DOM or screenshots.

Browser: installed Chromium `156.0.8078.4`, executable SHA256
`377a9fc07b495c3b8d0ab8ec1fdfd153641759f9756fea34d8dfce4de82f5025`.
Viewport: 390×1000 CSS pixels, device scale 1; browser emulation, not a physical
phone. Routes: `http://127.0.0.1:18869/?page=player` and `?page=squad`. Enter enables
Flutter semantics. The squad capture selects all four measures, then returns to
home scored. `checks/frames/browser.json` records actions, ARIA, bounds, requests,
responses, executable, and hashes; adjacent `*-dom.html` files retain raw DOM.

Both pages had zero page errors and zero blocked requests; all loaded responses
were successful. The player console includes WebGL `GPU stall due to ReadPixels`
performance notices, not runtime errors. Service workers were blocked. The
browser allowed only loopback GET/HEAD resources, fulfilled only the exact unused
host-page Google Fonts stylesheet with empty CSS, and would reject other
external/backend/mutation requests. Actual Flutter fonts loaded from bundled
unchanged assets. All contexts and the browser closed; the owned loopback server
on port 18869 was stopped. Unrelated services, including the public APK server,
were not touched.

## Reproduce without production services

Use existing SDK `/home/agents/.local/share/pickteams-f001-sdk/flutter/bin` and
offline enforced-lockfile dependencies. Before **each** Flutter/Dart/build/browser
command, separately use the immediate lock and memory gate above; on denial
save state and return, do not wait or poll. Do not use production release tooling.

```sh
cd app
flutter build web --release --no-pub --no-web-resources-cdn \
  --no-wasm-dry-run --target tool/role_goal_preview.dart
python3 -m http.server 18869 --bind 127.0.0.1 --directory build/web
# Separate shell and separate immediate gate:
playwright-local python tool/capture_role_goals.py http://127.0.0.1:18869 OUTPUT
# Stop the owned server after capture; open both OUTPUT/*-stats.png images.
```

The saved build is `synthetic-build-web.tar.gz`; its SHA256 is
`c2ab8f844a5202ae6e2abb73c68ffd20f91ef4a01f5e0796c57f240536d34a36`.
`main.dart.js` SHA256 is
`a67f551be97003b0117d4faafaef1bec4b68a4db0ebcd583b99621ba92931d9f`.
`checks/build-hashes.json` covers every served build file.
`checks/source-hashes.json` records build source; `capture-source-hashes.json`
records capture source. `candidate.patch` retains the code/tool change from the
base. `SHA256SUMS` covers both raw images, the build archive, and native coverage.

## Publication boundary

No push, draft PR, issue comment, merge, deploy, signing, permission changes,
production access, migration, ranking/draft algorithm changes, or history writes
were performed. Publication and independent review remain the parent
coordinator's work. The current transport forbids this worker from publishing;
it must not use another API/executor to bypass that restriction.
