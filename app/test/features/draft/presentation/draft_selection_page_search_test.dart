import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/draft/presentation/pages/draft_selection_page.dart';
import 'package:app/features/draft/presentation/widgets/draft_draggable_player_tile.dart';
import 'package:app/features/players/application/usecases/get_squad_players_usecase.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/domain/entities/player_head_to_head_stat.dart';
import 'package:app/features/players/domain/entities/player_stats.dart';
import 'package:app/features/players/domain/repositories/player_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('draft search filters both selected and available sections', (
    tester,
  ) async {
    await _pumpPage(tester, initialSelectedIds: const ['p2']);

    // Bartek is already selected; typing his name must show him in the
    // "Wybrani" section and no match in "Dostępni".
    await _enterSearchQuery(tester, 'bart');

    expect(_findInSection('Wybrani gracze', 'Bartek'), findsOneWidget);
    expect(_findInSection('Dostępni gracze', 'Anna'), findsNothing);
    expect(_findInSection('Dostępni gracze', 'Cezary'), findsNothing);
    expect(
      _findInSectionContaining('Dostępni gracze', 'Brak dostępnych graczy'),
      findsOneWidget,
    );

    // A name that matches only an available player.
    await _enterSearchQuery(tester, 'ann');
    expect(_findInSection('Dostępni gracze', 'Anna'), findsOneWidget);
    expect(
      _findInSectionContaining('Wybrani gracze', 'Brak wybranych graczy'),
      findsOneWidget,
    );
    expect(_findInSection('Wybrani gracze', 'Bartek'), findsNothing);

    // A name that matches nobody: both sections must report no results.
    await _enterSearchQuery(tester, 'zenek');
    expect(
      _findInSectionContaining('Dostępni gracze', 'Brak dostępnych graczy'),
      findsOneWidget,
    );
    expect(
      _findInSectionContaining('Wybrani gracze', 'Brak wybranych graczy'),
      findsOneWidget,
    );
    expect(find.text('Anna'), findsNothing);
    expect(find.text('Bartek'), findsNothing);
    expect(find.text('Cezary'), findsNothing);

    // Clearing the query restores the unfiltered lists.
    await _enterSearchQuery(tester, '');
    expect(_findInSection('Wybrani gracze', 'Bartek'), findsOneWidget);
    expect(_findInSection('Dostępni gracze', 'Anna'), findsOneWidget);
    expect(_findInSection('Dostępni gracze', 'Cezary'), findsOneWidget);
  });

  testWidgets(
    'draft search enter adds auto-highlighted first match and selects phrase',
    (tester) async {
      await _pumpPage(tester);

      await _enterSearchQuery(tester, 'a');
      expect(_highlightedPlayerName(tester), 'Anna');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Anna was added...
      expect(_findInSection('Wybrani gracze', 'Anna'), findsOneWidget);
      expect(_findInSection('Dostępni gracze', 'Anna'), findsNothing);
      // ...regardless of there being multiple results.
      expect(_findInSection('Dostępni gracze', 'Bartek'), findsOneWidget);
      expect(_findInSection('Dostępni gracze', 'Cezary'), findsOneWidget);

      // Focus stays on the search field with the whole phrase selected.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      final controller = field.controller!;
      expect(controller.text, 'a');
      final selection = controller.selection;
      expect(selection.isCollapsed, isFalse);
      expect(selection.baseOffset, 0);
      expect(selection.extentOffset, controller.text.length);
    },
  );

  testWidgets(
    'draft search software keyboard done action adds highlighted player',
    (tester) async {
      await _pumpPage(tester);

      await _enterSearchQuery(tester, 'a');
      expect(_highlightedPlayerName(tester), 'Anna');

      // Software keyboards (mobile browsers, on-screen keyboards) submit
      // through the editing-complete action, not hardware key events.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(_findInSection('Wybrani gracze', 'Anna'), findsOneWidget);
      expect(_findInSection('Dostępni gracze', 'Anna'), findsNothing);

      // Focus stays on the search field with the whole phrase selected.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      final controller = field.controller!;
      expect(controller.text, 'a');
      final selection = controller.selection;
      expect(selection.isCollapsed, isFalse);
      expect(selection.baseOffset, 0);
      expect(selection.extentOffset, controller.text.length);

      // A repeated submit must not add the next matching player.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_findInSection('Wybrani gracze', 'Anna'), findsOneWidget);
      expect(_findInSection('Wybrani gracze', 'Bartek'), findsNothing);
      expect(_findInSection('Wybrani gracze', 'Cezary'), findsNothing);
    },
  );

  testWidgets(
    'draft search arrow keys navigate results and enter adds highlighted player',
    (tester) async {
      await _pumpPage(tester);

      await _enterSearchQuery(tester, 'a');
      expect(_highlightedPlayerName(tester), 'Anna');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_highlightedPlayerName(tester), 'Bartek');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_highlightedPlayerName(tester), 'Cezary');

      // Clamped at the last result.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_highlightedPlayerName(tester), 'Cezary');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_highlightedPlayerName(tester), 'Bartek');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_findInSection('Wybrani gracze', 'Bartek'), findsOneWidget);
      expect(_findInSection('Dostępni gracze', 'Bartek'), findsNothing);
    },
  );

  testWidgets(
    'draft search picked tile looks like a normal tile (no color override)',
    (tester) async {
      await _pumpPage(tester);

      await _enterSearchQuery(tester, 'a');
      expect(_highlightedPlayerName(tester), 'Anna');

      // The tile picked by keyboard navigation must render exactly like
      // every other tile: no Card color override (e.g. a
      // primaryContainer background) may hint at the picked position.
      final pickedCard = tester.widget<Card>(
        find
            .descendant(of: _pickedTileFinder(), matching: find.byType(Card))
            .first,
      );
      expect(pickedCard.color, isNull);
    },
  );

  testWidgets('draft search enter without highlighted player adds nothing', (
    tester,
  ) async {
    await _pumpPage(tester);

    // Empty query: Enter must not add anyone.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Nie wybrano jeszcze graczy.'), findsOneWidget);

    // After a successful add the highlight resets: pressing Enter again
    // must not add the next matching player.
    await _enterSearchQuery(tester, 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_findInSection('Wybrani gracze', 'Anna'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_findInSection('Wybrani gracze', 'Anna'), findsOneWidget);
    expect(_findInSection('Wybrani gracze', 'Bartek'), findsNothing);
    expect(_findInSection('Wybrani gracze', 'Cezary'), findsNothing);
  });

  testWidgets('draft search query change resets highlight to first match', (
    tester,
  ) async {
    await _pumpPage(tester);

    await _enterSearchQuery(tester, 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_highlightedPlayerName(tester), 'Bartek');

    await _enterSearchQuery(tester, 'c');
    expect(_highlightedPlayerName(tester), 'Cezary');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_findInSection('Wybrani gracze', 'Cezary'), findsOneWidget);
    expect(_findInSection('Wybrani gracze', 'Bartek'), findsNothing);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  List<String> initialSelectedIds = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(1800, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final players = [
    _player('p1', 'Anna', 40),
    _player('p2', 'Bartek', 41),
    _player('p3', 'Cezary', 42),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        getSquadPlayersUseCaseProvider.overrideWithValue(
          GetSquadPlayersUseCase(_FakePlayerRepository(players)),
        ),
      ],
      child: MaterialApp(
        home: DraftSelectionPage(
          squadId: 'squad-1',
          initialSelectedIds: initialSelectedIds,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterSearchQuery(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

Finder _sectionCard(String header) {
  return find.ancestor(
    of: find.textContaining(header),
    matching: find.byType(Card),
  );
}

Finder _findInSection(String header, String text) {
  return find.descendant(of: _sectionCard(header), matching: find.text(text));
}

Finder _findInSectionContaining(String header, String text) {
  return find.descendant(
    of: _sectionCard(header),
    matching: find.textContaining(text),
  );
}

/// Finder for the tile currently picked by keyboard navigation. The
/// picked tile does not change its look, so the auto-scroll GlobalKey
/// is the only remaining marker of the picked position.
Finder _pickedTileFinder() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is DraftDraggablePlayerTile && widget.key is LabeledGlobalKey,
  );
}

String? _highlightedPlayerName(WidgetTester tester) {
  final finder = _pickedTileFinder();
  expect(finder, findsOneWidget);
  final tile = tester.widget<DraftDraggablePlayerTile>(finder);
  return tile.player.name;
}

class _FakePlayerRepository implements PlayerRepository {
  _FakePlayerRepository(this.players);

  final List<Player> players;

  @override
  Future<Player> addPlayer({
    required String squadId,
    required String name,
    String? position,
    required int baseRanking,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deletePlayer({required String playerId}) {
    throw UnimplementedError();
  }

  @override
  Future<Player> getPlayer({required String playerId}) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlayerHeadToHeadStat>> getPlayerHeadToHeadStats({
    required String playerId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<PlayerStats> getPlayerStats({required String playerId}) {
    throw UnimplementedError();
  }

  @override
  Future<List<Player>> getSquadPlayers({required String squadId}) async {
    return players;
  }

  @override
  Future<Player> updatePlayer({
    required String playerId,
    String? name,
    String? position,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> updatePlayerRanking({
    required String playerId,
    required double newRanking,
  }) {
    throw UnimplementedError();
  }
}

Player _player(String id, String name, int ranking) {
  return Player(
    playerId: id,
    squadId: 'squad-1',
    name: name,
    baseRanking: ranking,
    ranking: ranking.toDouble(),
    createdAt: DateTime(2026, 1, 1),
  );
}
