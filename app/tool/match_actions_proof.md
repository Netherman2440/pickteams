# Compact match action menu proof

`MatchDetailsPage` uses its available width, capped at 1000 px and reduced by the existing 16 px horizontal padding, for one compact decision. The header overflow and score/team layout use that same decision. In the real shell the switch is at 792 px (56 px rail + 16 px padding + 720 px content). The shared body-action descriptors keep the desktop action order, conditions, callbacks, and empty-draft attention marker. The narrow menu also includes the original team edit and delete operations. Team edit retains its existing no-op guard when either team is absent.

`match_actions_menu_test.dart` replaces the initial single-state menu probe with exact action-set checks for eight match states, owner/admin, and both narrow and desktop layouts. All other roles receive no management controls. It tests menu dispatch, cancellation, score validation, delete/rematch confirmation and writes, draft preview, and draft route arguments. The existing responsive tests still verify dragging, saving, confirmations, player navigation, player rows, and headings. All fourteen score-breakpoint cases retain their original score assertions and now enter through the menu when compact.

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
playwright-local python tool/capture_match_actions.py http://127.0.0.1:18842 /home/agents/dev/pickteams/.limen/proof/f002/<candidate>/frames
```

Stop the task server after capture. Open all three frames. The script captures the real Flutter page and shell at fixed 360×640 closed/open and 1440×1000 desktop sizes. It enables Flutter semantics to click the real menu button. It does not resize, hide shell content, or use production services. External requests are blocked. Widget checks include Android insets; web captures do not simulate native system bars.

Canonical evidence is under `/home/agents/dev/pickteams/.limen/proof/f002/`. Native device/emulator execution and Wasm compilation are outside this slice. A successful JavaScript build with `--no-wasm-dry-run` does not prove Wasm support. Keep previous proof and the Tailscale preview unchanged.
