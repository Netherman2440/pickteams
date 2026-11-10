# Responsive player list proof

This fixture renders the real draft selection, draft results, and match details pages inside `RootShell`. It uses the production dark theme and bundled Open Sans/Nunito fonts. It has 22 fake squad players, 16 selected, two eight-player teams, Polish names, decimal rankings, and historical match rankings that differ from current player rankings. It does not initialize Supabase or Sentry. Repository/provider overrides hold writes in memory. The player destination is a labelled stub; the three pages under review are not stubs.

## Reproduce

Use Flutter 3.47.9 / Dart 3.13.7. The official Linux archive is `https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz`. The SDK is installed outside the repository under `/home/agents/.local/share/pickteams-f001-sdk/flutter`; a user-local `unzip` executable is under `/home/agents/.local/share/pickteams-f001-sdk/unzip/usr/bin`. Neither is committed. No system install is required.

From the repository root:

```sh
export PATH="$HOME/.local/share/pickteams-f001-sdk/unzip/usr/bin:$HOME/.local/share/pickteams-f001-sdk/flutter/bin:$PATH"
cd app
flutter pub get --enforce-lockfile
flutter test test/features/draft/presentation test/features/matches/presentation test/draft/presentation/draft_results_page_rules_test.dart --reporter expanded
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --target tool/player_lists_preview.dart
python3 -m http.server 18841 --bind 127.0.0.1 --directory build/web
```

In a second terminal, from `app/`:

```sh
playwright-local python tool/capture_player_lists.py http://127.0.0.1:18841 /home/agents/dev/pickteams/.limen/proof/f001/frames
```

Stop the HTTP server after capture. Direct fixture links are `/?page=selection`, `/?page=results`, and `/?page=match`. They must be opened as new locations, not by changing only the query after Flutter starts. This is a local test server, not an owner-shared preview.

The browser script captures unchanged 360×640 and 1440×1000 viewports, plus 320×640 and 2560×1000 overflow frames. Device scale and text scale are 1. It blocks all external requests, including the existing web runner's optional Google CSS stylesheet. Flutter's font assets and CanvasKit are local. `browser.json` records viewport, image path, script errors, external requests, and document width. Document width alone cannot detect canvas clipping; review the frames and the widget bounds assertions together.

The widget tests assert Android target behavior with top/bottom insets of 24 px, actual shell space, all 16 row bounds, centered match team names, historical rankings, desktop bounds and inline rankings, and unclipped/reachable text at scale 1.6. They exercise phone selection, search, generation, proposal navigation and acceptance (including changed team IDs), score entry, read-only permissions, player navigation, redraft/rematch access, and long-press team dragging. The match score regression retains the reviewer's failing 768 px case and checks adjacent widths around the shell switch (600 px), former viewport decision (720 px), and actual content breakpoint (792 px: 56 px rail + 16 px page padding + 720 px content). It verifies exactly one score display, the placement change, two reachable score fields, and saved values. This replaces the weaker phone-only score assertion in the general interaction test. Score placement and team layout now use the same padded-content `LayoutBuilder` decision. Existing hardware/software keyboard, focus, and phrase-selection assertions remain in the search tests. No collapse control was introduced.

## Candidate checks

After committing the candidate, retain raw output for:

```sh
dart format --output=none --set-exit-if-changed <changed Dart files>
flutter analyze --no-pub
flutter test --coverage --reporter expanded
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --target tool/player_lists_preview.dart
```

Flutter 3.47.9 automatically inserts platform/build exclusions in `analysis_options.yaml`; restore that SDK-only edit after running commands. Do not format untouched files. Record `git rev-parse HEAD` beside logs and frames. The canonical proof directory is `/home/agents/dev/pickteams/.limen/proof/f001/`.

No physical Android device, emulator, APK build, or native screenshots are part of this harness. Android-target widget coverage is not device proof. HTML prototype images are not implementation evidence.
