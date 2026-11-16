import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/player_goal_comparison_provider.dart';
import '../../domain/services/player_goal_comparison.dart';

class PlayerGoalComparisonSection extends ConsumerWidget {
  const PlayerGoalComparisonSection({
    super.key,
    required this.squadId,
    required this.playerId,
  });
  final String squadId;
  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (squadId: squadId, playerId: playerId);
    final state = ref.watch(playerGoalComparisonProvider(key));
    final comparison = state.asData?.value;
    final message = state.hasError
        ? 'Nie udało się pobrać danych.'
        : state.isLoading
        ? 'Wczytywanie danych…'
        : switch (comparison?.unavailable) {
            GoalComparisonUnavailable.noAppearances =>
              'Brak rozegranych meczów zawodnika.',
            GoalComparisonUnavailable.noAbsences =>
              'Brak meczów bez zawodnika.',
            GoalComparisonUnavailable.incomplete =>
              'Brak kompletnych danych porównawczych.',
            null => null,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Drużyna z tym zawodnikiem',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _GoalTile(
                  scored: true,
                  delta: comparison?.scored,
                  message: message,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GoalTile(
                  scored: false,
                  delta: comparison?.conceded,
                  message: message,
                ),
              ),
            ],
          ),
        ),
        if (state.hasError)
          TextButton.icon(
            onPressed: () => ref.invalidate(squadGoalHistoryProvider(squadId)),
            icon: const Icon(Icons.refresh),
            label: const Text('Spróbuj ponownie'),
          ),
        const SizedBox(height: 8),
        Text(
          'Porównanie z meczami całkowitej nieobecności zawodnika, osobno dla kolorów, '
          'ważone liczbą jego występów. Każdy występ to cały mecz. '
          'Wynik drużyny, nie dowód indywidualnego wpływu przyczynowego.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.scored,
    required this.delta,
    required this.message,
  });
  final bool scored;
  final double? delta;
  final String? message;

  @override
  Widget build(BuildContext context) {
    // Use the same rounded value for number, label, arrow and color.
    final rounded = double.parse((delta ?? 0).toStringAsFixed(2));
    final zero = rounded == 0;
    final positive = rounded > 0;
    final neutral = Theme.of(context).colorScheme.onSurfaceVariant;
    final color = zero || delta == null
        ? neutral
        : (scored == positive ? Colors.green : Colors.red);
    final description = zero
        ? 'Brak różnicy'
        : '${positive ? 'więcej' : 'mniej'} ${scored ? 'strzelonych' : 'straconych'}';
    final number =
        '${zero
            ? ''
            : positive
            ? '+'
            : '−'}${rounded.abs().toStringAsFixed(2).replaceAll('.', ',')}';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              scored ? 'BRAMKI STRZELONE' : 'BRAMKI STRACONE',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 12),
            if (message != null) ...[
              Text('—', style: Theme.of(context).textTheme.headlineMedium),
              Text(message!),
            ] else ...[
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    number,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!zero)
                    Icon(
                      positive ? Icons.arrow_upward : Icons.arrow_downward,
                      color: color,
                      size: 24,
                    ),
                ],
              ),
              Text(description, style: TextStyle(color: color)),
              const SizedBox(height: 4),
              Text(
                'średnio na mecz',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
