import 'package:app/features/matches/application/dto/match_details_dto.dart';
import 'package:app/features/matches/domain/entities/match_enums.dart';
import 'package:app/features/matches/presentation/controllers/match_details_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lineup_app.dart';
import 'player_lists_app.dart';

void main() {
  test(
    'fixture updates retain full historical identity and match settings',
    () async {
      final players = lineupPlayers(11, longNames: true, wideRankings: true);
      final base = fixtureMatch(
        players: players,
        homeIds: players.take(11).map((p) => p.playerId).toList(),
        awayIds: players.skip(11).map((p) => p.playerId).toList(),
      );
      final initial = MatchDetailsDto(
        matchId: 'custom-match',
        squadId: 'custom-squad',
        tournamentId: 'tournament',
        createdAt: DateTime(2026, 3, 7),
        homeTeam: base.homeTeam,
        awayTeam: base.awayTeam,
        homeWinProbability: .73,
        scoreType: MatchScoreType.penalties,
        scoreMeta: const {'winner': 'home'},
        homeScore: 2,
        awayScore: 1,
      );
      final container = ProviderContainer(
        overrides: [
          matchDetailsProvider.overrideWith(
            () => FixtureMatch(initial: initial),
          ),
        ],
      );
      addTearDown(container.dispose);
      final provider = matchDetailsProvider('custom-match');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final notifier = container.read(provider.notifier);
      await notifier.updateScore('custom-squad', 17, 6);
      final saved = container.read(provider).requireValue;
      expect(saved.homeScore, 17);
      expect(saved.awayScore, 6);
      expect(saved.homeTeam, same(initial.homeTeam));
      expect(saved.awayTeam, same(initial.awayTeam));
      expect(saved.matchId, initial.matchId);
      expect(saved.squadId, initial.squadId);
      expect(saved.createdAt, initial.createdAt);
      expect(saved.tournamentId, initial.tournamentId);
      expect(saved.homeWinProbability, initial.homeWinProbability);
      expect(saved.scoreType, initial.scoreType);
      expect(saved.scoreMeta, same(initial.scoreMeta));
      final home = saved.homeTeam!.players;
      final away = saved.awayTeam!.players;
      await notifier.updateTeamsMeta(
        homeTeamId: saved.homeTeam!.teamId,
        awayTeamId: saved.awayTeam!.teamId,
        homeName: 'Updated home',
        homeColor: '#00897B',
      );
      await notifier.updateTeams(
        home.skip(1).map((p) => p.playerId).toList(),
        [...away, home.first].map((p) => p.playerId).toList(),
      );
      final moved = container.read(provider).requireValue;
      expect(moved.homeTeam!.name, 'Updated home');
      expect(moved.homeTeam!.color, '#00897B');
      expect(moved.awayTeam!.name, saved.awayTeam!.name);
      expect(moved.awayTeam!.color, saved.awayTeam!.color);
      expect(moved.homeTeam!.players, orderedEquals(home.skip(1)));
      expect(moved.awayTeam!.players, orderedEquals([...away, home.first]));
      expect(moved.homeScore, 17);
      expect(moved.awayScore, 6);
      expect(moved.homeWinProbability, .73);
      expect(moved.scoreMeta, same(initial.scoreMeta));
    },
  );
}
