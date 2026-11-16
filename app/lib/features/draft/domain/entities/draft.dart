import 'package:app/features/players/domain/entities/player.dart';

class DraftTeam {
  final int index;
  final List<Player> players;
  final double totalRanking;

  const DraftTeam({
    required this.index,
    required this.players,
    required this.totalRanking,
  });
}

class Draft {
  final List<DraftTeam> teams;
  final bool playWithSubstitute;

  const Draft({required this.teams, this.playWithSubstitute = true});

  Map<String, dynamic> toStoredProposal() => {
    'teams': [
      for (final team in teams) team.players.map((p) => p.playerId).toList(),
    ],
    'rankings': {
      for (final team in teams)
        for (final player in team.players) player.playerId: player.ranking,
    },
    'play_with_substitute': playWithSubstitute,
  };

  factory Draft.twoTeams({
    required List<Player> homePlayers,
    required List<Player> awayPlayers,
    required double homeTotalRanking,
    required double awayTotalRanking,
    bool playWithSubstitute = true,
  }) {
    return Draft(
      playWithSubstitute: playWithSubstitute,
      teams: [
        DraftTeam(
          index: 0,
          players: homePlayers,
          totalRanking: homeTotalRanking,
        ),
        DraftTeam(
          index: 1,
          players: awayPlayers,
          totalRanking: awayTotalRanking,
        ),
      ],
    );
  }

  List<Player> get homePlayers =>
      teams.isNotEmpty ? teams.first.players : const <Player>[];
  List<Player> get awayPlayers =>
      teams.length > 1 ? teams[1].players : const <Player>[];
  double get homeTotalRanking =>
      teams.isNotEmpty ? teams.first.totalRanking : 0.0;
  double get awayTotalRanking => teams.length > 1 ? teams[1].totalRanking : 0.0;
}
