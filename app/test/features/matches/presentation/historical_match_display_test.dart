import 'package:app/features/matches/infrastructure/repositories/supabase_team_repository.dart';
import 'package:app/features/matches/presentation/widgets/match_view_roster.dart';
import 'package:app/features/players/infrastructure/repositories/supabase_player_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../fixtures/historical_match_app.dart';
import '../../../fixtures/historical_match_data.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final unequal in [false, true]) {
    testWidgets(
      'repository → match rows/order/totals survive result, correction, later score; unequal=$unequal',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final data = (await tester.runAsync(
          () async => HistoricalMatchData(unequal: unequal),
        ))!;
        addTearDown(() => tester.runAsync(data.client.dispose));
        await tester.pumpWidget(HistoricalMatchApp(data: data));
        await tester.pumpAndSettle();
        for (var stage = 0; stage < 4; stage++) {
          if (stage > 0) {
            await tester.tap(find.text('Next state'));
            await tester.pumpAndSettle();
          }
          for (var reload = 0; reload < 2; reload++) {
            if (reload > 0) {
              await tester.tap(find.text('Reload'));
              await tester.pumpAndSettle();
            }
            final panels = tester
                .widgetList<MatchViewPlayerPanel>(
                  find.byType(MatchViewPlayerPanel),
                )
                .toList();
            expect(
              panels.map((p) => p.player.playerId),
              unequal
                  ? ['p1', 'p3', 'p0', 'p2', 'p4']
                  : ['p1', 'p3', 'p0', 'p2'],
            );
            for (final panel in panels) {
              expect(
                panel.player.ranking,
                data.snapshots[panel.player.playerId],
              );
              expect(
                find.text(panel.player.ranking.toStringAsFixed(2)),
                findsOneWidget,
              );
            }
            expect(
              find.text(unequal ? 'Ranking: 86.7' : 'Ranking: 100.0'),
              findsOneWidget,
            );
            expect(find.text('Ranking: 120.0'), findsOneWidget);
            final current = (await tester.runAsync(
              () => SupabasePlayerRepository(
                data.client,
              ).getPlayer(playerId: 'p0'),
            ))!;
            expect(current.ranking, [40, 95, 15, 150][stage]);
            expect(data.deltas['p0'], [null, 55, -25, -25][stage]);
            expect(tester.takeException(), isNull);
          }
        }
        final matchReads = data.requests.where(
          (u) =>
              u.path.endsWith('ranking_history') &&
              (u.queryParameters['player_id']?.startsWith('in.') ?? false) &&
              u.queryParameters.containsKey('match_id'),
        );
        expect(matchReads, isNotEmpty);
        expect(
          matchReads.every((u) => u.queryParameters['match_id'] == 'eq.match'),
          isTrue,
        );
      },
    );
  }

  test(
    'preserves current/no-history and team-level tournament fallback, including partial history',
    () async {
      final data = HistoricalMatchData();
      addTearDown(data.client.dispose);
      data.scores['p0'] = 200;
      data.missing.addAll(['p0', 'p1']);
      final repository = SupabaseTeamRepository(data.client);
      Future<List<double>> home() async => (await repository.getMatchTeams(
        'match',
      )).first.players.map((p) => p.ranking).toList();
      expect(await home(), [200, 60]);
      data.tournamentId = 'tournament';
      data.tournamentRanks.addAll({'p0': 12, 'p1': 24, 'p2': 999});
      expect(await home(), [12, 24]);
      final teams = await repository.getMatchTeams('match');
      expect(teams.last.players.map((p) => p.ranking), [50, 70]);
      data.missing.remove('p1');
      // Existing fallback is team-level: a partial match history does not query
      // tournament history for the missing player. Keep that behavior unchanged.
      expect(await home(), [200, 60]);
      data.missing.addAll(['p0', 'p1']);
      data.tournamentRanks.remove('p0');
      expect(await home(), [200, 24]);
    },
  );
}
