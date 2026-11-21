import 'package:app/core/error/supabase_error_extension.dart';
import 'package:app/core/global_dependencies.dart';
import 'package:app/features/draft/domain/repositories/draft_experience_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseDraftExperienceRepository implements DraftExperienceRepository {
  SupabaseDraftExperienceRepository(this._client, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SupabaseClient _client;
  final DateTime Function() _now;
  static const pageSize = 250;
  static final _logger = Logger('SupabaseDraftExperienceRepository');

  @override
  Future<Map<String, int>> getAppearances({
    required List<String> playerIds,
    String? currentMatchId,
  }) async {
    final counts = {for (final id in playerIds) id: 0};
    if (counts.isEmpty) return counts;
    try {
      var cutoff = _now().toUtc();
      if (currentMatchId != null) {
        final current = await _client
            .from('matches')
            .select('played_at,created_at')
            .eq('match_id', currentMatchId)
            .single();
        final date = _date(current);
        if (date.isBefore(cutoff)) cutoff = date;
      }
      final seen = <String, Set<String>>{};
      // Flat membership pages avoid nested relation limits and N+1 reads.
      // Use the domain chronology: played_at, falling back to created_at.
      for (var offset = 0; ; offset += pageSize) {
        final rows = await _client
            .from('team_players')
            .select(
              'player_id,match_id,team_id,matches!team_players_match_fk!inner(played_at,created_at,home_score,away_score)',
            )
            .inFilter('player_id', counts.keys.toList())
            .not('matches.home_score', 'is', null)
            .not('matches.away_score', 'is', null)
            .order('match_id', ascending: true)
            .order('team_id', ascending: true)
            .order('player_id', ascending: true)
            .range(offset, offset + pageSize - 1);
        for (final row in rows) {
          final matchId = row['match_id'] as String;
          final playerId = row['player_id'] as String;
          final match = row['matches'] as Map<String, dynamic>;
          if (!counts.containsKey(playerId) ||
              matchId == currentMatchId ||
              match['home_score'] == null ||
              match['away_score'] == null ||
              !_date(match).isBefore(cutoff)) {
            continue;
          }
          if (seen.putIfAbsent(playerId, () => <String>{}).add(matchId)) {
            counts[playerId] = counts[playerId]! + 1;
          }
        }
        if (rows.length < pageSize) break;
      }
      return counts;
    } catch (error, stack) {
      // A failed read is not evidence of zero experience.
      _logger.severe('Failed to read draft experience', error, stack);
      Error.throwWithStackTrace(error.toFailure(), stack);
    }
  }

  DateTime _date(Map<String, dynamic> row) =>
      DateTime.parse((row['played_at'] ?? row['created_at']) as String).toUtc();
}

final draftExperienceRepositoryProvider = Provider<DraftExperienceRepository>(
  (ref) => SupabaseDraftExperienceRepository(ref.read(supabaseProvider)),
);
