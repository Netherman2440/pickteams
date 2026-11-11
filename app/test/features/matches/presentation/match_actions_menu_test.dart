import 'package:app/features/matches/application/dto/match_details_dto.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../fixtures/player_lists_app.dart';

const _bodyLabels = [
  'Wprowadź wynik',
  'Podgląd propozycji',
  'Wylosuj jeszcze raz',
  'Zmień drużyny',
  'Rewanż',
];

Future<void> _pump(
  WidgetTester tester, {
  double width = 360,
  SquadRole role = SquadRole.owner,
  MatchDetailsDto? match,
  FixtureWrites? writes,
}) async {
  tester.view.physicalSize = Size(width, width == 360 ? 640 : 1000);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PlayerListsFixture(role: role, match: match, writes: writes),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Akcje meczu'));
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String label) async {
  await _openMenu(tester);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['OpenSans', 'Nunito']) {
      final loader = FontLoader('${family}_regular')
        ..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'));
      await loader.load();
    }
  });

  final states = <(String, MatchDetailsDto, List<String>)>[
    (
      'assigned',
      fixtureMatch(),
      ['Wprowadź wynik', 'Podgląd propozycji', 'Wylosuj jeszcze raz', 'Rewanż'],
    ),
    (
      'scored',
      fixtureMatch(homeScore: 3, awayScore: 2),
      ['Wprowadź wynik', 'Podgląd propozycji', 'Rewanż'],
    ),
    ('empty', fixtureMatch(homeIds: [], awayIds: []), ['Podgląd propozycji']),
    ('no teams', fixtureMatch(withoutTeams: true), ['Podgląd propozycji']),
    (
      'home only',
      fixtureMatch(awayIds: []),
      ['Wprowadź wynik', 'Podgląd propozycji', 'Zmień drużyny', 'Rewanż'],
    ),
    (
      'away only',
      fixtureMatch(homeIds: []),
      ['Wprowadź wynik', 'Podgląd propozycji', 'Zmień drużyny', 'Rewanż'],
    ),
    (
      'tournament',
      fixtureMatch(tournamentId: 'cup'),
      ['Wprowadź wynik', 'Podgląd propozycji'],
    ),
    (
      'partial tournament',
      fixtureMatch(tournamentId: 'cup', awayIds: []),
      ['Wprowadź wynik', 'Podgląd propozycji', 'Zmień drużyny'],
    ),
  ];
  for (final width in [360.0, 1440.0]) {
    for (final role in [SquadRole.owner, SquadRole.admin]) {
      for (final (name, match, bodyLabels) in states) {
        testWidgets('$width $role $name: exact closed and open actions', (
          tester,
        ) async {
          await _pump(tester, width: width, role: role, match: match);
          expect(find.byTooltip('Akcje meczu').hitTestable(), findsOneWidget);
          expect(find.byTooltip('Edytuj składy'), findsNothing);
          expect(find.byTooltip('Usuń mecz'), findsNothing);
          for (final label in _bodyLabels) {
            expect(find.text(label), findsNothing);
          }
          await _openMenu(tester);
          final expected = ['Edytuj składy', ...bodyLabels, 'Usuń mecz'];
          expect(
            find.byWidgetPredicate((w) => w is PopupMenuItem),
            findsNWidgets(expected.length),
          );
          for (final label in expected) {
            expect(find.text(label).hitTestable(), findsOneWidget);
          }
          for (final label in _bodyLabels) {
            expect(
              find.text(label),
              bodyLabels.contains(label) ? findsOneWidget : findsNothing,
            );
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
    for (final role in SquadRole.values.where(
      (r) => r != SquadRole.owner && r != SquadRole.admin,
    )) {
      testWidgets('$width $role has no modifying controls', (tester) async {
        await _pump(tester, width: width, role: role);
        expect(find.byTooltip('Akcje meczu'), findsNothing);
        expect(find.byTooltip('Edytuj składy'), findsNothing);
        expect(find.byTooltip('Usuń mecz'), findsNothing);
        for (final label in _bodyLabels) {
          expect(find.text(label), findsNothing);
        }
      });
    }
  }

  testWidgets('desktop menu dispatches edit and delete with cancellation', (
    tester,
  ) async {
    final writes = FixtureWrites();
    await _pump(tester, width: 1440, writes: writes);
    await _select(tester, 'Edytuj składy');
    expect(find.byTooltip('Zapisz').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Anuluj').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Akcje meczu'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Changed');
    await tester.tap(find.byTooltip('Anuluj'));
    await tester.pumpAndSettle();
    expect(find.text('Changed'), findsNothing);
    expect(find.text('Niebiescy'), findsOneWidget);
    await _select(tester, 'Usuń mecz');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(writes.deletions, 0);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(writes.deletions, 0);
    expect(find.byTooltip('Akcje meczu').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final action in ['Edytuj składy', 'Wprowadź wynik']) {
    testWidgets('$action exposes Save/Cancel and Cancel discards edits', (
      tester,
    ) async {
      await _pump(tester);
      await _select(tester, action);
      expect(find.byTooltip('Akcje meczu'), findsNothing);
      expect(find.byTooltip('Zapisz').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Anuluj').hitTestable(), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        action == 'Wprowadź wynik' ? '9' : 'Changed',
      );
      await tester.tap(find.byTooltip('Anuluj'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Changed'), findsNothing);
      expect(find.text('9'), findsNothing);
      expect(find.text('Niebiescy'), findsOneWidget);
      expect(find.byTooltip('Akcje meczu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('score validation keeps editing until both scores are entered', (
    tester,
  ) async {
    await _pump(tester);
    await _select(tester, 'Wprowadź wynik');
    await tester.enterText(find.byType(TextField).first, '3');
    await tester.tap(find.byTooltip('Zapisz'));
    await tester.pumpAndSettle();
    expect(find.text('Podaj oba wyniki'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byTooltip('Akcje meczu'), findsNothing);
  });

  for (final action in ['Usuń mecz', 'Rewanż']) {
    testWidgets('$action dispatches only after confirmation', (tester) async {
      final writes = FixtureWrites();
      await _pump(tester, writes: writes);
      await _select(tester, action);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(writes.deletions, 0);
      expect(writes.rematches, 0);
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      expect(writes.deletions, 0);
      expect(writes.rematches, 0);
      await _select(tester, action);
      await tester.tap(
        find.text(action == 'Rewanż' ? 'Utwórz rewanż' : 'Usuń'),
      );
      await tester.pumpAndSettle();
      expect(writes.deletions, action == 'Usuń mecz' ? 1 : 0);
      expect(writes.rematches, action == 'Rewanż' ? 1 : 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('lineup-home-badge')), findsOneWidget);
      expect(find.text('Niebiescy'), findsOneWidget);
      expect(find.text('Czerwoni'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty match draft preview opens proposals', (tester) async {
    await _pump(tester, match: fixtureMatch(withoutTeams: true));
    await _select(tester, 'Podgląd propozycji');
    expect(find.text('Propozycja 1 z 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final action in ['Wylosuj jeszcze raz', 'Zmień drużyny']) {
    testWidgets('$action routes with existing selected IDs and match ID', (
      tester,
    ) async {
      final writes = FixtureWrites();
      final partial = action == 'Zmień drużyny';
      await _pump(
        tester,
        writes: writes,
        match: partial ? fixtureMatch(awayIds: []) : null,
      );
      await _select(tester, action);
      if (!partial) {
        expect(
          find.text('Czy chcesz jeszcze raz wylosować składy?'),
          findsOneWidget,
        );
        expect(writes.draftExtra, isNull);
        await tester.tap(find.text('Wylosuj'));
        await tester.pumpAndSettle();
      }
      final ids = fixturePlayers
          .take(partial ? 8 : 16)
          .map((p) => p.playerId)
          .toList();
      expect(writes.draftExtra, {'selectedIds': ids, 'matchId': 'match'});
      expect(find.text('Wybrani gracze (${ids.length})'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
