import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/entities/match_enums.dart';
import 'package:app/features/matches/domain/entities/team.dart';

abstract class MatchRepository {
  Future<List<Match>> getSquadMatches({required String squadId});

  Future<Match> getMatch({required String matchId});

  Future<List<Match>> getMatches({required List<String> matchIds});

  Future<Match> createMatch({
    required String squadId,
    String? tournamentId,
    Map<String, dynamic>? scoreMeta,
    bool? playWithSubstitute,
    required Team homeTeam,
    required Team awayTeam,
  });

  Future<void> deleteMatch({required String matchId});

  Future<Match> updateMatchScore({
    required String matchId,
    MatchScoreType? scoreType,
    int? homeScore,
    int? awayScore,
    Map<String, dynamic>? scoreMeta,
  });

  Future<Match> updateMatchTeams({
    required String matchId,
    required List<String> homePlayerIds,
    required List<String> awayPlayerIds,
  });

  Future<Team> updateTeam({
    required String matchId,
    required String teamId,
    String? name,
    String? color,
  });

  Future<double?> refreshMatchWinProbability({required String matchId});
}
