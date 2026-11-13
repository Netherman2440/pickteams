import 'package:flutter/material.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';

import 'player_lists_app.dart';

List<Player> lineupPlayers(
  int count, {
  bool longNames = false,
  bool wideRankings = false,
}) => [
  for (final player in fixturePlayers.take(count * 2))
    Player(
      playerId: player.playerId,
      squadId: player.squadId,
      name: longNames
          ? '${player.name} Aleksander Długie-Nazwisko'
          : player.name,
      baseRanking: player.baseRanking,
      ranking: wideRankings
          ? (player == fixturePlayers.first ? 105.25 : 9.90) + 10.125
          : player.ranking,
      createdAt: player.createdAt,
    ),
];

Widget lineupFixture({
  String page = 'match',
  int count = 8,
  double scale = 1,
  bool longNames = false,
  bool savedScore = true,
  bool wideRankings = false,
  bool guest = false,
  int? awayCount,
  SquadRole role = SquadRole.owner,
}) {
  final players = lineupPlayers(
    count,
    longNames: longNames,
    wideRankings: wideRankings,
  );
  return PlayerListsFixture(
    page: page,
    role: role,
    guest: guest,
    players: players,
    textScale: scale,
    match: fixtureMatch(
      homeScore: savedScore ? 14 : null,
      awayScore: savedScore ? 5 : null,
      homeIds: players.take(count).map((p) => p.playerId).toList(),
      awayIds: players
          .skip(count)
          .take(awayCount ?? count)
          .map((p) => p.playerId)
          .toList(),
      players: players,
    ),
  );
}
