import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/utils/team_ranking.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/infrastructure/repositories/combinatory_draft_repository.dart';
import 'package:app/features/players/domain/entities/player.dart';

void main() {
  const repository = CombinatoryDraftRepository();

  test('ranking baseline: best first proposal is {1,1,4} vs {2,2,2}', () async {
    final players = [
      _player(id: 'p1', ranking: 1),
      _player(id: 'p2', ranking: 1),
      _player(id: 'p3', ranking: 4),
      _player(id: 'p4', ranking: 2),
      _player(id: 'p5', ranking: 2),
      _player(id: 'p6', ranking: 2),
    ];

    final proposals = await repository.createDraft(
      players: players,
      teamCount: 2,
    );
    expect(proposals, isNotEmpty);

    final first = proposals.first;
    final teamRankings =
        first.teams.map(_sortedRankings).toList(growable: false)
          ..sort((a, b) => _rankingKey(a).compareTo(_rankingKey(b)));

    expect(teamRankings, [
      [1.0, 1.0, 4.0],
      [2.0, 2.0, 2.0],
    ]);
  });

  test(
    'position penalty breaks ties by splitting duplicated positions',
    () async {
      final players = [
        _player(id: 'gk1', ranking: 2, position: 'gk'),
        _player(id: 'gk2', ranking: 2, position: 'gk'),
        _player(id: 'p1', ranking: 2, position: 'fwd'),
        _player(id: 'p2', ranking: 2, position: 'fwd'),
      ];

      final proposals = await repository.createDraft(
        players: players,
        teamCount: 2,
      );
      expect(proposals, isNotEmpty);
      expect(_sameTeam(proposals.first, 'gk1', 'gk2'), isFalse);
    },
  );

  test(
    'together rule: constrained players are together in first result',
    () async {
      final players = _players(6, ranking: 100);

      final proposals = await repository.createDraft(
        players: players,
        teamCount: 2,
        rules: const [
          DraftRule(
            type: DraftRuleType.together,
            playerIds: ['p1', 'p2', 'p3'],
          ),
        ],
      );

      expect(proposals, isNotEmpty);
      expect(_sameTeam(proposals.first, 'p1', 'p2'), isTrue);
      expect(_sameTeam(proposals.first, 'p2', 'p3'), isTrue);
    },
  );

  test(
    'against rule: constrained players are opposite in first result',
    () async {
      final players = _players(6, ranking: 100);

      final proposals = await repository.createDraft(
        players: players,
        teamCount: 2,
        rules: const [
          DraftRule(type: DraftRuleType.against, playerIds: ['p1', 'p2']),
        ],
      );

      expect(proposals, isNotEmpty);
      expect(_sameTeam(proposals.first, 'p1', 'p2'), isFalse);
    },
  );

  test('creates deterministic proposals for multiple teams', () async {
    final players = _players(10);

    final first = await repository.createDraft(players: players, teamCount: 3);
    final second = await repository.createDraft(players: players, teamCount: 3);

    expect(first, isNotEmpty);
    expect(second, isNotEmpty);
    expect(_draftKey(first.first), _draftKey(second.first));

    for (final proposal in first.take(5)) {
      expect(proposal.teams.length, 3);
      expect(_allPlayerIds(proposal).length, 10);
    }

    final teamSizes =
        first.first.teams.map((team) => team.players.length).toList()..sort();
    expect(teamSizes, [3, 3, 4]);
  });

  test('does not reject more than 16 players', () async {
    final players = _players(17, ranking: 50);

    final proposals = await repository.createDraft(
      players: players,
      teamCount: 2,
      limit: 1,
    );

    expect(proposals, isNotEmpty);
    expect(_allPlayerIds(proposals.first).length, 17);
  });

  test(
    'playWithSubstitute affects odd-team ranking analysis in combinatory draft',
    () async {
      final players = [
        _player(id: 'p1', ranking: 120),
        _player(id: 'p2', ranking: 100),
        _player(id: 'p3', ranking: 90),
        _player(id: 'p4', ranking: 80),
        _player(id: 'p5', ranking: 60),
      ];

      final noSubstitute = await repository.createDraft(
        players: players,
        teamCount: 2,
        limit: 1,
        playWithSubstitute: false,
      );
      final withSubstitute = await repository.createDraft(
        players: players,
        teamCount: 2,
        limit: 1,
        playWithSubstitute: true,
      );

      expect(noSubstitute, isNotEmpty);
      expect(withSubstitute, isNotEmpty);

      final noSubFirst = noSubstitute.first;
      final withSubFirst = withSubstitute.first;
      expect(noSubFirst.playWithSubstitute, isFalse);
      expect(withSubFirst.playWithSubstitute, isTrue);

      expect(noSubFirst.homePlayers.length, 3);
      expect(withSubFirst.homePlayers.length, 3);

      // Without substitute adjustment, the best raw split here is 260 vs 190.
      expect(noSubFirst.homeTotalRanking, 260);

      // With substitute adjustment, analysis should prefer 270 vs 180
      // because effective score of larger team becomes 180.
      expect(withSubFirst.homeTotalRanking, 270);

      final effectiveHome = effectiveTeamRanking(
        totalRanking: withSubFirst.homeTotalRanking,
        teamSize: withSubFirst.homePlayers.length,
        opponentTeamSize: withSubFirst.awayPlayers.length,
        playWithSubstitute: true,
      );
      final effectiveAway = effectiveTeamRanking(
        totalRanking: withSubFirst.awayTotalRanking,
        teamSize: withSubFirst.awayPlayers.length,
        opponentTeamSize: withSubFirst.homePlayers.length,
        playWithSubstitute: true,
      );

      expect((effectiveHome - effectiveAway).abs(), closeTo(0, 0.0001));
    },
  );
}

List<Player> _players(int count, {double ranking = 50}) {
  return List<Player>.generate(
    count,
    (index) => _player(
      id: 'p${index + 1}',
      ranking: ranking,
      position: index.isEven ? 'gk' : 'fwd',
    ),
  );
}

Player _player({
  required String id,
  required double ranking,
  String? position,
}) {
  return Player(
    playerId: id,
    squadId: 'squad-1',
    name: id,
    position: position,
    baseRanking: ranking.toInt(),
    ranking: ranking,
    createdAt: DateTime(2025, 1, 1),
  );
}

List<double> _sortedRankings(DraftTeam team) {
  final rankings = team.players.map((p) => p.ranking).toList(growable: false)
    ..sort();
  return rankings;
}

String _rankingKey(List<double> rankings) => rankings.join(',');

String _draftKey(Draft draft) {
  final teams = draft.teams
      .map((team) => team.players.map((p) => p.playerId).toList()..sort())
      .map((ids) => ids.join(','))
      .toList();
  return teams.join('|');
}

Set<String> _allPlayerIds(Draft draft) {
  return draft.teams
      .expand((team) => team.players)
      .map((player) => player.playerId)
      .toSet();
}

bool _sameTeam(Draft draft, String playerA, String playerB) {
  for (final team in draft.teams) {
    final ids = team.players.map((p) => p.playerId).toSet();
    if (ids.contains(playerA) && ids.contains(playerB)) {
      return true;
    }
  }
  return false;
}
