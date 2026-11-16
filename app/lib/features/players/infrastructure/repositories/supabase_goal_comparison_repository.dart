import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/repositories/goal_comparison_repository.dart';
import '../../domain/services/player_goal_comparison.dart';

/// Read only, paged squad history including persisted match membership IDs.
class SupabaseGoalComparisonRepository implements GoalComparisonRepository {
  SupabaseGoalComparisonRepository(this.client);
  final SupabaseClient client;
  static const pageSize = 200;
  static const selection = '''
    match_id, home_score, away_score, score_type, score_meta,
    teams:teams!teams_match_fk (
      side, color, team_players!team_players_team_fk (player_id)
    )
  ''';

  @override
  Future<List<GoalComparisonMatch>> getSquadHistory(String squadId) async {
    final result = <GoalComparisonMatch>[];
    for (var offset = 0; ; offset += pageSize) {
      final rows = await client
          .from('matches')
          .select(selection)
          .eq('squad_id', squadId)
          .order('match_id', ascending: true)
          .range(offset, offset + pageSize - 1);
      result.addAll(rows.map(decodeGoalComparisonMatch));
      if (rows.length < pageSize) return result;
    }
  }
}

GoalComparisonMatch decodeGoalComparisonMatch(Map<String, dynamic> row) {
  final teams = (row['teams'] as List).cast<Map<String, dynamic>>();
  GoalComparisonTeam? side(String side) {
    final found = teams.where((team) => team['side'] == side).toList();
    if (found.length != 1) return null;
    return GoalComparisonTeam(
      color: found.single['color'] as String?,
      playerIds: (found.single['team_players'] as List)
          .map((player) => player['player_id'] as String)
          .toList(),
    );
  }

  final meta = row['score_meta'];
  return GoalComparisonMatch(
    home: teams.length == 2 ? side('home') : null,
    away: teams.length == 2 ? side('away') : null,
    homeScore: row['home_score'] as int?,
    awayScore: row['away_score'] as int?,
    ordinaryGoals:
        (row['score_type'] == null || row['score_type'] == 'regular') &&
        (meta == null ||
            (meta is Map &&
                meta.keys.every(
                  (key) =>
                      key == 'tournament_home_team_id' ||
                      key == 'tournament_away_team_id',
                ))),
  );
}
