import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/dto/player_dto.dart';

TextStyle _nameStyle(BuildContext context) => DefaultTextStyle.of(context).style
    .merge(Theme.of(context).textTheme.bodyMedium)
    .copyWith(fontSize: 14, height: 1.35);

TextStyle _rankingStyle(BuildContext context) => DefaultTextStyle.of(context)
    .style
    .merge(Theme.of(context).textTheme.bodySmall)
    .copyWith(fontSize: 12, height: 1.35);

/// Measure at the final name width, not Flex's unconstrained intrinsic width.
/// The sliver still distributes spare viewport height after the real footer.
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

  double _rowHeight(BuildContext context, double columnWidth) {
    final scaler = MediaQuery.textScalerOf(context);
    final defaults = DefaultTextStyle.of(context);
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: scaler,
      locale: Localizations.maybeLocaleOf(context),
      textWidthBasis: defaults.textWidthBasis,
      textHeightBehavior: defaults.textHeightBehavior,
    );
    var height = scaler.scale(14) * 1.35 * 2 + 16;
    try {
      for (final player in [...home, ...away]) {
        painter.text = TextSpan(
          text: player.ranking.toStringAsFixed(2),
          style: _rankingStyle(context),
        );
        painter.layout();
        final rankingWidth = painter.width;
        final rankingHeight = painter.height;
        painter.text = TextSpan(text: player.name, style: _nameStyle(context));
        // Same 2px horizontal padding and 8px gap as the actual panel Row.
        final nameWidth = math.max(0.0, columnWidth - 4 - 8 - rankingWidth);
        painter.layout(minWidth: nameWidth, maxWidth: nameWidth);
        height = math.max(height, math.max(painter.height, rankingHeight) + 16);
      }
      return height;
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final count = math.max(home.length, away.length);
      final columnWidth = (constraints.crossAxisExtent - 16 - gap) / 2;
      final rowHeight = _rowHeight(context, columnWidth);
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
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: rowHeight * count),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        team(home),
                        SizedBox(width: gap),
                        team(away),
                      ],
                    ),
                  ),
                )
              else
                const Spacer(),
              footer,
            ],
          ),
        ),
      );
    },
  );
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
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.textScalerOf(context).scale(14) * 1.35 * 2 + 16,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: Text(player.name, style: _nameStyle(context))),
          const SizedBox(width: 8),
          Text(
            player.ranking.toStringAsFixed(2),
            style: _rankingStyle(context),
          ),
        ],
      ),
    ),
  );
}
