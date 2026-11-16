import 'dart:async';
import 'package:app/core/app_theme.dart';
import 'package:app/features/players/application/player_goal_comparison_provider.dart';
import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:app/features/players/presentation/widgets/player_goal_comparison_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../fixtures/goal_comparison_data.dart';

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
        final semantics = tester.ensureSemantics();
        try {
          var failHistory = scenario == 'error';
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                squadGoalHistoryProvider.overrideWith((ref, id) {
                  if (failHistory) {
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
          expect(
            tester.getSemantics(find.text('BRAMKI STRZELONE')).label,
            allOf(
              startsWith('BRAMKI STRZELONE\n'),
              isNot(contains('BRAMKI STRACONE')),
            ),
          );
          expect(
            tester.getSemantics(find.text('BRAMKI STRACONE')).label,
            allOf(
              startsWith('BRAMKI STRACONE\n'),
              isNot(contains('BRAMKI STRZELONE')),
            ),
          );
          final cards = find.byType(Card);
          expect(cards, findsNWidgets(2));
          expect(
            tester.getTopLeft(cards.at(0)).dy,
            tester.getTopLeft(cards.at(1)).dy,
          );
          for (var i = 0; i < 2; i++) {
            final bounds = tester.getRect(cards.at(i));
            final texts = find.descendant(
              of: cards.at(i),
              matching: find.byType(Text),
            );
            for (final element in texts.evaluate()) {
              final rect = tester.getRect(find.byWidget(element.widget));
              expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 0.5));
              expect(rect.left, greaterThanOrEqualTo(bounds.left));
              expect(rect.right, lessThanOrEqualTo(bounds.right + 0.5));
            }
          }
          if (['positive', 'negative'].contains(scenario)) {
            final positive = scenario == 'positive';
            expect(find.text(positive ? '+3,00' : '−2,00'), findsOneWidget);
            expect(find.text(positive ? '−0,50' : '+3,00'), findsOneWidget);
            expect(
              tester
                  .widget<Text>(find.text(positive ? '+3,00' : '−2,00'))
                  .maxLines,
              1,
            );
            expect(
              tester
                  .widget<Text>(find.text(positive ? '−0,50' : '+3,00'))
                  .softWrap,
              isFalse,
            );
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
                find.descendant(
                  of: cards.at(index),
                  matching: find.byType(Icon),
                ),
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
                findsOneWidget,
              );
              expect(
                find.text(
                  scenario == 'loading' ? 'Wczytywanie…' : 'Brak danych',
                ),
                findsNWidgets(2),
              );
            }
          }
          if (scenario == 'error') {
            failHistory = false;
            await tester.tap(find.text('Spróbuj ponownie'));
            await tester.pumpAndSettle();
            expect(find.text('+3,00'), findsOneWidget);
            expect(find.text('−0,50'), findsOneWidget);
            expect(find.text('Spróbuj ponownie'), findsNothing);
            expect(tester.takeException(), isNull);
          }
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
