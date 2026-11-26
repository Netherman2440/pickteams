import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/global_dependencies.dart';
import '../domain/repositories/goal_comparison_repository.dart';
import '../domain/entities/player.dart';
import 'usecases/get_squad_players_usecase.dart';
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

final playerRoleGoalComparisonProvider = FutureProvider.autoDispose
    .family<
      Map<GoalRole, RoleGoalComparison>,
      ({String squadId, String playerId})
    >((ref, key) async {
      final matches = await ref.watch(
        squadGoalHistoryProvider(key.squadId).future,
      );
      return comparePlayerRoleGoals(matches, key.playerId);
    });

class PlayerRoleGoals {
  const PlayerRoleGoals(this.player, this.comparison);
  final Player player;
  final Map<GoalRole, RoleGoalComparison> comparison;
}

final squadRoleGoalComparisonsProvider = FutureProvider.autoDispose
    .family<List<PlayerRoleGoals>, String>((ref, squadId) async {
      final roster = ref.watch(getSquadPlayersUseCaseProvider);
      final matches = await ref.watch(squadGoalHistoryProvider(squadId).future);
      final players = await roster.execute(squadId: squadId);
      return [
        for (final player in players)
          PlayerRoleGoals(
            player,
            comparePlayerRoleGoals(matches, player.playerId),
          ),
      ];
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
