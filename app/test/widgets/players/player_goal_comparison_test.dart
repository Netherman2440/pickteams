import 'dart:async';
import 'package:app/core/app_theme.dart';
import 'package:app/features/players/application/player_goal_comparison_provider.dart';
import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:app/features/players/presentation/widgets/player_goal_comparison_section.dart';
import 'package:app/features/players/presentation/pages/player_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../fixtures/goal_comparison_data.dart';
import '../../fixtures/player_details_app.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final width in [320.0, 360.0, 390.0, 1440.0]) {
    for (final scenario in [
      'positive',
      'negative',
      'zero',
      'rounded-zero',
      'missing-color',
      'empty',
      'no-absences',
      'error',
      'loading',
    ]) {
      testWidgets('$scenario at $width with large text', (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              squadGoalHistoryProvider.overrideWith((ref, id) {
                if (scenario == 'error') {
                  return Future.error(StateError('fixture'));
                }
                if (scenario == 'loading') {
                  return Completer<List<GoalComparisonMatch>>().future;
                }
                return Future.value(comparisonFixture(scenario));
              }),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 1200),
                    textScaler: const TextScaler.linear(1.6),
                  ),
                  child: const SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: PlayerGoalComparisonSection(
                      squadId: 's',
                      playerId: 'player',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('BRAMKI STRZELONE'), findsOneWidget);
        expect(find.text('BRAMKI STRACONE'), findsOneWidget);
        final cards = find.byType(Card);
        expect(cards, findsNWidgets(2));
        expect(
          tester.getTopLeft(cards.at(0)).dy,
          tester.getTopLeft(cards.at(1)).dy,
        );
        if (['positive', 'negative'].contains(scenario)) {
          final positive = scenario == 'positive';
          expect(find.text(positive ? '+3,00' : '−2,00'), findsOneWidget);
          expect(find.text(positive ? '−0,50' : '+3,00'), findsOneWidget);
          expect(
            find.text(positive ? 'więcej strzelonych' : 'mniej strzelonych'),
            findsOneWidget,
          );
          expect(
            find.text(positive ? 'mniej straconych' : 'więcej straconych'),
            findsOneWidget,
          );
          for (var index = 0; index < 2; index++) {
            final icon = tester.widget<Icon>(
              find.descendant(of: cards.at(index), matching: find.byType(Icon)),
            );
            expect(
              icon.icon,
              (index == 0) == positive
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
            );
            expect(icon.color, positive ? Colors.green : Colors.red);
          }
        } else {
          expect(find.byIcon(Icons.arrow_upward), findsNothing);
          expect(find.byIcon(Icons.arrow_downward), findsNothing);
          if (['zero', 'rounded-zero'].contains(scenario)) {
            expect(find.text('0,00'), findsNWidgets(2));
            expect(find.text('Brak różnicy'), findsNWidgets(2));
          } else {
            expect(
              find.text(switch (scenario) {
                'missing-color' => 'Brak kompletnych danych porównawczych.',
                'empty' => 'Brak rozegranych meczów zawodnika.',
                'no-absences' => 'Brak meczów bez zawodnika.',
                'loading' => 'Wczytywanie danych…',
                _ => 'Nie udało się pobrać danych.',
              }),
              findsNWidgets(2),
            );
          }
        }
      });
    }
  }
  testWidgets('production profile places comparisons before navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(PlayerDetailsFixture(data: ProfileFixtureData()));
    await tester.pumpAndSettle();
    final heading = find.text('Drużyna z tym zawodnikiem');
    expect(heading, findsOneWidget);
    expect(
      tester.getTopLeft(heading).dy,
      lessThan(
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(PlayerDetailsPage),
                matching: find.text('Mecze'),
              ),
            )
            .dy,
      ),
    );
    expect(find.text('Eksperymentalne'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
