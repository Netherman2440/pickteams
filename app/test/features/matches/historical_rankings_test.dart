import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/global_dependencies.dart';
import 'package:app/core/utils/team_ranking.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/infrastructure/repositories/supabase_draft_persistence_repository.dart';
import 'package:app/features/matches/application/usecases/get_match_usecase.dart';
import 'package:app/features/matches/application/usecases/update_match_score_usecase.dart';
import 'package:app/features/matches/application/usecases/update_match_teams_usecase.dart';
import 'package:app/features/matches/matches_providers.dart';
import 'package:app/features/players/players_providers.dart';
import '../../fixtures/snapshot_backend.dart';

void main() {
  setUp(() {
    final subscription = Logger.root.onRecord.listen((record) {
      if (record.level >= Level.SEVERE) {
        printOnFailure('${record.error}\n${record.stackTrace}');
      }
    });
    addTearDown(subscription.cancel);
  });
  for (final count in [4, 5]) {
    for (final substitutes in [false, true]) {
      test(
        'reload/result/correction/later match: $count players, substitutes=$substitutes',
        () async {
          final backend = SnapshotBackend(
            count: count,
            substitutes: substitutes,
          );
          final container = ProviderContainer(
            overrides: [
              supabaseProvider.overrideWithValue(backend.client),
              authStateProvider.overrideWith(SnapshotAuth.new),
            ],
          );
          addTearDown(() async {
            container.dispose();
            await backend.client.dispose();
          });
          final players = await container
              .read(playerRepositoryProvider)
              .getSquadPlayers(squadId: 'fixture');
          final draft = Draft.twoTeams(
            homePlayers: players.take(2).toList(),
            awayPlayers: players.skip(2).toList(),
            homeTotalRanking: 105,
            awayTotalRanking: count == 4 ? 110.75 : 167.25,
            playWithSubstitute: substitutes,
          );
          final persistence = container.read(
            draftPersistenceRepositoryProvider,
          );
          await persistence.upsertCompletedDraft(
            squadId: 'fixture',
            matchId: 'match',
            proposals: [draft],
            winRateMatrix: {},
            teamCount: 2,
          );
          backend.changeCurrentScores();
          final stored = (await persistence.getMatchDraft(matchId: 'match'))!;
          expect(
            stored.proposals.single.rankings,
            draft.toStoredProposal()['rankings'],
          );
          expect(stored.proposals.single.playWithSubstitute, substitutes);
          final getMatch = container.read(getMatchUseCaseProvider);
          final before = await getMatch.execute(matchId: 'match');
          final expected = [for (final p in players) p.ranking];
          Future<void> verifyHistorical() async {
            final match = await getMatch.execute(matchId: 'match');
            expect(
              [
                ...match.homeTeam!.players,
                ...match.awayTeam!.players,
              ].map((p) => p.ranking),
              expected,
            );
            expect(match.playWithSubstitute, substitutes);
            final sum = match.awayTeam!.players.fold(
              0.0,
              (sum, p) => sum + p.ranking,
            );
            expect(
              effectiveTeamRanking(
                totalRanking: sum,
                teamSize: count - 2,
                opponentTeamSize: 2,
                playWithSubstitute: match.playWithSubstitute!,
              ),
              count == 4 ? 110.75 : (substitutes ? 111.5 : 167.25),
            );
          }

          await verifyHistorical();
          final score = container.read(updateMatchScoreUseCaseProvider);
          await score.execute(
            matchId: 'match',
            squadId: 'fixture',
            homeScore: 1,
            awayScore: 0,
          );
          expect(backend.tables['players']!.first['score'], 95);
          await verifyHistorical();
          await score.execute(
            matchId: 'match',
            squadId: 'fixture',
            homeScore: 0,
            awayScore: 1,
          );
          expect(backend.tables['players']!.first['score'], 85);
          await verifyHistorical();
          // A subsequent match uses B, then applies a delta to current score only.
          backend.tables['matches']!.add({
            ...backend.tables['matches']!.first,
            'match_id': 'later',
            'home_score': null,
            'away_score': null,
          });
          backend.tables['teams']!.addAll([
            for (final t in [...backend.tables['teams']!])
              {...t, 'match_id': 'later', 'team_id': '${t['team_id']}-later'},
          ]);
          backend.tables['team_players']!.addAll([
            for (final t in [...backend.tables['team_players']!])
              {...t, 'match_id': 'later', 'team_id': '${t['team_id']}-later'},
          ]);
          backend.tables['ranking_history']!.addAll([
            for (final p in backend.tables['players']!)
              {
                'ranking_history_id': 'later-${p['player_id']}',
                'match_id': 'later',
                'player_id': p['player_id'],
                'ranking': p['score'],
                'change': null,
                'created_at': SnapshotBackend.date,
              },
          ]);
          await score.execute(
            matchId: 'later',
            squadId: 'fixture',
            homeScore: 2,
            awayScore: 0,
          );
          expect(backend.tables['players']!.first['score'], 95);
          await verifyHistorical();
          expect(before.homeTeam!.players.first.ranking, 41.25);
          await expectLater(
            container
                .read(updateMatchTeamsUseCaseProvider)
                .execute(
                  matchId: 'match',
                  homePlayerIds: ['p0'],
                  awayPlayerIds: ['p1'],
                ),
            throwsException,
          );
        },
      );
    }
  }

  test(
    'match transfer preserves A; remove/re-add records a new addition input',
    () async {
      final backend = SnapshotBackend();
      final container = ProviderContainer(
        overrides: [supabaseProvider.overrideWithValue(backend.client)],
      );
      addTearDown(() async {
        container.dispose();
        await backend.client.dispose();
      });
      backend.changeCurrentScores();
      final update = container.read(updateMatchTeamsUseCaseProvider);
      await update.execute(
        matchId: 'match',
        homePlayerIds: ['p1'],
        awayPlayerIds: ['p0', 'p2', 'p3', 'p4'],
      );
      expect(backend.tables['ranking_history']!.first['ranking'], 41.25);
      await update.execute(
        matchId: 'match',
        homePlayerIds: ['p1'],
        awayPlayerIds: ['p2', 'p3', 'p4'],
      );
      expect(
        backend.tables['ranking_history']!.where((r) => r['player_id'] == 'p0'),
        isEmpty,
      );
      await update.execute(
        matchId: 'match',
        homePlayerIds: ['p0', 'p1'],
        awayPlayerIds: ['p2', 'p3', 'p4'],
      );
      expect(
        backend.tables['ranking_history']!.singleWhere(
          (r) => r['player_id'] == 'p0',
        )['ranking'],
        90,
      );
      expect(
        (await container.read(teamRepositoryProvider).getMatchTeams('match'))
            .first
            .players
            .first
            .ranking,
        90,
      );
    },
  );
}

class SnapshotAuth extends AuthNotifier {
  @override
  AsyncValue<AuthEntity?> build() => AsyncData(
    AuthEntity(
      accessToken: 'fixture',
      refreshToken: 'fixture',
      userId: 'owner',
      isAnonymous: false,
      email: 'owner@example.test',
    ),
  );
}
