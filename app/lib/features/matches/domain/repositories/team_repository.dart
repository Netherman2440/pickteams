import 'package:app/features/matches/domain/entities/team.dart';

abstract class TeamRepository {
  Future<List<Team>> getMatchTeams(String matchId);

  Future<Team> getTeam({required String teamId, required String matchId});

  Future<void> createTeams({
    required String matchId,
    required Team homeTeam,
    required Team awayTeam,
    String? tournamentId,
  });

  Future<void> updateMatchTeams({
    required String matchId,
    required List<String> homePlayerIds,
    required List<String> awayPlayerIds,
  });

  Future<void> updatePreservedMatchRoster({
    required String matchId,
    required String requestId,
    required List<String> homePlayerIds,
    required List<String> awayPlayerIds,
    required Map<String, double> rankings,
    required String? expectedVersion,
  });

  Future<Team> updateTeam({
    required String matchId,
    required String teamId,
    String? name,
    String? color,
  });
}
