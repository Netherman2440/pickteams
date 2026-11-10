# Centered match score proof

The real match page uses `PlayerListsFixture` with fake providers. No Supabase or Sentry initialization runs. `?page=match&score=saved` starts at 14 : 5. The capture script opens the real action menu, enters score edit mode, changes both fields, restores 14 : 5 and saves. It captures saved, editing and resaved states. No public gallery is changed.

The compact header gives the date one bodySmall line above the centered score, with no extra spacer. Score entry uses flexible, text-scaled fields. Desktop keeps its score between the teams. Player rows and historical rankings are unchanged. At 360 × 640 with 24px top/bottom Android insets, all sixteen rows must still fit at text scale 1.

## Reproduce

Use the installed Flutter SDK on PATH and the lockfile:

```sh
cd app
flutter pub get --enforce-lockfile
flutter test --no-pub test/features/matches/presentation/match_score_breakpoint_test.dart --reporter expanded
flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run --target tool/player_lists_preview.dart
python3 -m http.server 18844 --bind 127.0.0.1 --directory build/web
# In a second terminal, from app/:
playwright-local python tool/capture_match_scores.py http://127.0.0.1:18844 /path/to/proof/frames
```

Stop this local server after capture. The script blocks every external request and records errors, semantics and viewport data in `browser.json`. It produces twelve real Flutter frames: three states at 360 × 640 without insets, with simulated 24px system insets, with those insets and text scale 1.6, and at 1440 × 1000. Open the images; canvas clipping is not detected by document width.

The score test replaces the weaker breakpoint assertions, retaining all fourteen original widths. It adds thirty phone cases: 320px at scale 1, and 360/393/412px at scales 1/1.6/2, each with missing, 14 : 5 and 123 : 98 results. It checks score bounds, date separation, centered entry, saving, 280px keyboard insets, player reachability and historical rankings. Android is asserted as the widget-test target.

Known separate limit: an exploratory 320px test at scale 1.6 or 2 exposes a 13px overflow in the existing `RootShell` title Row (`lib/core/root_shell.dart:281`), before score editing. These combinations are not claimed as passing. Global navigation is outside this change. No native keyboard image, hardware device, emulator, APK or Wasm run is proven by these web frames or widget tests.

## Committed candidate evidence

Commit all source, tests and proof tools first. Record `git rev-parse HEAD` and `git status --porcelain` before and after checks under `/home/agents/dev/pickteams/.limen/proof/f004/<candidate-sha>/`. Retain raw output and exit codes for:

```sh
dart format --output=none --set-exit-if-changed lib/features/matches/presentation/pages/match_details_page.dart test/features/matches/presentation/match_score_breakpoint_test.dart test/fixtures/player_lists_app.dart tool/player_lists_preview.dart
flutter analyze --no-pub
flutter test --no-pub --coverage --reporter expanded
flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run
flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run --target tool/player_lists_preview.dart
```

Keep production and fixture outputs separately. Copy coverage, the failing baseline regression, inspected frames and review notes into the candidate directory. Flutter may add platform/build analyzer exclusions; inspect and restore only that known SDK migration, not other configuration changes. Record that restoration if needed. The ticket stays open.
