import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/match_level.dart';
import '../../domain/repositories/match_level_repository.dart';

/// Reads only match-specific stored rankings. Does not change lineup fallbacks.
class SupabaseMatchLevelRepository implements MatchLevelRepository {
  SupabaseMatchLevelRepository(this.client);
  final SupabaseClient client;

  @override
  Future<MatchLevelThresholds?> loadThresholds(String squadId) async {
    final row = await client
        .from('squads')
        .select('star_thresholds')
        .eq('squad_id', squadId)
        .single();
    final raw = row['star_thresholds'] as List?;
    return raw == null
        ? null
        : MatchLevelThresholds(raw.map((v) => (v as num).toDouble()));
  }

  @override
  Future<void> saveThresholds(
    String squadId,
    MatchLevelThresholds thresholds,
  ) async {
    // select+single detects a denied update (RLS can silently affect zero rows).
    await client
        .from('squads')
        .update({'star_thresholds': thresholds.full})
        .eq('squad_id', squadId)
        .select('squad_id')
        .single();
  }

  Future<List<Map<String, dynamic>>> _pages(
    String table,
    String columns,
    String key,
    List<String> ids,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (var start = 0; start < ids.length; start += 100) {
      final chunk = ids.skip(start).take(100).toList();
      for (var offset = 0; ; offset += 500) {
        final page = await client
            .from(table)
            .select(columns)
            .inFilter(key, chunk)
            .order('match_id')
            .order('player_id')
            .range(offset, offset + 499);
        result.addAll(page);
        if (page.length < 500) break;
      }
    }
    return result;
  }

  @override
  Future<SquadMatchLevels> loadHistory(String squadId) async {
    final matches = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .from('matches')
          .select('match_id,home_score,away_score')
          .eq('squad_id', squadId)
          .order('match_id')
          .range(offset, offset + 499);
      matches.addAll(page);
      if (page.length < 500) break;
    }
    final completed = matches
        .where((m) => m['home_score'] != null && m['away_score'] != null)
        .length;
    if (!matchLevelEligible(completed)) {
      return SquadMatchLevels(completedMatches: completed, means: const {});
    }
    final ids = matches.map((m) => m['match_id'] as String).toList();
    final participants = await _pages(
      'team_players',
      'match_id,player_id',
      'match_id',
      ids,
    );
    final history = await _pages(
      'ranking_history',
      'match_id,player_id,ranking',
      'match_id',
      ids,
    );
    final byMatch = <String, Map<String, List<double?>>>{};
    for (final row in history) {
      final players = byMatch.putIfAbsent(row['match_id'] as String, () => {});
      players
          .putIfAbsent(row['player_id'] as String, () => [])
          .add((row['ranking'] as num?)?.toDouble());
    }
    final rosters = <String, Set<String>>{};
    for (final row in participants) {
      rosters
          .putIfAbsent(row['match_id'] as String, () => {})
          .add(row['player_id'] as String);
    }
    return SquadMatchLevels(
      completedMatches: completed,
      means: {
        for (final id in ids)
          id: historicalMatchMean(
            (rosters[id] ?? <String>{}).map((player) {
              final values = byMatch[id]?[player];
              return values != null && values.length == 1
                  ? values.single
                  : null;
            }),
          ),
      },
    );
  }
}
