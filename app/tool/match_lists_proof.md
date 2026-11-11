# Offline match-list proof

`match_lists_preview.dart` renders the real `SquadMatchesPage` and `PlayerMatchesPage` inside `RootShell`, with the production theme and bundled fonts. Fake providers supply synthetic auth, member permissions, squad, matches and player name. Services are not initialized. Only the match-details destination is a labelled route-ID stub.

The fixture includes 14:5, 8:16, 0:2, 0:0, 12345:67890, a partial result, long names, populated teams without a result, and empty teams with blank names. Query parameters: `page=squad|player`, `scale=1|1.6`, `insets=android` (24 px top/bottom).

`match_tile_test.dart` replaces the old wide horizontal-card assertions with the same three-column geometry at 360/768/1440 px, each at scales 1 and 1.6, in both real pages. It checks every non-whitespace glyph box, complete paragraphs, date centering beside both rows, score/name/color association, right-aligned score glyphs without bordered containers, full-date semantics and tooltip, provider order, and navigation from labels, date, score and card padding. Empty/error pages and member permissions remain covered. It also checks null teams and constrained desktop content. Half a logical pixel tolerates font metric rounding; wrapping whitespace is not ink. Scores use one non-wrapping line. Each team uses a full-width Row with an expanded name and a non-flex score. Normal layout gives the score its actual unwrapped width; neither table intrinsic widths nor dry-layout approximations constrain it. Both rows end at the same edge without a digit-count limit or manual font measurement. Score selection boxes must have exactly one vertical line extent before any union is taken. A centered union alone previously let stacked digits pass.

## Reproduce

Use the installed Flutter SDK. Install from the lockfile with `flutter pub get --enforce-lockfile`. Run each heavy command through `flock -n -E75 /tmp/pickteams-flutter-validation.lock`; exit 75 means busy, not a product failure. Before a JS build require at least 2.5 GiB MemAvailable. Restore only the known SDK insertion in `analysis_options.yaml`.

Commit before final validation. Store logs and frames under `/home/agents/dev/pickteams/.limen/proof/F013/<candidate-sha>/`. From `app/`:

```sh
flutter test --no-pub --concurrency=1 test/features/matches/presentation/match_tile_test.dart
flutter analyze --no-pub
flutter build web --no-pub --release --no-web-resources-cdn --no-wasm-dry-run --target tool/match_lists_preview.dart
```

Copy `build/web` to `<proof>/fixture-web`. Serve that directory on loopback, then capture under the validation lock:

```sh
python3 -m http.server 18847 --bind 127.0.0.1 --directory <proof>/fixture-web
playwright-local python tool/capture_match_lists.py http://127.0.0.1:18847 <proof>/frames
```

Stop the server after capture. The script covers both real lists at 360×640, 768×900 and 1440×1000, each at scales 1 and 1.6. It scrolls until all nine fixture cards have been fully visible, including the complete long-name card. Each newly covered group gets a PNG and measured paragraph/glyph data in `browser.json`.

`match_lists_metrics.dart` exports a browser-only function from the preview, not production. It reads the actual laid-out RenderParagraph constraints, intrinsic widths, unwrapped equivalent-font dimensions and individual character selection boxes. The capture checks that all score characters share one line, fit inside the paragraph, match the unwrapped height, and align with the correct row and right edge. It also compares paired score heights (14 vs 5, 8 vs 16, and longer values). The instrumented preview uses the same production widget; no copied card or modified font metrics.

Only the exact optional Google Fonts stylesheet referenced by the unchanged HTML shell is fulfilled as empty CSS. That interception is recorded separately. Actual Flutter fonts must load as local bundled TTF assets. All other external requests, console errors, page errors, Flutter overflow/exception messages and document overflow remain failures. The previous failed browser build and images under `F013/review-1/` are immutable evidence. Open the corrected PNGs; measurement assertions alone are not visual acceptance. The coordinator owns the unrelated combined suite.

## Limits

These checks do not prove physical Android rendering, APK behavior, live Supabase data or real match-details behavior. Navigation proves route IDs only. The coordinator owns combined integration checks and APK validation. No Flashscore assets or reference screenshots are included.
