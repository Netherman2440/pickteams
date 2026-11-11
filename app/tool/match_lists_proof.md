# Offline match-list proof

`match_lists_preview.dart` renders the real `SquadMatchesPage` and `PlayerMatchesPage` inside `RootShell`, with the production theme and bundled fonts. Fake providers supply synthetic auth, member permissions, squad, matches and player name. Services are not initialized. Only the match-details destination is a labelled route-ID stub.

The fixture includes 14:5, 8:16, 0:2, a partial result, long names, populated teams without a result, and empty teams with blank names. Query parameters: `page=squad|player`, `scale=1|1.6`, `insets=android` (24 px top/bottom).

`match_tile_test.dart` replaces the old wide horizontal-card assertions with the same three-column geometry at 360/768/1440 px, each at scales 1 and 1.6, in both real pages. It checks every non-whitespace glyph box, complete paragraphs, date centering beside both rows, score/name/color association, right-aligned scores without bordered containers, full-date semantics and tooltip, provider order, and navigation from labels, date, score and card padding. Empty/error pages and member permissions remain covered. It also checks null teams and constrained desktop content. Half a logical pixel tolerates font metric rounding; wrapping whitespace is not ink.

## Reproduce

Use the installed Flutter SDK. Install from the lockfile with `flutter pub get --enforce-lockfile`. Run each heavy command through `flock -n -E75 /tmp/pickteams-flutter-validation.lock`; exit 75 means busy, not a product failure. Before a JS build require at least 2.5 GiB MemAvailable. Restore only the known SDK insertion in `analysis_options.yaml`.

Commit before final validation. Store logs and frames under `/home/agents/dev/pickteams/.limen/proof/F013/<candidate-sha>/`. From `app/`:

```sh
flutter test --no-pub --concurrency=1 test/features/matches/presentation/match_tile_test.dart
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --reporter expanded
flutter build web --no-pub --release --no-web-resources-cdn --no-wasm-dry-run --target tool/match_lists_preview.dart
```

Copy `build/web` to `<proof>/fixture-web`. Serve that directory on loopback, then capture under the validation lock:

```sh
python3 -m http.server 18847 --bind 127.0.0.1 --directory <proof>/fixture-web
playwright-local python tool/capture_match_lists.py http://127.0.0.1:18847 <proof>/frames
```

Stop the server after capture. The script captures 14 actual Flutter frames: both pages at 360×640 and scales 1/1.6 at top/middle/bottom, plus both at 1440×1000. It rejects page errors, external requests, Flutter overflow/exception console messages, document overflow and identical top/bottom frames. Open the PNGs: document width alone does not prove canvas visibility.

## Limits

These checks do not prove physical Android rendering, APK behavior, live Supabase data or real match-details behavior. Navigation proves route IDs only. The coordinator owns combined integration checks and APK validation. No Flashscore assets or reference screenshots are included.
