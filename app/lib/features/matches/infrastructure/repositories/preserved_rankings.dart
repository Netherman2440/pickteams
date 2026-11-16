import 'package:supabase_flutter/supabase_flutter.dart';

/// Match inputs take precedence per player. Tournament inputs cover legacy gaps.
Future<Map<String, double>> loadPreservedRankings(
  SupabaseClient client, {
  required String matchId,
}) async {
  final match = await client
      .from('matches')
      .select('tournament_id')
      .eq('match_id', matchId)
      .maybeSingle();
  final tournamentId = match?['tournament_id'] as String?;
  final rankings = <String, double>{};
  if (tournamentId != null) {
    final history = await client
        .from('ranking_history')
        .select('player_id, ranking')
        .eq('tournament_id', tournamentId)
        .isFilter('match_id', null);
    for (final row in history) {
      rankings[row['player_id'] as String] = (row['ranking'] as num).toDouble();
    }
  }
  final history = await client
      .from('ranking_history')
      .select('player_id, ranking')
      .eq('match_id', matchId);
  for (final row in history) {
    rankings[row['player_id'] as String] = (row['ranking'] as num).toDouble();
  }
  return rankings;
}

/// A new score object is authoritative, never repaired from legacy history.
Map<String, double> resolveProposalRankings({
  required Map<String, dynamic> proposal,
  required Iterable<String> playerIds,
  required Map<String, double> preservedRankings,
}) {
  final hasRankings = proposal.containsKey('rankings');
  final raw = proposal['rankings'];
  final result = <String, double>{};
  for (final id in playerIds) {
    final value = hasRankings
        ? (raw is Map ? raw[id] : null)
        : preservedRankings[id];
    if (value is! num || !value.isFinite) {
      throw StateError('Missing preserved draft ranking for player $id');
    }
    result[id] = value.toDouble();
  }
  return result;
}
