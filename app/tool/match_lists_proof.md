# Offline match-list proof

`match_lists_preview.dart` renders the real `SquadMatchesPage` and `PlayerMatchesPage` in `RootShell`, with the production theme and bundled fonts. Its separate fixture overrides auth, squad, squad matches, player matches and player name providers. It does not initialize services. All names, IDs and results are synthetic. Only the match-details destination is a labelled stub that displays the route IDs.

The fixture covers 14:5, 8:16, independent long names, populated teams without a result, and empty teams with blank names. Query parameters are `page=squad|player`, `scale=1|1.6`, and `insets=android` (24 px top/bottom). The widget tests also cover null teams, a partial result, breakpoint neighbors, and a 360 px content constraint in a 1440 px desktop shell.

The rendered regression started by failing on `RenderParagraph.didExceedMaxLines` in the old single rich title. The final test replaces that probe with non-whitespace glyph-box bounds, complete paragraphs, separate rows, score/color alignment, dates, and route checks for both pages. Half a logical pixel tolerates font metric rounding; wrapping whitespace is not ink. At scale 1.6 the score boxes grow uniformly so two-digit scores stay aligned.

## Checks

Use the installed Flutter/Dart SDK from PATH. Run heavyweight checks through `flock -n -E 75 /tmp/pickteams-flutter-validation.lock`, with one test worker. Run individual commands; exit 75 means lock-busy, not a check failure. Install with `flutter pub get --enforce-lockfile`. Inspect and restore only the known SDK insertion of platform/build exclusions in `analysis_options.yaml`.

Commit all source, test and tool changes before candidate validation. Record `git rev-parse HEAD` and an empty `git status --porcelain` before checks, then save all logs under `/home/agents/dev/pickteams/.limen/proof/f007/<candidate-sha>/`:

```sh
dart format --output=none --set-exit-if-changed lib/features/matches/presentation/widgets/match_tile.dart test/features/matches/presentation/match_tile_test.dart test/fixtures/match_lists_app.dart tool/match_lists_preview.dart
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --coverage --reporter expanded
flutter build web --no-pub --release --no-web-resources-cdn --no-wasm-dry-run
flutter build web --no-pub --release --no-web-resources-cdn --no-wasm-dry-run --target tool/match_lists_preview.dart
```

Copy each JS build to its own artifact directory before the next build. Serve only the fixture build on loopback, then capture under the same lock:

```sh
python3 -m http.server 18847 --bind 127.0.0.1 --directory <proof>/fixture-web
playwright-local python tool/capture_match_lists.py http://127.0.0.1:18847 <proof>/frames
```

Stop that server after capture. The capture records 38 frames: both pages at 320/360/390×640, scales 1/1.6, at top/middle/bottom, plus both desktop pages at 1440×1000. External requests are blocked. Inspect the PNGs; document width cannot prove that Flutter canvas text is visible. The script also rejects identical top/bottom captures.

## Limitations

At 320 px and scale 1.6 the existing branding Row in `root_shell.dart:281` reports a 13 px overflow. This is outside the card and outside this slice. Tests allow only that exact source/error at that size and still check all card geometry. The fixture does not hide or resize the shell branding. Revisit this narrow allowlist when the branding owner changes that Row.

No physical Android device, emulator, APK, native screenshots or Wasm validation is provided by this harness. Android-target widget tests and browser-injected insets are not native device proof. The public gallery and the separate player-lists fixture are unchanged.
