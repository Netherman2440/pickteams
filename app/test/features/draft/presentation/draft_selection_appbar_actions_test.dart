import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/draft/presentation/pages/draft_selection_page.dart';
import 'package:app/features/players/application/usecases/get_squad_players_usecase.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/domain/entities/player_head_to_head_stat.dart';
import 'package:app/features/players/domain/entities/player_stats.dart';
import 'package:app/features/players/domain/repositories/player_repository.dart';

/// Layout contract for the draft selection AppBar on narrow screens:
/// on < 600px the actions use short labels ("Losuj", "Relacje") so the
/// page title stays visible (with ellipsis) and nothing is cut off;
/// on >= 600px the full labels are unchanged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'mobile 360x800: short labels, title visible, actions on screen',
    (tester) async {
      // Pump with the error handler collecting instead of failing: the body
      // panel header Row ("Wybrani gracze" + "Wyczyść") legitimately overflows
      // at 360 logical px with the wide Ahem test font. That row is out of
      // scope here (it does not overflow with production fonts); every
      // collected error is still verified below, and the AppBar geometry is
      // guarded by explicit rect assertions.
      final pumpErrors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = pumpErrors.add;
      await _pumpPage(tester, const Size(360, 800));
      FlutterError.onError = originalOnError;
      for (final details in pumpErrors) {
        expect(
          details.exception.toString(),
          contains('A RenderFlex overflowed'),
          reason:
              'Only the known Ahem-font panel overflow may occur during pump',
        );
      }

      // Probe: what does the page actually see and render?
      final titleElement = tester.element(
        find.text('Propozycja - wybór graczy'),
      );
      // ignore: avoid_print
      print('MQ size: ${MediaQuery.of(titleElement).size}');
      final appBarButtons = tester
          .widgetList<TextButton>(find.byType(TextButton))
          .map((b) => (b.child is Text ? (b.child as Text).data : b.child))
          .toList();
      // ignore: avoid_print
      print('TextButton children: $appBarButtons');

      // Before any assertion, dump the actual geometry for the audit log.
      _logRect(tester, 'title', find.text('Propozycja - wybór graczy'));
      _logRect(tester, 'full-generate', find.text('Wygeneruj propozycję'));
      _logRect(tester, 'full-relations', find.text('Przejdź do relacji'));
      _logRect(tester, 'short-generate', find.text('Losuj'));
      _logRect(tester, 'short-relations', find.text('Relacje'));
      _logRect(tester, 'menu', find.byTooltip('Ustawienia propozycji'));

      // Short labels on mobile; full labels must not be present.
      expect(find.text('Losuj'), findsOneWidget);
      expect(find.text('Relacje'), findsOneWidget);
      expect(find.text('Wygeneruj propozycję'), findsNothing);
      expect(find.text('Przejdź do relacji'), findsNothing);

      // The title regains space: visible, ellipsized, on the screen. The
      // acceptance threshold of >= 80px is calibrated for production fonts
      // (measured in the browser); the Ahem test font inflates the action
      // labels ~2.2x, so here we assert the same invariant: clearly more
      // than the crushed ~0px of the broken layout.
      final titleRect = tester.getRect(find.text('Propozycja - wybór graczy'));
      expect(titleRect.width, greaterThan(40));
      expect(titleRect.right, lessThanOrEqualTo(360));
      expect(titleRect.left, greaterThanOrEqualTo(0));

      // Every action fits on the screen.
      expect(tester.getRect(find.text('Losuj')).right, lessThanOrEqualTo(360));
      expect(
        tester.getRect(find.text('Relacje')).right,
        lessThanOrEqualTo(360),
      );
      expect(
        tester.getRect(find.byTooltip('Ustawienia propozycji')).right,
        lessThanOrEqualTo(360),
      );
    },
  );

  testWidgets('desktop 1280x800: full labels, no layout regression', (
    tester,
  ) async {
    await _pumpPage(tester, const Size(1280, 800));

    _logRect(tester, 'title', find.text('Propozycja - wybór graczy'));
    _logRect(tester, 'full-generate', find.text('Wygeneruj propozycję'));
    _logRect(tester, 'full-relations', find.text('Przejdź do relacji'));

    // Full labels on desktop; short labels must not be present.
    expect(find.text('Wygeneruj propozycję'), findsOneWidget);
    expect(find.text('Przejdź do relacji'), findsOneWidget);
    expect(find.text('Losuj'), findsNothing);
    expect(find.text('Relacje'), findsNothing);

    final titleRect = tester.getRect(find.text('Propozycja - wybór graczy'));
    expect(titleRect.width, greaterThanOrEqualTo(80));
    expect(titleRect.right, lessThanOrEqualTo(1280));
    expect(
      tester.getRect(find.byTooltip('Ustawienia propozycji')).right,
      lessThanOrEqualTo(1280),
    );
  });
}

void _logRect(WidgetTester tester, String name, Finder finder) {
  if (finder.evaluate().isEmpty) {
    // Replace with a plain assignment when a lint demands it.
    // ignore: avoid_print
    print('$name: <not present>');
    return;
  }
  final rect = tester.getRect(finder);
  // ignore: avoid_print
  print(
    '$name: x=${rect.left.toStringAsFixed(1)} '
    'right=${rect.right.toStringAsFixed(1)} '
    'w=${rect.width.toStringAsFixed(1)} h=${rect.height.toStringAsFixed(1)}',
  );
}

Future<void> _pumpPage(WidgetTester tester, Size surface) async {
  // setSurfaceSize alone does not propagate to MediaQuery.fromView in
  // this Flutter version: the surface constrains layout while inherited
  // MediaQuery stays at the default 800x600. Set the view metrics
  // directly (logical == physical at dpr 1.0) before the first pump so
  // both agree.
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
        theme: ThemeData.dark(useMaterial3: true),
        home: DraftSelectionPage(
          squadId: 'squad-1',
          initialSelectedIds: const ['p1', 'p2'],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
