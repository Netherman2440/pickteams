import 'package:flutter/material.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';

import 'player_lists_app.dart';

List<Player> lineupPlayers(int count, {bool longNames = false}) => [
  for (final player in fixturePlayers.take(count * 2))
    Player(
      playerId: player.playerId,
      squadId: player.squadId,
      name: longNames
          ? '${player.name} Aleksander Długie-Nazwisko'
          : player.name,
      baseRanking: player.baseRanking,
      ranking: player.ranking,
      createdAt: player.createdAt,
    ),
];

Widget lineupFixture({
  String page = 'match',
  int count = 8,
  double scale = 1,
  bool longNames = false,
  bool savedScore = true,
  SquadRole role = SquadRole.owner,
}) {
  final players = lineupPlayers(count, longNames: longNames);
  return PlayerListsFixture(
    page: page,
    role: role,
    players: players,
    textScale: scale,
    match: fixtureMatch(
      homeScore: savedScore ? 14 : null,
      awayScore: savedScore ? 5 : null,
      homeIds: players.take(count).map((p) => p.playerId).toList(),
      awayIds: players.skip(count).map((p) => p.playerId).toList(),
      players: players,
    ),
  );
}
