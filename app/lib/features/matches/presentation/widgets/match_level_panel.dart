import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/match_level_providers.dart';

class MatchLevelPanel extends ConsumerWidget {
  const MatchLevelPanel({
    super.key,
    required this.squadId,
    required this.matchId,
    this.details = false,
  });
  final String squadId;
  final String matchId;
  final bool details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating = ref
        .watch(squadMatchLevelsProvider(squadId))
        .asData
        ?.value[matchId];
    if (rating == null) return const SizedBox.shrink();
    return MatchLevelRating(rating: rating, details: details);
  }
}

class MatchLevelRating extends StatelessWidget {
  const MatchLevelRating({
    super.key,
    required this.rating,
    this.details = false,
  });
  final double rating;
  final bool details;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final number = rating
        .toStringAsFixed(rating == rating.roundToDouble() ? 0 : 1)
        .replaceAll('.', ',');
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Poziom meczu: $number na 5',
          excludeSemantics: true,
          child: Row(
            children: [
              const Expanded(child: Text('Poziom meczu')),
              for (var i = 1; i <= 5; i++)
                Icon(
                  rating >= i
                      ? Icons.star
                      : rating >= i - .5
                      ? Icons.star_half
                      : Icons.star_border,
                  size: 19,
                  color: color,
                ),
              const SizedBox(width: 6),
              Text(
                number,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (details) ...[
          const SizedBox(height: 8),
          Text(
            'Siła obsady na podstawie historycznych rankingów. To nie ocena wyniku ani wyrównania drużyn.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
    if (!details) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [const Divider(height: 24), content],
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: content,
    );
  }
}
