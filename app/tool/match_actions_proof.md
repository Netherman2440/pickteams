# Match action menu proof

`MatchDetailsPage` uses one header action menu at every width. There are no standalone Edit/Delete icons or below-roster action rows. The shared action descriptors preserve the original conditions and callbacks, including team editing and deletion; Save/Cancel remain directly visible during editing. Available width, capped at 1000 px and reduced by the existing 16 px padding, controls only score/team layout. In the real shell that layout switch remains at 792 px (56 px rail + 16 px padding + 720 px content). Team editing retains its existing no-op guard when either team is absent.

`match_actions_menu_test.dart` replaces the initial single-state menu probe with exact action-set checks for eight match states, owner/admin, and both narrow and desktop layouts. All other roles receive no management controls. It tests menu dispatch, cancellation, score validation, delete/rematch confirmation and writes, draft preview, and draft route arguments. The existing responsive tests still verify dragging, saving, confirmations, player navigation, player rows, and headings. All fourteen score-breakpoint cases retain their original score assertions and enter through the menu at every width. A separate desktop dispatch test exercises team editing and deletion cancellation.

Use the SDK and lockfile setup in `player_lists_proof.md`. After committing the candidate, verify a clean tracked tree before and after each command and retain the SHA and output:

```sh
dart format --output=none --set-exit-if-changed <changed Dart files>
flutter analyze --no-pub
flutter test --no-pub --coverage --reporter expanded
flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run
flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run --target tool/player_lists_preview.dart
```

Serve the fixture build only on loopback, then run:

```sh
playwright-local python tool/capture_match_actions.py http://127.0.0.1:18842 /home/agents/dev/pickteams/.limen/proof/f003/<candidate>/frames
```

Stop the task server after capture. Open all four frames. The script captures the real Flutter page and shell with the menu closed/open at fixed 360×640 and 1440×1000 sizes. It enables Flutter semantics to click the real menu button. It does not resize, hide shell content, or use production services. External requests are blocked. Widget checks include Android insets; web captures do not simulate native system bars.

Canonical evidence is under `/home/agents/dev/pickteams/.limen/proof/f003/`. Native device/emulator execution and Wasm compilation are outside this slice. A successful JavaScript build with `--no-wasm-dry-run` does not prove Wasm support. Keep previous proof and the Tailscale preview unchanged.
