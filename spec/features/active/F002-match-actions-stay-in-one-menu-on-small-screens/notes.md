# Implementation and proof map

## Boundaries and behavior

- The screenshot request is about viewing a match on a narrow screen: replace both standalone management icons and every below-roster action with a single header overflow menu.
- Keep Save/Cancel directly visible in either edit mode. The owner did not request hiding edit completion behind a menu.
- Reuse existing callbacks and applicability conditions. Empty, partially assigned, scored, and tournament matches must not gain invalid operations. Keep draft selection discoverable when no teams exist.
- Read-only users gain no editing/deletion operation. Destructive confirmations remain intact.
- Leave the accepted player rows, column headings, home screen, navigation behavior, and wide-screen controls alone.

## Seam and regression risk

- Start at `MatchDetailsPage` header actions and its below-roster `Wrap` in `app/lib/features/matches/presentation/pages/match_details_page.dart`.
- Use actual available/padded content width, not a competing device-width threshold. The earlier score-entry regression came from two contradictory width decisions; do not repeat it for menu versus inline actions.
- Retain all fourteen `match_score_breakpoint_test.dart` cases. Update test interaction helpers to open the new narrow menu; do not remove saving, permission, confirmation, redraft/rematch, navigation, or drag assertions.
- Existing real-page fixtures and screenshot helper are under `app/test/fixtures/` and `app/tool/`. Extend them only as needed for state/role coverage.

## Reproduction and evidence

- SDK: `$HOME/.local/share/pickteams-f001-sdk/flutter/bin`; user-local unzip: `$HOME/.local/share/pickteams-f001-sdk/unzip/usr/bin`. No new SDK installation is needed.
- `flutter pub get --enforce-lockfile` can insert SDK exclusions into `analysis_options.yaml`. Restore only that known SDK migration before validation; verify a clean tracked tree before and after every final command.
- Final checks: changed-Dart formatting, `flutter analyze --no-pub`, full `flutter test --no-pub --coverage`, and production/fixture JS web builds with the documented `--no-wasm-dry-run` flag.
- Capture real Flutter closed/open menu views at 360 × 640, plus a desktop frame showing unchanged controls. Include 768 px score entry and the actual menu/content breakpoint in widget coverage.
- Use fake providers, never production services. Commit the candidate before final proof; record its SHA and retain logs, scripts, and frames in canonical `.limen/proof/f002/` (outside the worker worktree).
- Preserve all previous proof and the owner’s Tailscale preview under canonical `.limen/visuals/mobile-concepts/public/`. No task server may remain running after capture. The coordinator publishes the reviewed result.
