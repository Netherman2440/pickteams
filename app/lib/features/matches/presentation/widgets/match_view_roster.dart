import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/dto/player_dto.dart';

/// Flex intrinsic height uses the tallest panel across both columns. The sliver
/// gives spare viewport height to rows, without guessing shell/footer heights.
class MatchViewRoster extends StatelessWidget {
  const MatchViewRoster({
    super.key,
    required this.home,
    required this.away,
    required this.onPlayerTap,
    required this.footer,
    required this.gap,
  });

  final List<PlayerDto> home;
  final List<PlayerDto> away;
  final ValueChanged<PlayerDto> onPlayerTap;
  final Widget footer;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final count = math.max(home.length, away.length);
    Widget team(List<PlayerDto> players) {
      final sorted = [...players]
        ..sort((a, b) => b.ranking.compareTo(a.ranking));
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < count; index++)
              Expanded(
                child: index < sorted.length
                    ? MatchViewPlayerPanel(
                        player: sorted[index],
                        onTap: () => onPlayerTap(sorted[index]),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      );
    }

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          children: [
            if (count > 0)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    team(home),
                    SizedBox(width: gap),
                    team(away),
                  ],
                ),
              )
            else
              const Spacer(),
            footer,
          ],
        ),
      ),
    );
  }
}

class MatchViewPlayerPanel extends StatelessWidget {
  const MatchViewPlayerPanel({
    super.key,
    required this.player,
    required this.onTap,
  });

  final PlayerDto player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameStyle = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      height: 1.35,
    );
    final rankingStyle = theme.textTheme.bodySmall!.copyWith(
      fontSize: 12,
      height: 1.35,
    );
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(
          minHeight: MediaQuery.textScalerOf(context).scale(14) * 1.35 * 2 + 16,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        foregroundDecoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(player.name, style: nameStyle)),
            const SizedBox(width: 8),
            Text(player.ranking.toStringAsFixed(2), style: rankingStyle),
          ],
        ),
      ),
    );
  }
}
