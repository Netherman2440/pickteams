import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/global_dependencies.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/matches/application/usecases/update_match_teams_usecase.dart';
import 'package:app/features/matches/infrastructure/repositories/supabase_team_repository.dart';
import 'package:app/features/tournaments/application/usecases/complete_tournament_usecase.dart';
import '../../../fixtures/atomic_roster_backend.dart';
import '../../../fixtures/snapshot_backend.dart';

void main() {
  for (final experience in [false, true]) {
    test(
      'roster RPC preserves completion arithmetic and experience=$experience',
      () async {
        final backend = AtomicRosterBackend();
        final creationInputs = {
          for (final p in backend.tables['players']!)
            p['player_id']: p['score'],
        };
        backend.tables['squads']!.single['use_experience_factor'] = experience;
        backend.tables['tournaments'] = [
          {
            'tournament_id': 'tournament',
            'squad_id': 'fixture',
            'status': 'active',
            'created_at': SnapshotBackend.date,
            'updated_at': SnapshotBackend.date,
          },
        ];
        backend.tables['tournament_teams'] = [
          for (var i = 0; i < 2; i++)
            {
              'tournament_team_id': 't$i',
              'tournament_id': 'tournament',
              'created_at': SnapshotBackend.date,
            },
        ];
        backend.tables['tournament_team_players'] = [
          for (var i = 0; i < 5; i++)
            {
              'tournament_team_id': i < 2 ? 't0' : 't1',
              'tournament_id': 'tournament',
              'player_id': 'p$i',
            },
        ];
        for (final row in backend.tables['ranking_history']!) {
          row['match_id'] = null;
          row['tournament_id'] = 'tournament';
        }
        backend.tables['ranking_history']!.addAll([
          for (final p in backend.tables['players']!)
            for (var i = 0; i < 2; i++)
              {
                'ranking_history_id': 'old$i-${p['player_id']}',
                'player_id': p['player_id'],
                'match_id': 'old$i',
                'ranking': 50.0,
                'change': 1.0,
                'created_at': SnapshotBackend.date,
              },
        ]);
        final match = backend.tables['matches']!.single;
        match['tournament_id'] = 'tournament';
        match['score_meta'] = {
          'draft_rankings': creationInputs,
          'tournament_home_team_id': 't0',
          'tournament_away_team_id': 't1',
        };
        backend.changeCurrentScores();
        final container = ProviderContainer(
          overrides: [
            supabaseProvider.overrideWithValue(backend.client),
            authStateProvider.overrideWith(_FixtureAuth.new),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await backend.client.dispose();
        });
        final edit = container.read(updateMatchTeamsUseCaseProvider);
        await edit.execute(
          matchId: 'match',
          homePlayerIds: ['p1'],
          awayPlayerIds: ['p2', 'p3', 'p4'],
        );
        await edit.execute(
          matchId: 'match',
          homePlayerIds: ['p0', 'p1'],
          awayPlayerIds: ['p2', 'p3', 'p4'],
        );
        expect(backend.tables['ranking_history']!.length, 15);
        expect((match['score_meta']['draft_rankings'] as Map)['p0'], 90);
        match['home_score'] = 2;
        match['away_score'] = 1;
        final complete = container.read(completeTournamentUseCaseProvider);
        await complete.execute(tournamentId: 'tournament');
        final delta = experience
            ? 2.75
            : 5.5; // (1 win + 1/10 goals) * 5 / two regular matches.
        expect(backend.tables['players']![0]['score'], 90 + delta);
        expect(backend.tables['players']![1]['score'], 20 + delta);
        expect(backend.tables['players']![2]['score'], 40 - delta);
        final creation = backend.tables['ranking_history']!
            .where((r) => r['tournament_id'] == 'tournament')
            .toList();
        expect(creation.first['change'], delta);
        expect(creation[2]['change'], -delta);
        expect(creation.first['ranking'], 41.25);
        expect(backend.tables['ranking_history']!.length, 15);
        await complete.execute(tournamentId: 'tournament');
        expect(backend.tables['players']![0]['score'], 90 + delta);
        final teams = await SupabaseTeamRepository(
          backend.client,
        ).getMatchTeams('match');
        expect(teams.first.players.first.ranking, 90);
        expect(teams.last.players.first.ranking, 38.5);
      },
    );
  }
}

class _FixtureAuth extends AuthNotifier {
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
