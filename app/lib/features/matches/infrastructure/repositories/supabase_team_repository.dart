import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
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
      final matchResponse = await _supabase
          .from('matches')
          .select('tournament_id')
          .eq('match_id', matchId)
          .maybeSingle();
      final tournamentId = matchResponse == null
          ? null
          : (matchResponse as Map)['tournament_id'] as String?;

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

        // Fetch ranking history for these players for this match to get snapshot ranking
        final rankingHistoryResponse = await _supabase
            .from('ranking_history')
            .select('player_id, ranking, change')
            .eq('match_id', matchId)
            .inFilter('player_id', playerIds);

        final rankingHistoryData = (rankingHistoryResponse as List<dynamic>)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);

        // Map players to use historical ranking if available
        List<Map<String, dynamic>> tournamentRankingData = const [];
        if (rankingHistoryData.isEmpty && tournamentId != null) {
          final tournamentRankingResponse = await _supabase
              .from('ranking_history')
              .select('player_id, ranking')
              .eq('tournament_id', tournamentId)
              .inFilter('player_id', playerIds);

          tournamentRankingData = (tournamentRankingResponse as List<dynamic>)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList(growable: false);
        }

        final playersWithHistory = players.map((player) {
          final historyEntry = rankingHistoryData.firstWhere(
            (entry) => entry['player_id'] == player.playerId,
            orElse: () => const <String, dynamic>{},
          );

          if (historyEntry.isNotEmpty) {
            // The history entry contains the ranking AFTER the match (if match finished) or initial?
            // "creates new ranking_history entry and updates player.ranking"
            // "ranking" column in ranking_history is usually the result.
            // But we want the ranking AT THE TIME of the match.
            // If the match is new (no result), it's the current ranking.
            // If the match has a result, the history entry has ranking + change.
            // Wait, if we look at `ranking_history` table:
            // It stores `ranking` (the new ranking) and `change`.
            // So ranking_before = ranking - change.
            // Or `ranking` is the ranking *before*?
            // Let's check `updatePlayerRanking` logic in ranking repo if possible.
            // Assuming `ranking` in history is the ranking stored at that point.
            // Usually history stores the snapshot.

            // Requirement: in match details we display historical snapshot:
            // ranking = ranking_entry.ranking + change

            final double storedRanking = (historyEntry['ranking'] as num)
                .toDouble();
            final double? change = (historyEntry['change'] as num?)?.toDouble();

            // If change is null, we treat storedRanking as snapshot ranking.

            if (change != null) {
              return player.copyWith(ranking: storedRanking + change);
            } else {
              // If change is null, it might be an initial entry or manual adjustment?
              // For a match, change is usually present if processed.
              // If not processed yet, current player.ranking is fine, or the one in history is the snapshot?
              // Let's assume the history ranking is the one valid for that entry.
              // If it's a snapshot, we use it.
              return player.copyWith(ranking: storedRanking);
            }
          }

          if (tournamentRankingData.isNotEmpty) {
            final tournamentEntry = tournamentRankingData.firstWhere(
              (entry) => entry['player_id'] == player.playerId,
              orElse: () => const <String, dynamic>{},
            );

            if (tournamentEntry.isNotEmpty) {
              final storedRanking = (tournamentEntry['ranking'] as num)
                  .toDouble();
              return player.copyWith(ranking: storedRanking);
            }
          }
          return player;
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
