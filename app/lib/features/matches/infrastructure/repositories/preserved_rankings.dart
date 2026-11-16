import 'package:supabase_flutter/supabase_flutter.dart';

/// Match inputs take precedence per player. Tournament inputs cover legacy gaps.
Future<Map<String, double>> loadPreservedRankings(
  SupabaseClient client, {
  required String matchId,
}) async {
  final match = await client
      .from('matches')
      .select('tournament_id, score_meta')
      .eq('match_id', matchId)
      .maybeSingle();
  final tournamentId = match?['tournament_id'] as String?;
  final metadata = match?['score_meta'];
  if (metadata is Map && metadata.containsKey('draft_rankings')) {
    final raw = metadata['draft_rankings'];
    if (raw is! Map || raw.keys.any((id) => id is! String)) {
      throw StateError('Malformed preserved match inputs');
    }
    // New tournament-match vectors are authoritative. Never fill a malformed
    // or partial vector from older creation history.
    return resolveProposalRankings(
      proposal: {'rankings': raw},
      playerIds: raw.keys.cast<String>(),
      preservedRankings: const {},
    );
  }
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

/// ID-only legacy proposals retain their old default; new metadata is strict.
bool resolveProposalSubstitutes(Map<String, dynamic> proposal) {
  final option = proposal['play_with_substitute'];
  if (option is bool) return option;
  if (proposal.containsKey('rankings') ||
      proposal.containsKey('play_with_substitute')) {
    throw StateError('Missing preserved draft substitute option');
  }
  return true;
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
