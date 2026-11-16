import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/global_dependencies.dart';
import 'package:app/features/matches/application/usecases/update_match_teams_usecase.dart';
import 'package:app/features/matches/infrastructure/repositories/preserved_rankings.dart';
import 'package:app/features/draft/infrastructure/repositories/supabase_draft_persistence_repository.dart';
import 'package:app/features/matches/infrastructure/repositories/supabase_team_repository.dart';
import '../../../fixtures/snapshot_backend.dart';

void main() {
  test(
    'new substitute metadata is required; legacy default stays explicit in the contract',
    () {
      expect(resolveProposalSubstitutes({}), isTrue);
      for (final option in [false, true]) {
        expect(
          resolveProposalSubstitutes({
            'rankings': {'p': 41.25},
            'play_with_substitute': option,
          }),
          option,
        );
      }
      for (final proposal in <Map<String, dynamic>>[
        {
          'rankings': {'p': 41.25},
        },
        {
          'rankings': {'p': 41.25},
          'play_with_substitute': null,
        },
        {'play_with_substitute': 'false'},
        {'play_with_substitute': null},
      ]) {
        expect(() => resolveProposalSubstitutes(proposal), throwsStateError);
      }
    },
  );
  test(
    'tournament match transfer/remove/re-add updates the vector without history events',
    () async {
      final backend = SnapshotBackend();
      final inputs = {
        for (final row in backend.tables['players']!)
          row['player_id'] as String: (row['score'] as num).toDouble(),
      };
      backend.tables['matches']!.single['score_meta'] = {
        'draft_rankings': inputs,
        'tournament_home_team_id': 't0',
      };
      backend.tables['matches']!.single['tournament_id'] = 'tournament';
      backend.tables['ranking_history']!.clear();
      backend.changeCurrentScores();
      final container = ProviderContainer(
        overrides: [supabaseProvider.overrideWithValue(backend.client)],
      );
      addTearDown(() async {
        container.dispose();
        await backend.client.dispose();
      });
      final update = container.read(updateMatchTeamsUseCaseProvider);
      Map<dynamic, dynamic> storedInputs() =>
          backend.tables['matches']!.single['score_meta']['draft_rankings']
              as Map;
      await update.execute(
        matchId: 'match',
        homePlayerIds: ['p1'],
        awayPlayerIds: ['p0', 'p2', 'p3', 'p4'],
      );
      expect(storedInputs()['p0'], 41.25);
      await update.execute(
        matchId: 'match',
        homePlayerIds: ['p1'],
        awayPlayerIds: ['p2', 'p3', 'p4'],
      );
      expect(storedInputs().containsKey('p0'), isFalse);
      await update.execute(
        matchId: 'match',
        homePlayerIds: ['p0', 'p1'],
        awayPlayerIds: ['p2', 'p3', 'p4'],
      );
      expect(storedInputs()['p0'], 90);
      expect(
        backend
            .tables['matches']!
            .single['score_meta']['tournament_home_team_id'],
        't0',
      );
      expect(backend.tables['ranking_history'], isEmpty);
      final teams = await SupabaseTeamRepository(
        backend.client,
      ).getMatchTeams('match');
      expect(teams.first.players.first.ranking, 90);
      backend.tables['matches']!.single['home_score'] = 1;
      await expectLater(
        update.execute(
          matchId: 'match',
          homePlayerIds: [],
          awayPlayerIds: ['p0'],
        ),
        throwsException,
      );
    },
  );
  test(
    'new match metadata is authoritative for details and legacy proposals',
    () async {
      final backend = SnapshotBackend()..changeCurrentScores();
      addTearDown(backend.client.dispose);
      backend.tables['drafts']!.add({'draft_id': 'draft', 'match_id': 'match'});
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
      });
      final inputs = {
        for (final row in backend.tables['players']!)
          row['player_id'] as String: (row['score'] as num).toDouble(),
      };
      backend.tables['matches']!.single['score_meta'] = {
        'draft_rankings': inputs,
      };
      final persistence = SupabaseDraftPersistenceRepository(backend.client);
      final teams = SupabaseTeamRepository(backend.client);
      expect(
        (await persistence.getMatchDraft(
          matchId: 'match',
        ))!.proposals.single.rankings,
        inputs,
      );
      expect({
        for (final p in (await teams.getMatchTeams(
          'match',
        )).expand((t) => t.players))
          p.playerId: p.ranking,
      }, inputs);
      inputs.remove('p4');
      await expectLater(
        persistence.getMatchDraft(matchId: 'match'),
        throwsException,
      );
      await expectLater(teams.getMatchTeams('match'), throwsException);
      backend.tables['matches']!.single['score_meta'] = {
        'draft_rankings': null,
      };
      await expectLater(teams.getMatchTeams('match'), throwsException);
    },
  );
  test('legacy IDs use history; complete new scores override history', () {
    expect(
      resolveProposalRankings(
        proposal: {},
        playerIds: ['p'],
        preservedRankings: {'p': 41.25},
      ),
      {'p': 41.25},
    );
    expect(
      resolveProposalRankings(
        proposal: {
          'rankings': {'p': 90},
        },
        playerIds: ['p'],
        preservedRankings: {'p': 41.25},
      ),
      {'p': 90.0},
    );
  });
  for (final raw in [
    null,
    'bad',
    {},
    {'p': '90'},
    {'p': double.nan},
    {'p': double.infinity},
  ]) {
    test('malformed explicit rankings fail without mixing history: $raw', () {
      expect(
        () => resolveProposalRankings(
          proposal: {'rankings': raw},
          playerIds: ['p'],
          preservedRankings: {'p': 41.25},
        ),
        throwsStateError,
      );
    });
  }
  test('partial new scores do not merge with history', () {
    expect(
      () => resolveProposalRankings(
        proposal: {
          'rankings': {'p': 90},
        },
        playerIds: ['p', 'q'],
        preservedRankings: {'p': 41.25, 'q': 56.5},
      ),
      throwsStateError,
    );
  });
  test(
    'absent legacy input fails in repository, not current-score fallback',
    () async {
      final backend = SnapshotBackend()..changeCurrentScores();
      addTearDown(backend.client.dispose);
      backend.tables['ranking_history']!.clear();
      backend.tables['drafts']!.add({'draft_id': 'draft', 'match_id': 'match'});
      backend.tables['draft_payloads']!.add({
        'draft_id': 'draft',
        'proposals': [
          {
            'teams': [
              ['p0'],
              ['p1'],
            ],
          },
        ],
      });
      await expectLater(
        SupabaseDraftPersistenceRepository(
          backend.client,
        ).getMatchDraft(matchId: 'match'),
        throwsException,
      );
    },
  );
}
