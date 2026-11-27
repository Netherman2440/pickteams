import 'package:flutter/material.dart';
import 'package:app/features/squads/presentation/widgets/stat_tile.dart';
import '../../domain/services/player_goal_comparison.dart';
import 'player_role_goal_section.dart' show goalDeltaText;

String _meaning(double? delta, bool scored) {
  if (delta == null) return 'Brak próbki porównawczej';
  final rounded = double.parse(delta.toStringAsFixed(2));
  if (rounded == 0) return 'Brak różnicy';
  return scored == (rounded > 0) ? 'Korzystnie' : 'Niekorzystnie';
}

/// Uses the same label/value list rhythm as the unchanged balance list.
class PlayerRoleGoalValues extends StatelessWidget {
  const PlayerRoleGoalValues({
    super.key,
    required this.role,
    required this.result,
  });
  final GoalRole role;
  final RoleGoalComparison result;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
        child: Text(
          role == GoalRole.home ? 'Gospodarze' : 'Goście',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      for (final scored in [true, false])
        Builder(
          builder: (context) {
            final delta = scored ? result.scored : result.conceded;
            final meaning = _meaning(delta, scored);
            final color = meaning == 'Korzystnie'
                ? const Color(0xff86c36a)
                : meaning == 'Niekorzystnie'
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurfaceVariant;
            return StatTile(
              label: scored ? 'Strzelone' : 'Stracone',
              value: goalDeltaText(delta),
              valueColor: color,
              maxValueWidthFraction: .45,
              valueSemanticsLabel:
                  '${goalDeltaText(delta)} gola na mecz. $meaning',
            );
          },
        ),
    ],
  );
}

class PlayerRoleGoalDetails extends StatelessWidget {
  const PlayerRoleGoalDetails({
    super.key,
    required this.role,
    required this.result,
  });
  final GoalRole role;
  final RoleGoalComparison result;

  String average(double? value) =>
      value == null ? '—' : value.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          role == GoalRole.home ? 'Gospodarze' : 'Goście',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          'Z zawodnikiem: ${result.withPlayer} · Bez zawodnika: ${result.withoutPlayer}',
        ),
        for (final scored in [true, false])
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scored ? 'Strzelone' : 'Stracone'),
                Text(
                  '${average(scored ? result.scoredWithPlayer : result.concededWithPlayer)} z graczem · ${average(scored ? result.scoredWithoutPlayer : result.concededWithoutPlayer)} bez',
                ),
                Text(
                  '${goalDeltaText(scored ? result.scored : result.conceded)} gola / mecz · ${_meaning(scored ? result.scored : result.conceded, scored)}',
                ),
              ],
            ),
          ),
        if (result.incomplete) const Text('Niekompletna historia meczów.'),
      ],
    ),
  );
}
