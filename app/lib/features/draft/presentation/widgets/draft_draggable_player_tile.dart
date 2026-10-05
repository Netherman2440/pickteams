import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/domain/entities/player_position.dart';

class DraftDraggablePlayerTile extends StatelessWidget {
  const DraftDraggablePlayerTile({
    super.key,
    required this.player,
    required this.trailing,
    this.compact = false,
    this.highlighted = false,
    this.onTap,
    this.dragData,
  });

  final Player player;
  final Widget trailing;
  final bool compact;

  /// Whether the tile is currently picked by keyboard navigation in the
  /// draft selection search field.
  final bool highlighted;
  final VoidCallback? onTap;
  final Object? dragData;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final difference = player.ranking - player.baseRanking;
    final positionText = playerPositionPolishLabel(player.position);

    final tile = Card(
      color: highlighted ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        dense: compact,
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 8)
            : null,
        leading: CircleAvatar(
          radius: compact ? 14 : null,
          child: Text(
            player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
            style: compact ? theme.textTheme.labelSmall : null,
          ),
        ),
        title: Text(
          player.name,
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: compact ? theme.textTheme.bodyMedium : null,
        ),
        subtitle: compact
            ? Text(
                'Ranking: ${player.ranking.toStringAsFixed(2)}',
                style: theme.textTheme.bodySmall,
              )
            : Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (positionText != null) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sports_soccer,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(positionText),
                      ],
                    ),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.insights,
                        size: 16,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 4),
                      Text('Ranking: ${player.ranking.toStringAsFixed(2)}'),
                    ],
                  ),
                  if (difference.abs() > 0) ...[
                    _RankingDifference(difference: difference),
                  ],
                ],
              ),
        trailing: trailing,
        onTap: onTap,
      ),
    );

    final data = dragData;
    if (data == null) {
      return tile;
    }

    final feedback = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 320 : 520),
      child: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.9, child: tile),
      ),
    );

    final childWhenDragging = Opacity(opacity: 0.4, child: tile);

    if (_shouldUseImmediateDrag) {
      return Draggable<Object>(
        data: data,
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        child: tile,
      );
    }

    return LongPressDraggable<Object>(
      data: data,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      child: tile,
    );
  }
}

bool get _shouldUseImmediateDrag {
  if (kIsWeb) {
    return true;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      return true;
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return false;
  }
}

class _RankingDifference extends StatelessWidget {
  const _RankingDifference({required this.difference});

  final double difference;

  @override
  Widget build(BuildContext context) {
    final isPositiveOrFlat = difference >= 0;
    final color = isPositiveOrFlat ? Colors.green : Colors.red;
    final formattedDifference =
        '${difference >= 0 ? '+' : ''}'
        '${difference.toStringAsFixed(2)}';

    return Row(
      children: [
        Icon(
          isPositiveOrFlat ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          formattedDifference,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
