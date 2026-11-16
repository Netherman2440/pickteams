import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'supabase_tournament_draft_repository.dart';

import 'package:app/core/error/supabase_error_extension.dart';
import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/entities/match_enums.dart';
import 'package:app/features/matches/domain/entities/team.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/tournaments/domain/entities/tournament.dart';
import 'package:app/features/tournaments/domain/entities/tournament_status.dart';
import 'package:app/features/tournaments/domain/entities/tournament_team.dart';
import 'package:app/features/tournaments/domain/repositories/tournament_repository.dart';

class SupabaseTournamentRepository implements TournamentRepository {
  final SupabaseClient _supabase;
  final Logger _logger = Logger('SupabaseTournamentRepository');

  static const _matchListSelect = '''
    *,
    teams:teams!teams_match_fk (
      team_id,
      match_id,
      side,
      name,
      color
    )
  ''';

  SupabaseTournamentRepository(this._supabase);

  @override
  Future<List<Tournament>> getTournaments({required String squadId}) async {
    try {
      final response = await _supabase
          .from('tournaments')
          .select(
            'tournament_id, squad_id, name, status, created_at, updated_at, accepted_tournament_draft_id',
          )
          .eq('squad_id', squadId)
          .order('created_at', ascending: false);

      final rows = response as List<dynamic>;
      return rows
          .map(
            (row) => Tournament.fromMap(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false);
    } catch (e, stack) {
      _logger.severe('Failed to load tournaments for squad $squadId', e, stack);
      throw e.toFailure();
    }
  }

  @override
  Future<Tournament> getTournament({required String tournamentId}) async {
    try {
      final response = await _supabase
          .from('tournaments')
          .select(
            'tournament_id, squad_id, name, status, created_at, updated_at, accepted_tournament_draft_id',
          )
          .eq('tournament_id', tournamentId)
          .single();

      return Tournament.fromMap(Map<String, dynamic>.from(response as Map));
    } catch (e, stack) {
      _logger.severe('Failed to load tournament $tournamentId', e, stack);
      throw e.toFailure();
    }
  }

  @override
  Future<Tournament> createTournament({
    required String squadId,
    String? name,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final response = await _supabase
          .from('tournaments')
          .insert({
            'squad_id': squadId,
            'name': name,
            'status': TournamentStatus.drafting.name,
            'updated_at': now,
          })
          .select(
            'tournament_id, squad_id, name, status, created_at, updated_at, accepted_tournament_draft_id',
          )
          .single();

      return Tournament.fromMap(Map<String, dynamic>.from(response as Map));
    } catch (e, stack) {
      _logger.severe('Failed to create tournament in squad $squadId', e, stack);
      throw e.toFailure();
    }
  }

  @override
  Future<Tournament> updateTournament({
    required String tournamentId,
    String? name,
    TournamentStatus? status,
    String? acceptedTournamentDraftId,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (name != null) {
        updates['name'] = name;
      }
      if (status != null) {
        updates['status'] = status.name;
      }
      if (acceptedTournamentDraftId != null) {
        updates['accepted_tournament_draft_id'] = acceptedTournamentDraftId;
      }

      final response = await _supabase
          .from('tournaments')
          .update(updates)
          .eq('tournament_id', tournamentId)
          .select(
            'tournament_id, squad_id, name, status, created_at, updated_at, accepted_tournament_draft_id',
          )
          .single();

      return Tournament.fromMap(Map<String, dynamic>.from(response as Map));
    } catch (e, stack) {
      _logger.severe('Failed to update tournament $tournamentId', e, stack);
      throw e.toFailure();
    }
  }

  @override
  Future<void> deleteTournament({required String tournamentId}) async {
    try {
      await _supabase
          .from('tournaments')
          .delete()
          .eq('tournament_id', tournamentId);
    } catch (e, stack) {
      _logger.severe('Failed to delete tournament $tournamentId', e, stack);
      throw e.toFailure();
    }
  }

  @override
  Future<List<TournamentTeam>> getTournamentTeams({
    required String tournamentId,
  }) async {
    try {
      final teamsResponse = await _supabase
          .from('tournament_teams')
          .select('tournament_team_id, tournament_id, name, color, created_at')
          .eq('tournament_id', tournamentId)
          .order('created_at', ascending: true);

      final teamsRows = teamsResponse as List<dynamic>;
      final teams = teamsRows
          .map(
            (row) =>
                TournamentTeam.fromMap(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false);

      if (teams.isEmpty) {
        return const [];
      }

      final teamPlayersResponse = await _supabase
          .from('tournament_team_players')
          .select('tournament_team_id, player_id')
          .eq('tournament_id', tournamentId);

      final teamPlayerRows = teamPlayersResponse as List<dynamic>;
      final playerIds = teamPlayerRows
          .map((row) => (row as Map)['player_id'])
          .whereType<String>()
          .toSet()
          .toList(growable: false);

      if (playerIds.isEmpty) {
        return teams;
      }

      final playersResponse = await _supabase
          .from('players')
          .select()
          .inFilter('player_id', playerIds);

      final players = (playersResponse as List<dynamic>)
          .map((row) => Player.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList(growable: false);

      final rankingResponse = await _supabase
          .from('ranking_history')
          .select('player_id, ranking')
          .eq('tournament_id', tournamentId)
          .isFilter('match_id', null)
          .inFilter('player_id', playerIds);

      final rankingByPlayerId = <String, double>{
        for (final row in (rankingResponse as List<dynamic>))
          if ((row as Map)['player_id'] is String && row['ranking'] is num)
            row['player_id'] as String: (row['ranking'] as num).toDouble(),
      };

      final tournament = await getTournament(tournamentId: tournamentId);
      final acceptedId = tournament.acceptedTournamentDraftId;
      if (acceptedId != null) {
        final draft = await SupabaseTournamentDraftRepository(
          _supabase,
        ).getTournamentDraft(tournamentDraftId: acceptedId);
        if (draft == null || draft.tournamentId != tournamentId) {
          throw StateError('Missing preserved tournament draft');
        }
        // Accepted generation inputs supersede the earlier creation snapshot.
        rankingByPlayerId
          ..clear()
          ..addAll(draft.inputs.rankings);
      }
      final playersById = <String, Player>{};
      for (final player in players) {
        final ranking = rankingByPlayerId[player.playerId];
        if (ranking == null || !ranking.isFinite) {
          throw StateError(
            'Missing preserved tournament ranking for ${player.playerId}',
          );
        }
        playersById[player.playerId] = player.copyWith(ranking: ranking);
      }

      final playersByTeam = <String, List<Player>>{};
      for (final row in teamPlayerRows) {
        final map = Map<String, dynamic>.from(row as Map);
        final teamId = map['tournament_team_id'] as String;
        final playerId = map['player_id'] as String;
        final player = playersById[playerId];
        if (player == null) {
          continue;
        }
        playersByTeam.putIfAbsent(teamId, () => <Player>[]).add(player);
      }

      return teams
          .map(
            (team) => team.copyWith(
              players: playersByTeam[team.tournamentTeamId] ?? const [],
            ),
          )
          .toList(growable: false);
    } catch (e, stack) {
      _logger.severe(
        'Failed to load tournament teams for tournament $tournamentId',
        e,
        stack,
      );
      throw e.toFailure();
    }
  }

  @override
  Future<List<String>> getTournamentPlayerIds({
    required String tournamentId,
  }) async {
    try {
      final response = await _supabase
          .from('tournament_team_players')
          .select('player_id')
          .eq('tournament_id', tournamentId);

      final rows = response as List<dynamic>;
      return rows
          .map((row) => (row as Map)['player_id'])
          .whereType<String>()
          .toSet()
          .toList(growable: false);
    } catch (e, stack) {
      _logger.severe(
        'Failed to load tournament player ids for tournament $tournamentId',
        e,
        stack,
      );
      throw e.toFailure();
    }
  }

  @override
  Future<void> replaceTournamentTeams({
    required String tournamentId,
    required List<TournamentTeamInput> teams,
  }) async {
    try {
      final existingTeamsResponse = await _supabase
          .from('tournament_teams')
          .select('tournament_team_id')
          .eq('tournament_id', tournamentId);

      final existingIds = (existingTeamsResponse as List<dynamic>)
          .map((row) => (row as Map)['tournament_team_id'])
          .whereType<String>()
          .toSet();

      final retainedIds = <String>{};
      final teamRows = <Map<String, dynamic>>[];

      for (var index = 0; index < teams.length; index++) {
        final team = teams[index];
        final providedId = team.tournamentTeamId;
        final teamId = providedId != null && existingIds.contains(providedId)
            ? providedId
            : const Uuid().v4();

        retainedIds.add(teamId);
        teamRows.add({
          'tournament_team_id': teamId,
          'tournament_id': tournamentId,
          'name': team.name,
          'color': team.color,
        });
      }

      if (teamRows.isNotEmpty) {
        await _supabase
            .from('tournament_teams')
            .upsert(teamRows, onConflict: 'tournament_team_id');
      }

      final idsToDelete = existingIds
          .difference(retainedIds)
          .toList(growable: false);
      if (idsToDelete.isNotEmpty) {
        await _supabase
            .from('tournament_teams')
            .delete()
            .eq('tournament_id', tournamentId)
            .inFilter('tournament_team_id', idsToDelete);
      }

      await _supabase
          .from('tournament_team_players')
          .delete()
          .eq('tournament_id', tournamentId);

      final rosterRows = <Map<String, dynamic>>[];
      for (var index = 0; index < teams.length; index++) {
        final teamId = teamRows[index]['tournament_team_id'] as String;
        final playerIds = teams[index].playerIds.toSet().toList(
          growable: false,
        );

        for (final playerId in playerIds) {
          rosterRows.add({
            'tournament_team_id': teamId,
            'tournament_id': tournamentId,
            'player_id': playerId,
          });
        }
      }

      if (rosterRows.isNotEmpty) {
        await _supabase.from('tournament_team_players').insert(rosterRows);
      }
    } catch (e, stack) {
      _logger.severe(
        'Failed to replace tournament teams for tournament $tournamentId',
        e,
        stack,
      );
      throw e.toFailure();
    }
  }

  @override
  Future<List<Match>> getTournamentMatches({
    required String tournamentId,
  }) async {
    try {
      final response = await _supabase
          .from('matches')
          .select(_matchListSelect)
          .eq('tournament_id', tournamentId)
          .order('played_at', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false);

      final rows = response as List<dynamic>;
      return rows.map(_matchFromListRow).toList(growable: false);
    } catch (e, stack) {
      _logger.severe(
        'Failed to load tournament matches for tournament $tournamentId',
        e,
        stack,
      );
      throw e.toFailure();
    }
  }

  Match _matchFromListRow(dynamic row) {
    final rowData = Map<String, dynamic>.from(row as Map);
    final teamsData = rowData.remove('teams');
    final match = Match.fromJson(rowData);

    if (teamsData is! List<dynamic>) {
      return match;
    }

    Team? homeTeam;
    Team? awayTeam;

    for (final teamRow in teamsData) {
      final team = Team.fromJson(Map<String, dynamic>.from(teamRow as Map));
      if (team.side == Side.home) {
        homeTeam = team;
      } else {
        awayTeam = team;
      }
    }

    return match.copyWith(homeTeam: homeTeam, awayTeam: awayTeam);
  }
}
