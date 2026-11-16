import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'preserved_rankings.dart';
import 'package:app/core/error/supabase_error_extension.dart';
import 'package:app/features/matches/domain/entities/team.dart';
import 'package:app/features/matches/domain/repositories/team_repository.dart';
import 'package:app/features/players/domain/entities/player.dart';

class SupabaseTeamRepository implements TeamRepository {
  final SupabaseClient _supabase;
  final Logger _logger = Logger('SupabaseTeamRepository');

  SupabaseTeamRepository(this._supabase);

  @override
  Future<List<Team>> getMatchTeams(String matchId) async {
    try {
      final preservedRankings = await loadPreservedRankings(
        _supabase,
        matchId: matchId,
      );

      // 1. Fetch Teams
      final teamsResponse = await _supabase
          .from('teams')
          .select()
          .eq('match_id', matchId);

      final List<dynamic> teamsData = teamsResponse as List<dynamic>;
      List<Team> teams = teamsData
          .map((row) => Team.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();

      // 2. For each team, fetch players
      List<Team> teamsWithPlayers = [];
      for (var team in teams) {
        // Fetch team_players
        final teamPlayersResponse = await _supabase
            .from('team_players')
            .select('player_id')
            .eq('match_id', matchId)
            .eq('team_id', team.teamId);

        final List<dynamic> teamPlayersData =
            teamPlayersResponse as List<dynamic>;
        if (teamPlayersData.isEmpty) {
          teamsWithPlayers.add(team);
          continue;
        }

        final playerIds = teamPlayersData
            .map((tp) => tp['player_id'] as String)
            .toList();

        // Fetch players details
        final playersResponse = await _supabase
            .from('players')
            .select()
            .inFilter('player_id', playerIds);

        final List<dynamic> playersData = playersResponse as List<dynamic>;
        final players = playersData
            .map((row) => Player.fromMap(Map<String, dynamic>.from(row as Map)))
            .toList();

        final playersWithHistory = players.map((player) {
          final ranking = preservedRankings[player.playerId];
          if (ranking == null || !ranking.isFinite) {
            throw StateError(
              'Missing preserved ranking for match $matchId, player ${player.playerId}',
            );
          }
          return player.copyWith(ranking: ranking);
        }).toList();

        teamsWithPlayers.add(team.copyWith(players: playersWithHistory));
      }
      return teamsWithPlayers;
    } catch (e, stack) {
      _logger.severe('Failed to fetch teams for match $matchId', e, stack);
      throw e.toFailure();
    }
  }

  @override
  Future<Team> getTeam({
    required String teamId,
    required String matchId,
  }) async {
    // Implementation for single team if needed, or reuse getMatchTeams logic
    final teams = await getMatchTeams(matchId);
    return teams.firstWhere((t) => t.teamId == teamId);
  }

  @override
  Future<void> createTeams({
    required String matchId,
    required Team homeTeam,
    required Team awayTeam,
    String? tournamentId,
  }) async {
    final homeTeamId = const Uuid().v4();
    final awayTeamId = const Uuid().v4();
    final now = DateTime.now().toUtc();

    // 1. Insert Teams
    final homeTeamData = {
      'team_id': homeTeamId,
      'match_id': matchId,
      'side': 'home',
      'name': homeTeam.name,
      'color': homeTeam.color,
      'created_at': now.toIso8601String(),
    };
    final awayTeamData = {
      'team_id': awayTeamId,
      'match_id': matchId,
      'side': 'away',
      'name': awayTeam.name,
      'color': awayTeam.color,
      'created_at': now.toIso8601String(),
    };

    await _supabase.from('teams').insert([homeTeamData, awayTeamData]);

    // 2. Insert Team Players
    final List<Map<String, dynamic>> teamPlayersRows = [];

    for (final player in homeTeam.players) {
      teamPlayersRows.add({
        'match_id': matchId,
        'team_id': homeTeamId,
        'player_id': player.playerId,
        'tournament_id': tournamentId,
        'created_at': now.toIso8601String(),
      });
    }
    for (final player in awayTeam.players) {
      teamPlayersRows.add({
        'match_id': matchId,
        'team_id': awayTeamId,
        'player_id': player.playerId,
        'tournament_id': tournamentId,
        'created_at': now.toIso8601String(),
      });
    }

    if (teamPlayersRows.isNotEmpty) {
      await _supabase.from('team_players').insert(teamPlayersRows);
    }
  }

  @override
  Future<void> updateMatchTeams({
    required String matchId,
    required List<String> homePlayerIds,
    required List<String> awayPlayerIds,
  }) async {
    try {
      final teamsResponse = await _supabase
          .from('teams')
          .select('team_id, side')
          .eq('match_id', matchId);

      final teamsData = teamsResponse as List<dynamic>;
      final homeTeamId =
          teamsData.firstWhere((t) => t['side'] == 'home')['team_id'] as String;
      final awayTeamId =
          teamsData.firstWhere((t) => t['side'] == 'away')['team_id'] as String;

      await _supabase.from('team_players').delete().eq('match_id', matchId);

      final List<Map<String, dynamic>> teamPlayersRows = [];
      final now = DateTime.now().toUtc();

      for (final pid in homePlayerIds) {
        teamPlayersRows.add({
          'match_id': matchId,
          'team_id': homeTeamId,
          'player_id': pid,
          'created_at': now.toIso8601String(),
        });
      }
      for (final pid in awayPlayerIds) {
        teamPlayersRows.add({
          'match_id': matchId,
          'team_id': awayTeamId,
          'player_id': pid,
          'created_at': now.toIso8601String(),
        });
      }

      if (teamPlayersRows.isNotEmpty) {
        await _supabase.from('team_players').insert(teamPlayersRows);
      }
    } catch (e, stack) {
      _logger.severe('Failed to update teams for match $matchId', e, stack);
      throw e.toFailure();
    }
  }

  @override
  Future<Team> updateTeam({
    required String matchId,
    required String teamId,
    String? name,
    String? color,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (color != null) updates['color'] = color;

      if (updates.isEmpty) {
        return await getTeam(teamId: teamId, matchId: matchId);
      }

      await _supabase
          .from('teams')
          .update(updates)
          .eq('team_id', teamId)
          .eq('match_id', matchId);

      return await getTeam(teamId: teamId, matchId: matchId);
    } catch (e, stack) {
      _logger.severe('Failed to update team $teamId', e, stack);
      throw e.toFailure();
    }
  }
}
