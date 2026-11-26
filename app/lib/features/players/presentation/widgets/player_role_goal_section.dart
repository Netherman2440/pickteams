import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/player_goal_comparison_provider.dart';
import '../../domain/services/player_goal_comparison.dart';
import 'player_role_goal_values.dart';

String goalDeltaText(double? value) {
  if (value == null) return 'Brak danych';
  final rounded = value.toStringAsFixed(2);
  final normalized = double.parse(rounded) == 0 ? '0.00' : rounded;
  return '${value > 0 && normalized != '0.00' ? '+' : ''}${normalized.replaceAll('.', ',')}';
}

const roleGoalExplanation =
    'Porównanie wyników drużyny, nie wpływ zawodnika. '
    'Różnica średniej goli na mecz: z zawodnikiem po tej stronie minus '
    'mecze bez niego w obu drużynach.';

class RoleGoalValues extends StatelessWidget {
  const RoleGoalValues({super.key, required this.role, required this.result});
  final GoalRole role;
  final RoleGoalComparison result;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        role == GoalRole.home ? 'Gospodarze' : 'Goście',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Text(
        'Z zawodnikiem: ${result.withPlayer} · Bez zawodnika: ${result.withoutPlayer}',
      ),
      Text(
        'Strzelone: ${goalDeltaText(result.scored)} · Stracone: ${goalDeltaText(result.conceded)}',
      ),
      if (result.incomplete) const Text('Niekompletna historia meczów.'),
    ],
  );
}

class PlayerRoleGoalSection extends ConsumerWidget {
  const PlayerRoleGoalSection({
    super.key,
    required this.squadId,
    required this.playerId,
  });
  final String squadId;
  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comparison = ref.watch(
      playerRoleGoalComparisonProvider((squadId: squadId, playerId: playerId)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gole według strony',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(roleGoalExplanation),
        const SizedBox(height: 12),
        comparison.when(
          loading: () => const CircularProgressIndicator(),
          error: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nie udało się pobrać porównań.'),
              TextButton(
                onPressed: () =>
                    ref.invalidate(squadGoalHistoryProvider(squadId)),
                child: const Text('Ponów'),
              ),
            ],
          ),
          data: (values) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final role in GoalRole.values) ...[
                PlayerRoleGoalValues(role: role, result: values[role]!),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
