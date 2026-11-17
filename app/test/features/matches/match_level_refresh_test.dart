import 'dart:async';
import 'package:app/core/widgets/team_transfer_target.dart';
import 'package:app/features/matches/application/usecases/update_match_score_usecase.dart';
import 'package:app/features/matches/application/usecases/update_match_teams_usecase.dart';
import 'package:app/features/matches/presentation/pages/match_details_page.dart';
import 'package:app/features/matches/presentation/widgets/match_level_panel.dart';
import 'package:app/features/squads/presentation/pages/squad_star_thresholds_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import '../../fixtures/match_level_app.dart';

class ScoreSave extends Mock implements UpdateMatchScoreUseCase {}

class RosterSave extends Mock implements UpdateMatchTeamsUseCase {}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  List<double> ratings(WidgetTester tester) => tester
      .widgetList<MatchLevelRating>(
        find.byType(MatchLevelRating, skipOffstage: false),
      )
      .map((w) => w.rating)
      .toList();
  testWidgets(
    'threshold save refreshes retained real list and details, then remounted form rereads',
    (tester) async {
      viewport(tester);
      final data = (await tester.runAsync(() async => MatchLevelData()))!;
      addTearDown(() => tester.runAsync(data.dispose));
      await tester.pumpWidget(
        MatchLevelApp(data: data, screen: 'details', retainList: true),
      );
      await tester.pumpAndSettle();
      expect(ratings(tester), [3.5, 3.5]);
      final router = GoRouter.of(tester.element(find.byType(MatchDetailsPage)));
      unawaited(router.push('/squads/fixture/settings/stars'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.enterText(find.byType(TextField).at(i), '${i + 1}');
      }
      await tester.ensureVisible(find.text('Zapisz'));
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();
      // Navigator pauses subscriptions on its covered details route. The retained
      // list stays active; details must show the fresh value as soon as it returns.
      expect(ratings(tester).last, 5);
      router.pop();
      await tester.pumpAndSettle();
      expect(ratings(tester), [5, 5]);
      unawaited(router.push('/squads/fixture/settings/stars'));
      await tester.pumpAndSettle();
      expect(find.byType(SquadStarThresholdsPage), findsOneWidget);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((f) => f.controller!.text),
        ['1,0', '2,0', '3,0', '4,0', '5,0'],
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final edit in ['score', 'roster']) {
    for (final success in [true, false]) {
      testWidgets(
        'pending $edit save=$success updates both retained views, 25→26 only after success',
        (tester) async {
          viewport(tester);
          final data = (await tester.runAsync(
            () async =>
                MatchLevelData(completed: edit == 'score' ? 25 : 26)
                  ..hasResult = false,
          ))!;
          addTearDown(() => tester.runAsync(data.dispose));
          final pending = Completer<void>();
          final score = ScoreSave();
          final roster = RosterSave();
          when(
            () => score.execute(
              matchId: 'match',
              squadId: 'fixture',
              homeScore: 4,
              awayScore: 4,
            ),
          ).thenAnswer((_) async {
            await pending.future;
            if (!success) throw StateError('Synthetic rejected save');
            data.completed = 26;
            data.hasResult = true;
            return data.reader.execute(matchId: 'match');
          });
          when(
            () => roster.execute(
              matchId: 'match',
              homePlayerIds: ['p1'],
              awayPlayerIds: ['p2', 'p3', 'p0'],
            ),
          ).thenAnswer((_) async {
            await pending.future;
            if (!success) throw StateError('Synthetic rejected save');
          });
          await tester.pumpWidget(
            MatchLevelApp(
              data: data,
              screen: 'details',
              retainList: true,
              providerOverrides: [
                updateMatchScoreUseCaseProvider.overrideWithValue(score),
                updateMatchTeamsUseCaseProvider.overrideWithValue(roster),
              ],
            ),
          );
          await tester.pumpAndSettle();
          expect(ratings(tester), edit == 'score' ? isEmpty : [3.5, 3.5]);
          final initialReads = data.requests
              .where((r) => r == 'GET matches')
              .length;
          await tester.tap(find.byTooltip('Akcje meczu'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(edit == 'score' ? 'Wprowadź wynik' : 'Edytuj składy'),
          );
          await tester.pumpAndSettle();
          if (edit == 'score') {
            await tester.enterText(find.byType(TextField).at(0), '4');
            await tester.enterText(find.byType(TextField).at(1), '4');
          } else {
            // Drive the existing drop callback; this is not a drag-gesture test.
            tester
                .widget<TeamTransferTarget>(
                  find.byKey(const ValueKey('match-away-target')),
                )
                .onAccept('p0');
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byTooltip('Zapisz'));
          await tester.pump();
          if (edit == 'score') {
            expect(data.completed, 25);
          }
          pending.complete();
          await tester.pumpAndSettle();
          if (edit == 'score') {
            expect(data.completed, success ? 26 : 25);
            if (success) {
              expect(ratings(tester), [3.5, 3.5]);
            } else {
              expect(ratings(tester), isEmpty);
            }
          } else {
            // A side swap preserves the equal-player mean (no team multipliers).
            expect(ratings(tester), success ? [3.5, 3.5] : [3.5]);
          }
          expect(
            data.requests.where((r) => r == 'GET matches').length,
            greaterThan(initialReads),
          );
          if (edit == 'score') {
            verify(
              () => score.execute(
                matchId: 'match',
                squadId: 'fixture',
                homeScore: 4,
                awayScore: 4,
              ),
            ).called(1);
          } else {
            verify(
              () => roster.execute(
                matchId: 'match',
                homePlayerIds: ['p1'],
                awayPlayerIds: ['p2', 'p3', 'p0'],
              ),
            ).called(1);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
