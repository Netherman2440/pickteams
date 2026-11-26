# Player profile and full statistics (#79)

The presentation uses the existing player routes, DTOs and goal comparison providers. `PlayerNavigation` keeps the same squad/player parameters and pushes destinations so Back returns to the caller. The full matches and tournaments pages retain their existing lists and detail links. Profile preview cards open those full destinations, not fixture-only views.

`RankingHistoryGraphWidget` pages the complete history in windows of six, starting at the latest entries. It reads each saved entry's `currentRanking` (pre-event ranking plus that event's delta), not an accumulation from today's base ranking. Arrow buttons, keyboard arrows, swipes, chart points and date buttons expose the history without truncating the provider data.

The color-weighted aggregate comparison and the home/away comparison remain separate. The role result adds four nullable averages from the same existing accumulators. Delta calculations, sample inclusion, absence semantics and incompleteness rules are unchanged. Missing means use a dash; missing comparisons use `Brak danych`. Numeric zero uses `0,00` and `Brak różnicy`. Favorability has a text description and does not depend on color. The shared compact `RoleGoalValues` used by squad statistics is unchanged.

The head-to-head table retains its original value formatting and comparator, including match-count and name tie-breaks in the selected direction. Modes show eight measures each. Mode changes reset sorting to that mode's match count descending. Existing synchronized horizontal and vertical controllers keep player names pinned and column headers aligned. Cell semantics include player name, measure, mode and value.

## Reproduction

Use the installed Flutter SDK and locked packages. Every heavy operation needs its own nonblocking `/tmp/pickteams-flutter-validation.lock` and `MemAvailable >=2621440 KiB`, held through execution. Stop heavy work on a denied admission. Run focused tests in `test/features/players`, `test/widgets/players`, and `test/players`; run the full suite once on the committed candidate with `timeout 900s flutter test --no-pub --coverage`.

`tool/player_profile_preview.dart` mounts the production pages on synthetic provider data only. It does not initialize Supabase or load an environment. Build it with `flutter build web --no-pub --no-web-resources-cdn -t tool/player_profile_preview.dart`, or `flutter build apk --debug --target-platform android-x64 --no-pub -t tool/player_profile_preview.dart`. This is a lab APK, never a production or release artifact. `SECTION=/stats`, `MATCHES=0` or `1`, and `LONG_NAME=true` are optional Dart defines for focused captures. The banner marks all data as synthetic. Match/tournament detail destinations in this fixture are labelled stubs; real match details and save/return refresh are tested separately in `player_goal_comparison_refresh_test.dart`.

`player_profile_statistics_test.dart` checks 320/390/1440 widths, both themes, keyboard/gesture history access, saved-value inspection, all sixteen head-to-head measures in both sort directions, pinned names, cards, Back, all original metric labels, and zero/one/many-match states. Existing edit/permission, comparison, repository and save/return tests remain. Old assertions that placed navigation below comparisons are replaced by the approved top-navigation assertion. The role UI test now asserts all four means and favorable/adverse labels instead of the old combined text line.

Rendered screenshots, videos, resource receipts, failed probes and exact tested SHA belong in the external job evidence directory, not in the release tree. Native GitHub video publication must be checked separately; a local MP4 is not proof of a rendered PR video player.
