import 'package:app/core/widgets/player_transfer_drag.dart';
import 'package:flutter/material.dart';
import 'package:app/core/widgets/player_list_row.dart';

import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/domain/entities/player_position.dart';

class DraftDraggablePlayerTile extends StatelessWidget {
  const DraftDraggablePlayerTile({
    super.key,
    required this.player,
    required this.trailing,
    this.compact = false,
    this.simple = false,
    this.density,
    this.leading,
    this.onTap,
    this.dragData,
  });

  final Player player;
  final Widget trailing;
  final bool compact;
  final bool simple;
  final PlayerRowDensity? density;
  final Widget? leading;

  final VoidCallback? onTap;
  final Object? dragData;

  @override
  Widget build(BuildContext context) {
    final difference = player.ranking - player.baseRanking;
    final positionText = playerPositionPolishLabel(player.position);

    final tile = PlayerListRow(
      name: player.name,
      ranking: player.ranking,
      compact: compact,
      density: density,
      leading:
          leading ??
          (dragData == null
              ? null
              : const Tooltip(
                  message: 'Przytrzymaj i przeciągnij',
                  child: Icon(Icons.drag_indicator, size: 16),
                )),
      trailing: trailing,
      onTap: onTap,
      supporting: !simple && (positionText != null || difference != 0)
          ? Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (positionText != null) Text(positionText),
                if (difference != 0) _RankingDifference(difference: difference),
              ],
            )
          : null,
    );

    final data = dragData;
    if (data == null) {
      return tile;
    }

    final feedback = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: compact
            ? (MediaQuery.sizeOf(context).width < 640
                  ? MediaQuery.sizeOf(context).width / 2 - 8
                  : 320)
            : 520,
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: tile,
      ),
    );

    return PlayerTransferDrag(data: data, feedback: feedback, child: tile);
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
      mainAxisSize: MainAxisSize.min,
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
