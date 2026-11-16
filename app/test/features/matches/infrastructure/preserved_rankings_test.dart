import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/matches/infrastructure/repositories/preserved_rankings.dart';
import 'package:app/features/draft/infrastructure/repositories/supabase_draft_persistence_repository.dart';
import '../../../fixtures/snapshot_backend.dart';

void main() {
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
