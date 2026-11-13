# Shared player rows (F014)

`lib/core/widgets/player_list_row.dart` owns the name/rating rendering.
`PlayerListRow` requires `String name` and `double ranking`. Optional parameters:
`PlayerRowDensity? density`, `bool compact = false`, `Widget? leading`,
`Widget? trailing`, `Widget? supporting`, `Widget? rankingSupport`, and
`VoidCallback? onTap`.

- `density` overrides the compatibility `compact` flag. Without either, density is comfortable.
- `compact`: minimum 32 px height; 4 px horizontal and 3 px vertical padding.
- `comfortable`: minimum 48 px height; 4 px horizontal and 8 px vertical padding.
- Both use a 14 px name (18 px line height) and a 12 px ranking (16 px line height), respecting text scaling. Ranking remains `toStringAsFixed(2)`.
- Name expands and wraps without a line cap. Rating stays inline, never a compulsory second line. Long names, text scaling, large actions, and optional metadata increase height. A 32 px minimum is not a fixed roster height.
- `rankingSupport` renders directly under the ranking as one right-hand block; the full name then centers vertically against that block instead of sharing its baseline. It is exclusive with `supporting`. The ordinary players list uses it for the ranking delta when the player has no position; with a position the existing name/position arrangement and `supporting` line stay.
- `leading` and `trailing` are intrinsic-width slots. Callers must bound their actions. `supporting` is optional metadata below the inline row, not another rating renderer.

`DraftDraggablePlayerTile` and `MatchPlayerTile` preserve all old constructor parameters and add `density` and `leading`. Draft `simple` now controls optional position/ranking-change metadata only. Drag payloads, feedback, platform choice, callbacks and match snapshot ranking remain unchanged. Selection explicitly uses comfortable rows. F015 can keep `compact: true` or use `density: PlayerRowDensity.compact` for rosters.

The selection edit is in `_AvailablePlayersPanelState.build` and `_SelectedPlayersPanel.build`, plus an import. Search stays above the single `SingleChildScrollView` keyed `selection-scroll`. Existing keyboard handling, toggle callbacks, selection state, generate/navigation methods and limits are unchanged.

Checks: `flutter test --no-pub --concurrency=1 test/features/draft/presentation/draft_selection_page_search_test.dart test/features/draft/presentation/shared_rows_test.dart test/features/draft/presentation/player_lists_responsive_test.dart`.

Frames: `flutter test --no-pub --update-goldens --concurrency=1 --dart-define=F014_FRAME_DIR=/absolute/output --dart-define=F014_SDK=/path/to/flutter tool/shared_rows_frames_test.dart`. These are Flutter test-rendered real RootShell pages with fake providers, not browser/device captures. Selection fixtures include 100 players and a full long name; frames include 360×640 and 1440×1000 at 1× and 1.6× text, the bottom of the list, search, ordinary players, proposals and match rosters.
