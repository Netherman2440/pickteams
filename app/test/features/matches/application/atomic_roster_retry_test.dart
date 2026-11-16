import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/global_dependencies.dart';
import 'package:app/features/matches/application/usecases/update_match_teams_usecase.dart';
import 'package:app/features/matches/infrastructure/repositories/supabase_team_repository.dart';
import '../../../fixtures/atomic_roster_backend.dart';

void main() {
  late AtomicRosterBackend backend;
  late ProviderContainer container;
  late UpdateMatchTeamsUseCase update;
  setUp(() {
    backend = AtomicRosterBackend();
    backend.tables['team_players']!.removeWhere(
      (r) => ['p0', 'p2'].contains(r['player_id']),
    );
    backend.tables['ranking_history']!.clear();
    backend.tables['matches']!.single['tournament_id'] = 'tournament';
    backend.tables['matches']!.single['score_meta'] = {
      'draft_rankings': {
        for (final row in backend.tables['players']!)
          if (!['p0', 'p2'].contains(row['player_id']))
            row['player_id']: row['score'],
      },
      'tournament_home_team_id': 't0',
      'unrelated': {'keep': true},
    };
    backend.changeCurrentScores();
    container = ProviderContainer(
      overrides: [supabaseProvider.overrideWithValue(backend.client)],
    );
    update = container.read(updateMatchTeamsUseCaseProvider);
  });
  tearDown(() async {
    container.dispose();
    await backend.client.dispose();
  });
  Future<void> add() => update.execute(
    matchId: 'match',
    homePlayerIds: ['p0', 'p1'],
    awayPlayerIds: ['p2', 'p3', 'p4'],
  );
  Map<dynamic, dynamic> vector() =>
      backend.tables['matches']!.single['score_meta']['draft_rankings'] as Map;
  Future<void> readable() async {
    final teams = await SupabaseTeamRepository(
      backend.client,
    ).getMatchTeams('match');
    expect(
      teams.expand((t) => t.players).length,
      backend.tables['team_players']!.length,
    );
  }

  test(
    'failed atomic write leaves old roster readable; retry freezes both addition inputs',
    () async {
      backend.failBeforeCommit = true;
      final before = jsonEncode(backend.tables['team_players']);
      await expectLater(add(), throwsException);
      expect(jsonEncode(backend.tables['team_players']), before);
      expect(vector().containsKey('p0'), isFalse);
      await readable();
      final request = jsonEncode(backend.commands.single);
      for (final p in backend.tables['players']!) {
        p['score'] = 12.0;
      }
      await add();
      expect(jsonEncode(backend.commands.last), request);
      expect(vector()['p0'], 90);
      expect(vector()['p2'], 40);
      expect(vector()['p1'], 63.75);
      await readable();
      expect(backend.tables['ranking_history'], isEmpty);
      expect(backend.tables['matches']!.single['score_meta']['unrelated'], {
        'keep': true,
      });
      expect(backend.tables['teams']!.map((t) => t['color']), [
        '#FFFFFF',
        '#000000',
      ]);
      expect(
        backend.requests.where(
          (r) => r.startsWith('PATCH') || r.startsWith('DELETE'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'lost response replay sends the identical request without re-reading scores, even after result',
    () async {
      backend.loseReply = true;
      await expectLater(add(), throwsException);
      await readable();
      final request = jsonEncode(backend.commands.single);
      final committed = jsonEncode(backend.tables['team_players']);
      backend.tables['matches']!.single['home_score'] = 1;
      for (final p in backend.tables['players']!) {
        p['score'] = 12.0;
      }
      final reads = backend.requests.where((r) => r.startsWith('GET')).length;
      await add();
      expect(backend.requests.where((r) => r.startsWith('GET')).length, reads);
      expect(jsonEncode(backend.commands.last), request);
      expect(jsonEncode(backend.tables['team_players']), committed);
      expect(vector()['p0'], 90);
      expect(backend.tables['ranking_history'], isEmpty);
    },
  );

  test('score arriving after client read rejects the whole edit', () async {
    backend.beforeRpc = () {
      backend.tables['matches']!.single['home_score'] = 1;
    };
    final before = jsonEncode(backend.tables['team_players']);
    await expectLater(add(), throwsException);
    expect(jsonEncode(backend.tables['team_players']), before);
    expect(vector().containsKey('p0'), isFalse);
    await readable();
  });
}
