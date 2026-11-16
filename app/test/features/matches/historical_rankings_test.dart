import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/global_dependencies.dart';
import 'package:app/core/utils/team_ranking.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/presentation/controllers/draft_session_notifier.dart';
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
  test(
    'legacy proposal and details share per-player match/tournament inputs, not current score',
    () async {
      final backend = SnapshotBackend()..changeCurrentScores();
      backend.tables['matches']!.single['tournament_id'] = 'tournament';
      backend.tables['ranking_history']!.last
        ..['match_id'] = null
        ..['tournament_id'] = 'tournament';
      // A match input must override an older tournament input for p0.
      backend.tables['ranking_history']!.add({
        'player_id': 'p0',
        'match_id': null,
        'tournament_id': 'tournament',
        'ranking': 1.0,
      });
      backend.tables['drafts']!.add({
        'draft_id': 'draft',
        'match_id': 'match',
        'status': 'completed',
        'team_count': 2,
        'proposals_count': 1,
      });
      backend.tables['draft_payloads']!.add({
        'draft_id': 'draft',
        'proposals': [
          {
            'teams': [
              ['p0', 'p1'],
              ['p2', 'p3', 'p4'],
            ],
          },
        ],
        'win_rate_matrix': {},
      });
      final container = ProviderContainer(
        overrides: [supabaseProvider.overrideWithValue(backend.client)],
      );
      addTearDown(() async {
        container.dispose();
        await backend.client.dispose();
      });
      final payload = (await container
          .read(draftPersistenceRepositoryProvider)
          .getMatchDraft(matchId: 'match'))!;
      expect(payload.proposals.single.rankings['p0'], 41.25);
      expect(payload.proposals.single.rankings['p3'], 72.25);
      expect(payload.proposals.single.rankings['p4'], 56.5);
      await container
          .read(draftSessionNotifierProvider.notifier)
          .load(
            squadId: 'fixture',
            selectedPlayerIds: [],
            algorithm: DraftAlgorithm.combinatory,
            matchId: 'match',
          );
      final state = container.read(draftSessionNotifierProvider);
      expect(state.hasError, isFalse);
      expect(state.requireValue.away.last.ranking, 56.5);
      final teams = await container
          .read(teamRepositoryProvider)
          .getMatchTeams('match');
      expect({
        for (final p in teams.expand((team) => team.players))
          p.playerId: p.ranking,
      }, payload.proposals.single.rankings);
    },
  );

  test('no preserved input cannot silently use current score', () async {
    final backend = SnapshotBackend()..changeCurrentScores();
    backend.tables['ranking_history']!.removeAt(0);
    final container = ProviderContainer(
      overrides: [supabaseProvider.overrideWithValue(backend.client)],
    );
    addTearDown(() async {
      container.dispose();
      await backend.client.dispose();
    });
    await expectLater(
      container.read(teamRepositoryProvider).getMatchTeams('match'),
      throwsException,
    );
  });

  test(
    'current-ranking clamps, repeated result and experience factor remain unchanged',
    () async {
      final backend = SnapshotBackend();
      backend.tables['players']!.first['score'] = 99.0;
      backend.tables['players']![2]['score'] = 1.0;
      backend.tables['squads']!.single['use_experience_factor'] = true;
      backend.tables['ranking_history']!.add({
        'ranking_history_id': 'older-p0',
        'match_id': 'older',
        'player_id': 'p0',
        'ranking': 90,
        'change': 1,
        'created_at': SnapshotBackend.date,
      });
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
      final score = container.read(updateMatchScoreUseCaseProvider);
      await score.execute(
        matchId: 'match',
        squadId: 'fixture',
        homeScore: 1,
        awayScore: 0,
      );
      expect(backend.tables['players']!.first['score'], 100);
      expect(backend.tables['players']![2]['score'], 0);
      expect(backend.tables['ranking_history']!.first['change'], 1);
      expect(backend.tables['ranking_history']![2]['change'], -1);
      expect(backend.tables['ranking_history']!.first['ranking'], 41.25);
      await score.execute(
        matchId: 'match',
        squadId: 'fixture',
        homeScore: 1,
        awayScore: 0,
      );
      expect(backend.tables['players']!.first['score'], 100);
      await score.execute(
        matchId: 'match',
        squadId: 'fixture',
        homeScore: 0,
        awayScore: 1,
      );
      expect(backend.tables['players']!.first['score'], 96.5);
      expect(backend.tables['players']![2]['score'], 6);
      expect(backend.tables['ranking_history']!.first['ranking'], 41.25);
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
