PASS a8bce0f57765b21d5cc522db52c7c80a01431d43

No blocking findings against the six acceptance bullets in `spec/features/active/F007-match-lists-show-both-team-names-on-phones/ticket.md`. Reviewed against base `b8efb75`. HEAD matches; the worktree is clean before and after review.

Unverified / not rerun:
- No independent full coverage, analyze, format, JS build, or browser capture run. I inspected the exact-candidate handoff and logs: format unchanged, analyze clean, 154 coverage tests passed, both JS builds passed, and 38+2 frames captured. Native APK/device/emulator and Wasm remain unperformed and outside this contract.
- The historical `red.log` shows `didExceedMaxLines == true`, but does not pin its source revision or preserve that earlier test. It supports the regression history, not a reproducible exact-base negative run. I did not mutate the candidate to rerun it. This is an evidence limit, not a product failure.

Acceptance decisions — proven by independent tests, source inspection, and frame inspection:
- **Labels and association:** Both 360 px real-shell top frames paint all letters of GOSPODARZE and GOŚCIE. Red/home and blue/away markers remain paired with 14/5 and 8/16. The targeted tests independently check glyph boxes, row centers, marker colors, and score placement.
- **Independent long names:** Both 320 px/1.6 centered frames show complete long names, separate wrapping rows, 8/16, and the date. Words break across lines, but letters are not lost. Each row has its own Expanded name (`app/lib/features/matches/presentation/widgets/match_tile.dart:166`).
- **Fallback and missing states:** Both 320 px/1.6 bottom frames show two missing-score dashes, complete fallback names, the unselected-team message, and dates inside the cards. The final E of scored GOSPODARZE wraps onto another line. Tests also pass for blank/null names, null teams, and a partial result.
- **Navigation:** All four row-tap tests pass for squad/player lists and preserve `original-squad/original-match`. The unchanged whole-card InkWell is at `match_tile.dart:37`; the stub route matches the production named route at `app/lib/core/app_router.dart:376`. Both real page callers still pass their squad ID. Match-details rendering itself is not tested here.
- **Responsive and desktop:** The breakpoint uses padded card-content width and text scaling (`match_tile.dart:46–49`), not viewport width. Tests pass for 320/360/390 px, 1/1.6 scaling, 24 px Android-style insets, breakpoint neighbors, and a narrow card inside a desktop shell. Both 1440 px frames retain horizontal names, markers, dates, colon, and score pair.

Test-discrimination note — proven by inspection and the passing targeted run: `app/test/features/matches/presentation/match_tile_test.dart:65–89` allows only the 320 px/1.6 diagnostic naming `root_shell.dart:281:19` and a 13-pixel overflow, and requires exactly one such error per pump. That source is the branding Row, not an ancestor containing the cards. Other errors go to Flutter's original handler and `takeException()` must stay null. The separate glyph/card-bound assertions remain active. This is not a blanket overflow allowance. The pre-existing shell overflow and enlarged player-title ellipsis are outside this diff; no card overflow was found.

Independent checks actually run:
- `git rev-parse HEAD`, `git status --short`, and `git diff --check b8efb75..HEAD`: expected SHA, clean tree, no whitespace errors. Evidence: `start.txt`, `final-state.txt` beside this review.
- `cd app && flock -n -E 75 /tmp/pickteams-flutter-validation.lock flutter pub get --enforce-lockfile`: exit 0. Inspected and restored only the known `analysis_options.yaml` exclusion insertion.
- `cd app && flock -n -E 75 /tmp/pickteams-flutter-validation.lock flutter test --no-pub --concurrency=1 --reporter expanded test/features/matches/presentation/match_tile_test.dart`: exit 0, all 20 tests passed. Commands, logs, and exits are beside this review. No busy lock or transient failure occurred in these independent runs.
- Parsed supplied browser metadata: 38 primary records, no page errors, all document widths match viewports; two supplemental records present. Metadata alone was not used as visual acceptance.
- Opened eight original PNGs under `/home/agents/dev/pickteams/.limen/proof/f007/a8bce0f57765b21d5cc522db52c7c80a01431d43/frames/`: both `squad` and `player` variants of `360-scale1-top.png`, `320-scale1.6-long-centered.png`, `320-scale1.6-bottom.png`, and `1440-scale1-top.png`. Observations are recorded above; I did not independently inspect all 40 frames.

No candidate code, ticket, board, main, gallery, icon resources, or production state changed. No merge or landing was performed.
