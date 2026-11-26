import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:app/features/players/presentation/widgets/player_role_goal_values.dart';
import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/players/application/player_goal_comparison_provider.dart';
import 'package:app/features/players/presentation/state/player_matches_provider.dart';
import 'package:app/features/players/presentation/widgets/player_profile_previews.dart';
import 'package:app/features/players/presentation/widgets/player_role_goal_section.dart';
import 'package:app/features/players/presentation/widgets/player_recent_match_row.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../fixtures/player_profile_app.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('recent away appearance shows player-team score and outcome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const PlayerProfileFixture());
    await tester.pumpAndSettle();
    expect(find.text('Wygrana'), findsNWidgets(3));
    expect(find.text('Goście'), findsOneWidget);
    expect(find.text('4 : 2'), findsOneWidget);
  });

  testWidgets('normal phone role means and delta stay side by side', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 256,
              child: PlayerRoleGoalValues(
                role: GoalRole.home,
                result: RoleGoalComparison(
                  withPlayer: 8,
                  withoutPlayer: 10,
                  scored: 1.5,
                  conceded: -.5,
                  scoredWithPlayer: 3.5,
                  scoredWithoutPlayer: 2,
                  concededWithPlayer: 1,
                  concededWithoutPlayer: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final labelY = tester.getCenter(find.text('Strzelone')).dy;
    final deltaY = tester.getCenter(find.text('+1,50')).dy;
    expect((labelY - deltaY).abs(), lessThan(2));
    expect(find.text('3,50 z graczem · 2,00 bez'), findsNothing);
    expect(tester.getTopRight(find.text('+1,50')).dx, 248);
  });

  for (final (atHome, hs, aws, result, score) in [
    (true, 5, 2, 'Wygrana', '5 : 2'),
    (false, 2, 4, 'Wygrana', '4 : 2'),
    (false, 4, 2, 'Porażka', '2 : 4'),
    (true, 0, 0, 'Remis', '0 : 0'),
    (false, 0, 0, 'Remis', '0 : 0'),
    (true, null, null, 'Brak wyniku', '— : —'),
  ]) {
    testWidgets('recent row renders $result and $score for home=$atHome', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 256,
              child: PlayerRecentMatchRow(
                match: Match(
                  matchId: 'm',
                  squadId: 's',
                  createdAt: DateTime(2026),
                  homeScore: hs,
                  awayScore: aws,
                ),
                playerId: 'p',
                snapshot: GoalComparisonMatch(
                  matchId: 'm',
                  home: GoalComparisonTeam(
                    color: null,
                    playerIds: atHome ? ['p'] : ['other'],
                  ),
                  away: GoalComparisonTeam(
                    color: null,
                    playerIds: atHome ? ['other'] : ['p'],
                  ),
                  homeScore: hs,
                  awayScore: aws,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text(atHome ? 'Gospodarze' : 'Goście'), findsOneWidget);
      expect(find.text(result), findsOneWidget);
      expect(find.text(score), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in ['absent', 'ambiguous', 'duplicate', 'error']) {
    testWidgets(
      'preview $mode membership is neutral and shares one history read',
      (tester) async {
        var reads = 0;
        final snapshot = GoalComparisonMatch(
          matchId: 'm',
          home: GoalComparisonTeam(
            color: null,
            playerIds: mode == 'absent' ? ['other'] : ['p'],
          ),
          away: GoalComparisonTeam(
            color: null,
            playerIds: mode == 'ambiguous' ? ['p'] : ['other-away'],
          ),
          homeScore: 2,
          awayScore: 4,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              squadGoalHistoryProvider.overrideWith((ref, id) async {
                reads++;
                if (mode == 'error') {
                  throw StateError('Synthetic history failure');
                }
                return [snapshot, if (mode == 'duplicate') snapshot];
              }),
              playerMatchesProvider.overrideWith(
                (ref, id) async => [
                  Match(
                    matchId: 'm',
                    squadId: 's',
                    createdAt: DateTime(2026),
                    homeScore: 2,
                    awayScore: 4,
                  ),
                ],
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: PlayerProfilePreviews(
                    squadId: 's',
                    playerId: 'p',
                    rankingCard: SizedBox(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(reads, 1);
        expect(find.text('Brak danych o stronie'), findsOneWidget);
        expect(find.text('Gospodarze : goście'), findsOneWidget);
        expect(find.text('2 : 4'), findsOneWidget);
        expect(find.text('Wygrana'), findsNothing);
        expect(find.text('Porażka'), findsNothing);
        expect(find.text('Remis'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets(
      'four list rows, semantic meaning, keyboard details and larger text at scale $scale',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerRoleGoalComparisonProvider.overrideWith(
                (ref, key) async => {
                  GoalRole.home: const RoleGoalComparison(
                    withPlayer: 8,
                    withoutPlayer: 10,
                    scored: 1.5,
                    conceded: -.5,
                    scoredWithPlayer: 3.5,
                    scoredWithoutPlayer: 2,
                    concededWithPlayer: 1,
                    concededWithoutPlayer: 1.5,
                  ),
                  GoalRole.away: const RoleGoalComparison(
                    withPlayer: 0,
                    withoutPlayer: 10,
                    scored: null,
                    conceded: 0,
                    concededWithPlayer: 0,
                    concededWithoutPlayer: 0,
                  ),
                },
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: const SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: PlayerRoleGoalSection(squadId: 's', playerId: 'p'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Strzelone'), findsNWidgets(2));
        expect(find.text('Stracone'), findsNWidgets(2));
        expect(find.text('3,50 z graczem · 2,00 bez'), findsNothing);
        expect(
          find.bySemanticsLabel(RegExp('0,00 gola na mecz. Brak różnicy')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp('Brak danych gola na mecz. Brak próbki porównawczej'),
          ),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('3,50 z graczem · 2,00 bez'), findsOneWidget);
        expect(
          find.text('Z zawodnikiem: 8 · Bez zawodnika: 10'),
          findsOneWidget,
        );
        expect(
          find.text('Z zawodnikiem: 0 · Bez zawodnika: 10'),
          findsOneWidget,
        );
        expect(find.text('+1,50 gola / mecz · Korzystnie'), findsOneWidget);
        expect(find.text('0,00 gola / mecz · Brak różnicy'), findsOneWidget);
        expect(find.text(roleGoalExplanation), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('3,50 z graczem · 2,00 bez'), findsNothing);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}
