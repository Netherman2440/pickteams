import 'dart:async';
import 'package:app/features/players/application/player_goal_comparison_provider.dart';
import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:app/features/players/presentation/widgets/player_role_goal_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../fixtures/goal_comparison_data.dart';
import '../../fixtures/role_goal_app.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  Future<void> open(
    WidgetTester tester, {
    bool squad = false,
    RoleHistory? history,
  }) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RoleGoalFixtureApp(squad: squad, history: history));
    await tester.pumpAndSettle();
  }

  Future<void> details(WidgetTester tester) async {
    final disclosure = find.text('Jak czytać te liczby?');
    await tester.ensureVisible(disclosure);
    await tester.tap(disclosure);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'actual player and squad pages show identical role values and counts',
    (tester) async {
      await open(tester);
      expect(find.textContaining('SYNTHETIC DATA'), findsOneWidget);
      expect(find.text('+3,00'), findsNWidgets(2));
      expect(find.text('-1,00'), findsOneWidget);
      expect(find.text('+2,00'), findsOneWidget);
      expect(find.text('5,00 z graczem · 2,00 bez'), findsNothing);
      await details(tester);
      expect(find.text('5,00 z graczem · 2,00 bez'), findsOneWidget);
      expect(find.text('2,00 z graczem · 3,00 bez'), findsOneWidget);
      expect(find.text('6,00 z graczem · 3,00 bez'), findsOneWidget);
      expect(find.text('4,00 z graczem · 2,00 bez'), findsOneWidget);
      expect(find.textContaining('gola / mecz · Korzystnie'), findsNWidgets(3));
      expect(
        find.textContaining('gola / mecz · Niekorzystnie'),
        findsOneWidget,
      );
      expect(
        find.text('Z zawodnikiem: 1 · Bez zawodnika: 1'),
        findsNWidgets(2),
      );
      expect(find.text('Ranking bazowy'), findsOneWidget);
      expect(find.text(roleGoalExplanation), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await open(tester, squad: true);
      expect(find.text('Strzelone: +3,00 · Stracone: -1,00'), findsOneWidget);
      expect(find.text('Z zawodnikiem: 1 · Bez zawodnika: 1'), findsOneWidget);
      expect(find.text('Najlepszy gracz'), findsOneWidget);
      for (final measure in GoalMeasure.values) {
        await tester.tap(find.byType(DropdownButton<GoalMeasure>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(measure.label).last);
        await tester.pumpAndSettle();
        expect(
          find.text(
            measure.role == GoalRole.home
                ? 'Strzelone: +3,00 · Stracone: -1,00'
                : 'Strzelone: +3,00 · Stracone: +2,00',
          ),
          findsOneWidget,
        );
        final expectedValue = measure == GoalMeasure.homeConceded
            ? '-1,00'
            : measure == GoalMeasure.awayConceded
            ? '+2,00'
            : '+3,00';
        expect(find.text('Jan Testowy · $expectedValue'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Jan Testowy · $expectedValue')).dy,
          lessThan(
            tester.getTopLeft(find.text('Nowy bez występów · Brak danych')).dy,
          ),
        );
        await tester.tap(find.text('Najkorzystniejsze najpierw'));
        await tester.pumpAndSettle();
        expect(find.text('Odwrócona kolejność'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Jan Testowy · $expectedValue')).dy,
          lessThan(
            tester.getTopLeft(find.text('Nowy bez występów · Brak danych')).dy,
          ),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final squad in [false, true]) {
    testWidgets('history error and retry on actual page: squad=$squad', (
      tester,
    ) async {
      final history = RoleHistory()..fail = true;
      await open(tester, squad: squad, history: history);
      expect(find.text('Nie udało się pobrać porównań.'), findsOneWidget);
      expect(find.textContaining('Strzelone: +3,00'), findsNothing);
      history.fail = false;
      await tester.tap(find.text('Ponów'));
      await tester.pumpAndSettle();
      expect(
        squad
            ? find.text('Strzelone: +3,00 · Stracone: -1,00')
            : find.text('-1,00'),
        findsOneWidget,
      );
      expect(history.reads, 2);
      history.matches = [];
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(history.reads, 3);
      expect(find.textContaining('Strzelone: +3,00'), findsNothing);
      expect(
        squad
            ? find.textContaining('Strzelone: Brak danych')
            : find.text('Brak danych'),
        findsWidgets,
      );
    });
  }
  testWidgets('missing samples show counts and Brak danych, not a zero delta', (
    tester,
  ) async {
    await open(tester, history: RoleHistory()..matches = [goalMatch()]);
    expect(find.text('Brak danych'), findsWidgets);
    await details(tester);
    expect(find.text('Z zawodnikiem: 1 · Bez zawodnika: 0'), findsOneWidget);
    expect(find.text('Z zawodnikiem: 0 · Bez zawodnika: 0'), findsOneWidget);
    expect(
      find.textContaining('gola / mecz · Brak próbki porównawczej'),
      findsNWidgets(4),
    );
  });
  testWidgets(
    'loading is not missing data; narrow large-text section has no overflow',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            squadGoalHistoryProvider.overrideWith(
              (ref, id) => Completer<List<GoalComparisonMatch>>().future,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PlayerRoleGoalSection(squadId: 's', playerId: 'p'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('Brak danych'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            goalComparisonRepositoryProvider.overrideWithValue(RoleHistory()),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: const Scaffold(
                body: SingleChildScrollView(
                  child: PlayerRoleGoalSection(
                    squadId: 's',
                    playerId: 'player',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
