import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/global_dependencies.dart';
import '../domain/repositories/goal_comparison_repository.dart';
import '../domain/services/player_goal_comparison.dart';
import '../infrastructure/repositories/supabase_goal_comparison_repository.dart';

final goalComparisonRepositoryProvider = Provider<GoalComparisonRepository>((
  ref,
) {
  return SupabaseGoalComparisonRepository(ref.watch(supabaseProvider));
});

final squadGoalHistoryProvider = FutureProvider.autoDispose
    .family<List<GoalComparisonMatch>, String>((ref, squadId) {
      return ref
          .watch(goalComparisonRepositoryProvider)
          .getSquadHistory(squadId);
    });

final playerGoalComparisonProvider = FutureProvider.autoDispose
    .family<GoalComparison, ({String squadId, String playerId})>((
      ref,
      key,
    ) async {
      final matches = await ref.watch(
        squadGoalHistoryProvider(key.squadId).future,
      );
      return comparePlayerGoals(matches, key.playerId);
    });
