import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/players/application/player_goal_comparison_provider.dart';
import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:app/features/players/presentation/widgets/player_role_goal_section.dart';

class SquadRoleGoalSection extends ConsumerStatefulWidget {
  const SquadRoleGoalSection({super.key, required this.squadId});
  final String squadId;

  @override
  ConsumerState<SquadRoleGoalSection> createState() =>
      _SquadRoleGoalSectionState();
}

class _SquadRoleGoalSectionState extends ConsumerState<SquadRoleGoalSection> {
  GoalMeasure measure = GoalMeasure.homeScored;
  bool reverse = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(squadRoleGoalComparisonsProvider(widget.squadId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gole według strony',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(roleGoalExplanation),
        const SizedBox(height: 12),
        DropdownButton<GoalMeasure>(
          value: measure,
          isExpanded: true,
          items: [
            for (final item in GoalMeasure.values)
              DropdownMenuItem(value: item, child: Text(item.label)),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                measure = value;
                reverse = false;
              });
            }
          },
        ),
        TextButton.icon(
          onPressed: () => setState(() => reverse = !reverse),
          icon: Icon(reverse ? Icons.arrow_upward : Icons.arrow_downward),
          label: Text(
            reverse ? 'Odwrócona kolejność' : 'Najkorzystniejsze najpierw',
          ),
        ),
        state.when(
          loading: () => const CircularProgressIndicator(),
          error: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nie udało się pobrać porównań.'),
              TextButton(
                onPressed: () {
                  ref.invalidate(squadGoalHistoryProvider(widget.squadId));
                  ref.invalidate(
                    squadRoleGoalComparisonsProvider(widget.squadId),
                  );
                },
                child: const Text('Ponów'),
              ),
            ],
          ),
          data: (rows) {
            final sorted = [...rows]
              ..sort(
                (a, b) => compareGoalMeasure(
                  measure,
                  a.player.playerId,
                  a.comparison,
                  b.player.playerId,
                  b.comparison,
                  reverse: reverse,
                ),
              );
            if (sorted.isEmpty) return const Text('Brak graczy.');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in sorted)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row.player.name} · ${goalDeltaText(measure.value(row.comparison))}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        RoleGoalValues(
                          role: measure.role,
                          result: row.comparison[measure.role]!,
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
