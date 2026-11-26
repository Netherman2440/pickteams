import 'package:flutter/material.dart';
import '../../domain/services/player_goal_comparison.dart';
import 'player_role_goal_section.dart' show goalDeltaText;

class PlayerRoleGoalValues extends StatelessWidget {
  const PlayerRoleGoalValues({
    super.key,
    required this.role,
    required this.result,
  });
  final GoalRole role;
  final RoleGoalComparison result;

  String average(double? v) =>
      v == null ? '—' : v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Wrap(
          spacing: 16,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              role == GoalRole.home ? 'Gospodarze' : 'Goście',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Z zawodnikiem: ${result.withPlayer} · Bez zawodnika: ${result.withoutPlayer}',
            ),
          ],
        ),
      ),
      for (final scored in [true, false]) ...[
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final delta = scored ? result.scored : result.conceded;
              final rounded = delta == null
                  ? null
                  : double.parse(delta.toStringAsFixed(2));
              final favorable =
                  rounded != null && rounded != 0 && (scored == (rounded > 0));
              final description = rounded == null
                  ? 'Brak próbki porównawczej'
                  : rounded == 0
                  ? 'Brak różnicy'
                  : favorable
                  ? 'Korzystnie'
                  : 'Niekorzystnie';
              final color = rounded == null || rounded == 0
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : favorable
                  ? const Color(0xff86c36a)
                  : Theme.of(context).colorScheme.error;
              final label = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scored ? 'Strzelone' : 'Stracone',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '${average(scored ? result.scoredWithPlayer : result.concededWithPlayer)} z graczem · ${average(scored ? result.scoredWithoutPlayer : result.concededWithoutPlayer)} bez',
                  ),
                  Text(
                    'gola / mecz',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
              final value = Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    goalDeltaText(delta),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    description,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: color),
                  ),
                ],
              );
              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [label, const SizedBox(height: 8), value],
                );
              }
              return Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 12),
                  Flexible(child: value),
                ],
              );
            },
          ),
        ),
      ],
      if (result.incomplete) const Text('Niekompletna historia meczów.'),
    ],
  );
}
