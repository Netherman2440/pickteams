PASS af9a39c365b6083acab2f11f6aaa150336bcfefb

No blocking findings. Reviewed against base `9e573fe` and all five acceptance bullets in `spec/features/active/F004-match-scores-stay-centered-on-phones/ticket.md`.

## Unverified and unrun checks

- Native Android device/emulator, APK, physical keyboard rendering, and Wasm remain unverified. The independent tests simulate Android padding and a 280px keyboard inset; the supplied browser frames do not show a native keyboard.
- I did not rerun analysis, formatting, full coverage, either JavaScript build, or browser capture. I inspected the supplied exact-candidate logs and all twelve frames. Those are coordinator evidence, not commands I independently ran.
- The 320px enlarged-text RootShell case remains unverified here. The matrix excludes only that known navigation case; 360/393/412px run at 1.0, 1.6, and 2.0. This is not a general overflow exemption.
- The future integration rebase is unverified. Preserve the separately landed Android icons and confirm feature-source equivalence after rebase. The reviewed diff contains no icon changes.

## Acceptance decisions and source review

1. **PROVEN — centered saved 14 : 5.** `app/lib/features/matches/presentation/pages/match_details_page.dart:620-630` puts the date and compact scoreboard in separate vertical children. The date cannot consume horizontal scoreboard space. Independent geometry tests check the combined score bounds against the team/content center, not the colon alone. The opened 360×640 saved/resaved frames show the score centered above both teams.
2. **PROVEN within tested values — missing and larger scores.** The phone matrix covers `- : -`, `14 : 5`, and `123 : 98`, with padded horizontal bounds and date/team separation. All pass. This does not claim arbitrary-length integer scores fit.
3. **PROVEN — editing and saving at all fourteen breakpoints.** Independent tests pass at 360, 599, 600, 601, 719, 720, 721, 767, 768, 769, 791, 792, 793, and 1440px. Thirty additional phone cases cover text scaling, Android insets, visible fields and Save above the simulated keyboard, changed results, and final-player reachability. The separate actions suite verifies cancellation and rejection of an incomplete score. Controllers, digit filtering, validation, notifier dispatch, and persistence code are unchanged. The fixture updates state from the submitted integers; these are UI save checks, not backend persistence tests.
4. **PROVEN — desktop placement.** The central 220px scoreboard slot remains between the two expanded team sections. Desktop input width remains 80px; the new Flexible wrappers do not shrink it under the existing constraints. Opened saved/edit/resaved 1440×1000 frames show the original central placement and player-row layout.
5. **PROVEN — real 360×640 frames and preserved player rows.** I opened all twelve PNGs in the exact-candidate `frames/` directory. Default-size view and edit frames, both with and without 24px simulated insets, show all sixteen player rows. The inset edit frame retains the last names and rankings above the bottom inset. Names, historical rankings, dividers, and team headings retain their design. At 1.6x, names wrap and the lists need scrolling. The editing frame has the date out of the visible scrolled region; it is not visual proof of date separation at that scale. The transformed-label widget assertion supplies that check. Saved/resaved 1.6x frames show a separated date and centered score. Desktop frames retain inline player rankings.

## Regression and capture evidence

- **PROVEN by source inspection and the independent test run:** `app/test/features/matches/presentation/match_score_breakpoint_test.dart:198-218` measures the label RenderBox through `getTransformTo(null)` and `MatrixUtils.transformRect`. This includes InputDecorator's floating-label paint translation and scaling. It does not merely compare the TextField layout rectangle with the date. `match_details_page.dart:626` supplies the scaled edit-only gap; line 753 supplies flexible scaled compact field widths.
- I read `../floating-label-regression/before.log` and `after.log`. The historical negative probe reports label top 142.5 against date bottom 148.0, then the repaired matrix reports 44 passes. These historical probes are not independently rerun or treated as exact-candidate checks. The final committed assertion passed in my clean candidate run. The default-size edit frames visibly show space between the date and floating labels; the home label uses standard ellipsis, with its full name in accessibility semantics.
- `app/tool/capture_match_scores.py:50-92` uses focused keyboard selection/deletion/typing with frame settling and value assertions. It checks the resaved accessibility snapshot. I read all twelve records in `frames/browser.json`: no page errors, document widths match viewports, and edit semantics expose both complete labels. External Google Fonts CSS requests were blocked. The helper restores 14 : 5 before saving, so browser frames alone do not prove changed-value persistence; the widget cases starting from missing/123 : 98 scores do prove the UI update path.

## Independent commands and real results

Commands ran in `/home/agents/dev/.pickteams-limen-worktrees/2026-11-11-f004-score-layout-review-ea1fd128`.

- `git rev-parse HEAD` — matched the requested full SHA before and after review.
- `git status --short` / `git status --porcelain` — clean initially, before tests, and after tests.
- `git diff --stat 9e573fe..HEAD`, `git diff 9e573fe..HEAD -- ...`, and `git diff --name-only 9e573fe..HEAD` — inspected all six changed files; only one production Dart file changes.
- `git diff --check 9e573fe..HEAD` — passed, no output.
- `flock -n -E 75 /tmp/pickteams-flutter-validation.lock bash -c 'cd app && flutter pub get --enforce-lockfile'` — exit 0. Inspected the generated analyzer exclusions with `git diff -- app/analysis_options.yaml`, then restored only that known migration with `git restore -- app/analysis_options.yaml`. No other source edits.
- `flock -n -E 75 /tmp/pickteams-flutter-validation.lock bash -c 'cd app && flutter test --no-pub --concurrency=1 test/features/matches/presentation/match_score_breakpoint_test.dart test/features/matches/presentation/match_actions_menu_test.dart --reporter expanded'` — exit 0, all 99 tests passed: 44 score cases and 55 action/role/save/cancel cases. No retry or background command.
- File reads and `rg` inspected the changed boundaries, fixture save implementation, labels, and existing save/cancel tests. Initial dependency-file discovery found no `.dart_tool/package_config.json`; lockfile installation resolved it before tests.

Independent logs and exit codes are beside this review: `pub-get.log/.exit`, `targeted-tests.log/.exit`, `candidate-sha.txt`, and `status-after.txt`.

The supplied evidence root is `/home/agents/dev/pickteams/.limen/proof/f004/af9a39c365b6083acab2f11f6aaa150336bcfefb/`. I checked its matching before/after SHA files and empty status files. Its inspected logs report zero format changes, no analysis issues, 164 coverage tests passed, and successful production/fixture JavaScript builds. No older capture failure was counted as a pass. No source, ticket, board, main branch, gallery, or production change was made by this review.
